import 'dart:collection';

/// Turns a raw Laplacian variance into a 0–1 sharpness score by comparing it
/// against **what this device has actually achieved in this session**.
///
/// The old code divided the variance by a hard-coded 2000 and called
/// anything above 0.45 sharp. That constant is meaningless across hardware:
/// sensor resolution, lens, ISP sharpening and even the ROI size all move
/// the absolute variance by an order of magnitude, so the same threshold was
/// simultaneously unreachable on some phones and trivially passed on others.
/// For a study whose whole claim is "the guidance improves image quality",
/// a focus gate that is really a device-model lottery is not usable.
///
/// Instead: keep a moving window of recent readings and score each frame
/// against the best focus seen inside that window. A phone that peaks at 400
/// and one that peaks at 6000 both report ~1.0 when they are at their own
/// best, and the threshold means the same thing on both.
///
/// The window slides so the reference tracks the current scene: walking from
/// a detailed forearm to a smooth cheek re-baselines within [windowSize]
/// samples instead of holding a stale, unreachable peak.
class SharpnessCalibrator {
  SharpnessCalibrator({
    this.windowSize = 90,
    this.minSamples = 5,
    this.minUsableVariance = 25.0,
  })  : assert(windowSize > 0),
        assert(minSamples > 0);

  /// Samples retained. At the camera service's ~3 Hz cadence, 90 ≈ 30 s.
  final int windowSize;

  /// Readings needed before [normalized] is trusted. Below this the score is
  /// reported as calibrating and the focus gate stays shut — an early frame
  /// is trivially its own maximum and would otherwise score a perfect 1.0.
  final int minSamples;

  /// Absolute floor on the window maximum.
  ///
  /// This is the one place an absolute number is unavoidable, and it guards
  /// the failure mode that pure relative scoring cannot see: pointed at a
  /// blank wall every frame has variance ~2, the max is also ~2, and the
  /// ratio would report a flawless 1.0 for a frame with no detail at all.
  /// Below this floor we refuse to call anything sharp.
  final double minUsableVariance;

  final ListQueue<double> _window = ListQueue<double>();
  double _latest = 0;

  /// Highest variance in the current window. 0 when empty.
  double get observedMax =>
      _window.isEmpty ? 0 : _window.reduce((a, b) => a > b ? a : b);

  int get sampleCount => _window.length;

  /// True while the window is too short, or too flat, to score against.
  bool get isCalibrating =>
      _window.length < minSamples || observedMax < minUsableVariance;

  /// Latest reading as a fraction of the window's best, clamped to 0–1.
  /// Returns 0 while [isCalibrating] so a half-built window can never report
  /// a passing score.
  double get normalized {
    if (isCalibrating) return 0;
    final max = observedMax;
    if (max <= 0) return 0;
    final ratio = _latest / max;
    if (!ratio.isFinite) return 0;
    return ratio.clamp(0.0, 1.0);
  }

  /// Fraction of this device's own best focus that counts as in-focus.
  ///
  /// 0.60 was picked to sit below the natural spread of a hand-held sharp
  /// frame (autofocus hunting and micro-tremor make consecutive sharp frames
  /// vary by roughly 20–30% of peak) while still rejecting the clearly soft
  /// ones. Tighter than ~0.75 and a steady hand never clears it; looser than
  /// ~0.5 and visibly blurred frames pass.
  static const double sharpThreshold = 0.60;

  bool get isSharp => !isCalibrating && normalized >= sharpThreshold;

  /// Feeds one raw Laplacian variance. Negative and non-finite inputs are
  /// treated as 0 so a malformed frame cannot poison the maximum.
  void add(double rawVariance) {
    final value =
        (!rawVariance.isFinite || rawVariance < 0) ? 0.0 : rawVariance;
    _latest = value;
    _window.addLast(value);
    while (_window.length > windowSize) {
      _window.removeFirst();
    }
  }

  /// Drops the window. Called when the camera session restarts, since the
  /// previous scene's peak says nothing about the new one.
  void reset() {
    _window.clear();
    _latest = 0;
  }

  /// Diagnostic snapshot persisted with each capture so thresholds can be
  /// re-derived from field data instead of argued about.
  Map<String, dynamic> toJson() => {
        'sharpness_normalized': normalized,
        'sharpness_observed_max': observedMax,
        'sharpness_window_samples': sampleCount,
        'sharpness_calibrating': isCalibrating,
        'sharpness_threshold': sharpThreshold,
      };

  @override
  String toString() => 'SharpnessCalibrator('
      'n=${_window.length}, max=${observedMax.toStringAsFixed(1)}, '
      'norm=${normalized.toStringAsFixed(2)})';
}
