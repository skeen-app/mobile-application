import 'package:skeen/core/localization/locale_controller.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import '../../application/sync_orchestrator.dart';
import '../../domain/ar_geometry.dart';
import '../../domain/capture_quality.dart';
import '../../domain/capture_roi.dart';
import '../../infrastructure/ar_session_service.dart';
import '../widgets/body_region_picker.dart';
import '../widgets/camera_controls.dart';
import '../widgets/capture_guide_overlay.dart';
import '../widgets/floating_diagnosis_label.dart';
import '../widgets/not_skin_detected_dialog.dart';
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
  bool _permissionPermanentlyDenied = false;
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
  // Last instant we got a valid projection from the native AR side.
  // When the projection drops out for a frame or two (camera tracking
  // briefly paused, lastFrame still updating after captureFrame, etc.)
  // we keep the popup at its last known position for a short grace
  // window so it doesn't flicker off-screen on every micro-blip.
  DateTime? _lastGoodAnchorAt;
  static const _anchorGraceMs = 1500;

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
      // Camera permission gate: ARCore/ARKit silently fail to start when
      // the OS has the permission set to denied. Re-prompting here
      // catches the new-user flow where camera was declined during
      // onboarding — the user grants now and AR boots in the same
      // session instead of forcing a navigate-away-and-back.
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

      final session = ref.read(arSessionProvider);
      await session.start();
      _listenStreams();
      _startMappingTicker();
      _startAnchorRefresher();
      if (mounted) {
        setState(() {
          _initError = null;
          _permissionPermanentlyDenied = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('AR bootstrap failed: $e');
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  /// Re-runs [_bootstrap] from the empty-state retry button. When the
  /// previous failure was a permanent denial we route through the system
  /// settings page first — once the user comes back, the lifecycle
  /// observer will re-call [_bootstrap] automatically.
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
    // The AR surface has no ROI metric pipeline: ARCore owns the camera, so
    // there is no image stream to measure glare, colour cast or lesion scale
    // from. `gatingSignals: false` keeps this surface on the two-term gate it
    // has always used rather than blocking it on signals it never populates —
    // and those unmeasured signals are correspondingly not shown to the user.
    //
    // The old `distance` term is gone entirely. It was sourced from ARCore
    // Depth, which does not resolve below roughly half a metre, so at macro
    // working distance it was noise being presented as a measurement.
    return CaptureReadiness(
      lighting: lighting,
      focus: tracking,
      gatingSignals: false,
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
      _lastGoodAnchorAt = null;
      return;
    }

    // Live AR projection from the native side (frame-by-frame).
    Offset? rawPx;
    if (state.anchor != null) {
      rawPx = await ref
          .read(detectionControllerProvider.notifier)
          .projectAnchorToScreen(previewSize: _previewSize);
      if (!mounted) return;
    }

    if (rawPx == null) {
      // No live projection right now. Two scenarios:
      //   1. The anchor exists but the native side hasn't refreshed
      //      `lastFrame` yet (the immediate post-capture frame, a brief
      //      tracking pause, etc.) — keep the last known position for
      //      a 1.5s grace window so the popup doesn't flicker.
      //   2. The capture never produced an anchor (raycast returned
      //      null) — use the inference centroid so the popup is at
      //      least pinned to the lesion's screen position.
      final lastGood = _lastGoodAnchorAt;
      final stillInGrace = lastGood != null &&
          DateTime.now().difference(lastGood).inMilliseconds <
              _anchorGraceMs;
      if (state.anchor != null && stillInGrace && _anchorScreen != null) {
        // Hold the last known projected position; tracking will resume
        // in a few ms and we don't want the popup blinking.
        return;
      }
      // Fallback: centroid-pinned position. Static against camera
      // motion (we don't have a world anchor) but at least visible.
      final centroid = state.result?.lesionCentroid ?? const Offset(0.5, 0.5);
      rawPx = Offset(
        centroid.dx * _previewSize.width,
        centroid.dy * _previewSize.height,
      );
    } else {
      _lastGoodAnchorAt = DateTime.now();
    }

    // Compensate for the Flutter-side Transform.scale that powers the
    // digital pinch zoom on the camera view. The native AR side
    // projects to NDC against the unzoomed frame; the camera RENDERS
    // through `Transform.scale(scale=_currentZoom, alignment=center)`,
    // so a point at `rawPx` on the original frame appears at
    //   (rawPx - center) * zoom + center
    // in screen space. Without this the label tracks correctly along
    // the unscaled frame but visually slides away from the zoomed
    // lesion — looks "broken" / "static-vs-lesion" to the user.
    final centerX = _previewSize.width / 2;
    final centerY = _previewSize.height / 2;
    final displayPx = Offset(
      (rawPx.dx - centerX) * _currentZoom + centerX,
      (rawPx.dy - centerY) * _currentZoom + centerY,
    );

    if (_anchorScreen != displayPx || !_anchorVisible) {
      setState(() {
        _anchorScreen = displayPx;
        _anchorVisible = true;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The host Activity / SceneDelegate forwards normal lifecycle events
    // to the native AR session, so we don't need to start/stop here.
    //
    // What we DO need to handle: resume after a system permission dialog
    // or a trip to app-settings. In that case [_initError] is set from
    // the previous failed bootstrap; rerun it so a freshly-granted camera
    // permission lights up AR immediately without a screen pop.
    if (state == AppLifecycleState.resumed && _initError != null) {
      _bootstrap();
    }
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
    await controller.captureAndClassify(
      previewSize: _previewSize,
      // ARCore owns the camera here and never reports the CPU frame's
      // dimensions to Dart, so this surface genuinely cannot derive the real
      // preview↔frame mapping. It keeps the historical constant, explicitly
      // named. Not the study's capture surface.
      roi: const CaptureRoi.unverifiedGuideFraction(),
    );
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
      final repo = ref.read(lesionRepositoryProvider);
      await repo.updateBodyRegion(state.savedAnalysisId!, region);
      ref.invalidate(scanHistoryProvider);
      ref.invalidate(lesionSummariesProvider);
      // Patch the region straight onto the cloud doc via uploadOne — the
      // capture flow already uploaded this row with no region, and the
      // debounced syncNow could silently drop the patch (5s window), making
      // the scan read back at the chest default. uploadOne bypasses both
      // the debounce and the running-lock.
      final tagged = await repo.findById(state.savedAnalysisId!);
      if (tagged != null) {
        ref.read(syncOrchestratorProvider).uploadOne(tagged);
      }
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

  Future<void> _showNotSkinDialog() async {
    await NotSkinDetectedDialog.show(context);
    if (!mounted) return;
    // Whatever the dismiss path (CTA or back gesture), return the AR flow
    // to the scene-mapping coaching state so the next attempt re-runs the
    // readiness gate.
    await _scanAgain();
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
    // Skin-gate rejection → educational modal, then back to mapping. The
    // listener runs once per transition, not on every rebuild.
    ref.listen<DetectionState>(detectionControllerProvider, (prev, next) {
      final wasRejected = prev?.phase == DetectionPhase.notSkinRejected;
      final isRejected = next.phase == DetectionPhase.notSkinRejected;
      if (isRejected && !wasRejected) {
        _showNotSkinDialog();
      }
    });
    final detection = ref.watch(detectionControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SkeenTopAppBar(
              title: 'Scan a mole'.tr,
              subtitle: 'AR-AI guided · ARKit / ARCore'.tr,
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
                else
                  // Digital zoom: ARCore's native session ignores setZoom
                  // calls on this build (the Kotlin handler is a no-op),
                  // so we scale the PlatformView itself. Center-aligned
                  // so the focal point stays put as the user pinches.
                  ClipRect(
                    child: Transform.scale(
                      scale: _currentZoom,
                      alignment: Alignment.center,
                      child: const _ArNativeView(),
                    ),
                  ),

                if (detection.phase == DetectionPhase.ready)
                  CaptureGuideOverlay(
                    readiness: detection.readiness,
                    boxSide: resolveGuideBoxSide(_previewSize.shortestSide),
                  ),

                if (detection.phase == DetectionPhase.mapping ||
                    detection.phase == DetectionPhase.initializing)
                  SceneMappingOverlay(
                    readiness: detection.readiness,
                    elapsedMs: _mappingElapsedMs,
                  ),

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
                    detection.phase == DetectionPhase.standardizing ||
                    detection.phase == DetectionPhase.gating ||
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
        detection.phase == DetectionPhase.gating ||
        detection.phase == DetectionPhase.uploading;
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
    // Recognizers that Flutter must claim from the native AR view so the
    // parent GestureDetector (pinch-to-zoom) actually fires. With an
    // empty set + opaque hit-test the native view used to swallow every
    // touch — pinch never reached the Flutter side. By declaring a
    // ScaleGestureRecognizer here Flutter wins it in the gesture arena
    // and forwards it up the tree.
    final gestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{
      Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
    };

    if (defaultTargetPlatform == TargetPlatform.android) {
      return PlatformViewLink(
        viewType: 'skeen.detection/ar_view',
        surfaceFactory: (context, controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: gestureRecognizers,
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
      return UiKitView(
        viewType: 'skeen.detection/ar_view',
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: gestureRecognizers,
      );
    }
    return Center(
      child: Text(
        'AR is not supported on this platform'.tr,
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.replay, color: AppColors.violetaClaro, size: 18),
            SizedBox(width: 8),
            Text(
              'Aim back at the lesion'.tr,
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
