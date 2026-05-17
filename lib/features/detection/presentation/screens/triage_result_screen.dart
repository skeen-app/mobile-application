import 'package:skeen/core/localization/locale_controller.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../../core/logger/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/notifications/notifications_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/full_screen_image_viewer.dart';

import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../../../core/widgets/tutorial_coach_mark.dart';
import '../../../../core/widgets/tutorial_controller.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../patient/application/lesion_summary_providers.dart';
import '../../../patient/application/scan_history_providers.dart';
import '../../../reminders/application/reminders_controller.dart';
import '../../application/pdf_report_service.dart';
import '../../application/providers.dart';
import '../../application/sync_orchestrator.dart';
import '../../domain/class_label.dart';
import '../../domain/inference_result.dart';
import '../../domain/lesion_analysis.dart';
import '../widgets/confidence_bar.dart';
import '../widgets/quality_verified_badge.dart';

/// Triage result screen — full-vertical layout that fills the viewport on
/// most phones and falls back to scroll on smaller screens.
class TriageResultScreen extends ConsumerStatefulWidget {
  const TriageResultScreen({
    super.key,
    required this.analysisId,
    required this.capturedImageBytes,
    this.bodyRegion,
  });

  final String analysisId;
  final Uint8List capturedImageBytes;
  final String? bodyRegion;

  @override
  ConsumerState<TriageResultScreen> createState() => _TriageResultScreenState();
}

