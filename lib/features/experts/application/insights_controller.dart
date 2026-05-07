import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/article.dart';
import '../infrastructure/experts_api.dart';

/// Snapshot of the Insights feed for the UI.
@immutable
class InsightsState {
  const InsightsState({
    required this.articles,
    required this.category,
    required this.query,
    required this.isLoading,
    required this.errorMessage,
  });

  final List<Article> articles;
  final ArticleCategory category;
  final String query;
  final bool isLoading;
  final String? errorMessage;

  static const InsightsState initial = InsightsState(
    articles: [],
    category: ArticleCategory.all,
    query: '',
    isLoading: true,
    errorMessage: null,
  );

  InsightsState copyWith({
    List<Article>? articles,
    ArticleCategory? category,
    String? query,
    bool? isLoading,
    Object? errorMessage = _sentinel,
  }) {
    return InsightsState(
      articles: articles ?? this.articles,
      category: category ?? this.category,
      query: query ?? this.query,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

const _sentinel = Object();

/// Drives the Insights feed: holds the active filter chip + free-text
/// query, fetches via [ExpertsApi], and exposes the result for the UI.
///
/// Search input is debounced 500 ms inside [setQuery] so each keystroke
/// doesn't fire an HTTP request.
class InsightsController extends StateNotifier<InsightsState> {
  InsightsController(this._api) : super(InsightsState.initial) {
    refresh();
  }

  final ExpertsApi _api;
  Timer? _debounce;

  Future<void> refresh() => _load(state.category, state.query);

  void selectCategory(ArticleCategory category) {
    if (state.category == category && !state.isLoading) return;
    _debounce?.cancel();
    state = state.copyWith(category: category);
    _load(category, state.query);
  }

  void setQuery(String raw) {
    final trimmed = raw.trim();
    if (trimmed == state.query) return;
    state = state.copyWith(query: trimmed);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _load(state.category, trimmed);
    });
  }

  Future<void> _load(ArticleCategory category, String query) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final articles = await _api.listArticles(
        category: category,
        query: query.isEmpty ? null : query,
      );
      if (!mounted) return;
      state = state.copyWith(articles: articles, isLoading: false);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage:
            'Could not load articles right now. Pull down to retry.',
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final expertsApiProvider = Provider<ExpertsApi>((ref) {
  final api = ExpertsApi();
  ref.onDispose(api.dispose);
  return api;
});

final insightsControllerProvider =
    StateNotifierProvider<InsightsController, InsightsState>((ref) {
  return InsightsController(ref.watch(expertsApiProvider));
});
