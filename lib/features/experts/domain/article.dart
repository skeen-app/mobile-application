/// Coarse buckets surfaced as filter chips on the Insights feed.
enum ArticleCategory {
  all,
  prevention,
  detection,
  treatment;

  String get slug => name;

  String get displayLabel {
    switch (this) {
      case ArticleCategory.all:
        return 'All';
      case ArticleCategory.prevention:
        return 'Prevention';
      case ArticleCategory.detection:
        return 'Detection';
      case ArticleCategory.treatment:
        return 'Treatment';
    }
  }

  static ArticleCategory fromSlug(String? slug) {
    return ArticleCategory.values.firstWhere(
      (c) => c.slug == slug,
      orElse: () => ArticleCategory.all,
    );
  }
}

/// One author of a published article. ``country`` is best-effort.
class ArticleAuthor {
  const ArticleAuthor({
    required this.name,
    this.country,
    this.affiliation,
  });

  final String name;
  final String? country;
  final String? affiliation;

  factory ArticleAuthor.fromJson(Map<String, dynamic> json) => ArticleAuthor(
        name: json['name'] as String,
        country: json['country'] as String?,
        affiliation: json['affiliation'] as String?,
      );
}

/// One curated item shown on the Insights feed.
class Article {
  const Article({
    required this.id,
    required this.title,
    required this.url,
    required this.category,
    this.summary,
    this.authors = const [],
    this.journal,
    this.publishedAt,
    this.articleType,
  });

  final String id;
  final String title;
  final String? summary;
  final List<ArticleAuthor> authors;
  final String? journal;
  final DateTime? publishedAt;
  final String? articleType;
  final String url;
  final ArticleCategory category;

  factory Article.fromJson(Map<String, dynamic> json) {
    final authorsRaw = (json['authors'] as List?) ?? const [];
    DateTime? parsedDate;
    final dateText = json['published_at'] as String?;
    if (dateText != null && dateText.isNotEmpty) {
      parsedDate = DateTime.tryParse(dateText);
    }
    return Article(
      id: json['id'] as String,
      title: json['title'] as String,
      summary: json['summary'] as String?,
      authors: authorsRaw
          .whereType<Map<String, dynamic>>()
          .map(ArticleAuthor.fromJson)
          .toList(growable: false),
      journal: json['journal'] as String?,
      publishedAt: parsedDate,
      articleType: json['article_type'] as String?,
      url: json['url'] as String,
      category: ArticleCategory.fromSlug(json['category'] as String?),
    );
  }
}
