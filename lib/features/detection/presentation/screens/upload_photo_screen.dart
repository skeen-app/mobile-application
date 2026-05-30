import 'package:skeen/core/localization/locale_controller.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/notifications/notifications_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../../../core/widgets/tutorial_controller.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/application/privacy_settings.dart';
import '../../application/providers.dart';
import '../../application/sync_orchestrator.dart';
import '../../domain/ar_geometry.dart';
import '../../domain/class_label.dart';
import '../widgets/body_region_picker.dart';
import '../widgets/not_skin_detected_dialog.dart';

/// Gallery upload variant of the Detection scan flow.
///
/// On entry: picks an image via [ImagePicker] (which on Android 13+ uses
/// the system Photo Picker — no runtime permission needed; on older Android
/// and iOS we surface a clear permission-denied state pointing the user
/// at the onboarding settings).
///
/// Once an image is selected the user picks a body region and taps
/// "Analyze". The pipeline mirrors the camera flow: center-crop to 1:1,
/// re-encode JPEG, run TFLite inference, persist encrypted, record
/// notifications, and navigate to the triage result screen.
class UploadPhotoScreen extends ConsumerStatefulWidget {
  const UploadPhotoScreen({super.key});

  @override
  ConsumerState<UploadPhotoScreen> createState() => _UploadPhotoScreenState();
}

