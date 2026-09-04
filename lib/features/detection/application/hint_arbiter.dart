/// Priority + hysteresis arbiter for the single coaching line.
///
/// Lifted verbatim (behaviour-wise) out of `SceneMappingOverlay`, which had
/// this logic embedded in its State. It was the one piece of the capture UX
/// that was already right, and now that the gate blocks the shutter it
/// matters more: with six signals instead of three, a naive "show the first
/// failing check" would strobe between messages several times a second and
/// the user would never finish reading one.
///
/// Rules:
///   • A higher-priority problem (lower index) takes the line immediately —
///     if the light collapses, saying so cannot wait behind a framing hint.
///   • A lower-priority problem waits [settleMs] before taking over, and
///     only while the current message is no longer failing.
///   • The all-clear message is subject to the same delay, so a signal that
///     flickers in and out does not flash "ready" between failures.
class HintArbiter {
  HintArbiter({
    required this.priority,
    required this.resolvedKey,
    this.settleMs = 1500,
    String? initial,
  })  : assert(priority.isNotEmpty),
        _active = initial ?? priority.first;

  /// Keys ordered most to least urgent. Index 0 wins ties and pre-empts.
  final List<String> priority;

  /// Key shown when nothing is failing.
  final String resolvedKey;

  /// How long a lower-priority hint must wait before claiming the line.
  final int settleMs;

  String _active;
  int _satisfiedMs = 0;

  String get active => _active;

  /// Milliseconds the current message has spent not-failing. Exposed for
  /// tests and telemetry.
  int get satisfiedMs => _satisfiedMs;

  /// Advances the arbiter. [failing] is the highest-priority failing key, or
  /// null when every check passes. [dtMs] is elapsed time since the previous
  /// call, clamped defensively so a stalled frame pump cannot jump the
  /// hysteresis.
  void update({required String? failing, required int dtMs}) {
    final dt = dtMs.clamp(0, 1000);

    if (failing == null) {
      _satisfiedMs += dt;
      if (_active != resolvedKey && _satisfiedMs >= settleMs) {
        _active = resolvedKey;
        _satisfiedMs = 0;
      }
      return;
    }

    if (failing == _active) {
      _satisfiedMs = 0;
      return;
    }

    final newPriority = _indexOf(failing);
    final currentPriority = _indexOf(_active);

    if (newPriority < currentPriority) {
      _active = failing;
      _satisfiedMs = 0;
      return;
    }

    // Lower priority: the current message is no longer the failing one, so
    // accumulate settled time before yielding the line.
    _satisfiedMs += dt;
    if (_satisfiedMs >= settleMs) {
      _active = failing;
      _satisfiedMs = 0;
    }
  }

  /// Unknown keys sort last so an unregistered hint can never pre-empt.
  int _indexOf(String key) {
    final index = priority.indexOf(key);
    return index < 0 ? priority.length : index;
  }

  void reset({String? to}) {
    _active = to ?? priority.first;
    _satisfiedMs = 0;
  }
}
