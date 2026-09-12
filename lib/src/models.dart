part of '../system_search_index.dart';

/// Immutable content to index. IDs are unique within a domain.
class SearchItem {
  SearchItem({
    required this.id,
    required this.title,
    this.domain = defaultDomain,
    this.description,
    this.textContent,
    List<String> keywords = const [],
    this.deepLink,
    this.thumbnailUri,
    this.expiresAt,
  }) : keywords = List.unmodifiable(keywords) {
    _nonEmpty(id, 'id');
    _nonEmpty(title, 'title');
    _nonEmpty(domain, 'domain');
    for (final keyword in keywords) {
      _nonEmpty(keyword, 'keywords');
    }
    if (deepLink != null && !deepLink!.hasScheme) {
      throw ArgumentError.value(deepLink, 'deepLink', 'Use an absolute URI.');
    }
    if (thumbnailUri != null && thumbnailUri!.scheme != 'file') {
      throw ArgumentError.value(
        thumbnailUri,
        'thumbnailUri',
        'Use a local file URI.',
      );
    }
  }

  static const defaultDomain = 'default';
  final String id;
  final String domain;
  final String title;
  final String? description;
  final String? textContent;
  final List<String> keywords;

  /// Stored as contentURL on iOS and url on Android. Register the URI scheme
  /// or app links in your host app; Android navigation uses the host router.
  final Uri? deepLink;

  /// A local image file for Spotlight. Ignored by Android.
  final Uri? thumbnailUri;

  /// Absolute expiry. Null means no scheduled expiry. The OS can still evict
  /// indexed data, so keep the application's database as the source of truth.
  final DateTime? expiresAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'domain': domain,
    'title': title,
    'description': ?description,
    'textContent': ?textContent,
    'keywords': keywords,
    'deepLink': ?deepLink?.toString(),
    'thumbnailUri': ?thumbnailUri?.toString(),
    'expiresAt': ?expiresAt?.millisecondsSinceEpoch,
  };

  factory SearchItem.fromMap(Map<Object?, Object?> map) => SearchItem(
    id: map['id'] as String,
    domain: map['domain'] as String,
    title: map['title'] as String,
    description: map['description'] as String?,
    textContent: map['textContent'] as String?,
    keywords: (map['keywords'] as List?)?.cast<String>() ?? const [],
    deepLink: map['deepLink'] == null
        ? null
        : Uri.parse(map['deepLink'] as String),
    thumbnailUri: map['thumbnailUri'] == null
        ? null
        : Uri.parse(map['thumbnailUri'] as String),
    expiresAt: map['expiresAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (map['expiresAt'] as num).toInt(),
            isUtc: true,
          ),
  );
}

enum SearchSystemSurface { spotlight, deviceDependent, unavailable }

class SearchCapabilities {
  const SearchCapabilities({
    required this.indexing,
    required this.semanticSearch,
    required this.suggestions,
    required this.activationEvents,
    required this.systemSurface,
  });

  const SearchCapabilities.unsupported()
    : indexing = false,
      semanticSearch = false,
      suggestions = false,
      activationEvents = false,
      systemSurface = SearchSystemSurface.unavailable;

  final bool indexing;

  /// API availability, not model readiness or a guarantee of semantic matches.
  final bool semanticSearch;
  final bool suggestions;
  final bool activationEvents;
  final SearchSystemSurface systemSurface;

  factory SearchCapabilities.fromMap(Map<Object?, Object?> map) =>
      SearchCapabilities(
        indexing: map['indexing'] == true,
        semanticSearch: map['semanticSearch'] == true,
        suggestions: map['suggestions'] == true,
        activationEvents: map['activationEvents'] == true,
        systemSurface: SearchSystemSurface.values.firstWhere(
          (s) => s.name == map['systemSurface'],
          orElse: () => SearchSystemSurface.unavailable,
        ),
      );
}

class SearchResponse {
  SearchResponse({
    required List<SearchItem> items,
    required List<String> suggestions,
  }) : items = List.unmodifiable(items),
       suggestions = List.unmodifiable(suggestions);

  const SearchResponse.empty() : items = const [], suggestions = const [];

  final List<SearchItem> items;
  final List<String> suggestions;

  factory SearchResponse.fromMap(Map<Object?, Object?> map) => SearchResponse(
    items: (map['items'] as List)
        .map((i) => SearchItem.fromMap(_map(i)))
        .toList(),
    suggestions: (map['suggestions'] as List).cast<String>(),
  );
}

/// Spotlight selection. Resolve the pair against your application's database.
class SearchActivation {
  const SearchActivation({required this.id, required this.domain});

  final String id;
  final String domain;

  factory SearchActivation.fromMap(Map<Object?, Object?> map) =>
      SearchActivation(
        id: map['id'] as String,
        domain: map['domain'] as String,
      );
}
