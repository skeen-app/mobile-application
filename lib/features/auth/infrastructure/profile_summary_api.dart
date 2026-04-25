import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/logger/app_logger.dart';
import '../domain/patient_profile_summary.dart';

/// Placeholder for the backend `GET /me/profile-summary` endpoint.
///
/// The endpoint is not implemented yet, so [fetch] currently throws
/// [ProfileSummaryUnavailable]. The repository catches this and falls back
/// to local-derived data — once the route ships, only this method changes.
class ProfileSummaryApi {
  ProfileSummaryApi({http.Client? client}) : _client = client ?? http.Client();

  // ignore: unused_field
  final http.Client _client;

  Future<PatientProfileSummary> fetch({required String authToken}) async {
    AppLogger.info('Fetching profile summary', tag: 'ProfileSummaryApi');
    // TODO(backend): replace with `GET /me/profile-summary` once available.
    // The endpoint should return:
    //   { "registeredMoles": <int>, "lastScanAt": <iso8601 | null> }
    AppLogger.warning('Profile summary endpoint not implemented yet', tag: 'ProfileSummaryApi');
    throw const ProfileSummaryUnavailable('Endpoint not yet implemented');
  }

  void dispose() => _client.close();
}

class ProfileSummaryUnavailable implements Exception {
  const ProfileSummaryUnavailable(this.message);
  final String message;
  @override
  String toString() => 'ProfileSummaryUnavailable: $message';
}
