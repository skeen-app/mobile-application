import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../domain/ar_geometry.dart';
import '../domain/inference_result.dart';
import '../domain/ports.dart';
import 'coordinate_translator.dart';
import 'detection_result_mapper.dart';
import 'providers.dart';

/// Phases of the AR-AI bridge flow, exposed to the UI as a single state
/// stream so the presentation layer can react declaratively rather than
/// juggling several booleans.
enum DetectionPhase {
  initializing,
  ready,
  capturing,
  analyzing,
  presented,
  failed,
}

@immutable
class DetectionState {
  const DetectionState({
    required this.phase,
    this.distance = const CaptureDistance.unknown(),
    this.result,
    this.anchor,
    this.savedAnalysisId,
    this.flashOn = false,
    this.zoom = 1.0,
    this.errorMessage,
  });

  final DetectionPhase phase;
  final CaptureDistance distance;
  final InferenceResult? result;
  final WorldAnchor? anchor;
  final String? savedAnalysisId;
  final bool flashOn;
  final double zoom;
  final String? errorMessage;

  DetectionState copyWith({
    DetectionPhase? phase,
    CaptureDistance? distance,
    InferenceResult? result,
    WorldAnchor? anchor,
    String? savedAnalysisId,
    bool? flashOn,
    double? zoom,
    String? errorMessage,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return DetectionState(
      phase: phase ?? this.phase,
      distance: distance ?? this.distance,
      result: clearResult ? null : (result ?? this.result),
      anchor: clearResult ? null : (anchor ?? this.anchor),
      savedAnalysisId: clearResult
          ? null
          : (savedAnalysisId ?? this.savedAnalysisId),
      flashOn: flashOn ?? this.flashOn,
      zoom: zoom ?? this.zoom,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Riverpod controller orchestrating the single-shot AR-AI pipeline:
/// `start session → live distance updates → capture frame → TFLite classify
/// → hit-test for anchor → persist encrypted → present floating label`.
///
/// The controller is the only place that talks to multiple ports at once;
/// individual screens read [DetectionState] and call action methods.
class DetectionController extends StateNotifier<DetectionState> {
  DetectionController({
    required ArSessionPort session,
    required InferenceServicePort inference,
    required CoordinateTranslator translator,
    required DetectionResultMapper mapper,
    required LesionRepositoryPort repository,
    required this.patientId,
  })  : _session = session,
        _inference = inference,
        _translator = translator,
        _mapper = mapper,
        _repository = repository,
        super(const DetectionState(phase: DetectionPhase.initializing));

  final ArSessionPort _session;
  final InferenceServicePort _inference;
  final CoordinateTranslator _translator;
  final DetectionResultMapper _mapper;
  final LesionRepositoryPort _repository;
  final String patientId;

  StreamSubscription<CaptureDistance>? _distanceSub;

  Future<void> bootstrap() async {
    try {
      await Future.wait([
        _session.start(),
        _inference.load(),
        _repository.initialize(),
      ]);
      _distanceSub = _session.distance.listen((d) {
        if (!mounted) return;
        state = state.copyWith(distance: d);
      });
      state = state.copyWith(phase: DetectionPhase.ready, clearError: true);
    } catch (e, st) {
      if (kDebugMode) debugPrint('Detection bootstrap failed: $e\n$st');
      state = state.copyWith(
        phase: DetectionPhase.failed,
        errorMessage: 'Could not start AR session: $e',
      );
    }
  }

  Future<void> setFlash(bool on) async {
    await _session.setFlash(on);
    state = state.copyWith(flashOn: on);
  }

  Future<void> setZoom(double zoom) async {
    final clamped = zoom.clamp(1.0, 5.0);
    await _session.setZoom(clamped);
    state = state.copyWith(zoom: clamped);
  }

  /// The capture pipeline. Designed to keep the AR view at 60 fps:
  /// inference runs in an isolate (see [TfliteInferenceService]) and we
  /// only block the controller's own state machine, not the render loop.
  ///
  /// JPEG bytes come from the camera plugin (which owns the preview
  /// surface), not from the AR session — the native ARSession runs in
  /// parallel for depth/anchor only.
  Future<void> captureWithBytes({
    required Uint8List bytes,
    required Size previewSize,
  }) async {
    if (state.phase != DetectionPhase.ready) return;
    state = state.copyWith(phase: DetectionPhase.capturing, clearResult: true);

    try {
      state = state.copyWith(phase: DetectionPhase.analyzing);
      final result = await _inference.classify(bytes);

      // Build the bbox from the on-screen reticle (centered square ~33% of
      // the shorter dimension). When a real detector lands this is the only
      // line that changes — everything else already speaks BoundingBox.
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

      final anchor = await _translator.bboxToAnchor(bbox);

      final analysis = _mapper.toAnalysis(
        result: result,
        boundingBox: bbox,
        patientId: patientId,
        anchor: anchor,
        distanceCm: state.distance.isKnown ? state.distance.cm : null,
      );
      await _repository.save(analysis);

      state = state.copyWith(
        phase: DetectionPhase.presented,
        result: result,
        anchor: anchor,
        savedAnalysisId: analysis.id,
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('Capture pipeline failed: $e\n$st');
      state = state.copyWith(
        phase: DetectionPhase.failed,
        errorMessage: 'Capture failed: $e',
      );
    }
  }

  /// Reset the floating label and return to live preview. Called when the
  /// user taps the "Scan again" CTA after seeing a result.
  Future<void> reset() async {
    state = state.copyWith(
      phase: DetectionPhase.ready,
      clearResult: true,
      clearError: true,
    );
  }

  Future<Offset?> projectAnchorToScreen() async {
    final anchor = state.anchor;
    if (anchor == null) return null;
    return _translator.anchorToScreen(anchor);
  }

  @override
  void dispose() {
    _distanceSub?.cancel();
    _session.stop();
    super.dispose();
  }
}

/// Provider scoped to the AR scan screen lifecycle. Auto-disposed on screen
/// exit so the AR session and TFLite isolate are torn down promptly.
final detectionControllerProvider =
    StateNotifierProvider.autoDispose<DetectionController, DetectionState>(
  (ref) {
    final user = ref.watch(authControllerProvider).user;
    return DetectionController(
      session: ref.watch(arSessionProvider),
      inference: ref.watch(inferenceServiceProvider),
      translator: ref.watch(coordinateTranslatorProvider),
      mapper: ref.watch(detectionResultMapperProvider),
      repository: ref.watch(lesionRepositoryProvider),
      // Patient-context aggregate not yet built; auth user.id is the
      // canonical owner identifier in the meantime.
      patientId: user?.id ?? 'anonymous',
    )..bootstrap();
  },
);
