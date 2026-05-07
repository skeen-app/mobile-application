import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/logger/app_logger.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/api_exception.dart';
import '../domain/lesion_analysis.dart';
import '../domain/scan_remote.dart';

/// HTTP client for the `/api/v1/scans` REST surface.
///
/// Two-step upload contract — keeps the Cloud Run instance off the image
/// path so it can stay small and cheap:
///   1. POST /scans         → creates the Firestore doc, returns an upload URL
///   2. PUT  <signed_url>   → client uploads the (re-encrypted) JPEG to GCS
///   3. POST /scans/{id}/image → confirms the upload landed
class ScansApi {
  ScansApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // ── CRUD ────────────────────────────────────────────────────────────

  /// Step 1: register the scan metadata. Returns the freshly-created
  /// remote record plus the signed PUT URL the client should upload to.
  // ignore: unintended_html_in_doc_comment
  Future<({ScanRemote scan, String? uploadUrl, String? objectPath})>
      createScan({
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _send(
      'POST',
      '/scans',
      token: token,
      body: payload,
    );
    final json = _decodeJson(res);
    return (
      scan: ScanRemote.fromJson(json['scan'] as Map<String, dynamic>),
      uploadUrl: json['image_upload_url'] as String?,
      objectPath: json['image_object_path'] as String?,
    );
  }

  /// Step 2: PUT the (re-encrypted) JPEG to the signed URL. The bucket is
  /// owned by the backend and the URL is one-shot, so no auth header here.
  Future<bool> uploadImage({
    required String uploadUrl,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    try {
      final res = await _client
          .put(
            Uri.parse(uploadUrl),
            headers: {'Content-Type': contentType},
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      if (!ok) {
        AppLogger.warning(
          'ScansApi: signed-URL PUT failed (${res.statusCode}): ${res.body}',
          tag: 'ScansApi',
        );
      }
      return ok;
    } on TimeoutException {
      AppLogger.warning('ScansApi: upload timed out', tag: 'ScansApi');
      return false;
    } catch (e, st) {
      AppLogger.error('ScansApi: upload threw', tag: 'ScansApi', error: e, stackTrace: st);
      return false;
    }
  }

  /// Step 3: tell the backend the image landed at [objectPath].
  Future<ScanRemote> confirmImageUpload({
    required String token,
    required String scanId,
    required String objectPath,
  }) async {
    final res = await _send(
      'POST',
      '/scans/$scanId/image',
      token: token,
      body: {'object_path': objectPath},
    );
    return ScanRemote.fromJson(_decodeJson(res));
  }

  Future<List<ScanRemote>> listScans({required String token}) async {
    final res = await _send('GET', '/scans', token: token);
    final json = _decodeJson(res);
    final items = (json['items'] as List).cast<Map<String, dynamic>>();
    return items.map(ScanRemote.fromJson).toList(growable: false);
  }

  Future<ScanRemote> getScan({
    required String token,
    required String scanId,
  }) async {
    final res = await _send('GET', '/scans/$scanId', token: token);
    return ScanRemote.fromJson(_decodeJson(res));
  }

  Future<({int total, Map<String, int> byGroup})> getStats({
    required String token,
  }) async {
    final res = await _send('GET', '/scans/stats', token: token);
    final json = _decodeJson(res);
    final by = (json['by_group'] as Map).cast<String, dynamic>();
    return (
      total: (json['total'] as num).toInt(),
      byGroup: by.map((k, v) => MapEntry(k, (v as num).toInt())),
    );
  }

  Future<bool> deleteScan({
    required String token,
    required String scanId,
  }) async {
    final res = await _send('DELETE', '/scans/$scanId', token: token);
    final json = _decodeJson(res);
    return json['deleted'] as bool? ?? false;
  }

  // ── Mappers from local domain → wire payload ────────────────────────

  /// Maps a local [LesionAnalysis] into the request payload expected by
  /// `POST /scans`. Body region + body part are passed through verbatim;
  /// the backend treats the client UUID as the canonical scan id.
  Map<String, dynamic> toCreatePayload(
    LesionAnalysis a, {
    required String? bodyRegionSlug,
    required String? bodyPartLabel,
    required String riskLevelSlug,
    double? relativePositionX,
    double? relativePositionY,
    bool hasImage = true,
  }) {
    return {
      'id': a.id,
      'top_label': a.result.topLabel.slug,
      'confidence': a.confidence,
      'risk_level': riskLevelSlug,
      'body_region': ?bodyRegionSlug,
      'body_part_label': ?bodyPartLabel,
      'captured_at': a.capturedAt.toUtc().toIso8601String(),
      'distance_cm': ?a.distanceCm,
      'image_hash': ?a.imageHash,
      'relative_position_x': ?relativePositionX,
      'relative_position_y': ?relativePositionY,
      'has_image': hasImage,
      'image_content_type': 'image/jpeg',
    };
  }

  // ── Internals ───────────────────────────────────────────────────────

  Future<http.Response> _send(
    String method,
    String path, {
    required String token,
    Map<String, dynamic>? body,
  }) async {
    final uri = ApiConfig.uri(path);
    final headers = {
      ...ApiConfig.jsonHeaders,
      'Authorization': 'Bearer $token',
    };
    final http.Response res;
    try {
      switch (method) {
        case 'GET':
          res = await _client.get(uri, headers: headers).timeout(ApiConfig.defaultTimeout);
        case 'POST':
          res = await _client
              .post(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(ApiConfig.defaultTimeout);
        case 'DELETE':
          res = await _client.delete(uri, headers: headers).timeout(ApiConfig.defaultTimeout);
        default:
          throw UnsupportedError('HTTP $method not supported');
      }
    } on TimeoutException {
      throw const ApiException(statusCode: 0, message: 'Request timed out');
    } catch (e) {
      throw ApiException(statusCode: 0, message: 'Network error: $e');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      AppLogger.warning(
        'ScansApi $method $path → ${res.statusCode}: ${res.body}',
        tag: 'ScansApi',
      );
      throw ApiException(
        statusCode: res.statusCode,
        message: 'HTTP ${res.statusCode}',
        body: res.body,
      );
    }
    return res;
  }

  Map<String, dynamic> _decodeJson(http.Response res) {
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(
        statusCode: res.statusCode,
        message: 'Invalid JSON',
        body: res.body,
      );
    }
  }

  void dispose() => _client.close();
}
