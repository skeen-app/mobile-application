import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/application/marker_detector.dart';
import 'package:skeen/features/detection/application/pose_tracker.dart';
import 'package:skeen/features/detection/domain/camera_intrinsics.dart';
import 'package:skeen/features/detection/domain/capture_roi.dart';
import 'package:skeen/features/detection/domain/capture_stability.dart';
import 'package:skeen/features/detection/domain/display_mapping.dart';
import 'package:skeen/features/detection/domain/luma_frame.dart';
import 'package:skeen/features/detection/domain/ports.dart';
import 'package:skeen/features/detection/domain/roi_frame_metrics.dart';
import 'package:skeen/features/detection/domain/skin_plane_pose.dart';
import 'package:skeen/features/detection/infrastructure/camera_intrinsics_service.dart';

/// WP-1 — the tracker's contract: cadence, staleness, prediction, and no
/// subscription leaks across restarts.
///
/// Detection itself is injected as a synchronous fake here; the detector and
/// estimator have their own accuracy suite in `marker_pose_test.dart`.
void main() {
  late _FakeCamera camera;
  late _FakeSensor sensor;
  late _FakeIntrinsics intrinsics;
  late DateTime clock;
  late int detectCalls;

  /// A 100 px square centred in a 320×240 detection frame (×2 to full).
  /// At f = 800 on the 640×480 full frame that is 200 px for 30 mm.
  MarkerDetection square() => const MarkerDetection(
        corners: [
          Offset(110, 70),
          Offset(210, 70),
          Offset(210, 170),
          Offset(110, 170),
        ],
        rotation: 0,
        hammingErrors: 0,
        elapsedMs: 7,
      );

  LumaFrame frame() => LumaFrame(
        luma: Uint8List(320 * 240),
        width: 320,
        height: 240,
        capturedAt: clock,
        scaleToFull: 2.0,
        zoom: 1.0,
      );

  PoseTracker build({
    MarkerDetectFn? detect,
    bool withIntrinsics = true,
    int sensorOrientation = 90,
  }) {
    camera = _FakeCamera(sensorOrientation: sensorOrientation);
    sensor = _FakeSensor();
    intrinsics = _FakeIntrinsics(available: withIntrinsics);
    clock = DateTime(2026, 9, 4, 10);
    detectCalls = 0;
    return PoseTracker(
      camera: camera,
      stabilitySensor: sensor,
      intrinsics: intrinsics,
      clock: () => clock,
      detect: detect ??
          (f) async {
            detectCalls++;
            return square();
          },
    );
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('detection → pose', () {
    test('a detected marker yields a pose in full-frame coordinates',
        () async {
      final tracker = build();
      await tracker.start();
      final seen = <SkinPlanePose?>[];
      final sub = tracker.pose.listen(seen.add);

      camera.emit(frame());
      await settle();
      await settle();

      expect(seen, hasLength(1));
      final pose = seen.single!;
      expect(pose.source, PoseSource.detected);
      // 200 px across 30 mm.
      expect(pose.pxPerMm, closeTo(200 / 30, 0.05));
      expect(pose.tiltDeg, lessThan(1.0));
      expect(pose.markerCentre.dx, closeTo(320, 0.5));
      expect(pose.markerCentre.dy, closeTo(240, 0.5));
      expect(pose.detectionMs, 7);
      expect(tracker.current, isNotNull);

      await sub.cancel();
      await tracker.dispose();
    });

    test('a frame with no marker leaves the pose unchanged', () async {
      final tracker = build(detect: (_) async => null);
      await tracker.start();
      final seen = <SkinPlanePose?>[];
      final sub = tracker.pose.listen(seen.add);

      camera.emit(frame());
      await settle();

      expect(seen, isEmpty);
      expect(tracker.current, isNull);

      await sub.cancel();
      await tracker.dispose();
    });

    test('frames arriving while a detection is in flight are dropped, not '
        'queued', () async {
      final gate = Completer<MarkerDetection?>();
      var calls = 0;
      final tracker = build(detect: (_) {
        calls++;
        return gate.future;
      });
      await tracker.start();

      camera.emit(frame());
      camera.emit(frame());
      camera.emit(frame());
      await settle();
      gate.complete(square());
      await settle();
      await settle();

      expect(calls, 1);
      expect(tracker.droppedFrameCount, 2);
      expect(tracker.current, isNotNull);

      await tracker.dispose();
    });

    test('zoom scales the focal length, not the marker', () async {
      // At 2× digital zoom the same 200 px square is 15 mm of skin, so px/mm
      // doubles — but tilt (which depends on f) must not change.
      final tracker = build();
      await tracker.start();
      final seen = <SkinPlanePose?>[];
      final sub = tracker.pose.listen(seen.add);

      camera.emit(LumaFrame(
        luma: Uint8List(320 * 240),
        width: 320,
        height: 240,
        capturedAt: clock,
        scaleToFull: 2.0,
        zoom: 2.0,
      ));
      await settle();
      await settle();

      expect(intrinsics.lastZoomSeen, isNull,
          reason: 'zoom is applied in the tracker, not the port');
      expect(seen.single!.tiltDeg, lessThan(1.0));

      await sub.cancel();
      await tracker.dispose();
    });
  });

  group('fail-closed', () {
    test('no intrinsics ⇒ no pose, and the tracker says why', () async {
      final tracker = build(withIntrinsics: false);
      await tracker.start();
      final seen = <SkinPlanePose?>[];
      final sub = tracker.pose.listen(seen.add);

      camera.emit(frame());
      await settle();
      await settle();

      expect(seen, isEmpty);
      expect(tracker.current, isNull);
      expect(tracker.intrinsicsUnavailable, isTrue);

      await sub.cancel();
      await tracker.dispose();
    });

    test('a pose goes stale after 400 ms without a real detection', () async {
      final tracker = build();
      await tracker.start();
      camera.emit(frame());
      await settle();
      await settle();
      expect(tracker.current, isNotNull);

      clock = clock.add(const Duration(milliseconds: 399));
      expect(tracker.current, isNotNull);

      clock = clock.add(const Duration(milliseconds: 2));
      expect(tracker.current, isNull, reason: 'stale ⇒ no pose');
      expect(tracker.lastDetected, isNotNull,
          reason: 'the last detection is still there for telemetry');

      await tracker.dispose();
    });

    test('the stream announces the pose going stale', () async {
      final tracker = build();
      await tracker.start();
      final seen = <SkinPlanePose?>[];
      final sub = tracker.pose.listen(seen.add);
      camera.emit(frame());
      await settle();
      await settle();

      clock = clock.add(const Duration(milliseconds: 500));
      // The stale sweep runs on a real 100 ms timer.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(seen.last, isNull);

      await sub.cancel();
      await tracker.dispose();
    });
  });

  group('gyroscope prediction', () {
    test('rotating the phone about the stream x axis tips the tilt', () async {
      // sensorOrientation 0 maps device x → stream x directly.
      final tracker = build(sensorOrientation: 0);
      await tracker.start();
      final seen = <SkinPlanePose?>[];
      final sub = tracker.pose.listen(seen.add);
      camera.emit(frame());
      await settle();
      await settle();
      expect(seen.single!.tiltDeg, lessThan(1.0));

      // 0.2 rad/s about device x for 0.5 s = 0.1 rad ≈ 5.73°.
      var t = clock;
      sensor.emit(AngularVelocity(x: 0.2, y: 0, z: 0, at: t));
      for (var i = 0; i < 10; i++) {
        t = t.add(const Duration(milliseconds: 50));
        sensor.emit(AngularVelocity(x: 0.2, y: 0, z: 0, at: t));
      }
      await settle();

      final predicted = seen.last!;
      expect(predicted.source, PoseSource.predicted);
      expect(predicted.tiltDeg, closeTo(5.73, 0.3));
      // Px/mm is a property of distance, unchanged by a pure rotation.
      expect(predicted.pxPerMm, closeTo(seen.first!.pxPerMm, 1e-6));
      // The plane→image map moved with the rotation: the marker centre
      // projects to a different pixel now.
      expect((predicted.markerCentre - predicted.project(0, 0)!).distance,
          greaterThan(5));

      await sub.cancel();
      await tracker.dispose();
    });

    test('a real detection resets the prediction', () async {
      final tracker = build(sensorOrientation: 0);
      await tracker.start();
      final seen = <SkinPlanePose?>[];
      final sub = tracker.pose.listen(seen.add);
      camera.emit(frame());
      await settle();
      await settle();

      var t = clock;
      sensor.emit(AngularVelocity(x: 0.5, y: 0, z: 0, at: t));
      t = t.add(const Duration(milliseconds: 100));
      sensor.emit(AngularVelocity(x: 0.5, y: 0, z: 0, at: t));
      await settle();
      expect(seen.last!.source, PoseSource.predicted);

      camera.emit(frame());
      await settle();
      await settle();

      expect(seen.last!.source, PoseSource.detected);
      expect(seen.last!.tiltDeg, lessThan(1.0));

      await sub.cancel();
      await tracker.dispose();
    });

    test('a stale pose is not predicted forward', () async {
      final tracker = build(sensorOrientation: 0);
      await tracker.start();
      final seen = <SkinPlanePose?>[];
      final sub = tracker.pose.listen(seen.add);
      camera.emit(frame());
      await settle();
      await settle();

      clock = clock.add(const Duration(milliseconds: 600));
      var t = clock;
      sensor.emit(AngularVelocity(x: 0.5, y: 0, z: 0, at: t));
      t = t.add(const Duration(milliseconds: 100));
      sensor.emit(AngularVelocity(x: 0.5, y: 0, z: 0, at: t));
      await settle();

      expect(seen.where((p) => p?.source == PoseSource.predicted), isEmpty);

      await sub.cancel();
      await tracker.dispose();
    });

    test('device→stream axis mapping for the common 90° mounting', () {
      final g = AngularVelocity(x: 1, y: 2, z: 3, at: DateTime(2026));
      expect(gyroToStreamFrame(g, 90), [-2, -1, -3]);
      expect(gyroToStreamFrame(g, 270), [2, 1, -3]);
      expect(gyroToStreamFrame(g, 0), [1, -2, -3]);
      expect(gyroToStreamFrame(g, 180), [-1, 2, -3]);
    });
  });

  group('subscription lifecycle', () {
    test('three restarts still process each frame exactly once', () async {
      // The leak the module has been bitten by twice: start() on every app
      // resume without cancelling the previous listener.
      final tracker = build();
      await tracker.start();
      await tracker.start();
      await tracker.start();
      final seen = <SkinPlanePose?>[];
      final sub = tracker.pose.listen(seen.add);

      camera.emit(frame());
      await settle();
      await settle();

      expect(detectCalls, 1);
      expect(seen, hasLength(1));

      await sub.cancel();
      await tracker.dispose();
    });

    test('stop() clears the pose and releases the streams', () async {
      final tracker = build();
      await tracker.start();
      camera.emit(frame());
      await settle();
      await settle();
      expect(tracker.current, isNotNull);

      await tracker.stop();

      expect(tracker.current, isNull);
      camera.emit(frame());
      await settle();
      await settle();
      expect(detectCalls, 1, reason: 'no listener after stop');

      await tracker.dispose();
    });
  });

  group('intrinsics conversion', () {
    test('Android focal length + sensor size', () {
      // 4.25 mm lens on a 6.4 mm-wide sensor, 1280-wide stream.
      final k = intrinsicsFromPlatform(
        {'focalMm': 4.25, 'sensorWidthMm': 6.4},
        frameWidth: 1280,
        frameHeight: 720,
      );

      expect(k, isNotNull);
      expect(k!.focalPx, closeTo(850, 0.5));
      expect(k.principalX, 640);
      expect(k.principalY, 360);
    });

    test('iOS horizontal field of view', () {
      final k = intrinsicsFromPlatform(
        {'horizontalFovDeg': 60.0},
        frameWidth: 1280,
        frameHeight: 720,
      );

      expect(k, isNotNull);
      // f = (W/2) / tan(30°) = 640 / 0.5774
      expect(k!.focalPx, closeTo(1108.5, 1.0));
    });

    test('missing or absurd values are "no intrinsics", never a default',
        () {
      expect(intrinsicsFromPlatform({}, frameWidth: 1280, frameHeight: 720),
          isNull);
      expect(
          intrinsicsFromPlatform({'focalMm': 0, 'sensorWidthMm': 6.4},
              frameWidth: 1280, frameHeight: 720),
          isNull);
      expect(
          intrinsicsFromPlatform({'horizontalFovDeg': 200.0},
              frameWidth: 1280, frameHeight: 720),
          isNull);
    });

    test('zoom scales f, not the principal point', () {
      const k = CameraIntrinsics(
        focalPx: 800,
        principalX: 320,
        principalY: 240,
        frameWidth: 640,
        frameHeight: 480,
      );
      final z = k.zoomed(2.0);
      expect(z.focalPx, 1600);
      expect(z.principalX, 320);
    });
  });
}

// ──────────────────────────────────────────────────────────────────────
// Fakes — hand written, matching the repo's mock-framework-free style.
// ──────────────────────────────────────────────────────────────────────

class _FakeCamera implements ScanCameraServicePort {
  _FakeCamera({required this.sensorOrientation});

  final int sensorOrientation;
  final StreamController<LumaFrame> _frames =
      StreamController<LumaFrame>.broadcast();

  void emit(LumaFrame f) => _frames.add(f);

  @override
  Stream<LumaFrame> get detectionFrames => _frames.stream;

  @override
  int get sensorOrientationDegrees => sensorOrientation;

  @override
  Stream<RoiFrameMetrics> get metrics => const Stream.empty();

  @override
  CaptureRoi get roi => CaptureRoi.full;

  @override
  void setRoi(CaptureRoi roi) {}

  @override
  Size? get previewFrameSize => const Size(640, 480);

  @override
  bool get isReady => true;

  @override
  Future<bool> hasCamera() async => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<Uint8List?> captureStandardized() async => null;

  @override
  Future<void> restartSampling() async {}

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
  Future<void> dispose() async => _frames.close();
}

class _FakeSensor implements StabilitySensorPort {
  final StreamController<AngularVelocity> _velocity =
      StreamController<AngularVelocity>.broadcast();

  void emit(AngularVelocity v) => _velocity.add(v);

  @override
  Stream<AngularVelocity> get angularVelocity => _velocity.stream;

  @override
  Stream<double> get angularSpeed => const Stream.empty();

  @override
  Future<bool> isAvailable({Duration timeout = const Duration(seconds: 2)}) async =>
      true;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

class _FakeIntrinsics implements CameraIntrinsicsPort {
  _FakeIntrinsics({required this.available});

  final bool available;
  double? lastZoomSeen;

  @override
  Future<CameraIntrinsics?> read({
    required int frameWidth,
    required int frameHeight,
  }) async {
    if (!available) return null;
    return CameraIntrinsics(
      focalPx: 800,
      principalX: frameWidth / 2,
      principalY: frameHeight / 2,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
    );
  }
}
