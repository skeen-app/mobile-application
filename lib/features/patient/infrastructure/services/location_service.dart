import 'package:geolocator/geolocator.dart';

class LocationService {
  const LocationService();

  /// Resolves the device's current geographic position.
  ///
  /// Throws [LocationPermissionDeniedException] when the user denies the
  /// runtime prompt or when location services are disabled on the device.
  Future<DeviceLocation> currentPosition() async {
    final servicesEnabled = await Geolocator.isLocationServiceEnabled();
    if (!servicesEnabled) {
      throw const LocationServicesDisabledException();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDeniedException();
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return DeviceLocation(latitude: position.latitude, longitude: position.longitude);
  }
}

class DeviceLocation {
  const DeviceLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class LocationPermissionDeniedException implements Exception {
  const LocationPermissionDeniedException();
}

class LocationServicesDisabledException implements Exception {
  const LocationServicesDisabledException();
}
