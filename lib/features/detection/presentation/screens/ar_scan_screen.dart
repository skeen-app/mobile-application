import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../application/detection_controller.dart';
import '../../application/providers.dart';
import '../../domain/ar_geometry.dart';
import '../../domain/capture_quality.dart';
import '../../infrastructure/ar_session_service.dart';
import '../widgets/ar_distance_ring.dart';
import '../widgets/ar_reticle_overlay.dart';
import '../widgets/body_region_picker.dart';
import '../widgets/camera_controls.dart';
import '../widgets/floating_diagnosis_label.dart';
import '../widgets/readiness_checklist_overlay.dart';
import '../widgets/scan_capture_button.dart';
import '../widgets/scene_mapping_overlay.dart';

/// AR-AI bridge screen.
///
/// Pipeline:
///   1. Mount the native AR PlatformView (ARCore on Android · RealityKit on iOS).
///   2. Run a *scene-mapping* phase: assistive popups guide the user while
///      ARCore / ARKit detects planes and the readiness gate stabilizes.
///   3. Capture → standardize → TFLite inference → raycast against the
///      detected plane → create a tracked AR Anchor at the lesion.
///   4. Project the anchor each frame so the diagnosis label sticks to the
///      skin Pokémon-GO-style. The label hides when the anchor leaves the
///      camera frustum and re-appears when it returns.
class ArScanScreen extends ConsumerStatefulWidget {
  const ArScanScreen({super.key});

  @override
  ConsumerState<ArScanScreen> createState() => _ArScanScreenState();
}