class _TriageResultScreenState extends ConsumerState<TriageResultScreen> {
  LesionAnalysis? _analysis;
  bool _loading = true;
  bool _exporting = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _loadAnalysis();
  }

  Future<void> _loadAnalysis() async {
    try {
      final repo = ref.read(lesionRepositoryProvider);
      await repo.initialize();
      final analysis = await repo.findById(widget.analysisId, includeImage: false);
      if (mounted) {
        setState(() {
          _analysis = analysis;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadPdf() async {
    final analysis = _analysis;
    if (analysis == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      await PdfReportService().shareReport(
        analysis: analysis.copyWithImage(widget.capturedImageBytes),
        imageBytes: widget.capturedImageBytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'Could not generate PDF'.tr}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── Delete flow ─────────────────────────────────────────────────────

  Future<void> _confirmAndDelete() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteConfirmDialog(
        bodyRegion: _analysis?.bodyRegion ?? widget.bodyRegion,
      ),
    );
    if (confirmed != true || !mounted) return;
    await _delete();
  }

  Future<void> _delete() async {
    setState(() => _deleting = true);
    final scanId = widget.analysisId;
    final analysis = _analysis;
    final wasUploaded =
        analysis != null && (analysis.pendingUpload == false);
    var pendingCloudDelete = false;

    final repo = ref.read(lesionRepositoryProvider);
    await repo.initialize();

    try {
      if (wasUploaded) {
        // The row exists in cloud — we need the API to delete the GCS
        // blob + Firestore doc before purging local SQLite.
        final token = ref.read(authControllerProvider).token?.value;
        final api = ref.read(scansApiProvider);
        if (token != null) {
          try {
            await api.deleteScan(token: token, scanId: scanId);
          } on ApiException catch (e) {
            if (e.statusCode == 0) {
              // Network / timeout → mark for retry, hide from UI.
              await repo.markPendingDeletion(scanId);
              pendingCloudDelete = true;
            } else {
              rethrow;
            }
          }
        } else {
          // No session — queue and let the orchestrator handle on next login.
          await repo.markPendingDeletion(scanId);
          pendingCloudDelete = true;
        }
      }

      if (!pendingCloudDelete) {
        await repo.delete(scanId);
      }

      // Cancel any reminders pinned to this scan so taps don't navigate
      // to a now-deleted detail.
      try {
        await ref
            .read(remindersControllerProvider.notifier)
            .removeForScan(scanId);
      } catch (e) {
        AppLogger.warning('Failed cleaning reminders: $e', tag: 'TriageDelete');
      }

      // Refresh every projection that may have shown this scan.
      ref.invalidate(scanHistoryProvider);
      ref.invalidate(lesionSummariesProvider);
      ref.invalidate(pendingScanCountProvider);

      ref.read(notificationsControllerProvider.notifier).recordScanDeleted(
            bodyRegion: analysis?.bodyRegion ?? widget.bodyRegion,
            pendingCloudDelete: pendingCloudDelete,
          );

      if (!mounted) return;
      if (pendingCloudDelete) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Removed locally — the cloud copy will be deleted once you are online.'.tr,
            ),
          ),
        );
      }
      if (context.canPop()) {
        context.pop();
      } else {
        context.goNamed('home');
      }
    } catch (e, st) {
      AppLogger.error('Delete scan failed',
          tag: 'TriageDelete', error: e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete this scan. Please try again.'.tr),
        ),
      );
      setState(() => _deleting = false);
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tutorialStep = ref.watch(tutorialControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                SkeenTopAppBar(
                  title: 'Mole detail'.tr,
                  subtitle: 'analysis mole'.tr,
                  showBack: true,
                ),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.violetaClaro,
                            ),
                          ),
                        )
                      : _buildContent(),
                ),
              ],
            ),
          ),
          if (tutorialStep == TutorialStep.reportDownload)
            TutorialCoachMark(
              isFloatingTooltip: true,
              floatingAlignment: Alignment.bottomCenter,
              title: 'Download your Report'.tr,
              description:
                  'After the analysis, download a detailed PDF report '
                  'by tapping the PDF icon below to share with your dermatologist.',
              onSkip: () =>
                  ref.read(tutorialControllerProvider.notifier).finish(),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final analysis = _analysis;
    final result = analysis?.result;
    if (analysis == null || result == null) return _buildError();

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  _buildImageCard(),
                  const SizedBox(height: 16),
                  _buildRiskCard(result, analysis),
                  const SizedBox(height: 14),
                  _buildMetadataTiles(analysis),
                  const Spacer(),
                  _buildActionRow(),
                  const SizedBox(height: 12),
                  _buildDeleteButton(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 21),
      child: GestureDetector(
        onTap: () => FullScreenImageViewer.showMemory(
          context,
          bytes: widget.capturedImageBytes,
        ),
        child: AspectRatio(
          aspectRatio: 1.5,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.violetaOscuro, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    widget.capturedImageBytes,
                    fit: BoxFit.cover,
                    errorBuilder: (_, e, st) => Container(
                      color: AppColors.indigo,
                      child: const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.hintText,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 12,
                    right: 12,
                    child: QualityVerifiedBadge(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRiskCard(InferenceResult result, LesionAnalysis analysis) {
    final riskColor = _riskColor(result.warningLevel);
    final riskTitle = _riskTitle(result.warningLevel);
    final riskDesc = _riskDescription(result);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 21),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1444),
          border: Border.all(color: const Color(0xFF2F1B66)),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child:
                      Icon(Icons.error_outline, color: riskColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(riskTitle,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            letterSpacing: -0.16,
                            color: riskColor,
                          )),
                      Text('${result.topLabel.slug} analyzed',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            letterSpacing: -0.12,
                            color: Color(0xFF6B6098),
                          )),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(riskDesc,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  height: 18 / 14,
                  color: Color(0xFFCCC3D8),
                )),
            const SizedBox(height: 16),
            Text(result.topLabel.display,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  letterSpacing: -0.16,
                  color: AppColors.violeta,
                )),
            const SizedBox(height: 12),
            ConfidenceBar(confidence: result.confidence),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataTiles(LesionAnalysis analysis) {
    final bodyRegion =
        widget.bodyRegion ?? analysis.bodyRegion ?? 'Not set'.tr;
    final capturedAt = DateFormat('MMM d, y').format(analysis.capturedAt);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 21),
      child: Row(
        children: [
          Expanded(
            child: _MetadataTile(
              icon: Icons.pin_drop_outlined,
              label: 'LOCATION'.tr,
              value: bodyRegion,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MetadataTile(
              icon: Icons.calendar_today_outlined,
              label: 'CAPTURED'.tr,
              value: capturedAt,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 21),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _exporting || _deleting ? null : _downloadPdf,
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(_exporting ? 'Generating…'.tr : 'Download PDF'.tr),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.violetaClaro,
                side: const BorderSide(color: Color(0xFF44248D)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _deleting
                  ? null
                  : () => context.canPop() ? context.pop() : context.go('/home'),
              icon: const Icon(Icons.check, size: 18),
              label: Text('Done'.tr),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.violeta,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 21),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _deleting ? null : _confirmAndDelete,
          icon: _deleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.fucsia,
                  ),
                )
              : const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppColors.fucsia,
                ),
          label: Text(
            _deleting ? 'Deleting…'.tr : 'Delete this scan'.tr,
            style: const TextStyle(color: AppColors.fucsia),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: AppColors.fucsia.withValues(alpha: 0.6),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline,
              color: AppColors.hintText, size: 48),
          const SizedBox(height: 16),
          Text('Could not load analysis'.tr,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: AppColors.violetaClaro,
              )),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/home'),
            child: Text('Go back'.tr),
          ),
        ],
      ),
    );
  }

  Color _riskColor(WarningLevel level) {
    switch (level) {
      case WarningLevel.alert:
        return AppColors.fucsia;
      case WarningLevel.caution:
        return AppColors.naranja;
      case WarningLevel.reassuring:
        return AppColors.turquesa;
    }
  }

  String _riskTitle(WarningLevel level) {
    switch (level) {
      case WarningLevel.alert:
        return 'High Risk Detected'.tr;
      case WarningLevel.caution:
        return 'Medium Risk Detected'.tr;
      case WarningLevel.reassuring:
        return 'Low Risk Detected'.tr;
    }
  }

  String _riskDescription(InferenceResult result) {
    switch (result.warningLevel) {
      case WarningLevel.alert:
        return ('High-risk patterns identified. Urgent clinical review '
                'is strongly recommended. Please consult a dermatologist.')
            .tr;
      case WarningLevel.caution:
        return ('Atypical patterns identified. Clinical review suggested '
                'based on visual analysis markers.')
            .tr;
      case WarningLevel.reassuring:
        return ('No concerning patterns identified. Continue routine '
                'self-monitoring and periodic dermatological check-ups.')
            .tr;
    }
  }
}

