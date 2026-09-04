import 'package:uuid/uuid.dart';

import '../domain/capture_telemetry.dart';
import '../domain/device_eligibility.dart';
import '../domain/ports.dart';
import 'experiment_session.dart';

/// Start-of-session hardware check for the study.
///
/// The problem it closes: a device with no gyroscope left the guided arm's
/// shutter locked forever. Fail-closed was right — the stability signal is
/// measured, and an unmeasured signal must never read as passing — but being
/// *silent* about it was not. The participant could not produce a capture,
/// gave up, and nothing recorded why. Gyroscope availability tracks device
/// tier, so that silent failure would have skewed the sample toward
/// higher-end phones without anyone being able to see it in the data.
///
/// The probe result is cached: capabilities are a property of the hardware,
/// not of the moment. The telemetry row is (re)written whenever the
/// participant identifier changes, so a device configured before the
/// participant was assigned still ends up with a row attributed correctly.
class EligibilityChecker {
  EligibilityChecker({
    required ScanCameraServicePort camera,
    required StabilitySensorPort stabilitySensor,
    required CaptureTelemetryPort telemetry,
    required ExperimentSession Function() sessionReader,
    Duration gyroscopeProbeTimeout = const Duration(seconds: 2),
    String Function()? idFactory,
    DateTime Function()? clock,
  })  : _camera = camera,
        _stabilitySensor = stabilitySensor,
        _telemetry = telemetry,
        _sessionReader = sessionReader,
        _gyroscopeProbeTimeout = gyroscopeProbeTimeout,
        _idFactory = idFactory ?? (() => const Uuid().v4()),
        _now = clock ?? DateTime.now;

  final ScanCameraServicePort _camera;
  final StabilitySensorPort _stabilitySensor;
  final CaptureTelemetryPort _telemetry;
  final ExperimentSession Function() _sessionReader;
  final Duration _gyroscopeProbeTimeout;
  final String Function() _idFactory;
  final DateTime Function() _now;

  DeviceEligibility? _cached;
  String? _recordedFor;

  /// Probes the hardware once, then records the outcome against the current
  /// participant.
  Future<DeviceEligibility> evaluate() async {
    final result = _cached ??= await _probe();
    await _recordIfNeeded(result);
    return result;
  }

  Future<DeviceEligibility> _probe() async {
    final missing = <EligibilityRequirement>{};

    if (!await _camera.hasCamera()) {
      missing.add(EligibilityRequirement.camera);
    }
    if (!await _stabilitySensor.isAvailable(
      timeout: _gyroscopeProbeTimeout,
    )) {
      missing.add(EligibilityRequirement.gyroscope);
    }

    return DeviceEligibility(missing: missing);
  }

  /// Writes one row per participant. Eligible devices are recorded too: they
  /// are the denominator that turns "three exclusions" into a rate.
  Future<void> _recordIfNeeded(DeviceEligibility eligibility) async {
    final session = _sessionReader();
    if (_recordedFor == session.participantId) return;
    _recordedFor = session.participantId;

    await _telemetry.recordEligibility(
      DeviceEligibilityRecord(
        id: _idFactory(),
        participantId: session.participantId,
        condition: session.condition,
        checkedAt: _now(),
        eligibility: eligibility,
      ),
    );
  }
}
