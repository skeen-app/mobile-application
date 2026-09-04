import 'dart:async';
import 'dart:ui';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/notifications/notifications_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/privacy_settings.dart';
import '../domain/ar_geometry.dart';
import '../domain/capture_quality.dart';
import '../domain/capture_roi.dart';
import '../domain/class_label.dart';
import '../domain/inference_result.dart';
import '../domain/lesion_analysis.dart';
import '../domain/ports.dart';
import '../domain/skin_gate_exception.dart';
import 'coordinate_translator.dart';
import 'detection_result_mapper.dart';
import 'providers.dart';
import 'sync_orchestrator.dart';

/// Phases of the AR-AI bridge flow, exposed to the UI as a single state
/// stream so the presentation layer can react declaratively rather than
/// juggling several booleans.
enum DetectionPhase {
  initializing,
  mapping,
  ready,
  capturing,
  standardizing,
  // Cascade stage-1: the skin / not-skin filter runs before the cancer
  // classifier. Short-circuits the pipeline (no persistence, no upload)
  // when the captured frame doesn't look like skin.
  gating,
  analyzing,
  // The post-inference step where, with cloud sync consent + connectivity,
  // we synchronously push the freshly captured scan to the cloud before
  // showing the result. Guarantees the row survives a quick sign-out.
  uploading,
  presented,
  // Terminal phase reached when the skin-gate rejected the frame. The
  // screen shows the educational dialog and calls [reset] to return to
  // [ready] once the user acknowledges.
  notSkinRejected,
  failed,
}

@immutable
class DetectionState {
  const DetectionState({
    required this.phase,
    this.readiness = CaptureReadiness.initializing,
    this.distance = const CaptureDistance.unknown(),
    this.result,
    this.anchor,
    this.savedAnalysisId,
    this.capturedImageBytes,
    this.flashOn = false,
    this.zoom = 1.0,
    this.errorMessage,
  });

  final DetectionPhase phase;
  final CaptureReadiness readiness;
  final CaptureDistance distance;
  final InferenceResult? result;
  final WorldAnchor? anchor;
  final String? savedAnalysisId;
  final Uint8List? capturedImageBytes;
  final bool flashOn;
  final double zoom;
  final String? errorMessage;

