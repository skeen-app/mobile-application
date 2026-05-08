import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../../patient/application/lesion_summary_providers.dart';
import '../../../patient/application/scan_history_providers.dart';
import '../../application/detection_controller.dart';
import '../../application/providers.dart';
import '../../application/sync_orchestrator.dart';
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

/// AR-AI bridge screen — true 3D AR via ARCore (Android) / ARKit (iOS).
///
/// Architecture:
///   • Native AR session owns the camera (ARCore on Android, ARKit on iOS)
///     and renders the camera background through a [PlatformView] in
///     **Hybrid Composition** mode. HC was chosen over TLHC because the
///     latter composites the GL framebuffer as a Flutter layer, which on
///     ARCore's OES external texture caused rotation/aspect artifacts.
///     HC layers the native GL view directly above the Flutter UI like
///     a regular Android view.
///   • Plane detection + raycast hit-test on capture creates a tracked
///     [Anchor]. Each frame the screen re-projects the anchor's *current*
///     world pose to screen pixels, so the diagnosis label stays glued to
///     the lesion as the user moves the phone (Pokémon-GO style).
///   • Readiness gate is derived from ARCore's `lightEstimate.pixelIntensity`
///     and `camera.trackingState`, with depth from `frame.depthImage`.
class ArScanScreen extends ConsumerStatefulWidget {
  const ArScanScreen({super.key});

  @override
  ConsumerState<ArScanScreen> createState() => _ArScanScreenState();
}

