import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../domain/camera_intrinsics.dart';
import '../domain/capture_stability.dart';
import '../domain/color_calibration.dart';
import '../domain/display_mapping.dart';
import '../domain/fiducial_marker.dart';
import '../domain/luma_frame.dart';
import '../domain/ports.dart';
import '../domain/skin_plane_pose.dart';
import 'marker_detector.dart';
import 'patch_sampler.dart';
import 'pose_estimator.dart';

/// Detects a [LumaFrame]. Injected so tests can run synchronously; the
/// default runs [detectMarker] in a persistent worker isolate.
typedef MarkerDetectFn = Future<MarkerDetection?> Function(LumaFrame frame);

/// Keeps a live [SkinPlanePose] from the camera's detection frames and the
/// gyroscope.
///
/// Cadence: the camera service emits detection frames at ~10 Hz. Each is
/// detected off the UI thread; while one is in flight, newer frames are
/// dropped rather than queued (a backlog of stale frames is worse than a
/// skipped one). Between detections the last pose is carried forward by the
/// integrated gyroscope — a pure rotation of the camera, which leaves px/mm
/// unchanged to first order and updates tilt and the plane→image map — so
/// registered overlays move with the phone instead of stepping every 100 ms.
///
/// **Fail-closed.** A pose that has gone [SkinPlanePose.staleAfterMs]
/// without a real detection is reported as null. Prediction smooths the
/// gaps between detections; it never substitutes for them.
///
/// **Re-entrancy.** [start] cancels its own previous subscriptions before
/// re-subscribing, so an app resume — which calls it again — cannot leave a
/// second listener processing every frame. The module has been bitten by
/// exactly that twice; the test suite pins it here.
class PoseTracker {
  PoseTracker({
    required ScanCameraServicePort camera,
    required StabilitySensorPort stabilitySensor,
    required CameraIntrinsicsPort intrinsics,
    MarkerDetectFn? detect,
    DateTime Function()? clock,
    this.marker = FiducialMarker.study,
  })  : _camera = camera,
        _stabilitySensor = stabilitySensor,
        _intrinsicsPort = intrinsics,
        _detect = detect,
        _now = clock ?? DateTime.now;

  final ScanCameraServicePort _camera;
  final StabilitySensorPort _stabilitySensor;
  final CameraIntrinsicsPort _intrinsicsPort;
  final MarkerDetectFn? _detect;
  final DateTime Function() _now;
  final FiducialMarker marker;

  final StreamController<SkinPlanePose?> _poseController =
      StreamController<SkinPlanePose?>.broadcast();

  StreamSubscription<LumaFrame>? _frameSub;
  StreamSubscription<AngularVelocity>? _gyroSub;
  Timer? _staleTimer;
  _DetectionWorker? _worker;

  bool _inFlight = false;
  SkinPlanePose? _lastDetected;
  SkinPlanePose? _current;
  ColorCalibration? _calibration;
  PatchReading? _lastPatchReading;
  bool _emittedNull = true;
  DateTime? _lastGyroAt;

  CameraIntrinsics? _intrinsics;
  bool _intrinsicsResolved = false;
  int _intrinsicsFrameW = 0;
  int _intrinsicsFrameH = 0;

  double _detectionMsEma = 0;
  int _detections = 0;
  int _dropped = 0;
  double _lastZoom = 1.0;

  /// Emits on every change: a detected or predicted pose, or null when there
  /// is none / it went stale.
  Stream<SkinPlanePose?> get pose => _poseController.stream;

  /// The pose right now, or null when none or stale.
  SkinPlanePose? get current {
    final c = _current;
    if (c == null) return null;
    return c.isStaleAt(_now()) ? null : c;
  }

  /// Last real detection regardless of age, for telemetry.
  SkinPlanePose? get lastDetected => _lastDetected;

  /// Ground-truth colour/luma calibration from the marker's patches, taken
  /// on the frame of the current pose. Null when the patches could not be
  /// read (see [lastPatchReading]) or the pose is gone: never carried past
  /// the pose it belongs to.
  ColorCalibration? get calibration => current == null ? null : _calibration;

  /// Why the last patch read did or did not yield a calibration.
  PatchReading? get lastPatchReading => _lastPatchReading;

  /// True once the platform has been asked for intrinsics and had none.
  /// Tilt is unmeasurable on this device: an eligibility matter.
  bool get intrinsicsUnavailable => _intrinsicsResolved && _intrinsics == null;

  CameraIntrinsics? get intrinsics => _intrinsics;

