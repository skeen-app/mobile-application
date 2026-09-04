import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../domain/ports.dart';

/// Measures camera shake with the gyroscope.
///
/// `sensors_plus` was already a dependency — added for AR anchoring and then
/// never used — so the stability signal costs no new packages.
///
/// The raw gyroscope is noisy at the sample rates the plugin delivers, so the
/// magnitude is smoothed with an exponential moving average before it reaches
/// the gate. Without smoothing, a single sensor spike would drop the shutter
/// out of the green state and cancel a nearly-complete auto-capture.
class GyroscopeStabilityService implements StabilitySensorPort {
  GyroscopeStabilityService({this.smoothing = 0.3})
      : assert(smoothing > 0 && smoothing <= 1);

  /// EMA weight on the newest sample. 0.3 keeps ~3 samples of memory: fast
  /// enough that setting the phone down registers within ~100 ms, slow enough
  /// that one noisy sample cannot flip the gate.
  final double smoothing;

  StreamSubscription<GyroscopeEvent>? _sub;
  final StreamController<double> _controller =
      StreamController<double>.broadcast();
  double? _ema;

  @override
  Stream<double> get angularSpeed => _controller.stream;

  @override
  Future<bool> isAvailable({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final completer = Completer<bool>();
    StreamSubscription<GyroscopeEvent>? probe;
    try {
      probe = gyroscopeEventStream(
        samplingPeriod: const Duration(milliseconds: 50),
      ).listen(
        (_) {
          if (!completer.isCompleted) completer.complete(true);
        },
        onError: (Object error) {
          if (kDebugMode) debugPrint('Gyroscope probe error: $error');
          if (!completer.isCompleted) completer.complete(false);
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Gyroscope probe failed to subscribe: $e');
      return false;
    }

    // A gyroscope streams continuously — near-zero values when the phone is
    // still — so silence across this window means the sensor is absent or the
    // platform refused it, not that the device was held steady.
    final available =
        await completer.future.timeout(timeout, onTimeout: () => false);
    await probe.cancel();
    return available;
  }

  @override
  Future<void> start() async {
    if (_sub != null) return;
    _ema = null;
    try {
      _sub = gyroscopeEventStream(
        samplingPeriod: const Duration(milliseconds: 50),
      ).listen(
        _onEvent,
        onError: (Object error) {
          // No gyroscope on this device. Emitting nothing leaves the domain
          // in CaptureStability.unknown, which holds the gate shut — the
          // honest outcome, since we genuinely cannot measure shake here.
          if (kDebugMode) debugPrint('Gyroscope unavailable: $error');
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Gyroscope subscribe failed: $e');
    }
  }

  void _onEvent(GyroscopeEvent event) {
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    if (!magnitude.isFinite) return;
    final previous = _ema;
    final next = previous == null
        ? magnitude
        : previous + smoothing * (magnitude - previous);
    _ema = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _ema = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