  DetectionState copyWith({
    DetectionPhase? phase,
    CaptureReadiness? readiness,
    CaptureDistance? distance,
    InferenceResult? result,
    WorldAnchor? anchor,
    String? savedAnalysisId,
    Uint8List? capturedImageBytes,
    bool? flashOn,
    double? zoom,
    String? errorMessage,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return DetectionState(
      phase: phase ?? this.phase,
      readiness: readiness ?? this.readiness,
      distance: distance ?? this.distance,
      result: clearResult ? null : (result ?? this.result),
      anchor: clearResult ? null : (anchor ?? this.anchor),
      savedAnalysisId: clearResult
          ? null
          : (savedAnalysisId ?? this.savedAnalysisId),
      capturedImageBytes: clearResult
          ? null
          : (capturedImageBytes ?? this.capturedImageBytes),
      flashOn: flashOn ?? this.flashOn,
      zoom: zoom ?? this.zoom,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Riverpod controller orchestrating the single-shot AR-AI pipeline:
///
/// `start session → live readiness updates → capture standardized frame
///  → TFLite classify → hit-test for anchor → persist encrypted (+ image)
///  → present floating label`.
///
/// Flash and zoom are dispatched to **both** the camera plugin (physical
/// torch/zoom) and the AR session (native overlay sync). This ensures the
/// torch works even on devices where the native AR plugin isn't registered.
class DetectionController extends StateNotifier<DetectionState> {
  DetectionController({
    required ArSessionPort session,
    required InferenceServicePort inference,
    required SkinGateServicePort skinGate,
    required CaptureCropperPort cropper,
    required ScanCameraServicePort camera,
    required CoordinateTranslator translator,
    required DetectionResultMapper mapper,
    required LesionRepositoryPort repository,
    required this.patientId,
    required this.cloudSyncEnabledReader,
    required this.isOnlineChecker,
    required this.uploadScan,
    NotificationsController? notifications,
    void Function()? onScanSaved,
  })  : _session = session,
        _inference = inference,
        _skinGate = skinGate,
        _cropper = cropper,
        _camera = camera,
        _translator = translator,
        _mapper = mapper,
        _repository = repository,
        _notifications = notifications,
        _onScanSaved = onScanSaved,
        super(const DetectionState(phase: DetectionPhase.initializing));

  final ArSessionPort _session;
  final InferenceServicePort _inference;
  final SkinGateServicePort _skinGate;
  final CaptureCropperPort _cropper;
  final ScanCameraServicePort _camera;
  final CoordinateTranslator _translator;
  final DetectionResultMapper _mapper;
  final LesionRepositoryPort _repository;
  final NotificationsController? _notifications;
  final void Function()? _onScanSaved;
  final String patientId;

  /// Resolves the user's current cloud-sync consent at capture time.
  final bool Function() cloudSyncEnabledReader;
  /// Returns true when the device has any kind of network reachability.
  final Future<bool> Function() isOnlineChecker;
  /// Pushes a single scan to the cloud now. The capture flow awaits this
  /// before transitioning to [DetectionPhase.presented] so a scan can't be
  /// lost to a quick sign-out before the orchestrator's next tick.
  final Future<bool> Function(LesionAnalysis) uploadScan;

  StreamSubscription<CaptureDistance>? _distanceSub;

  Future<void> bootstrap() async {
    try {
      // The AR session is no longer started here — the camera plugin owns
      // the back camera in the AR scan flow (it renders a reliable preview;
      // ARCore's GLSurfaceView path had rotation/aspect issues inside
      // Flutter's PlatformView compositor). The session can still be
      // started explicitly by a screen that wants 3D anchors via shared
      // camera mode in the future.
      await Future.wait([
        _inference.load(),
        _skinGate.load(),
        _repository.initialize(),
      ]);
      _distanceSub = _session.distance.listen((d) {
        if (!mounted) return;
        state = state.copyWith(distance: d);
      });
      // Enter the scene-mapping phase first; the screen will call
      // [completeMapping] once tracking + readiness gate has passed.
      state = state.copyWith(phase: DetectionPhase.mapping, clearError: true);
    } catch (e, st) {
      if (kDebugMode) debugPrint('Detection bootstrap failed: $e\n$st');
      state = state.copyWith(
        phase: DetectionPhase.failed,
        errorMessage: 'Could not start AR session: $e',
      );
    }
  }

  /// Toggle flash — dispatches to BOTH camera plugin (physical torch LED)
  /// and AR session (native overlay sync). The camera plugin call is the
  /// one that actually turns the torch on; the AR session call syncs the
  /// native AR view's flash state for consistency.
  Future<void> setFlash(bool on) async {
    // Camera plugin — this is the real torch control
    await _camera.setFlash(on);
    // AR session — sync native overlay (graceful no-op if not registered)
    await _session.setFlash(on);
    if (!mounted) return;
    state = state.copyWith(flashOn: on);
  }

  /// Set zoom — dual dispatch to camera plugin + AR session.
  Future<void> setZoom(double zoom) async {
    final clamped = zoom.clamp(1.0, 5.0);
    await _camera.setZoom(clamped);
    await _session.setZoom(clamped);
    if (!mounted) return;
    state = state.copyWith(zoom: clamped);
  }

  /// Update readiness from the ReadinessEvaluator stream.
  void updateReadiness(CaptureReadiness readiness) {
    if (!mounted) return;
    state = state.copyWith(readiness: readiness);
  }

  /// Advance from the AR scene-mapping phase to ready, unlocking capture.
  /// Called by the AR screen once tracking has stabilized and the readiness
  /// gate (lighting / focus / distance) passes.
  void completeMapping() {
    if (!mounted) return;
    if (state.phase != DetectionPhase.mapping) return;
    state = state.copyWith(phase: DetectionPhase.ready);
  }

  /// Restart the scene-mapping phase. Called when the user taps "Scan again"
  /// so the AR overlay re-walks the assistive hints before each capture.
  Future<void> restartMapping() async {
    await _camera.restartSampling();
    await _camera.unlockExposure();
    if (!mounted) return;
    state = state.copyWith(
      phase: DetectionPhase.mapping,
      clearResult: true,
      clearError: true,
    );
  }

  /// The full capture-classify-persist pipeline.
  ///
  /// Flow: ready → capturing → standardizing → analyzing → presented
  ///
  /// JPEG bytes come from the standardized camera capture (center-cropped 1:1).
  /// The camera service auto-restarts the image stream after capture, so the
  /// readiness overlay resumes live updates immediately.
  Future<void> captureAndClassify({
    required Size previewSize,
    required CaptureRoi roi,
  }) async {
    if (state.phase != DetectionPhase.ready) return;
    // Ensure any leftover anchor from a previous capture is cleared.
    state = state.copyWith(phase: DetectionPhase.capturing, clearResult: true);

    try {
      // Lock AE/AF for stable exposure during capture (camera plugin path).
      // No-op when the camera plugin isn't initialized (AR-only path).
      await _camera.lockExposure();

      // Phase: standardizing — try AR session capture first (ARCore /
      // ARKit own the camera in this flow); fall back to the camera
      // plugin when AR isn't active.
      state = state.copyWith(phase: DetectionPhase.standardizing);
      Uint8List? bytes;
      if (_camera.isReady) {
        bytes = await _camera.captureStandardized();
      } else {
        bytes = await _session.captureFrame();
      }

      await _camera.unlockExposure();

      if (bytes == null || !mounted) {
        state = state.copyWith(
          phase: DetectionPhase.ready,
          errorMessage: 'Capture failed — try again',
        );
        return;
      }

      // Compute image hash for dedup + integrity. Hashes the FULL capture —
      // the crop below only narrows what the models see, not what we persist
      // or display.
      final hash = sha256.convert(bytes).toString();

      // ── FASE 2: guide-box crop (flag-gated) ───────────────────────────
      // Crop the guide region ONCE, here, and feed that single buffer to
      // BOTH cascade stages so they see the same (tighter) input. [roi] is
      // supplied by the surface that drew the guide box and measured the
      // readiness metrics, so all three describe one region.
      // Persistence, PDF and the displayed photo keep the full `bytes`.
      // When the flag is off, [CropOutcome.applied] is false and `modelBytes`
      // == `bytes` (legacy behavior, byte-for-byte).
      final crop = await _cropper.crop(bytes, roi: roi);
      final modelBytes = crop.bytes;

      // Phase: gating — cascade stage-1 (skin / not-skin). Runs on the
      // (possibly cropped) JPEG so both stages of the cascade see the same
      // buffer. A negative verdict short-circuits the pipeline: no
      // classifier call, no persistence, no notifications, no upload.
      state = state.copyWith(phase: DetectionPhase.gating);
      final gate = await _skinGate.evaluate(modelBytes);
      if (!gate.isSkin) {
        throw NotSkinDetectedException(gate);
      }

      // Phase: analyzing — run TFLite inference on isolate (non-blocking)
      state = state.copyWith(phase: DetectionPhase.analyzing);
      var result = await _inference.classify(modelBytes);

      // The classifier computes the lesion centroid in the cropped image's
      // coordinate space. Remap it back to FULL-frame normalized coords so
      // the AR anchor / floating-label fallback still lands on the lesion.
      // For a centered crop spanning `frac` of each axis:
      //   full = 0.5 + (cropNorm - 0.5) * frac
      if (crop.applied && result.lesionCentroid != null) {
        final c = result.lesionCentroid!;
        result = InferenceResult(
          scores: result.scores,
          lesionCentroid: Offset(
            (0.5 + (c.dx - 0.5) * crop.fracX).clamp(0.0, 1.0),
            (0.5 + (c.dy - 0.5) * crop.fracY).clamp(0.0, 1.0),
          ),
        );
      }

      if (kDebugMode) {
        debugPrint(
          'Inference result: ${result.topLabel.display} '
          '(${(result.confidence * 100).toStringAsFixed(1)}%) '
          'warning=${result.warningLevel}',
        );
      }

      // ── Center-of-Interest Anchoring Strategy ─────────────────────
      // The model is a classifier (no bounding boxes). The user centers
      // the lesion in the target ring by UX design, so the initial
      // raycast origin is viewport center (0.5, 0.5).
      //
      // Optional refinement: the InferenceService extracts a 300x300 ROI,
      // finds the centroid of the darkest blob, and returns it as [lesionCentroid].
      final interestPoint = result.lesionCentroid ?? const Offset(0.5, 0.5);
      
      final anchor = await _translator.anchorAtCenterOfInterest(
        interestPoint: interestPoint,
      );

      if (kDebugMode && anchor != null) {
        debugPrint(
          'AR Anchor created at: '
          '(${anchor.translation.x.toStringAsFixed(3)}, '
          '${anchor.translation.y.toStringAsFixed(3)}, '
          '${anchor.translation.z.toStringAsFixed(3)})',
        );
      }

      // Build a synthetic BoundingBox for the mapper (metadata/display).
      // Center-positioned in the preview since the model assumes centered input.
      final shortest = previewSize.shortestSide;
      final side = shortest * 0.33;
      final bbox = BoundingBox(
        left: (previewSize.width - side) / 2,
        top: (previewSize.height - side) / 2,
        width: side,
        height: side,
        frameWidth: previewSize.width,
        frameHeight: previewSize.height,
      );

      // Decide the row's sync intent at capture time so the bookkeeping
      // matches reality before we even touch the DB:
      //   • cloudSyncEnabled = true  → eligible for cloud upload
      //       - online  → mark pendingUpload, attempt sync inline below
      //       - offline → mark pendingUpload, orchestrator retries later
      //   • cloudSyncEnabled = false → localOnly, never enters the queue,
      //       surfaces as "Not synced" instead of "Pending" in the UI.
      final cloudSyncEnabled = cloudSyncEnabledReader();
      final analysis = _mapper.toAnalysis(
        result: result,
        boundingBox: bbox,
        patientId: patientId,
        anchor: anchor,
        distanceCm: state.distance.isKnown ? state.distance.cm : null,
        imageHash: hash,
        pendingUpload: cloudSyncEnabled,
        localOnly: !cloudSyncEnabled,
      );

      // Persist encrypted (metadata + image blob AES-256)
      await _repository.save(analysis, jpegBytes: bytes);

      // Activity log: a freshly captured scan + its prediction. The
      // high-risk row is split out so the user gets a separate banner
      // when the model flags something concerning — easier to spot in
      // the activity list later.
      _notifications?.recordScanCompleted(
        scanId: analysis.id,
        bodyRegion: analysis.bodyRegion,
      );
      _notifications?.recordPredictionReady(
        scanId: analysis.id,
        label: result.topLabel.display,
        confidence: result.confidence,
      );
      if (result.warningLevel == WarningLevel.alert) {
        _notifications?.recordHighRiskDetected(
          scanId: analysis.id,
          label: result.topLabel.display,
          confidence: result.confidence,
        );
      }

      // Prioritise the cloud upload: when consent is on AND the device is
      // online, await the upload before showing the result so the row
      // can't be lost to an immediate sign-out (which purges the local
      // DB). When offline, the row stays pending and the orchestrator
      // drains the queue on the next connectivity event. Notify the host
      // either way so the home counts/history list refresh.
      if (cloudSyncEnabled && await isOnlineChecker()) {
        if (!mounted) return;
        state = state.copyWith(phase: DetectionPhase.uploading);
        final ok = await uploadScan(analysis);
        if (!ok) {
          AppLogger.warning(
            'Inline cloud upload failed for ${analysis.id} — '
            'row stays pending for the next sync trigger',
            tag: 'Detection',
          );
        }
      }
      _onScanSaved?.call();

      if (!mounted) return;
      state = state.copyWith(
        phase: DetectionPhase.presented,
        result: result,
        anchor: anchor,
        savedAnalysisId: analysis.id,
        capturedImageBytes: bytes,
      );
    } on NotSkinDetectedException catch (e) {
      // Cascade stage-1 rejected the frame. Don't unlock exposure here —
      // [reset] / [restartMapping] handle that when the user dismisses
      // the educational dialog.
      if (kDebugMode) debugPrint('Skin-gate rejected capture: $e');
      if (!mounted) return;
      state = state.copyWith(phase: DetectionPhase.notSkinRejected);
    } catch (e, st) {
      if (kDebugMode) debugPrint('Capture pipeline failed: $e\n$st');
      if (!mounted) return;
      state = state.copyWith(
        phase: DetectionPhase.failed,
        errorMessage: 'Capture failed: $e',
      );
    }
  }

  /// Reset the floating label and return to live preview. Called when the
  /// user taps the "Scan again" CTA after seeing a result.
  Future<void> reset() async {
    // Ensure the image stream is running for readiness updates
    await _camera.restartSampling();
    await _camera.unlockExposure();
    if (!mounted) return;
    state = state.copyWith(
      phase: DetectionPhase.ready,
      clearResult: true,
      clearError: true,
    );
  }

  /// Per-frame world-anchor → screen-pixel projection for the floating
  /// diagnosis label. Returns pixel coordinates in the preview widget space.
  Future<Offset?> projectAnchorToScreen({required Size previewSize}) async {
    final anchor = state.anchor;
    if (anchor == null) return null;
    return _translator.anchorToScreen(anchor, previewSize: previewSize);
  }

  @override
  void dispose() {
    _distanceSub?.cancel();
    _session.stop();
    super.dispose();
  }
}

/// Bound from `main.dart` once the orchestrator is wired so this file
/// doesn't import sync_orchestrator.dart (which already depends on
/// providers declared here). Whoever creates the orchestrator must call
/// [bindPostCaptureHook] to register the callback.
typedef PostCaptureHook = void Function();

PostCaptureHook? _postCaptureHook;

void bindPostCaptureHook(PostCaptureHook hook) {
  _postCaptureHook = hook;
}

/// Provider scoped to the AR scan screen lifecycle. Auto-disposed on screen
/// exit so the AR session and TFLite isolate are torn down promptly.
final detectionControllerProvider =
    StateNotifierProvider.autoDispose<DetectionController, DetectionState>(
  (ref) {
    final user = ref.watch(authControllerProvider).user;
    final orchestrator = ref.read(syncOrchestratorProvider);
    return DetectionController(
      session: ref.watch(arSessionProvider),
      inference: ref.watch(inferenceServiceProvider),
      skinGate: ref.watch(skinGateServiceProvider),
      cropper: ref.watch(captureCropperProvider),
      camera: ref.watch(scanCameraPortProvider),
      translator: ref.watch(coordinateTranslatorProvider),
      mapper: ref.watch(detectionResultMapperProvider),
      repository: ref.watch(lesionRepositoryProvider),
      patientId: user?.id ?? 'anonymous',
      cloudSyncEnabledReader: () =>
          ref.read(privacySettingsProvider).cloudSyncEnabled,
      isOnlineChecker: () async {
        final results = await Connectivity().checkConnectivity();
        return results.any(
          (r) =>
              r == ConnectivityResult.wifi ||
              r == ConnectivityResult.mobile ||
              r == ConnectivityResult.ethernet ||
              r == ConnectivityResult.vpn,
        );
      },
      uploadScan: orchestrator.uploadOne,
      notifications: ref.read(notificationsControllerProvider.notifier),
      onScanSaved: () => _postCaptureHook?.call(),
    )..bootstrap();
  },
);