  /// Intrinsics for the stream at the zoom of the latest frame — what any
  /// consumer predicting image motion from the gyroscope must use.
  CameraIntrinsics? get intrinsicsAtZoom => _intrinsics?.zoomed(_lastZoom);

  /// Smoothed detector time per frame, ms. Persisted with captures.
  double get detectionMsEma => _detectionMsEma;
  int get detectionCount => _detections;
  int get droppedFrameCount => _dropped;

  Future<void> start() async {
    await _cancelSubscriptions();
    _inFlight = false;
    _lastGyroAt = null;

    _frameSub = _camera.detectionFrames.listen(_onFrame);
    _gyroSub = _stabilitySensor.angularVelocity.listen(_onGyro);
    _staleTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _checkStale(),
    );
  }

  Future<void> _onFrame(LumaFrame frame) async {
    if (_inFlight) {
      _dropped++;
      return;
    }
    _inFlight = true;
    try {
      // Resolved on the first frame, not the first detection: the reticle's
      // gyroscope prediction needs the focal length whether or not a marker
      // is ever in view.
      _lastZoom = frame.zoom;
      final intrinsics = await _resolveIntrinsics(frame);

      final detection = await _detectFrame(frame);
      if (detection == null) return;

      if (intrinsics == null) {
        // Tilt cannot be measured without a focal length. No pose — the
        // gate stays closed and the eligibility path names the reason.
        return;
      }

      final pose = estimatePose(
        corners: detection.scaled(frame.scaleToFull).corners,
        intrinsics: intrinsics.zoomed(frame.zoom),
        detectedAt: frame.capturedAt,
        detectionMs: detection.elapsedMs,
        marker: marker,
      );
      if (pose == null) return;

      _detections++;
      _detectionMsEma = _detections == 1
          ? detection.elapsedMs.toDouble()
          : _detectionMsEma + 0.2 * (detection.elapsedMs - _detectionMsEma);
      _lastDetected = pose;
      _current = pose;
      // Patches are read off THIS frame, through THIS pose: one instant.
      final reading = samplePatches(frame: frame, pose: pose, marker: marker);
      _lastPatchReading = reading;
      _calibration = ColorCalibration.fromReading(reading);
      _emit(pose);
    } finally {
      _inFlight = false;
    }
  }

  Future<MarkerDetection?> _detectFrame(LumaFrame frame) {
    final custom = _detect;
    if (custom != null) return custom(frame);
    return (_worker ??= _DetectionWorker(marker)).detect(frame);
  }

  Future<CameraIntrinsics?> _resolveIntrinsics(LumaFrame frame) async {
    final w = frame.fullWidth, h = frame.fullHeight;
    if (_intrinsicsResolved &&
        _intrinsicsFrameW == w &&
        _intrinsicsFrameH == h) {
      return _intrinsics;
    }
    _intrinsics = await _intrinsicsPort.read(frameWidth: w, frameHeight: h);
    _intrinsicsResolved = true;
    _intrinsicsFrameW = w;
    _intrinsicsFrameH = h;
    return _intrinsics;
  }

  /// Carries the current pose forward through a small camera rotation.
  ///
  /// For a pure rotation `R` of the camera, a fixed world direction `n` reads
  /// `Rᵀ n` in the new camera frame, and image points move by the conjugate
  /// homography `K Rᵀ K⁻¹`. Both are first-order exact for the ~50 ms steps
  /// the gyroscope delivers.
  void _onGyro(AngularVelocity sample) {
    final previous = _lastGyroAt;
    _lastGyroAt = sample.at;
    final pose = _current;
    // The conjugation must use the SAME K the pose was estimated with —
    // i.e. at the zoom in force when it was detected.
    final k = _intrinsics?.zoomed(_lastZoom);
    if (previous == null || pose == null || k == null) return;
    if (pose.isStaleAt(_now())) return;

    final dt = sample.at.difference(previous).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 0.25) return;

    final omega = gyroToStreamFrame(sample, _camera.sensorOrientationDegrees);
    final r = Vec3.rodrigues([omega[0] * dt, omega[1] * dt, omega[2] * dt]);
    final rT = Vec3.transpose(r);

    final normal = Vec3.rotate(rT, pose.planeNormalCamera);
    final tilt = math.acos(normal[2].abs().clamp(0.0, 1.0)) * 180 / math.pi;

    final kMat = Matrix3([
      k.focalPx, 0, k.principalX,
      0, k.focalPx, k.principalY,
      0, 0, 1,
    ]);
    final kInv = kMat.inverse();
    if (kInv == null) return;
    final conj = kMat.multiply(Matrix3(rT)).multiply(kInv);
    final predictedH = conj.multiply(pose.planeToImage);

    _current = pose.copyWith(
      tiltDeg: tilt,
      planeToImage: predictedH,
      planeNormalCamera: normal,
      // The same rotation applied to the rigid frame, so project3 (the
      // nadir cue) stays consistent with the predicted homography.
      rotation: Vec3.matMul(rT, pose.rotation),
      translation: Vec3.rotate(rT, pose.translation),
      source: PoseSource.predicted,
    );
    _emit(_current);
  }

  void _checkStale() {
    final c = _current;
    if (c == null) return;
    if (c.isStaleAt(_now())) {
      _current = null;
      _calibration = null;
      _emit(null);
    }
  }

  void _emit(SkinPlanePose? p) {
    if (_poseController.isClosed) return;
    if (p == null) {
      if (_emittedNull) return;
      _emittedNull = true;
    } else {
      _emittedNull = false;
    }
    _poseController.add(p);
  }

  Future<void> _cancelSubscriptions() async {
    await _frameSub?.cancel();
    await _gyroSub?.cancel();
    _staleTimer?.cancel();
    _frameSub = null;
    _gyroSub = null;
    _staleTimer = null;
  }

  Future<void> stop() async {
    await _cancelSubscriptions();
    _current = null;
    _calibration = null;
    _emit(null);
  }

  Future<void> dispose() async {
    await stop();
    _worker?.dispose();
    _worker = null;
    await _poseController.close();
  }
}

