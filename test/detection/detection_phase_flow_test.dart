import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/application/coordinate_translator.dart';
import 'package:skeen/features/detection/application/detection_controller.dart';
import 'package:skeen/features/detection/application/detection_result_mapper.dart';
import 'package:skeen/features/detection/domain/ar_geometry.dart';
import 'package:skeen/features/detection/domain/capture_roi.dart';
import 'package:skeen/features/detection/domain/inference_result.dart';
import 'package:skeen/features/detection/domain/lesion_analysis.dart';
import 'package:skeen/features/detection/domain/luma_frame.dart';
import 'package:skeen/features/detection/domain/ports.dart';
import 'package:skeen/features/detection/domain/roi_frame_metrics.dart';
import 'package:skeen/features/detection/domain/scan_remote.dart';
import 'package:skeen/features/detection/domain/skin_gate_result.dart';

/// Phase-machine contract behind the P0 capture-flow fixes.
///
/// The bug these lock down was never in the controller: it was that the
/// plain-camera surface ([ScanAMoleScreen]) had no caller for
/// [DetectionController.completeMapping], so the flow sat in
/// `mapping` forever and `captureAndClassify` bailed on its `ready` guard.
/// These tests pin the transitions that surface now drives from its
/// readiness listener, so a future edit can't silently strand it again.
void main() {
  late _FakeArSession session;
  late _FakeCamera camera;
  late _FakeSkinGate skinGate;

  DetectionController build() {
    session = _FakeArSession();
    camera = _FakeCamera();
    skinGate = _FakeSkinGate();
    return DetectionController(
      session: session,
      inference: _FakeInference(),
      skinGate: skinGate,
      cropper: const _PassthroughCropper(),
      camera: camera,
      translator: CoordinateTranslator(session),
      mapper: DetectionResultMapper(),
      repository: _FakeRepository(),
      patientId: 'patient-1',
      cloudSyncEnabledReader: () => false,
      isOnlineChecker: () async => false,
      uploadScan: (_) async => false,
    );
  }

  test('bootstrap parks the flow in mapping, not ready', () async {
    final controller = build();
    await controller.bootstrap();

    // Capture stays locked until a surface says the camera is live.
    expect(controller.state.phase, DetectionPhase.mapping);
  });

  test('completeMapping opens the shutter — the transition the plain-camera '
      'surface had no caller for', () async {
    final controller = build();
    await controller.bootstrap();

    controller.completeMapping();

    expect(controller.state.phase, DetectionPhase.ready);
  });

  test('completeMapping is inert outside the mapping phase', () async {
    // ScanAMoleScreen calls this on EVERY readiness event (~3 Hz), so it has
    // to be a no-op once the flow has moved on — otherwise a late event
    // would yank a presented result back to `ready`.
    final controller = build();
    await controller.bootstrap();
    controller.completeMapping();
    expect(controller.state.phase, DetectionPhase.ready);

    await controller.captureAndClassify(
      previewSize: const Size(400, 800),
      roi: const CaptureRoi(sideFraction: 0.55),
    );
    expect(controller.state.phase, DetectionPhase.notSkinRejected);

    controller.completeMapping();

    expect(controller.state.phase, DetectionPhase.notSkinRejected);
  });

  test('a rejected capture recovers through restartMapping → completeMapping',
      () async {
    // The recovery loop both capture surfaces now share: the skin gate
    // rejects, the screen shows the modal, restartMapping() rewinds to
    // `mapping`, and the next readiness event promotes back to `ready`.
    final controller = build();
    await controller.bootstrap();
    controller.completeMapping();

    await controller.captureAndClassify(
      previewSize: const Size(400, 800),
      roi: const CaptureRoi(sideFraction: 0.55),
    );
    expect(controller.state.phase, DetectionPhase.notSkinRejected);

    await controller.restartMapping();
    expect(controller.state.phase, DetectionPhase.mapping);
    // restartMapping must re-arm the sampling the readiness listener rides on,
    // otherwise the promotion below would never be triggered on device.
    expect(camera.restartSamplingCalls, 1);

    controller.completeMapping();

    expect(controller.state.phase, DetectionPhase.ready);
  });
}