class _ArScanScreenState extends ConsumerState<ArScanScreen>
    with WidgetsBindingObserver {
  StreamSubscription<CaptureDistance>? _distanceSub;
  StreamSubscription<ArFrameInfo>? _frameInfoSub;
  Timer? _mappingTicker;
  Timer? _anchorRefresher;

  Size _previewSize = Size.zero;
  String? _initError;
  int _mappingElapsedMs = 0;
  int _readyStreakMs = 0;
  static const _mappingMinMs = 400;
  static const _readyStreakRequiredMs = 100;

  // Readiness derived from native ARCore frame stream.
  double _seenBrightness = 0;
  String _tracking = 'UNKNOWN';
  int _trackingStableMs = 0;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);

  // AR popup screen-space position from anchor projection.
  Offset? _anchorScreen;
  bool _anchorVisible = false;

  // Pinch-to-zoom state
  double _currentZoom = 1.0;
  static const double _maxZoom = 5.0;
  double _baseZoom = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final session = ref.read(arSessionProvider);
      await session.start();
      _listenStreams();
      _startMappingTicker();
      _startAnchorRefresher();
      if (mounted) setState(() {});
    } catch (e) {
      if (kDebugMode) debugPrint('AR bootstrap failed: $e');
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  void _listenStreams() {
    final session = ref.read(arSessionProvider);
    final concrete = session is ArSessionService ? session : null;

    _distanceSub = session.distance.listen((_) {
      // Distance is forwarded by the controller into state.distance for
      // the UI ring; readiness no longer gates on it.
    });

    _frameInfoSub = concrete?.frameInfo.listen((info) {
      final now = DateTime.now();
      final dt = now.difference(_lastFrameAt).inMilliseconds.clamp(0, 500);
      _lastFrameAt = now;
      if (info.brightness != null) _seenBrightness = info.brightness!;
      _tracking = info.tracking;
      _trackingStableMs =
          info.isTracking ? _trackingStableMs + dt : 0;
      if (mounted) {
        ref
            .read(detectionControllerProvider.notifier)
            .updateReadiness(_buildReadiness());
      }
    });
  }

  CaptureReadiness _buildReadiness() {
    final lighting = _seenBrightness > 0
        ? CaptureQuality.fromBrightness(_seenBrightness)
        : CaptureQuality.initial;
    final tracking = _tracking == 'TRACKING';
    // Distance is feedback-only — ARCore depth is unreliable below 10 cm
    // (the optimal lesion distance) so we don't gate on it. The on-screen
    // distance ring still shows the real reading for the user.
    return CaptureReadiness(
      lighting: lighting,
      focus: tracking,
      distance: true,
      isStable: tracking,
    );
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
      // Mapping unlocks on tracking alone — the assistive hints during
      // capture (lighting / center-the-mole) keep coaching after the gate
      // opens, but the user is no longer waiting on them to capture.
      final tracking = _tracking == 'TRACKING';
      _readyStreakMs = tracking ? _readyStreakMs + 100 : 0;

      if (_mappingElapsedMs >= _mappingMinMs &&
          _readyStreakMs >= _readyStreakRequiredMs) {
        ref.read(detectionControllerProvider.notifier).completeMapping();
      }
    });
  }

  /// 30 fps anchor projection so the popup follows the lesion as the
  /// camera moves. The native side returns visible=false when the anchor
  /// is outside the frustum or tracking is lost — the popup hides until
  /// it returns to the FOV.
  void _startAnchorRefresher() {
    _anchorRefresher?.cancel();
    _anchorRefresher = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => _refreshAnchorPosition(),
    );
  }

  Future<void> _refreshAnchorPosition() async {
    final state = ref.read(detectionControllerProvider);
    if (_previewSize == Size.zero) return;

    if (state.phase != DetectionPhase.presented) {
      if (_anchorScreen != null || _anchorVisible) {
        setState(() {
          _anchorScreen = null;
          _anchorVisible = false;
        });
      }
      return;
    }

    // Try the AR anchor first — gives 3D follow as the user moves the phone.
    if (state.anchor != null) {
      final px = await ref
          .read(detectionControllerProvider.notifier)
          .projectAnchorToScreen(previewSize: _previewSize);
      if (!mounted) return;
      if (px != null) {
        if (_anchorScreen != px || !_anchorVisible) {
          setState(() {
            _anchorScreen = px;
            _anchorVisible = true;
          });
        }
        return;
      }
      // Anchor exists but is outside the camera frustum — hide popup.
      if (_anchorVisible) {
        setState(() {
          _anchorScreen = null;
          _anchorVisible = false;
        });
      }
      return;
    }

    // No AR anchor → fall back to screen-space lesion centroid so the
    // popup is always visible after capture, even on devices where the
    // raycast returns nothing.
    final centroid = state.result?.lesionCentroid ?? const Offset(0.5, 0.5);
    final pos = Offset(
      centroid.dx * _previewSize.width,
      centroid.dy * _previewSize.height,
    );
    if (_anchorScreen != pos || !_anchorVisible) {
      setState(() {
        _anchorScreen = pos;
        _anchorVisible = true;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The host Activity / SceneDelegate forwards lifecycle to the native
    // AR session. Nothing to do here.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _distanceSub?.cancel();
    _frameInfoSub?.cancel();
    _mappingTicker?.cancel();
    _anchorRefresher?.cancel();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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
    if (region != null) {
      // Persist the freshly picked region on the already-saved scan +
      // re-flip pending_upload so the orchestrator re-syncs.
      await ref
          .read(lesionRepositoryProvider)
          .updateBodyRegion(state.savedAnalysisId!, region);
      ref.invalidate(scanHistoryProvider);
      ref.invalidate(lesionSummariesProvider);
      ref.read(syncOrchestratorProvider).syncNow(reason: 'region-picked');
    }
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
      _mappingElapsedMs = 0;
      _readyStreakMs = 0;
      _anchorScreen = null;
      _anchorVisible = false;
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
                  const _ArNativeView(),

                if (detection.phase == DetectionPhase.ready) ...[
                  ArReticleOverlay(quality: detection.readiness.lighting),
                  ArDistanceRing(distance: detection.distance),
                ],

                if (detection.phase == DetectionPhase.mapping ||
                    detection.phase == DetectionPhase.initializing)
                  SceneMappingOverlay(
                    readiness: detection.readiness,
                    elapsedMs: _mappingElapsedMs,
                  ),

                if (detection.phase == DetectionPhase.ready)
                  ReadinessChecklistOverlay(readiness: detection.readiness),

                if (detection.phase == DetectionPhase.presented &&
                    detection.result != null &&
                    _anchorVisible &&
                    _anchorScreen != null)
                  _AnchoredLabel(
                    anchorPoint: _anchorScreen!,
                    previewSize: _previewSize,
                    child: FloatingDiagnosisLabel(
                      result: detection.result!,
                      onTap: () => _navigateToTriage(detection),
                    ),
                  ),

                if (detection.phase == DetectionPhase.presented &&
                    !_anchorVisible)
                  const _AnchorLostHint(),

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
              if (isPresented)
                _SecondaryAction(
                  icon: Icons.refresh,
                  label: 'Scan again',
                  onTap: _scanAgain,
                )
              else
                // Reserve the slot so the capture button stays centered
                // even before a result is presented.
                const SizedBox(width: 60),
            ],
          ),
        ],
      ),
    );
  }
}

