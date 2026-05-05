import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../../core/theme/app_colors.dart';
import '../../application/providers.dart';
import '../../domain/class_label.dart';
import '../../domain/inference_result.dart';
import '../../domain/lesion_analysis.dart';
import '../widgets/confidence_bar.dart';
import '../widgets/quality_verified_badge.dart';

/// Triage result screen matching Figma "tamizaje" (node 153:549).
///
/// Receives [analysisId] and [capturedImageBytes] via route arguments.
/// Displays:
///   1. Captured image with Quality Verified badge
///   2. Risk assessment card (level + class + description + confidence bar)
///   3. Metadata tiles (body region + capture date)
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

  @override
  void initState() {
    super.initState();
    _loadAnalysis();
  }

  Future<void> _loadAnalysis() async {
    try {
      final repo = ref.read(lesionRepositoryProvider);
      await repo.initialize();
      final analysis =
          await repo.findById(widget.analysisId, includeImage: false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.violetaClaro),
                ),
              )
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final analysis = _analysis;
    final result = analysis?.result;
    if (analysis == null || result == null) {
      return _buildError();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          _buildImageCard(),
          const SizedBox(height: 16),
          _buildRiskCard(result, analysis),
          const SizedBox(height: 16),
          _buildMetadataTiles(analysis),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.canPop() ? context.pop() : null,
            child: Container(
              width: 27,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFF9057F0),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Mole detail',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  letterSpacing: -0.16,
                  color: Color(0xFFF5F5F5),
                ),
              ),
              Text(
                'analysis mole',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                  letterSpacing: -0.11,
                  color: Color(0x87EDE9FE), // rgba(237,233,254,0.53)
                ),
              ),
            ],
          ),
          const Spacer(),
          // Constellation decoration (from Figma)
          const Text(
            '✧ *˚',
            style: TextStyle(
              fontSize: 18,
              color: Color(0x59EDE9FE), // rgba(237,233,254,0.35)
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 21),
      child: Container(
        height: 265,
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
            // Risk level header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.error_outline,
                    color: riskColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        riskTitle,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          letterSpacing: -0.16,
                          color: riskColor,
                        ),
                      ),
                      Text(
                        '${result.topLabel.slug} analyzed',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          letterSpacing: -0.12,
                          color: Color(0xFF6B6098),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Description
            Text(
              riskDesc,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
                fontSize: 14,
                height: 18 / 14,
                color: Color(0xFFCCC3D8),
              ),
            ),
            const SizedBox(height: 16),
            // Class label
            Text(
              result.topLabel.display,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 16,
                letterSpacing: -0.16,
                color: AppColors.violeta,
              ),
            ),
            const SizedBox(height: 12),
            // Confidence bar
            ConfidenceBar(confidence: result.confidence),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataTiles(LesionAnalysis analysis) {
    final bodyRegion = widget.bodyRegion ?? analysis.bodyRegion ?? 'Not set';
    final capturedAt = DateFormat('MMMM d, y').format(analysis.capturedAt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 21),
      child: Row(
        children: [
          Expanded(
            child: _MetadataTile(
              icon: Icons.pin_drop_outlined,
              label: 'Location: $bodyRegion',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MetadataTile(
              icon: Icons.calendar_today_outlined,
              label: 'Captured: $capturedAt',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            color: AppColors.hintText,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            'Could not load analysis',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: AppColors.violetaClaro,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/home'),
            child: const Text('Go back'),
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
        return 'High Risk Detected';
      case WarningLevel.caution:
        return 'Medium Risk Detected';
      case WarningLevel.reassuring:
        return 'Low Risk Detected';
    }
  }

  String _riskDescription(InferenceResult result) {
    switch (result.warningLevel) {
      case WarningLevel.alert:
        return 'High-risk patterns identified. Urgent clinical review '
            'is strongly recommended. Please consult a dermatologist.';
      case WarningLevel.caution:
        return 'Atypical patterns identified. Clinical review suggested '
            'based on visual analysis markers.';
      case WarningLevel.reassuring:
        return 'No concerning patterns identified. Continue routine '
            'self-monitoring and periodic dermatological check-ups.';
    }
  }
}

class _MetadataTile extends StatelessWidget {
  const _MetadataTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 69,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1444),
        border: Border.all(color: const Color(0xFF2F1B66)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.violeta, size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: 8,
              color: Color(0xFFCCC3D8),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
