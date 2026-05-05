import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../application/detection_controller.dart';
import '../../application/providers.dart';
import '../../application/readiness_evaluator.dart';
import '../../domain/capture_quality.dart';
import '../../infrastructure/scan_camera_service.dart';
import '../widgets/ar_distance_ring.dart';
import '../widgets/ar_reticle_overlay.dart';
import '../widgets/body_region_picker.dart';
import '../widgets/camera_controls.dart';
import '../widgets/floating_diagnosis_label.dart';
import '../widgets/readiness_checklist_overlay.dart';
import '../widgets/scan_capture_button.dart';

/// AR-AI bridge screen — full pipeline:
/// assisted capture → TFLite inference → AR-anchored popup → triage result.
///
/// Layout (top → bottom):
///   • Skeen top app bar
///   • Camera preview with overlays:
///       - AR reticle (corner brackets)
///       - 3D Target Ring (distance)
///       - Floating diagnosis label (anchored to lesion after inference)
///       - Readiness checklist overlay (4-item quality gate)
///       - Flash toggle, pinch-to-zoom
///   • Capture row (gallery / shutter / scan again)
class ArScanScreen extends ConsumerStatefulWidget {
  const ArScanScreen({super.key});

  @override
  ConsumerState<ArScanScreen> createState() => _ArScanScreenState();
}

