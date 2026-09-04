import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/capture_telemetry.dart';

/// Which arm of the paired study this device session is running, and for whom.
///
/// The study compares guided capture against the native camera on the same
/// participants (McNemar), so the app has to be able to run *without* its own
/// guidance — otherwise there is no control arm to compare against.
@immutable
class ExperimentSession {
  const ExperimentSession({
    required this.condition,
    required this.participantId,
  });

  final CaptureCondition condition;

  /// Study identifier for the person holding the phone. Never a name or an
  /// account id — the telemetry sidecar is analysed separately from the
  /// clinical record and must not carry direct identifiers.
  final String participantId;

  bool get isGuided => condition.showsGuidance;

  /// True when this session was launched with a study participant attached.
  /// Ordinary (non-study) use must not be shown study-specific messaging, and
  /// must not be blocked by study eligibility rules.
  bool get isStudyDevice => participantId != unassignedParticipant;

  /// Placeholder used when a build was not launched with study parameters,
  /// so ordinary (non-study) use is still recorded as such rather than being
  /// silently attributed to a participant.
  static const String unassignedParticipant = 'unassigned';

  ExperimentSession copyWith({
    CaptureCondition? condition,
    String? participantId,
  }) =>
      ExperimentSession(
        condition: condition ?? this.condition,
        participantId: participantId ?? this.participantId,
      );

  @override
  bool operator ==(Object other) =>
      other is ExperimentSession &&
      other.condition == condition &&
      other.participantId == participantId;

  @override
  int get hashCode => Object.hash(condition, participantId);
}

/// Session parameters, seeded from `--dart-define` at launch so a field
/// device can be pinned to an arm before it is handed over:
///
/// ```
/// flutter run \
///   --dart-define=SKEEN_TRIAL_CONDITION=control \
///   --dart-define=SKEEN_TRIAL_PARTICIPANT=P014
/// ```
///
/// Both can also be switched at runtime for a within-participant crossover,
/// which is what the paired design actually needs: the same person captures
/// once per arm in a randomised order.
class ExperimentSessionController extends StateNotifier<ExperimentSession> {
  ExperimentSessionController() : super(_fromEnvironment());

  static const String _conditionKey = 'SKEEN_TRIAL_CONDITION';
  static const String _participantKey = 'SKEEN_TRIAL_PARTICIPANT';

  static ExperimentSession _fromEnvironment() {
    const rawCondition =
        String.fromEnvironment(_conditionKey, defaultValue: 'guided');
    const rawParticipant =
        String.fromEnvironment(_participantKey, defaultValue: '');

    // Anything other than an explicit "control" runs guided. A typo in a
    // launch flag must not silently strip the guidance from a device that
    // was meant to have it.
    final condition = rawCondition.trim().toLowerCase() == 'control'
        ? CaptureCondition.control
        : CaptureCondition.guided;

    return ExperimentSession(
      condition: condition,
      participantId: rawParticipant.trim().isEmpty
          ? ExperimentSession.unassignedParticipant
          : rawParticipant.trim(),
    );
  }

  void setCondition(CaptureCondition condition) =>
      state = state.copyWith(condition: condition);

  void setParticipantId(String participantId) {
    final trimmed = participantId.trim();
    state = state.copyWith(
      participantId:
          trimmed.isEmpty ? ExperimentSession.unassignedParticipant : trimmed,
    );
  }

  /// Crossover helper for the in-clinic protocol.
  void toggleCondition() => setCondition(
        state.condition == CaptureCondition.guided
            ? CaptureCondition.control
            : CaptureCondition.guided,
      );
}

final experimentSessionProvider =
    StateNotifierProvider<ExperimentSessionController, ExperimentSession>(
  (ref) => ExperimentSessionController(),
);
