import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../application/detection_controller.dart';
import '../../domain/capture_quality.dart';
import '../../infrastructure/scan_camera_service.dart';
import '../widgets/ar_distance_ring.dart';
import '../widgets/ar_reticle_overlay.dart';
import '../widgets/camera_controls.dart';
import '../widgets/floating_diagnosis_label.dart';
import '../widgets/scan_capture_button.dart';
import '../widgets/scan_quality_hint.dart';

/// AR-AI bridge screen — Tasks 1, 2 and 3 wired together.
///
/// Layout (top → bottom):
///   • Skeen top app bar
///   • Camera preview (existing `camera` plugin) with overlays:
///       - AR reticle (corner brackets)
///       - 3D Target Ring driven by [DetectionController.distance]
///       - Floating diagnosis label, anchored to the lesion via
///         CoordinateTranslator.anchorToScreen on every frame
///       - Right-edge zoom slider, top-right flash toggle
///   • Quality hint card + capture row (gallery / shutter / scan again)
///
/// The native ARSession runs in parallel via SkeenArPlugin (Kotlin/Swift)
/// to feed depth + hit-test results; the Flutter side never owns the
/// ARView render loop — keeping inference non-blocking and the camera
/// preview at native frame rate.
class ArScanScreen extends ConsumerStatefulWidget {
  const ArScanScreen({super.key});

  @override
  ConsumerState<ArScanScreen> createState() => _ArScanScreenState();
}

class _ArScanScreenState extends ConsumerState<ArScanScreen>
    with WidgetsBindingObserver {
  final ScanCameraService _camera = ScanCameraService();
  StreamSubscription<double>? _brightnessSub;
  Timer? _anchorProjector;

  CaptureQuality _quality = CaptureQuality.initial;
  Offset? _anchorScreenPosition;
  Size _previewSize = Size.zero;
  String? _initError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _camera.initialize();
      _brightnessSub = _camera.brightness.listen((b) {
        if (!mounted) return;
        setState(() => _quality = CaptureQuality.fromBrightness(b));
      });
      // Re-project the world anchor onto screen coords every 33 ms (~30
      // fps) so the floating label tracks the lesion as the phone moves.
      _anchorProjector = Timer.periodic(
        const Duration(milliseconds: 33),
        (_) => _refreshAnchorPosition(),
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (kDebugMode) debugPrint('Camera init failed: $e');
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  Future<void> _refreshAnchorPosition() async {
    final state = ref.read(detectionControllerProvider);
    if (state.anchor == null) {
      if (_anchorScreenPosition != null) {
        setState(() => _anchorScreenPosition = null);
      }
      return;
    }
    final controller = ref.read(detectionControllerProvider.notifier);
    final pt = await controller.projectAnchorToScreen();
    if (!mounted) return;
    if (pt != null && _previewSize != Size.zero) {
      // Plugin returns normalized [0,1] coords — map to local pixels.
      final px = Offset(pt.dx * _previewSize.width,
          pt.dy * _previewSize.height);
      setState(() => _anchorScreenPosition = px);
    } else {
      setState(() => _anchorScreenPosition = null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _camera.controller;
    if (controller == null) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _camera.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _bootstrap();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _brightnessSub?.cancel();
    _anchorProjector?.cancel();
    _camera.dispose();
    super.dispose();
  }

  Future<void> _handleCapture() async {
    final controller = ref.read(detectionControllerProvider.notifier);
    final state = ref.read(detectionControllerProvider);

    // After a presented result, the same shutter resets and arms again.
    if (state.phase == DetectionPhase.presented) {
      await controller.reset();
      return;
    }

    // Pull JPEG from the camera plugin; the native ARSession reads its
    // own frames in parallel for depth/anchor.
    final file = await _camera.capture();
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await _classifyBytes(bytes);
  }

  Future<void> _classifyBytes(Uint8List bytes) async {
    final ctl = ref.read(detectionControllerProvider.notifier);
    await ctl.captureWithBytes(bytes: bytes, previewSize: _previewSize);
  }

  Future<void> _handleZoom(double v) async {
    await _camera.controller?.setZoomLevel(v);
    await ref.read(detectionControllerProvider.notifier).setZoom(v);
  }

  Future<void> _handleFlash() async {
    final state = ref.read(detectionControllerProvider);
    final next = !state.flashOn;
    await _camera.controller?.setFlashMode(
      next ? FlashMode.torch : FlashMode.off,
    );
    await ref.read(detectionControllerProvider.notifier).setFlash(next);
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
            const SkeenTopAppBar(
              title: 'Scan a mole',
              subtitle: 'AR-AI guided · ARKit / ARCore',
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
          return Stack(
            fit: StackFit.expand,
            children: [
              if (_initError != null)
                _CameraUnavailable(message: _initError!)
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
              ArDistanceRing(distance: detection.distance),
              if (detection.result != null)
                _AnchoredLabel(
                  position: _anchorScreenPosition ??
                      Offset(_previewSize.width / 2,
                          _previewSize.height * 0.28),
                  child: FloatingDiagnosisLabel(result: detection.result!),
                ),
              Positioned(
                top: 16,
                right: 16,
                child: CameraFlashButton(
                  isOn: detection.flashOn,
                  onTap: _handleFlash,
                ),
              ),
              Positioned(
                top: 70,
                right: 16,
                bottom: 16,
                child: CameraZoomSlider(
                  value: detection.zoom,
                  onChanged: _handleZoom,
                ),
              ),
              if (detection.phase == DetectionPhase.analyzing)
                Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.violetaClaro,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Running on-device analysis…',
                          style: TextStyle(
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
          );
        },
      ),
    );
  }

  Widget _buildBottomControls(DetectionState detection) {
    final isPresented = detection.phase == DetectionPhase.presented;
    final isBusy = detection.phase == DetectionPhase.capturing ||
        detection.phase == DetectionPhase.analyzing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          ScanQualityHint(quality: _quality),
          const SizedBox(height: 16),
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
              _SecondaryAction(
                icon: isPresented ? Icons.refresh : Icons.tune_rounded,
                label: isPresented ? 'Scan again' : 'Calibrate',
                onTap: () async {
                  if (isPresented) {
                    await ref
                        .read(detectionControllerProvider.notifier)
                        .reset();
                  } else {
                    context.pushNamed('calibrate');
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnchoredLabel extends StatelessWidget {
  const _AnchoredLabel({required this.position, required this.child});
  final Offset position;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 130,
      top: (position.dy - 80).clamp(0.0, double.infinity),
      child: child,
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
  const _CameraUnavailable({required this.message});
  final String message;

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
          const Text(
            'Camera unavailable',
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
        ],
      ),
    );
  }
}
