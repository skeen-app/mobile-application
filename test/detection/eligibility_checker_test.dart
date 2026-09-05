import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/application/eligibility_checker.dart';
import 'package:skeen/features/detection/application/experiment_session.dart';
import 'package:skeen/features/detection/domain/camera_intrinsics.dart';
import 'package:skeen/features/detection/domain/capture_roi.dart';
import 'package:skeen/features/detection/domain/capture_stability.dart';
import 'package:skeen/features/detection/domain/capture_telemetry.dart';
import 'package:skeen/features/detection/domain/device_eligibility.dart';
import 'package:skeen/features/detection/domain/luma_frame.dart';
import 'package:skeen/features/detection/domain/ports.dart';
import 'package:skeen/features/detection/domain/roi_frame_metrics.dart';

/// Device exclusion has to be **declared and countable**.
///
/// Before this check, a phone with no gyroscope sat in the guided arm with the
/// shutter permanently locked: correct under fail-closed, but silent. The
/// participant dropped out and the study recorded nothing — and because
/// gyroscope availability tracks device tier, that invisible dropout would
/// have reshaped the sample.
void main() {
  late _FakeCamera camera;
  late _FakeSensor sensor;
  late _FakeIntrinsics intrinsics;
  late _FakeTelemetry telemetry;
  late ExperimentSession session;
  var nextId = 0;

  EligibilityChecker build({
    bool hasCamera = true,
    bool hasGyroscope = true,
    bool hasIntrinsics = true,
  }) {
    camera = _FakeCamera(present: hasCamera);
    sensor = _FakeSensor(present: hasGyroscope);
    intrinsics = _FakeIntrinsics(present: hasIntrinsics);
    telemetry = _FakeTelemetry();
    session = const ExperimentSession(
      condition: CaptureCondition.guided,
      participantId: 'P014',
    );
    nextId = 0;
    return EligibilityChecker(
      camera: camera,
      stabilitySensor: sensor,
      cameraIntrinsics: intrinsics,
      telemetry: telemetry,
      sessionReader: () => session,
      idFactory: () => 'rec-${nextId++}',
      clock: () => DateTime.utc(2026, 4, 1, 9),
    );
  }

  group('probing', () {
    test('a fully capable device is eligible', () async {
      final result = await build().evaluate();

      expect(result.isEligible, isTrue);
      expect(result.missing, isEmpty);
    });

    test('a missing gyroscope is an exclusion, not a silent lock', () async {
      final result = await build(hasGyroscope: false).evaluate();

      expect(result.isEligible, isFalse);
      expect(result.lacks(EligibilityRequirement.gyroscope), isTrue);
      expect(result.lacks(EligibilityRequirement.camera), isFalse);
    });

    test('a missing camera is an exclusion', () async {
      final result = await build(hasCamera: false).evaluate();

      expect(result.lacks(EligibilityRequirement.camera), isTrue);
    });

    test('every missing capability is reported, not just the first', () async {
      final result = await build(
        hasCamera: false,
        hasGyroscope: false,
        hasIntrinsics: false,
      ).evaluate();

      expect(result.missing, {
        EligibilityRequirement.camera,
        EligibilityRequirement.gyroscope,
        EligibilityRequirement.cameraIntrinsics,
      });
    });

    test('no reported focal length is an exclusion — tilt is unmeasurable',
        () async {
      // WP-3: the physical gate needs intrinsics. A device that cannot
      // report them would sit with the shutter locked; it is excluded on
      // that named ground instead.
      final result = await build(hasIntrinsics: false).evaluate();

      expect(result.isEligible, isFalse);
      expect(result.lacks(EligibilityRequirement.cameraIntrinsics), isTrue);
      expect(
        telemetry.eligibilityRows.single.toJson()['missing'],
        ['camera_intrinsics'],
      );
    });

    test('the hardware is probed once and cached', () async {
      // The gyroscope probe costs a real wait on device; re-running it on
      // every screen entry would put a two-second stall in front of capture.
      final checker = build();
      await checker.evaluate();
      await checker.evaluate();
      await checker.evaluate();

      expect(camera.probes, 1);
      expect(sensor.probes, 1);
    });
  });

  group('recording the exclusion', () {
    test('an excluded device writes a row naming the reason', () async {
      await build(hasGyroscope: false).evaluate();

      expect(telemetry.eligibilityRows, hasLength(1));
      final json = telemetry.eligibilityRows.single.toJson();
      expect(json['kind'], 'eligibility');
      expect(json['eligible'], isFalse);
      expect(json['missing'], ['gyroscope']);
      expect(json['participant_id'], 'P014');
      expect(json['condition'], 'guided');
      expect(json['checked_at'], '2026-04-01T09:00:00.000Z');
    });

    test('an ELIGIBLE device is recorded too — it is the denominator',
        () async {
      // Without these rows an analyst cannot tell "no exclusions" from
      // "the check never ran", and the exclusion rate is uninterpretable.
      await build().evaluate();

      expect(telemetry.eligibilityRows, hasLength(1));
      expect(telemetry.eligibilityRows.single.toJson()['eligible'], isTrue);
    });

    test('repeated checks for one participant write one row', () async {
      final checker = build();
      await checker.evaluate();
      await checker.evaluate();

      expect(telemetry.eligibilityRows, hasLength(1));
    });

    test('a re-assigned participant gets their own row', () async {
      // Devices are configured before a participant is attached, so the first
      // check can land against "unassigned". The exclusion still has to be
      // attributable once the coordinator assigns someone.
      final checker = build(hasGyroscope: false);
      session = const ExperimentSession(
        condition: CaptureCondition.guided,
        participantId: ExperimentSession.unassignedParticipant,
      );
      await checker.evaluate();

      session = const ExperimentSession(
        condition: CaptureCondition.control,
        participantId: 'P022',
      );
      await checker.evaluate();

      expect(telemetry.eligibilityRows, hasLength(2));
      expect(
        telemetry.eligibilityRows.map((r) => r.participantId),
        ['unassigned', 'P022'],
      );
      // Still the cached hardware verdict — the device did not change.
      expect(sensor.probes, 1);
      expect(
        telemetry.eligibilityRows.last.eligibility
            .lacks(EligibilityRequirement.gyroscope),
        isTrue,
      );
    });
  });

  group('ExperimentSession', () {
    test('an unassigned session is not a study device', () {
      const ordinary = ExperimentSession(
        condition: CaptureCondition.guided,
        participantId: ExperimentSession.unassignedParticipant,
      );

      expect(ordinary.isStudyDevice, isFalse);
    });

    test('an assigned participant makes it a study device', () {
      const study = ExperimentSession(
        condition: CaptureCondition.guided,
        participantId: 'P001',
      );

      expect(study.isStudyDevice, isTrue);
    });
  });
}