class _UploadPhotoScreenState extends ConsumerState<UploadPhotoScreen> {
  Uint8List? _previewBytes;
  String? _bodyRegion;
  bool _picking = false;
  bool _analyzing = false;
  String? _error;
  bool _permissionBlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickFromGallery());
  }

  // ── Gallery flow ────────────────────────────────────────────────────

  Future<void> _pickFromGallery() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
      _permissionBlocked = false;
    });

    // image_picker on Android 13+ uses the Photo Picker (no perm
    // required). On older Android and on iOS the platform itself shows
    // the gallery permission prompt — but if the user permanently denied
    // it during onboarding, the picker silently returns null. We probe
    // the Photo permission first so we can render a clear "open settings"
    // state instead of an empty pop.
    final status = await Permission.photos.status;
    if (status.isPermanentlyDenied || status.isDenied) {
      final requested = await Permission.photos.request();
      if (!mounted) return;
      if (!requested.isGranted &&
          !requested.isLimited &&
          !requested.isProvisional) {
        setState(() {
          _picking = false;
          _permissionBlocked = true;
          _error = 'Gallery access is needed to upload a photo.';
        });
        return;
      }
    }

    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _error = 'Could not open the gallery: $e';
      });
      return;
    }

    if (picked == null) {
      if (!mounted) return;
      // User cancelled the picker — pop back to the previous screen so
      // the upload-photo route doesn't leave a dead-end on the stack.
      if (context.canPop()) {
        context.pop();
      } else {
        setState(() => _picking = false);
      }
      return;
    }

    final raw = await picked.readAsBytes();
    final cropped = await compute(_centerCropJpeg, raw);
    if (!mounted) return;
    setState(() {
      _previewBytes = cropped;
      _picking = false;
    });
  }

  // ── Analysis pipeline ───────────────────────────────────────────────

  Future<void> _analyze() async {
    final bytes = _previewBytes;
    if (bytes == null || _analyzing) return;

    // Capture screen size before any async gap so we don't read from
    // `context` after awaits (avoids use_build_context_synchronously).
    final screenSize = MediaQuery.of(context).size;

    final region = _bodyRegion ??
        // ignore: use_build_context_synchronously
        await BodyRegionPicker.show(context);
    if (!mounted) return;
    if (region == null) return;
    setState(() {
      _bodyRegion = region;
      _analyzing = true;
      _error = null;
    });

    try {
      // Cascade stage-1: skin / not-skin filter. Runs on the same
      // center-cropped JPEG that would feed the cancer classifier, so
      // both stages see identical inputs. A negative verdict short-
      // circuits the pipeline — no classify call, no persistence, no
      // notifications, no upload — and surfaces the educational dialog.
      final skinGate = ref.read(skinGateServiceProvider);
      await skinGate.load();
      final gateResult = await skinGate.evaluate(bytes);
      if (!gateResult.isSkin) {
        if (!mounted) return;
        setState(() => _analyzing = false);
        await NotSkinDetectedDialog.show(context);
        if (!mounted) return;
        // Send the user back to pick another photo. The picker also
        // re-renders the "Waiting for your selection…" state so the
        // rejected preview doesn't linger.
        setState(() {
          _previewBytes = null;
          _bodyRegion = null;
        });
        await _pickFromGallery();
        return;
      }

      final inference = ref.read(inferenceServiceProvider);
      await inference.load();
      final result = await inference.classify(bytes);

      final user = ref.read(authControllerProvider).user;
      final patientId = user?.id ?? 'anonymous';
      final mapper = ref.read(detectionResultMapperProvider);
      final repo = ref.read(lesionRepositoryProvider);
      await repo.initialize();

      final hash = sha256.convert(bytes).toString();
      final shortest = screenSize.shortestSide;
      final side = shortest * 0.33;
      final bbox = BoundingBox(
        left: (screenSize.width - side) / 2,
        top: (screenSize.height - side) / 2,
        width: side,
        height: side,
        frameWidth: screenSize.width,
        frameHeight: screenSize.height,
      );
      // Same sync-intent contract as the camera capture flow:
      //   cloud sync ON  → pendingUpload, attempt inline upload if online
      //   cloud sync OFF → localOnly, "Not synced" badge in history.
      final cloudSyncEnabled =
          ref.read(privacySettingsProvider).cloudSyncEnabled;
      final analysis = mapper.toAnalysis(
        result: result,
        boundingBox: bbox,
        patientId: patientId,
        bodyRegion: region,
        imageHash: hash,
        pendingUpload: cloudSyncEnabled,
        localOnly: !cloudSyncEnabled,
      );
      await repo.save(analysis, jpegBytes: bytes);

      ref.notifications.recordScanCompleted(
        scanId: analysis.id,
        bodyRegion: region,
      );
      ref.notifications.recordPredictionReady(
        scanId: analysis.id,
        label: result.topLabel.display,
        confidence: result.confidence,
      );
      if (result.warningLevel == WarningLevel.alert) {
        ref.notifications.recordHighRiskDetected(
          scanId: analysis.id,
          label: result.topLabel.display,
          confidence: result.confidence,
        );
      }

      if (cloudSyncEnabled && await _isOnline()) {
        await ref.read(syncOrchestratorProvider).uploadOne(analysis);
      }

      if (!mounted) return;
      ref.read(tutorialControllerProvider.notifier).advanceToReport();
      context.pushReplacementNamed(
        'triage-result',
        extra: {
          'analysisId': analysis.id,
          'capturedImageBytes': bytes,
          'bodyRegion': region,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error = 'Analysis failed. Please try again.';
      });
    }
  }

  Future<bool> _isOnline() async {
    final results = await Connectivity().checkConnectivity();
    return results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn,
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            SkeenTopAppBar(
              title: 'Upload a photo'.tr,
              subtitle: 'from your gallery'.tr,
              showBack: true,
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_permissionBlocked) return _buildPermissionBlocked();
    if (_picking) return _buildLoading('Opening your gallery…');
    if (_previewBytes == null) {
      return _buildLoading('Waiting for your selection…');
    }
    return _buildPreviewAndAnalyze();
  }

  Widget _buildLoading(String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.violetaClaro),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: AppColors.hintText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionBlocked() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.fucsia.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                size: 28,
                color: AppColors.fucsia,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Gallery access blocked'.tr,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: AppColors.violetaClaro,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ('Enable photo library access from system settings — ' 'the same permission you saw during onboarding.').tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                height: 1.5,
                color: AppColors.hintText,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => openAppSettings(),
              icon: const Icon(Icons.settings, size: 18),
              label: Text('Open settings'.tr),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.violeta,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _pickFromGallery,
              child: Text('Try again'.tr),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewAndAnalyze() {
    final region = _bodyRegion;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.violetaOscuro, width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.memory(
                  _previewBytes!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.hintText,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _analyzing ? null : _pickFromGallery,
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: Text('Pick a different photo'.tr),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.violetaClaro,
              side: const BorderSide(color: Color(0xFF44248D)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _RegionTile(
            region: region,
            onTap: _analyzing
                ? null
                : () async {
                    final picked = await BodyRegionPicker.show(context);
                    if (picked != null && mounted) {
                      setState(() => _bodyRegion = picked);
                    }
                  },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: AppColors.fucsia,
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _analyzing ? null : _analyze,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.violeta,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            child: _analyzing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text('Analyze photo'.tr),
          ),
        ],
      ),
    );
  }
}

class _RegionTile extends StatelessWidget {
  const _RegionTile({required this.region, required this.onTap});

  final String? region;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1444),
            border: Border.all(color: const Color(0xFF2F1B66)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.violeta.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.pin_drop_outlined,
                  color: AppColors.violeta,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Body region'.tr,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.violetaClaro,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      region ?? 'Tap to select',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: region == null
                            ? AppColors.hintText
                            : const Color(0xFFCCC3D8),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF958DA1),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top-level so it can run inside `compute()` — center-crop the picked
/// image to a 1:1 square and re-encode as JPEG. Mirrors what the camera
/// service does for live captures so model input is consistent.
Uint8List _centerCropJpeg(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;
  final side = decoded.width < decoded.height ? decoded.width : decoded.height;
  final left = (decoded.width - side) ~/ 2;
  final top = (decoded.height - side) ~/ 2;
  final cropped =
      img.copyCrop(decoded, x: left, y: top, width: side, height: side);
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
}