// ──────────────────────────────────────────────────────────────────────
// Fakes — hand written to match the repo's mock-framework-free test style.
// ──────────────────────────────────────────────────────────────────────

class _FakeArSession implements ArSessionPort {
  @override
  Stream<CaptureDistance> get distance => const Stream.empty();

  @override
  Future<ArCapabilities> probeCapabilities() async => ArCapabilities.none;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<WorldAnchor?> hitTest(Offset normalizedScreenPoint) async => null;

  @override
  Future<Offset?> projectToScreen(WorldAnchor anchor) async => null;

  @override
  Future<Uint8List?> captureFrame() async => null;

  @override
  Future<void> setFlash(bool on) async {}

  @override
  Future<void> setZoom(double zoom) async {}
}

class _FakeCamera implements ScanCameraServicePort {
  int restartSamplingCalls = 0;
  CaptureRoi _roi = CaptureRoi.full;

  @override
  bool get isReady => true;

  @override
  Future<bool> hasCamera() async => true;

  @override
  Stream<LumaFrame> get detectionFrames => const Stream.empty();

  @override
  int get sensorOrientationDegrees => 90;

  @override
  Stream<RoiFrameMetrics> get metrics => const Stream.empty();

  @override
  CaptureRoi get roi => _roi;

  @override
  void setRoi(CaptureRoi roi) => _roi = roi;

  @override
  Size? get previewFrameSize => const Size(1280, 720);

  @override
  Future<void> initialize() async {}

  @override
  Future<Uint8List?> captureStandardized() async =>
      Uint8List.fromList(List<int>.filled(64, 7));

  @override
  Future<void> restartSampling() async => restartSamplingCalls++;

  @override
  Future<void> lockExposure() async {}

  @override
  Future<void> unlockExposure() async {}

  @override
  Future<void> setFlash(bool on) async {}

  @override
  Future<void> setZoom(double level) async {}

  @override
  Future<double> getMaxZoom() async => 5.0;

  @override
  Future<void> dispose() async {}
}

/// Always rejects, so the pipeline short-circuits at the cascade's stage 1
/// and never reaches the classifier — these tests are about phases only.
class _FakeSkinGate implements SkinGateServicePort {
  @override
  Future<void> load() async {}

  @override
  Future<SkinGateResult> evaluate(Uint8List jpegBytes) async =>
      const SkinGateResult(skinScore: 0.0);

  @override
  Future<void> dispose() async {}
}

class _FakeInference implements InferenceServicePort {
  @override
  Future<void> load() async {}

  @override
  Future<InferenceResult> classify(Uint8List jpegBytes) async =>
      throw StateError('classifier must not run on a rejected frame');

  @override
  Future<void> dispose() async {}
}

class _PassthroughCropper implements CaptureCropperPort {
  const _PassthroughCropper();

  @override
  Future<CropOutcome> crop(
    Uint8List jpegBytes, {
    required CaptureRoi roi,
  }) async =>
      CropOutcome(bytes: jpegBytes, fracX: 1.0, fracY: 1.0, applied: false);
}

class _FakeRepository implements LesionRepositoryPort {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> save(LesionAnalysis analysis, {Uint8List? jpegBytes}) async {}

  @override
  Future<List<LesionAnalysis>> findByPatient(String patientId) async => [];

  @override
  Future<LesionAnalysis?> findById(String id, {bool includeImage = false}) async =>
      null;

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> updateBodyRegion(String id, String? bodyRegion) async {}

  @override
  Future<List<LesionAnalysis>> findPendingUpload(String patientId) async => [];

  @override
  Future<void> markUploaded(String id) async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> markPendingDeletion(String id) async {}

  @override
  Future<List<String>> findPendingDeletionIds() async => [];

  @override
  Future<void> upsertCloudSnapshot(ScanRemote remote) async {}
}
