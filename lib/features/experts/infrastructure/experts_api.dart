import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/logger/app_logger.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/api_exception.dart';
import '../domain/article.dart';

/// HTTP client for the Insights feed (`/api/v1/experts/articles`).
///
/// Public endpoint — no auth header required. Failures bubble up as
/// [ApiException] so the controller can surface them as a retry state.
class ExpertsApi {
  ExpertsApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<Article>> listArticles({
    String? query,
    ArticleCategory category = ArticleCategory.all,
    int limit = 10,
  }) async {
    final params = <String, String>{
      'category': category.slug,
      'limit': '$limit',
    };
    final trimmed = (query ?? '').trim();
    if (trimmed.isNotEmpty) params['query'] = trimmed;

    final uri = ApiConfig.uri('/experts/articles')
        .replace(queryParameters: params);

    AppLogger.info('GET ${uri.path}?${uri.query}', tag: 'ExpertsApi');
    final http.Response res;
    try {
      res = await _client
          .get(uri, headers: ApiConfig.jsonHeaders)
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const ApiException(statusCode: 0, message: 'Request timed out');
    } catch (e) {
      throw ApiException(statusCode: 0, message: 'Network error: $e');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        statusCode: res.statusCode,
        message: 'HTTP ${res.statusCode}',
        body: res.body,
      );
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (json['items'] as List).cast<Map<String, dynamic>>();
    return items.map(Article.fromJson).toList(growable: false);
  }

  void dispose() => _client.close();
}