// ──────────────────────────────────────────────────────────────────────
// Fakes — hand written, matching the repo's mock-framework-free style.
// ──────────────────────────────────────────────────────────────────────

class _FakeCamera implements ScanCameraServicePort {
  _FakeCamera({required this.present});

  final bool present;
  int probes = 0;

  @override
  Future<bool> hasCamera() async {
    probes++;
    return present;
  }

  @override
  Stream<LumaFrame> get detectionFrames => const Stream.empty();

  @override
  int get sensorOrientationDegrees => 90;

  @override
  bool get isReady => present;

  @override
  Stream<RoiFrameMetrics> get metrics => const Stream.empty();

  @override
  CaptureRoi get roi => CaptureRoi.full;

  @override
  void setRoi(CaptureRoi roi) {}

  @override
  Size? get previewFrameSize => null;

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
  Future<double> getMaxZoom() async => 1.0;

  @override
  Future<void> dispose() async {}
}

class _FakeSensor implements StabilitySensorPort {
  _FakeSensor({required this.present});

  final bool present;
  int probes = 0;

  @override
  Future<bool> isAvailable({Duration timeout = const Duration(seconds: 2)}) async {
    probes++;
    return present;
  }

  @override
  Stream<double> get angularSpeed => const Stream.empty();

  @override
  Stream<AngularVelocity> get angularVelocity => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

class _FakeIntrinsics implements CameraIntrinsicsPort {
  _FakeIntrinsics({required this.present});

  final bool present;

  @override
  Future<CameraIntrinsics?> read({
    required int frameWidth,
    required int frameHeight,
  }) async =>
      present
          ? CameraIntrinsics(
              focalPx: 800,
              principalX: frameWidth / 2,
              principalY: frameHeight / 2,
              frameWidth: frameWidth,
              frameHeight: frameHeight,
            )
          : null;
}

class _FakeTelemetry implements CaptureTelemetryPort {
  final List<CaptureTelemetryRecord> captureRows = [];
  final List<DeviceEligibilityRecord> eligibilityRows = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> record(CaptureTelemetryRecord record) async =>
      captureRows.add(record);

  @override
  Future<void> recordEligibility(DeviceEligibilityRecord record) async =>
      eligibilityRows.add(record);

  @override
  Future<String> exportJsonl() async => '';

  @override
  Future<int> count() async => captureRows.length + eligibilityRows.length;
}
