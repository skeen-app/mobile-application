import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/environment_reading.dart';
import '../infrastructure/services/location_service.dart';
import '../infrastructure/services/weather_service.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return const LocationService();
});

final weatherServiceProvider = Provider<WeatherService>((ref) {
  final service = WeatherService();
  ref.onDispose(service.dispose);
  return service;
});

/// Resolves device location → current temperature + UV index for the home
/// dashboard. Surfaces typed errors so the UI can render a degraded state
/// (permission denied, offline, etc.) without leaking exceptions.
final environmentProvider = FutureProvider<EnvironmentReading>((ref) async {
  final location = await ref.read(locationServiceProvider).currentPosition();
  return ref.read(weatherServiceProvider).fetch(location);
});