class _ArScanScreenState extends ConsumerState<ArScanScreen>
    with WidgetsBindingObserver {
  late final ScanCameraService _camera;
  late final ReadinessEvaluator _evaluator;
  StreamSubscription<CaptureReadiness>? _readinessSub;
  Timer? _anchorProjector;

  CaptureQuality _quality = CaptureQuality.initial;
  CaptureReadiness _readiness = CaptureReadiness.initializing;
  Offset? _anchorScreenPosition;
  Size _previewSize = Size.zero;
  String? _initError;

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
      if (defaultTargetPlatform != TargetPlatform.android) {
        await _camera.initialize();
        _maxZoom = await _camera.getMaxZoom();
      } else {
        _maxZoom = 1.0;
      }

      // Start readiness evaluation with AR distance stream
      final arSession = ref.read(arSessionProvider);
      
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Fast-track readiness on Android since native ARCore handles camera
        Future.microtask(() {
          if (!mounted) return;
          setState(() {
            _readiness = CaptureReadiness(
              lighting: CaptureQuality.fromBrightness(200),
              focus: true,
              distance: true,
              isStable: true,
            );
            _quality = _readiness.lighting;
          });
          ref.read(detectionControllerProvider.notifier).updateReadiness(_readiness);
        });
      } else {
        _evaluator.start(distanceStream: arSession.distance);
        _readinessSub = _evaluator.readiness.listen((r) {
          if (!mounted) return;
          setState(() {
            _readiness = r;
            _quality = r.lighting;
          });
          // Sync to detection controller state
          ref.read(detectionControllerProvider.notifier).updateReadiness(r);
        });
      }

      // Re-project the world anchor onto screen coords every 33 ms (~30 fps)
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

  /// Per-frame projection: world anchor → screen pixel.
  /// Called at 30 fps by the timer. The heavy work (method channel call)
  /// is async so it doesn't block the render thread.
  Future<void> _refreshAnchorPosition() async {
    final state = ref.read(detectionControllerProvider);
    if (state.anchor == null) {
      if (_anchorScreenPosition != null && mounted) {
        setState(() => _anchorScreenPosition = null);
      }
      return;
    }
    if (_previewSize == Size.zero) return;

    final controller = ref.read(detectionControllerProvider.notifier);
    final px = await controller.projectAnchorToScreen(
        previewSize: _previewSize);
    if (!mounted) return;

    if (px != null) {
      setState(() => _anchorScreenPosition = px);
    } else {
      // Anchor behind camera or off-screen — fall back to center
      setState(() => _anchorScreenPosition = null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (defaultTargetPlatform == TargetPlatform.android) return;
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
    _readinessSub?.cancel();
    _anchorProjector?.cancel();
    _camera.dispose();
    super.dispose();
  }

  /// Capture pipeline — all flash/zoom/AE logic is handled by the
  /// DetectionController, which dispatches to both camera plugin and AR
  /// session internally.
  Future<void> _handleCapture() async {
    final detection = ref.read(detectionControllerProvider);

    if (detection.phase == DetectionPhase.presented) {
      _navigateToTriage(detection);
      return;
    }

    final controller = ref.read(detectionControllerProvider.notifier);
    await controller.captureAndClassify(previewSize: _previewSize);
  }

  Future<void> _navigateToTriage(DetectionState state) async {
    if (state.savedAnalysisId == null || state.capturedImageBytes == null) {
      return;
    }

    final region = await BodyRegionPicker.show(context);
    if (!mounted) return;

    context.pushNamed(
      'triage-result',
      extra: {
        'analysisId': state.savedAnalysisId!,
        'capturedImageBytes': state.capturedImageBytes!,
        'bodyRegion': region,
      },
    );
  }

  // ── Pinch-to-zoom handlers ────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final newZoom = (_baseZoom * details.scale).clamp(1.0, _maxZoom);
    if ((newZoom - _currentZoom).abs() > 0.05) {
      setState(() => _currentZoom = newZoom);
      // Dispatch through controller — it handles both camera + AR session
      ref.read(detectionControllerProvider.notifier).setZoom(newZoom);
    }
  }

  /// Flash toggle — dispatches through DetectionController which sends to
  /// both the camera plugin (physical torch) and AR session (native sync).
  Future<void> _handleFlash() async {
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
          return GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_initError != null)
                  _CameraUnavailable(message: _initError!)
                else if (defaultTargetPlatform == TargetPlatform.android)
                  const AndroidView(
                    viewType: 'skeen.detection/ar_view',
                    creationParamsCodec: StandardMessageCodec(),
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
                ArDistanceRing(distance: detection.distance),

                // Floating diagnosis label — anchored to the lesion
                if (detection.result != null)
                  _AnchoredLabel(
                    position: _anchorScreenPosition ??
                        Offset(_previewSize.width / 2,
                            _previewSize.height * 0.28),
                    anchorPoint: _anchorScreenPosition,
                    child: FloatingDiagnosisLabel(
                      result: detection.result!,
                      onTap: () => _navigateToTriage(detection),
                    ),
                  ),

                // Readiness checklist (hide during analysis/presented)
                if (detection.phase == DetectionPhase.ready ||
                    detection.phase == DetectionPhase.initializing)
                  ReadinessChecklistOverlay(readiness: _readiness),

                // Flash toggle
                Positioned(
                  top: 16,
                  right: 16,
                  child: CameraFlashButton(
                    isOn: detection.flashOn,
                    onTap: _handleFlash,
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

                // Analyzing overlay
                if (detection.phase == DetectionPhase.analyzing ||
                    detection.phase == DetectionPhase.standardizing)
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
                            detection.phase == DetectionPhase.standardizing
                                ? 'Standardizing image…'
                                : 'Running on-device analysis…',
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
        detection.phase == DetectionPhase.standardizing;

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

/// Positions the label over the anchor point, with a "stem line" connecting
/// the popup to the lesion anchor.
class _AnchoredLabel extends StatelessWidget {
  const _AnchoredLabel({
    required this.position,
    required this.child,
    this.anchorPoint,
  });

  final Offset position;
  final Widget child;
  final Offset? anchorPoint;

  @override
  Widget build(BuildContext context) {
    // Position the label above and slightly left of the anchor
    final labelX = (position.dx - 130).clamp(8.0, double.infinity);
    final labelY = (position.dy - 100).clamp(8.0, double.infinity);

    return Stack(
      children: [
        // Stem line from anchor to label (if we have a real AR anchor)
        if (anchorPoint != null)
          Positioned.fill(
            child: CustomPaint(
              painter: _StemLinePainter(
                from: anchorPoint!,
                to: Offset(labelX + 130, labelY + 80),
              ),
            ),
          ),
        // The label itself
        Positioned(
          left: labelX,
          top: labelY,
          child: child,
        ),
      ],
    );
  }
}

/// Paints a thin dashed line from the anchor point to the popup.
class _StemLinePainter extends CustomPainter {
  _StemLinePainter({required this.from, required this.to});
  final Offset from;
  final Offset to;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.violeta.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Draw a small circle at the anchor point
    canvas.drawCircle(from, 4, paint..style = PaintingStyle.fill);

    // Draw the stem line
    paint.style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..lineTo(to.dx, to.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_StemLinePainter old) =>
      old.from != from || old.to != to;
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
