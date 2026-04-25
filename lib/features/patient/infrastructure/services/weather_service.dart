import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/environment_reading.dart';
import 'location_service.dart';

/// Talks to the public Open-Meteo APIs for current temperature and UV index,
/// plus reverse geocoding for a human-readable location label.
///
/// No API key is required. Endpoints are HTTPS-only.
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final Uri _forecastBase =
      Uri.parse('https://api.open-meteo.com/v1/forecast');
  static final Uri _geocodingBase =
      Uri.parse('https://geocoding-api.open-meteo.com/v1/reverse');

  Future<EnvironmentReading> fetch(DeviceLocation location) async {
    final results = await Future.wait([
      _fetchForecast(location),
      _fetchLocationLabel(location),
    ]);
    final forecast = results[0] as _Forecast;
    final label = results[1] as String;
    return EnvironmentReading(
      locationLabel: label,
      temperatureCelsius: forecast.temperatureC,
      uvIndex: forecast.uvIndex,
    );
  }

  Future<_Forecast> _fetchForecast(DeviceLocation location) async {
    final uri = _forecastBase.replace(queryParameters: {
      'latitude': location.latitude.toStringAsFixed(4),
      'longitude': location.longitude.toStringAsFixed(4),
      'current': 'temperature_2m,uv_index',
      'timezone': 'auto',
    });
    final response = await _client.get(uri).timeout(
          const Duration(seconds: 8),
        );
    if (response.statusCode != 200) {
      throw WeatherUnavailableException(
        'Forecast HTTP ${response.statusCode}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final current = json['current'] as Map<String, dynamic>?;
    if (current == null) {
      throw const WeatherUnavailableException('Missing current block');
    }
    return _Forecast(
      temperatureC: (current['temperature_2m'] as num?)?.toDouble() ?? 0.0,
      uvIndex: (current['uv_index'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Future<String> _fetchLocationLabel(DeviceLocation location) async {
    try {
      final uri = _geocodingBase.replace(queryParameters: {
        'latitude': location.latitude.toStringAsFixed(4),
        'longitude': location.longitude.toStringAsFixed(4),
        'language': 'en',
        'count': '1',
      });
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        return _fallbackLabel(location);
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final results = json['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        return _fallbackLabel(location);
      }
      final first = results.first as Map<String, dynamic>;
      final name = first['name'] as String?;
      final country = first['country'] as String?;
      if (name != null && country != null) return '$name, $country';
      if (name != null) return name;
      return _fallbackLabel(location);
    } catch (_) {
      return _fallbackLabel(location);
    }
  }

  String _fallbackLabel(DeviceLocation location) {
    // Reverse-geocoding failures used to surface raw lat/lon, but a numeric
    // pair on the home dashboard reads as broken. Show a neutral label and
    // let the temperature/UV reading still carry the value.
    return 'Your location';
  }

  void dispose() => _client.close();
}

class _Forecast {
  const _Forecast({required this.temperatureC, required this.uvIndex});
  final double temperatureC;
  final double uvIndex;
}

class WeatherUnavailableException implements Exception {
  const WeatherUnavailableException(this.message);
  final String message;
  @override
  String toString() => 'WeatherUnavailableException: $message';
}