class _MetadataTile extends StatelessWidget {
  const _MetadataTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1444),
        border: Border.all(color: const Color(0xFF2F1B66)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.violeta.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: AppColors.violeta, size: 18),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  letterSpacing: 1.0,
                  color: Color(0xFF8B82B5),
                ),
              ),
            ],
          ),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              height: 1.3,
              color: Color(0xFFE2DFFF),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteConfirmDialog extends StatelessWidget {
  const _DeleteConfirmDialog({this.bodyRegion});
  final String? bodyRegion;

  @override
  Widget build(BuildContext context) {
    final region = bodyRegion ?? 'this scan'.tr;
    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.violetaOscuro),
      ),
      title: Row(
        children: [
          Icon(Icons.delete_outline, color: AppColors.fucsia, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Delete this scan?'.tr,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                color: AppColors.violetaClaro,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        // Template parts translated separately; the dynamic body region is
        // inlined between them so the lookup key stays language-stable.
        '${'This permanently removes the photo and analysis on'.tr} $region '
        '${'from this device and from your private cloud.'.tr} '
        '${'This action cannot be undone.'.tr}',
        style: const TextStyle(
          fontFamily: 'Poppins',
          color: AppColors.hintText,
          fontSize: 13,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel'.tr),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.fucsia),
          child: Text('Delete'.tr),
        ),
      ],
    );
  }
}

extension _LesionAnalysisExt on LesionAnalysis {
  /// Lightweight rebuild including the JPEG bytes — used by the PDF
  /// service which expects them on the aggregate.
  LesionAnalysis copyWithImage(Uint8List image) => LesionAnalysis(
        id: id,
        patientId: patientId,
        result: result,
        anchor: anchor,
        boundingBox: boundingBox,
        capturedAt: capturedAt,
        bodyRegion: bodyRegion,
        distanceCm: distanceCm,
        imageBytes: image,
        pendingUpload: pendingUpload,
        imageHash: imageHash,
      );
}