class _ArScanScreenState extends ConsumerState<ArScanScreen>
    with WidgetsBindingObserver {
  Timer? _anchorProjector;
  Timer? _mappingTicker;
  StreamSubscription<ArFrameInfo>? _frameInfoSub;
  StreamSubscription<CaptureDistance>? _distanceSub;
  CaptureDistance _lastDistance = const CaptureDistance.unknown();
  String _lastTracking = 'UNKNOWN';
  int _trackingStableMs = 0;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);

  Offset? _anchorScreenPosition;
  Size _previewSize = Size.zero;
  String? _initError;
  int _mappingElapsedMs = 0;
  int _readyStreakMs = 0;
  static const _mappingMinMs = 2000;
  static const _readyStreakRequiredMs = 800;

  // Pinch-to-zoom state
  double _currentZoom = 1.0;
  static const double _maxZoom = 5.0;
  double _baseZoom = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // The DetectionController.bootstrap (run by the autoDispose provider)
      // already calls _session.start() — no need to duplicate that here.
      // We simply install our local timers.
      _startMappingTicker();
      _startAnchorProjector();
      _listenFrameInfo();
    } catch (e) {
      if (kDebugMode) debugPrint('AR bootstrap failed: $e');
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  /// Wire the native AR frame stream (ARCore lightEstimate + tracking
  /// state) into the readiness gate so the capture button reacts to real
  /// scene conditions instead of a static seed.
  ///
  /// Mapping:
  ///   • `lighting` ← `lightEstimate.pixelIntensity * 255` (0–255 scale)
  ///   • `distance` ← AR depth stream (existing controller wiring)
  ///   • `focus` and `isStable` ← `camera.trackingState == TRACKING`
  ///     debounced for 600 ms (ARCore can't track when the image is
  ///     out-of-focus or shaky, so this collapses both signals well).
  void _listenFrameInfo() {
    final session = ref.read(arSessionProvider);
    final concrete = session is ArSessionService ? session : null;
    _distanceSub = session.distance.listen((d) {
      _lastDistance = d;
      _emitReadiness();
    });
    _frameInfoSub = concrete?.frameInfo.listen((info) {
      final now = DateTime.now();
      final dt = now.difference(_lastFrameAt).inMilliseconds.clamp(0, 500);
      _lastFrameAt = now;
      if (info.isTracking && _lastTracking == 'TRACKING') {
        _trackingStableMs += dt;
      } else {
        _trackingStableMs = info.isTracking ? dt : 0;
      }
      _lastTracking = info.tracking;
      _emitReadiness(brightness: info.brightness);
    });
  }

  double _seenBrightness = 0;
  void _emitReadiness({double? brightness}) {
    if (brightness != null) _seenBrightness = brightness;
    final lighting = _seenBrightness > 0
        ? CaptureQuality.fromBrightness(_seenBrightness)
        : CaptureQuality.initial;
    final tracking = _lastTracking == 'TRACKING';
    final stable = tracking && _trackingStableMs >= 600;
    final readiness = CaptureReadiness(
      lighting: lighting,
      focus: tracking,
      distance: _lastDistance.isInAcceptableRange ||
          // No depth sensor → trust the user's framing.
          (!_lastDistance.isKnown && tracking),
      isStable: stable,
    );
    if (!mounted) return;
    ref.read(detectionControllerProvider.notifier).updateReadiness(readiness);
  }

  void _startMappingTicker() {
    _mappingTicker?.cancel();
    _mappingElapsedMs = 0;
    _readyStreakMs = 0;
    _mappingTicker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final detection = ref.read(detectionControllerProvider);
      if (detection.phase != DetectionPhase.mapping) return;

      setState(() => _mappingElapsedMs += 100);

      final readyNow = detection.readiness.isReady;
      _readyStreakMs = readyNow ? _readyStreakMs + 100 : 0;

      if (_mappingElapsedMs >= _mappingMinMs &&
          _readyStreakMs >= _readyStreakRequiredMs) {
        ref.read(detectionControllerProvider.notifier).completeMapping();
      }
    });
  }

  void _startAnchorProjector() {
    _anchorProjector?.cancel();
    // ~30 fps is enough; reading from the Dart side via channel adds latency
    // already, so going faster doesn't help.
    _anchorProjector = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => _refreshAnchorPosition(),
    );
  }

  /// Per-frame projection: world anchor → screen pixel.
  /// When the projection returns null (anchor behind camera, off-screen, or
  /// tracking lost), [_anchorScreenPosition] is cleared and the floating
  /// label is hidden — the popup re-appears the moment the anchor is
  /// visible again.
  Future<void> _refreshAnchorPosition() async {
    final state = ref.read(detectionControllerProvider);
    if (state.anchor == null || _previewSize == Size.zero) {
      if (_anchorScreenPosition != null && mounted) {
        setState(() => _anchorScreenPosition = null);
      }
      return;
    }
    final controller = ref.read(detectionControllerProvider.notifier);
    final px = await controller.projectAnchorToScreen(previewSize: _previewSize);
    if (!mounted) return;
    if (px != _anchorScreenPosition) {
      setState(() => _anchorScreenPosition = px);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Native AR session is paused/resumed by the host Activity / SceneDelegate.
    // Nothing to do here for now.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mappingTicker?.cancel();
    _anchorProjector?.cancel();
    _frameInfoSub?.cancel();
    _distanceSub?.cancel();
    super.dispose();
  }

  Future<void> _handleCapture() async {
    final detection = ref.read(detectionControllerProvider);
    if (detection.phase == DetectionPhase.presented) {
      _navigateToTriage(detection);
      return;
    }
    if (detection.phase != DetectionPhase.ready) return;
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

  void _onScaleStart(ScaleStartDetails _) => _baseZoom = _currentZoom;
  void _onScaleUpdate(ScaleUpdateDetails details) {
    final newZoom = (_baseZoom * details.scale).clamp(1.0, _maxZoom);
    if ((newZoom - _currentZoom).abs() > 0.05) {
      setState(() => _currentZoom = newZoom);
      ref.read(detectionControllerProvider.notifier).setZoom(newZoom);
    }
  }

  Future<void> _handleFlash() async {
    final state = ref.read(detectionControllerProvider);
    await ref
        .read(detectionControllerProvider.notifier)
        .setFlash(!state.flashOn);
  }

  Future<void> _scanAgain() async {
    setState(() {
      _anchorScreenPosition = null;
      _mappingElapsedMs = 0;
      _readyStreakMs = 0;
    });
    await ref.read(detectionControllerProvider.notifier).restartMapping();
    _startMappingTicker();
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
                else
                  const _ArPlatformView(),

                // Reticle + distance ring stay through capture, hidden once
                // the result has been presented (replaced by the floating
                // diagnosis label anchored to the lesion).
                if (detection.phase != DetectionPhase.presented) ...[
                  ArReticleOverlay(quality: detection.readiness.lighting),
                  ArDistanceRing(distance: detection.distance),
                ],

                // Scene-mapping pre-phase overlay (Pokémon-GO style).
                if (detection.phase == DetectionPhase.mapping ||
                    detection.phase == DetectionPhase.initializing)
                  SceneMappingOverlay(
                    readiness: detection.readiness,
                    elapsedMs: _mappingElapsedMs,
                  ),

                // Live readiness checklist once mapping completes.
                if (detection.phase == DetectionPhase.ready)
                  ReadinessChecklistOverlay(readiness: detection.readiness),

                // Floating diagnosis label — only shown when the anchor is
                // currently in the camera frustum.
                if (detection.phase == DetectionPhase.presented &&
                    detection.result != null &&
                    _anchorScreenPosition != null)
                  _AnchoredLabel(
                    anchorPoint: _anchorScreenPosition!,
                    child: FloatingDiagnosisLabel(
                      result: detection.result!,
                      onTap: () => _navigateToTriage(detection),
                    ),
                  ),

                // Re-acquisition hint when anchor is lost / out of frame.
                if (detection.phase == DetectionPhase.presented &&
                    _anchorScreenPosition == null)
                  const _AnchorLostHint(),

                // Flash + zoom HUD
                Positioned(
                  top: 16,
                  right: 16,
                  child: CameraFlashButton(
                    isOn: detection.flashOn,
                    onTap: _handleFlash,
                  ),
                ),
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
    final isMapping = detection.phase == DetectionPhase.mapping ||
        detection.phase == DetectionPhase.initializing;

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
                quality: detection.readiness.lighting,
                isCapturing: isBusy || isMapping,
                onPressed: _handleCapture,
              ),
              _SecondaryAction(
                icon: isPresented ? Icons.refresh : Icons.tune_rounded,
                label: isPresented ? 'Scan again' : 'Calibrate',
                onTap: () async {
                  if (isPresented) {
                    await _scanAgain();
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

/// Picks the right native AR PlatformView for the host platform.
class _ArPlatformView extends StatelessWidget {
  const _ArPlatformView();

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const AndroidView(
        viewType: 'skeen.detection/ar_view',
        creationParamsCodec: StandardMessageCodec(),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const UiKitView(
        viewType: 'skeen.detection/ar_view',
        creationParamsCodec: StandardMessageCodec(),
      );
    }
    return const Center(
      child: Text(
        'AR is not supported on this platform',
        style: TextStyle(color: AppColors.violetaClaro, fontFamily: 'Poppins'),
      ),
    );
  }
}

/// Positions the popup just above the anchor and draws a stem line down to it.
class _AnchoredLabel extends StatelessWidget {
  const _AnchoredLabel({required this.anchorPoint, required this.child});

  final Offset anchorPoint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final labelX = (anchorPoint.dx - 130).clamp(8.0, double.infinity);
    final labelY = (anchorPoint.dy - 110).clamp(8.0, double.infinity);
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _StemLinePainter(
              from: anchorPoint,
              to: Offset(labelX + 130, labelY + 80),
            ),
          ),
        ),
        Positioned(left: labelX, top: labelY, child: child),
      ],
    );
  }
}

class _StemLinePainter extends CustomPainter {
  _StemLinePainter({required this.from, required this.to});
  final Offset from;
  final Offset to;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.violeta.withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(from, 5, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;
    canvas.drawLine(from, to, paint);
  }

  @override
  bool shouldRepaint(_StemLinePainter old) => old.from != from || old.to != to;
}

class _AnchorLostHint extends StatelessWidget {
  const _AnchorLostHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          border: Border.all(color: AppColors.violetaClaro.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.replay, color: AppColors.violetaClaro, size: 18),
            SizedBox(width: 8),
            Text(
              'Aim back at the lesion',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.violetaClaro,
              ),
            ),
          ],
        ),
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
