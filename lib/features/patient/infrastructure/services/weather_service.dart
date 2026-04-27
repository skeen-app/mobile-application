import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/logger/app_logger.dart';
import '../../domain/environment_reading.dart';
import 'location_service.dart';

/// Talks to public Open-Meteo APIs for current temperature + UV index, and
/// to BigDataCloud's free client-reverse-geocode for a "City, Country" label.
///
/// All endpoints are HTTPS and key-less. Open-Meteo's `uv_index` is NOT a
/// supported `current=` field — it lives under `hourly=`, so the service
/// fetches the hourly array and selects the value matching the device's
/// current local hour.
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final Uri _forecastBase =
      Uri.parse('https://api.open-meteo.com/v1/forecast');
  static final Uri _openMeteoGeocodingBase =
      Uri.parse('https://geocoding-api.open-meteo.com/v1/reverse');
  static final Uri _bigDataCloudBase = Uri.parse(
    'https://api.bigdatacloud.net/data/reverse-geocode-client',
  );

  Future<EnvironmentReading> fetch(DeviceLocation location) async {
    AppLogger.info('Fetching weather data for coordinates: ${location.latitude}, ${location.longitude}', tag: 'WeatherService');
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
      'current': 'temperature_2m',
      'hourly': 'uv_index',
      'daily': 'uv_index_max',
      'forecast_days': '1',
      'timezone': 'auto',
    });
    final response = await _client.get(uri).timeout(
          const Duration(seconds: 8),
        );
    if (response.statusCode != 200) {
      AppLogger.warning('Forecast API failed: HTTP ${response.statusCode}', tag: 'WeatherService');
      throw WeatherUnavailableException(
        'Forecast HTTP ${response.statusCode}',
      );
    }
    AppLogger.info('Forecast API successful', tag: 'WeatherService');
    final json = jsonDecode(response.body) as Map<String, dynamic>;

    final current = json['current'] as Map<String, dynamic>?;
    final temperatureC =
        (current?['temperature_2m'] as num?)?.toDouble() ?? 0.0;

    final uvIndex = _resolveUvIndex(json) ?? 0.0;
    return _Forecast(temperatureC: temperatureC, uvIndex: uvIndex);
  }

  /// Picks the UV reading for the current local hour from the hourly array;
  /// falls back to today's `uv_index_max` if hourly data is missing.
  double? _resolveUvIndex(Map<String, dynamic> json) {
    final hourly = json['hourly'] as Map<String, dynamic>?;
    if (hourly != null) {
      final times = (hourly['time'] as List?)?.cast<String>();
      final values = (hourly['uv_index'] as List?)?.cast<num?>();
      if (times != null && values != null && times.length == values.length) {
        final nowIso = DateTime.now()
            .toIso8601String()
            .substring(0, 13); // YYYY-MM-DDTHH
        for (var i = 0; i < times.length; i++) {
          if (times[i].startsWith(nowIso)) {
            final v = values[i];
            if (v != null) return v.toDouble();
          }
        }
        // No exact hour match: use the maximum of the (typically 24-entry) day.
        final populated = values.whereType<num>().map((n) => n.toDouble());
        if (populated.isNotEmpty) {
          return populated.reduce((a, b) => a > b ? a : b);
        }
      }
    }
    final daily = json['daily'] as Map<String, dynamic>?;
    final dailyMax = (daily?['uv_index_max'] as List?)?.firstOrNull;
    if (dailyMax is num) return dailyMax.toDouble();
    return null;
  }

  Future<String> _fetchLocationLabel(DeviceLocation location) async {
    final candidates = await Future.wait([
      _bigDataCloudLabel(location),
      _openMeteoLabel(location),
    ]);
    for (final c in candidates) {
      if (c != null && c.isNotEmpty) return c;
    }
    return 'Your location';
  }

  Future<String?> _bigDataCloudLabel(DeviceLocation location) async {
    try {
      final uri = _bigDataCloudBase.replace(queryParameters: {
        'latitude': location.latitude.toString(),
        'longitude': location.longitude.toString(),
        'localityLanguage': 'en',
      });
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final city = (json['city'] as String?)?.trim();
      final locality = (json['locality'] as String?)?.trim();
      final principalSubdivision =
          (json['principalSubdivision'] as String?)?.trim();
      final country = (json['countryName'] as String?)?.trim();
      final cityName = _firstNonEmpty([city, locality, principalSubdivision]);
      if (cityName != null && country != null && country.isNotEmpty) {
        return '$cityName, $country';
      }
      if (cityName != null) return cityName;
      if (country != null && country.isNotEmpty) return country;
      return null;
    } catch (e) {
      AppLogger.warning('BigDataCloud reverse geocode failed: $e', tag: 'WeatherService');
      return null;
    }
  }

  Future<String?> _openMeteoLabel(DeviceLocation location) async {
    try {
      final uri = _openMeteoGeocodingBase.replace(queryParameters: {
        'latitude': location.latitude.toStringAsFixed(4),
        'longitude': location.longitude.toStringAsFixed(4),
        'language': 'en',
        'count': '1',
      });
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final results = json['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;
      final first = results.first as Map<String, dynamic>;
      final name = (first['name'] as String?)?.trim();
      final country = (first['country'] as String?)?.trim();
      if (name != null && country != null && country.isNotEmpty) {
        return '$name, $country';
      }
      return name;
    } catch (e) {
      AppLogger.warning('OpenMeteo reverse geocode failed: $e', tag: 'WeatherService');
      return null;
    }
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
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
