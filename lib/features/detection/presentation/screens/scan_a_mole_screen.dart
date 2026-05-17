import 'package:skeen/core/localization/locale_controller.dart';
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../../../core/widgets/tutorial_controller.dart';
import '../../../patient/application/lesion_summary_providers.dart';
import '../../../patient/application/scan_history_providers.dart';
import '../../application/detection_controller.dart';
import '../../application/providers.dart';
import '../../application/readiness_evaluator.dart';
import '../../application/sync_orchestrator.dart';
import '../../domain/capture_quality.dart';
import '../../infrastructure/scan_camera_service.dart';
import '../widgets/ar_reticle_overlay.dart';
import '../widgets/body_region_picker.dart';
import '../widgets/camera_controls.dart';
import '../widgets/floating_diagnosis_label.dart';
import '../widgets/readiness_checklist_overlay.dart';
import '../widgets/scan_capture_button.dart';

/// Fallback scan screen for devices without AR/depth sensor support.
/// Integrates full inline TFLite inference via DetectionController — same
/// pipeline as ArScanScreen, but without AR anchor positioning.
/// The floating diagnosis label centers in the viewport instead.
class ScanAMoleScreen extends ConsumerStatefulWidget {
  const ScanAMoleScreen({super.key});

  @override
  ConsumerState<ScanAMoleScreen> createState() => _ScanAMoleScreenState();
}

