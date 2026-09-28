import 'dart:convert';

import 'package:http/http.dart' as http;

class CatalogEntry {
  CatalogEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.imageUrl,
    required this.kind,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final String imageUrl;
  final String kind;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'category': category,
        'imageUrl': imageUrl,
        'kind': kind,
      };

  factory CatalogEntry.fromCache(Map<String, dynamic> json) => CatalogEntry(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        imageUrl: json['imageUrl']?.toString() ?? '',
        kind: json['kind']?.toString() ?? '',
      );

  factory CatalogEntry.fromAniList(Map<String, dynamic> node) {
    final titleMap = node['title'] as Map<String, dynamic>?;
    final title = (titleMap?['english'] ??
            titleMap?['romaji'] ??
            'Sem título')
        .toString();

    final genres = (node['genres'] as List?)?.cast<dynamic>() ?? const [];
    final cover = node['coverImage'] as Map<String, dynamic>?;

    return CatalogEntry(
      id: (node['id'] ?? '').toString(),
      title: title,
      description: _clean(node['description']?.toString() ?? ''),
      category: genres.take(4).map((g) => g.toString()).join(' · '),
      imageUrl: (cover?['large'] ?? cover?['medium'] ?? '').toString(),
      kind: (node['format'] ?? 'MANGA').toString(),
    );
  }

  static String _clean(String html) {
    if (html.isEmpty) return '';
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}

class MetadataService {
  MetadataService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _endpoint = 'https://graphql.anilist.co';

  static const String _query = r'''
query ($page: Int, $perPage: Int, $search: String) {
  Page(page: $page, perPage: $perPage) {
    media(type: MANGA, search: $search, isAdult: false, sort: POPULARITY_DESC) {
      id
      title { romaji english }
      description(asHtml: false)
      coverImage { large medium }
      genres
      format
    }
  }
}
''';

  Future<List<CatalogEntry>> topManga({int limit = 25}) {
    return _fetch(page: 1, perPage: limit, search: null);
  }

  Future<List<CatalogEntry>> searchManga(String query, {int limit = 25}) {
    return _fetch(page: 1, perPage: limit, search: query);
  }

  Future<List<CatalogEntry>> _fetch({
    required int page,
    required int perPage,
    required String? search,
  }) async {
    final data = await _postGraphql(_query, {
      'page': page,
      'perPage': perPage,
      'search': search,
    });
    final pageData = data?['Page'] as Map<String, dynamic>?;
    final media =
        (pageData?['media'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return media.map(CatalogEntry.fromAniList).toList();
  }

  static const String _recommendationsQuery = r'''
query ($id: Int, $perPage: Int) {
  Media(id: $id) {
    recommendations(sort: RATING_DESC, perPage: $perPage) {
      nodes {
        mediaRecommendation {
          id
          title { romaji english }
          description(asHtml: false)
          coverImage { large medium }
          genres
          format
        }
      }
    }
  }
}
''';

  Future<List<CatalogEntry>> recommendations(String id, {int limit = 12}) async {
    final numericId = int.tryParse(id);
    if (numericId == null) return [];
    final data = await _postGraphql(
      _recommendationsQuery,
      {'id': numericId, 'perPage': limit},
    );
    final media = data?['Media'] as Map<String, dynamic>?;
    final nodes = (media?['recommendations'] as Map<String, dynamic>?)?['nodes']
        as List?;
    if (nodes == null) return [];
    final result = <CatalogEntry>[];
    for (final node in nodes) {
      final recommended = (node as Map<String, dynamic>)['mediaRecommendation'];
      if (recommended is Map<String, dynamic>) {
        result.add(CatalogEntry.fromAniList(recommended));
      }
    }
    return result;
  }

  Future<Map<String, dynamic>?> _postGraphql(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final response = await _client
        .post(
          Uri.parse(_endpoint),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'query': query, 'variables': variables}),
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode == 429) {
      throw Exception('Muitas requisições à API. Tente de novo em instantes.');
    }
    if (response.statusCode != 200) {
      throw Exception('Falha ao consultar a API (HTTP ${response.statusCode}).');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>?;
  }

  Future<List<int>> downloadImage(String url) async {
    final response =
        await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Falha ao baixar a imagem (HTTP ${response.statusCode}).');
    }
    return response.bodyBytes;
  }
}