// ──────────────────────────────────────────────────────────────────────
// Worker isolate
// ──────────────────────────────────────────────────────────────────────

/// A persistent isolate running [detectMarker]. Spawned once; `compute()`
/// would pay an isolate spawn per frame at 10 Hz.
class _DetectionWorker {
  _DetectionWorker(this.marker);

  final FiducialMarker marker;
  Isolate? _isolate;
  SendPort? _toWorker;
  final ReceivePort _fromWorker = ReceivePort();
  Completer<MarkerDetection?>? _pending;
  Future<void>? _ready;

  Future<void> _ensureStarted() {
    return _ready ??= () async {
      final handshake = Completer<SendPort>();
      _fromWorker.listen((message) {
        if (message is SendPort) {
          handshake.complete(message);
          return;
        }
        final pending = _pending;
        _pending = null;
        if (pending == null) return;
        if (message == null) {
          pending.complete(null);
          return;
        }
        final m = message as Map;
        final xs = m['xs'] as List;
        final ys = m['ys'] as List;
        pending.complete(MarkerDetection(
          corners: [
            for (var i = 0; i < 4; i++)
              Offset((xs[i] as num).toDouble(), (ys[i] as num).toDouble()),
          ],
          rotation: m['rotation'] as int,
          hammingErrors: m['hamming'] as int,
          elapsedMs: m['elapsedMs'] as int,
        ));
      });
      _isolate = await Isolate.spawn(
        _workerMain,
        [_fromWorker.sendPort, marker.bits, marker.sideMm],
      );
      _toWorker = await handshake.future;
    }();
  }

  Future<MarkerDetection?> detect(LumaFrame frame) async {
    await _ensureStarted();
    final pending = _pending;
    if (pending != null) return pending.future;
    final completer = Completer<MarkerDetection?>();
    _pending = completer;
    _toWorker!.send([
      frame.luma,
      frame.width,
      frame.height,
    ]);
    return completer.future;
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _fromWorker.close();
  }

  static void _workerMain(List<Object> args) {
    final replyTo = args[0] as SendPort;
    final marker = FiducialMarker(
      bits: args[1] as int,
      sideMm: args[2] as double,
    );
    final inbox = ReceivePort();
    replyTo.send(inbox.sendPort);
    inbox.listen((message) {
      final req = message as List;
      final frame = LumaFrame(
        luma: req[0] as Uint8List,
        width: req[1] as int,
        height: req[2] as int,
        capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
        scaleToFull: 1,
        zoom: 1,
      );
      final d = detectMarker(frame, marker: marker);
      if (d == null) {
        replyTo.send(null);
        return;
      }
      replyTo.send({
        'xs': [for (final c in d.corners) c.dx],
        'ys': [for (final c in d.corners) c.dy],
        'rotation': d.rotation,
        'hamming': d.hammingErrors,
        'elapsedMs': d.elapsedMs,
      });
    });
  }
}