class _ScanAMoleScreenState extends ConsumerState<ScanAMoleScreen>
    with WidgetsBindingObserver {
  late final ScanCameraService _camera;
  late final ReadinessEvaluator _evaluator;
  StreamSubscription<CaptureReadiness>? _readinessSub;

  CaptureQuality _quality = CaptureQuality.initial;
  CaptureReadiness _readiness = CaptureReadiness.initializing;
  bool _showShutterFlash = false;
  String? _initError;
  bool _permissionPermanentlyDenied = false;
  Size _previewSize = Size.zero;

  // Pinch-to-zoom state
  double _currentZoom = 1.0;
  double _maxZoom = 5.0;
  double _baseZoom = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camera = ref.read(scanCameraServiceProvider);
    _evaluator = ref.read(readinessEvaluatorProvider);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // Camera permission gate: the camera plugin throws when permission
      // is denied. Re-prompting here covers the new-user case where the
      // permission was declined at onboarding — the user grants now and
      // the camera lights up immediately, without needing to navigate
      // away and back.
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        setState(() {
          _permissionPermanentlyDenied = status.isPermanentlyDenied;
          _initError = status.isPermanentlyDenied
              ? 'Camera access is blocked. Enable it from system settings to scan.'
                  .tr
              : 'Camera permission is required to scan.'.tr;
        });
        return;
      }

      await _camera.initialize();
      _maxZoom = await _camera.getMaxZoom();

      // Start readiness (no AR distance in fallback — defaults to OK)
      _evaluator.start();

      _readinessSub = _evaluator.readiness.listen((r) {
        if (!mounted) return;
        setState(() {
          _readiness = r;
          _quality = r.lighting;
        });
        ref.read(detectionControllerProvider.notifier).updateReadiness(r);
      });

      if (mounted) {
        setState(() {
          _initError = null;
          _permissionPermanentlyDenied = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Camera init failed: $e');
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  /// Empty-state retry CTA — opens system settings when the permission is
  /// permanently denied (OS won't show its dialog again), otherwise reruns
  /// the bootstrap which will re-request permission.
  Future<void> _retryBootstrap() async {
    if (_permissionPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    if (mounted) {
      setState(() {
        _initError = null;
        _permissionPermanentlyDenied = false;
      });
    }
    await _bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _camera.controller;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // Only release the camera when it was actually live. Skipping this
      // when controller is null also avoids a NoSuchMethodError on a
      // bootstrap that never reached initialize() (permission denied).
      if (controller != null) _camera.dispose();
    } else if (state == AppLifecycleState.resumed) {
      // Always retry on resume — handles BOTH the normal background-
      // foreground cycle (reattach the camera) AND the post-permission-
      // dialog case where a previous bootstrap aborted with _initError.
      _bootstrap();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _readinessSub?.cancel();
    _camera.dispose();
    super.dispose();
  }

  /// Capture pipeline — routed entirely through DetectionController which
  /// handles AE/AF lock, capture, inference, persistence, and stream restart.
  Future<void> _handleCapture() async {
    final detection = ref.read(detectionControllerProvider);

    if (detection.phase == DetectionPhase.presented) {
      _navigateToTriage(detection);
      return;
    }

    setState(() => _showShutterFlash = true);
    Future.delayed(const Duration(milliseconds: 140), () {
      if (mounted) setState(() => _showShutterFlash = false);
    });

    final controller = ref.read(detectionControllerProvider.notifier);
    await controller.captureAndClassify(previewSize: _previewSize);
  }

  Future<void> _navigateToTriage(DetectionState state) async {
    if (state.savedAnalysisId == null || state.capturedImageBytes == null) {
      return;
    }
    final region = await BodyRegionPicker.show(context);
    if (!mounted) return;
    if (region != null) {
      await ref
          .read(lesionRepositoryProvider)
          .updateBodyRegion(state.savedAnalysisId!, region);
      ref.invalidate(scanHistoryProvider);
      ref.invalidate(lesionSummariesProvider);
      ref.read(syncOrchestratorProvider).syncNow(reason: 'region-picked');
    }
    if (!mounted) return;
    ref.read(tutorialControllerProvider.notifier).advanceToReport();
    context.pushReplacementNamed(
      'triage-result',
      extra: {
        'analysisId': state.savedAnalysisId!,
        'capturedImageBytes': state.capturedImageBytes!,
        'bodyRegion': region,
      },
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final newZoom = (_baseZoom * details.scale).clamp(1.0, _maxZoom);
    if ((newZoom - _currentZoom).abs() > 0.05) {
      setState(() => _currentZoom = newZoom);
      // Dispatch through controller — handles both camera + AR session
      ref.read(detectionControllerProvider.notifier).setZoom(newZoom);
    }
  }

  /// Flash toggle — dispatches through DetectionController which sends to
  /// both the camera plugin (physical torch) and AR session (native sync).
  Future<void> _toggleFlash() async {
    final state = ref.read(detectionControllerProvider);
    await ref.read(detectionControllerProvider.notifier).setFlash(!state.flashOn);
  }

  @override
  Widget build(BuildContext context) {
    final detection = ref.watch(detectionControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SkeenTopAppBar(
              title: 'Scan a mole'.tr,
              subtitle: 'AI analysis in seconds'.tr,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _buildPreviewSurface(detection),
                ),
              ),
            ),
            _buildBottomControls(detection),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSurface(DetectionState detection) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.indigo,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF291859), width: 2),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _previewSize = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_initError != null)
                  _CameraUnavailable(
                    message: _initError!,
                    onRetry: _retryBootstrap,
                    permanentlyDenied: _permissionPermanentlyDenied,
                  )
                else if (_camera.isReady)
                  _FittedPreview(controller: _camera.controller!)
                else
                  const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.violetaClaro,
                      ),
                    ),
                  ),
                ArReticleOverlay(quality: _quality),

                // Subtle disclaimer: AR is not available on this device.
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        border: Border.all(
                          color: AppColors.violetaOscuro.withValues(alpha: 0.6),
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 12,
                            color: AppColors.hintText,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'AR not supported on this device'.tr,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w500,
                              fontSize: 10.5,
                              letterSpacing: 0.1,
                              color: AppColors.hintText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Floating diagnosis label (centered, no AR anchor)
                if (detection.result != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 80),
                      child: FloatingDiagnosisLabel(
                        result: detection.result!,
                        onTap: () => _navigateToTriage(detection),
                      ),
                    ),
                  ),

                // Readiness checklist
                if (detection.phase == DetectionPhase.ready ||
                    detection.phase == DetectionPhase.initializing)
                  ReadinessChecklistOverlay(readiness: _readiness),

                // Flash toggle
                Positioned(
                  top: 16,
                  right: 16,
                  child: CameraFlashButton(
                    isOn: detection.flashOn,
                    onTap: _toggleFlash,
                  ),
                ),

                // Zoom indicator
                if (_currentZoom > 1.05)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.background.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_currentZoom.toStringAsFixed(1)}×',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: AppColors.violetaClaro,
                        ),
                      ),
                    ),
                  ),

                // Shutter flash
                AnimatedOpacity(
                  opacity: _showShutterFlash ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Container(color: Colors.white),
                ),

                // Analyzing / uploading overlay
                if (detection.phase == DetectionPhase.analyzing ||
                    detection.phase == DetectionPhase.standardizing ||
                    detection.phase == DetectionPhase.uploading)
                  Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.violetaClaro,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            switch (detection.phase) {
                              DetectionPhase.standardizing =>
                                'Standardizing image…',
                              DetectionPhase.uploading =>
                                'Uploading to cloud…',
                              _ => 'Running on-device analysis…',
                            },
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: AppColors.violetaClaro,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomControls(DetectionState detection) {
    final isPresented = detection.phase == DetectionPhase.presented;
    final isBusy = detection.phase == DetectionPhase.capturing ||
        detection.phase == DetectionPhase.analyzing ||
        detection.phase == DetectionPhase.standardizing ||
        detection.phase == DetectionPhase.uploading;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SecondaryAction(
                icon: Icons.photo_library_outlined,
                label: 'Gallery',
                onTap: () => context.pushNamed('upload-photo'),
              ),
              ScanCaptureButton(
                quality: _quality,
                isCapturing: isBusy,
                onPressed: _handleCapture,
              ),
              if (isPresented)
                _SecondaryAction(
                  icon: Icons.refresh,
                  label: 'Scan again',
                  onTap: () async {
                    await ref
                        .read(detectionControllerProvider.notifier)
                        .reset();
                  },
                )
              else
                const SizedBox(width: 60),
            ],
          ),
        ],
      ),
    );
  }
}

class _FittedPreview extends StatelessWidget {
  const _FittedPreview({required this.controller});
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.value.previewSize;
    if (preview == null) return CameraPreview(controller);
    final aspect = preview.height / preview.width;
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: 100,
        height: 100 / aspect,
        child: CameraPreview(controller),
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.indigo.withValues(alpha: 0.65),
                border: Border.all(color: AppColors.violetaOscuro),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.violetaClaro, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                fontSize: 11,
                letterSpacing: -0.11,
                color: AppColors.hintText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({
    required this.message,
    this.onRetry,
    this.permanentlyDenied = false,
  });

  final String message;
  final VoidCallback? onRetry;
  // When true the retry CTA opens system settings instead of re-prompting
  // (the OS won't show its native dialog after two denials).
  final bool permanentlyDenied;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: AppColors.hintText,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            'Camera unavailable'.tr,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: AppColors.violetaClaro,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: AppColors.hintText,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: Icon(
                permanentlyDenied ? Icons.settings_outlined : Icons.refresh,
                size: 18,
              ),
              label: Text(
                permanentlyDenied
                    ? 'Open settings'.tr
                    : 'Grant camera access'.tr,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.violeta,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