/// Native AR view, mounted via Hybrid Composition (Android) /
/// UiKitView (iOS) so the GL framebuffer is presented natively without
/// Flutter's TLHC layer compositing distorting orientation.
class _ArNativeView extends StatelessWidget {
  const _ArNativeView();

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return PlatformViewLink(
        viewType: 'skeen.detection/ar_view',
        surfaceFactory: (context, controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (params) {
          return PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: 'skeen.detection/ar_view',
            layoutDirection: TextDirection.ltr,
            creationParams: const <String, dynamic>{},
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..create();
        },
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

class _AnchoredLabel extends StatelessWidget {
  const _AnchoredLabel({
    required this.anchorPoint,
    required this.previewSize,
    required this.child,
  });

  final Offset anchorPoint;
  final Size previewSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const labelW = 240.0;
    const labelH = 96.0;
    const gap = 36.0; // distance between card edge and the mole
    final maxX = math.max(0.0, previewSize.width - labelW - 8);
    final maxY = math.max(0.0, previewSize.height - labelH - 8);
    final labelX = (anchorPoint.dx - labelW / 2).clamp(8.0, maxX);

    // Prefer placing the card above the mole so the arrow points down at
    // the lesion (most natural). When there isn't enough room above, flip
    // it below so the arrow points up at the lesion instead.
    final placeAbove = anchorPoint.dy > labelH + gap + 8;
    final labelY = placeAbove
        ? (anchorPoint.dy - labelH - gap).clamp(8.0, maxY)
        : (anchorPoint.dy + gap).clamp(8.0, maxY);

    final cardEdge = placeAbove
        ? Offset(labelX + labelW / 2, labelY + labelH)
        : Offset(labelX + labelW / 2, labelY);

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _ArrowPointerPainter(
              cardEdge: cardEdge,
              anchorPoint: anchorPoint,
            ),
          ),
        ),
        Positioned(left: labelX, top: labelY, width: labelW, child: child),
      ],
    );
  }
}

/// Draws a speech-bubble-style triangular arrow that connects the popup's
/// edge to the lesion, then a soft halo + dot at the lesion itself. Reads
/// as a sign pointing at the mole.
class _ArrowPointerPainter extends CustomPainter {
  _ArrowPointerPainter({
    required this.cardEdge,
    required this.anchorPoint,
  });

  final Offset cardEdge;
  final Offset anchorPoint;

  @override
  void paint(Canvas canvas, Size size) {
    final dir = anchorPoint - cardEdge;
    final dist = dir.distance;
    if (dist < 1) return;

    final unit = Offset(dir.dx / dist, dir.dy / dist);
    final perp = Offset(-unit.dy, unit.dx);
    const halfBase = 11.0;

    // Triangle: base at the card edge, apex stops just shy of the anchor
    // so the dot at the anchor reads as a separate element.
    final apex = anchorPoint - unit * 6;
    final base1 = cardEdge + perp * halfBase;
    final base2 = cardEdge - perp * halfBase;

    final path = Path()
      ..moveTo(base1.dx, base1.dy)
      ..lineTo(apex.dx, apex.dy)
      ..lineTo(base2.dx, base2.dy)
      ..close();

    final fill = Paint()
      ..color = AppColors.violeta.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = AppColors.violetaClaro.withValues(alpha: 0.9)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);

    // Halo around the lesion anchor (subtle outer ring + filled dot).
    canvas.drawCircle(
      anchorPoint,
      11,
      Paint()
        ..color = AppColors.violetaClaro.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      anchorPoint,
      6,
      Paint()
        ..color = AppColors.violetaClaro
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      anchorPoint,
      6,
      Paint()
        ..color = AppColors.violeta
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_ArrowPointerPainter old) =>
      old.cardEdge != cardEdge || old.anchorPoint != anchorPoint;
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
          border: Border.all(
            color: AppColors.violetaClaro.withValues(alpha: 0.4),
          ),
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
