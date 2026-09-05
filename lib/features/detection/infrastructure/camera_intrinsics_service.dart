import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/camera_intrinsics.dart';
import '../domain/ports.dart';

/// Reads the back camera's focal length from platform metadata over a
/// method channel and converts it into pixels for the given stream size.
///
/// Native side:
///   • Android — `MainActivity.kt`: `LENS_INFO_AVAILABLE_FOCAL_LENGTHS` and
///     `SENSOR_INFO_PHYSICAL_SIZE`, both mandatory Camera2 characteristics.
///   • iOS — `AppDelegate.swift`: the active format's `videoFieldOfView`.
///
/// The stream is assumed to span the sensor's full **width** (the long side
/// in sensor orientation). That holds for a same-aspect stream and for the
/// usual 16:9-from-4:3 case, which crops rows, not columns. A stream that
/// cropped columns would over-estimate the focal length; no shipping preset
/// does that, and it is noted here rather than silently assumed away.
///
/// Returns null when the platform cannot answer. That device cannot measure
/// tilt and is excluded on that named ground.
class PlatformCameraIntrinsicsService implements CameraIntrinsicsPort {
  const PlatformCameraIntrinsicsService();

  static const MethodChannel _channel =
      MethodChannel('skeen.detection/camera_intrinsics');

  @override
  Future<CameraIntrinsics?> read({
    required int frameWidth,
    required int frameHeight,
  }) async {
    if (kIsWeb) return null;
    if (frameWidth <= 0 || frameHeight <= 0) return null;

    Map<String, dynamic>? result;
    try {
      result = await _channel.invokeMapMethod<String, dynamic>('read');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Camera intrinsics unavailable: $e');
      return null;
    }
    if (result == null) return null;

    return intrinsicsFromPlatform(
      result,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
    );
  }
}

/// Pure conversion, split out so it can be tested without a channel.
///
/// Accepts either `{focalMm, sensorWidthMm}` (Android) or
/// `{horizontalFovDeg}` (iOS). Anything else, or non-positive values, is
/// "no intrinsics" — never a default.
@visibleForTesting
CameraIntrinsics? intrinsicsFromPlatform(
  Map<String, dynamic> raw, {
  required int frameWidth,
  required int frameHeight,
}) {
  final long = math.max(frameWidth, frameHeight);
  double? focalPx;

  final focalMm = (raw['focalMm'] as num?)?.toDouble();
  final sensorWidthMm = (raw['sensorWidthMm'] as num?)?.toDouble();
  if (focalMm != null &&
      sensorWidthMm != null &&
      focalMm > 0 &&
      sensorWidthMm > 0) {
    // Pixel pitch along the long side = sensorWidthMm / long.
    focalPx = focalMm * long / sensorWidthMm;
  } else {
    final hfov = (raw['horizontalFovDeg'] as num?)?.toDouble();
    if (hfov != null && hfov > 0 && hfov < 180) {
      focalPx = (long / 2) / math.tan(hfov * math.pi / 360);
    }
  }

  if (focalPx == null || !focalPx.isFinite || focalPx <= 0) return null;
  return CameraIntrinsics(
    focalPx: focalPx,
    principalX: frameWidth / 2,
    principalY: frameHeight / 2,
    frameWidth: frameWidth,
    frameHeight: frameHeight,
  );
}
