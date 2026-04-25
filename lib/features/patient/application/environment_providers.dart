import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/environment_reading.dart';
import '../infrastructure/services/location_service.dart';
import '../infrastructure/services/weather_service.dart';
import '../../../core/logger/app_logger.dart';

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
  AppLogger.info('Starting environment reading via providers', tag: 'EnvironmentProvider');
  try {
    final location = await ref.read(locationServiceProvider).currentPosition();
    final reading = await ref.read(weatherServiceProvider).fetch(location);
    AppLogger.info('Environment reading loaded successfully', tag: 'EnvironmentProvider');
    return reading;
  } catch (e, stack) {
    AppLogger.error('Failed to load environment reading', tag: 'EnvironmentProvider', error: e, stackTrace: stack);
    rethrow;
  }
});
