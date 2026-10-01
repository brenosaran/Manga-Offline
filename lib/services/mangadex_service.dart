import 'dart:convert';

import 'package:http/http.dart' as http;

class MangaDexMatch {
  MangaDexMatch({required this.id, required this.title, this.anilistId});

  final String id;
  final String title;

  /// ID da obra na AniList, extraído de `attributes.links.al` (quando existir).
  /// É o vínculo determinístico entre as duas plataformas.
  final String? anilistId;
}

class MangaDexService {
  MangaDexService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _base = 'https://api.mangadex.org';
  static const Map<String, String> _headers = {
    'User-Agent': 'MangaOffline/1.0 (flutter)',
  };

  /// Lista candidatos do MangaDex para [title], já com o `links.al` (AniList)
  /// quando a obra o tiver.
  Future<List<MangaDexMatch>> searchMatches(String title, {int limit = 5}) async {
    final uri = Uri.parse(
      '$_base/manga?title=${Uri.encodeQueryComponent(title)}'
      '&limit=$limit&order[relevance]=desc&contentRating[]=safe'
      '&contentRating[]=suggestive&contentRating[]=erotica',
    );
    final response =
        await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return const [];
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = (body['data'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    final matches = <MangaDexMatch>[];
    for (final item in data) {
      final id = item['id']?.toString();
      if (id == null) continue;
      final attrs = item['attributes'] as Map<String, dynamic>?;
      final titleMap = attrs?['title'] as Map<String, dynamic>? ?? {};
      final links = attrs?['links'] as Map<String, dynamic>?;
      final al = links?['al']?.toString();
      matches.add(MangaDexMatch(
        id: id,
        title: _titleOf(titleMap),
        anilistId: (al == null || al.isEmpty) ? null : al,
      ));
    }
    return matches;
  }

  /// Vínculo determinístico AniList ↔ MangaDex: acha a obra no MangaDex cujo
  /// `links.al` casa exatamente com o [anilistId].
  Future<MangaDexMatch?> findByAnilistId({
    required String title,
    required String anilistId,
  }) async {
    if (anilistId.isEmpty) return null;
    final matches = await searchMatches(title);
    for (final match in matches) {
      if (match.anilistId == anilistId) return match;
    }
    return null;
  }

  /// Fallback: melhor candidato por semelhança de título.
  Future<MangaDexMatch?> findByTitle(String title) async {
    final matches = await searchMatches(title);
    MangaDexMatch? best;
    var bestScore = -1.0;
    for (final match in matches) {
      final score = _similarity(title, match.title);
      if (score > bestScore) {
        bestScore = score;
        best = match;
      }
    }
    return best;
  }

  /// Mapa capítulo → volume (0 quando desconhecido).
  Future<Map<int, int>> chapterVolumes(String mangaId) async {
    final uri = Uri.parse('$_base/manga/$mangaId/aggregate');
    final response =
        await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Falha ao buscar volumes (HTTP ${response.statusCode}).');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final volumes = body['volumes'] as Map<String, dynamic>? ?? {};
    final result = <int, int>{};

    volumes.forEach((volumeKey, volumeData) {
      final volume = int.tryParse(volumeKey);
      if (volume == null) return;
      final chapters = (volumeData as Map<String, dynamic>)['chapters'];
      if (chapters is! Map) return;
      chapters.forEach((chapterKey, chapterData) {
        final raw = (chapterData is Map)
            ? (chapterData['chapter'] ?? chapterKey)
            : chapterKey;
        final number = double.tryParse(raw.toString());
        if (number != null) {
          result[number.round()] = volume;
        }
      });
    });

    return result;
  }

  /// Capítulos esperados por volume (0 = sem volume), a partir do aggregate.
  Future<Map<int, List<int>>> chaptersByVolume(String mangaId) async {
    final uri = Uri.parse('$_base/manga/$mangaId/aggregate');
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) return {};

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final volumes = body['volumes'] as Map<String, dynamic>? ?? {};
    final result = <int, List<int>>{};

    volumes.forEach((volumeKey, volumeData) {
      final volume = int.tryParse(volumeKey) ?? 0;
      final chapters = (volumeData as Map<String, dynamic>)['chapters'];
      if (chapters is! Map) return;
      chapters.forEach((chapterKey, chapterData) {
        final raw = (chapterData is Map)
            ? (chapterData['chapter'] ?? chapterKey)
            : chapterKey;
        final number = double.tryParse(raw.toString());
        if (number != null) {
          result.putIfAbsent(volume, () => <int>[]).add(number.round());
        }
      });
    });
    for (final list in result.values) {
      list.sort();
    }
    return result;
  }

  /// Descrição localizada (ex.: 'pt-br', 'en').
  Future<String?> localizedDescription(String mangaId, String language) async {
    final uri = Uri.parse('$_base/manga/$mangaId');
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>?;
    final attributes = data?['attributes'] as Map<String, dynamic>?;
    final descriptions = attributes?['description'] as Map<String, dynamic>?;
    if (descriptions == null) return null;
    final value = descriptions[language] ??
        descriptions['pt-br'] ??
        descriptions['en'];
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  /// Mapa volume → URL da capa (capa colorida do volume físico).
  Future<Map<int, String>> volumeCoverUrls(String mangaId) async {
    final uri = Uri.parse('$_base/manga/$mangaId?includes[]=cover_art');
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return {};

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>?;
    final relationships = (data?['relationships'] as List?) ?? const [];
    final result = <int, String>{};

    for (final relationship in relationships) {
      if (relationship is! Map) continue;
      if (relationship['type'] != 'cover_art') continue;
      final attributes = relationship['attributes'];
      if (attributes is! Map) continue;
      final fileName = attributes['fileName']?.toString();
      final volume = int.tryParse(attributes['volume']?.toString() ?? '');
      if (fileName == null || fileName.isEmpty || volume == null) continue;
      result[volume] = 'https://uploads.mangadex.org/covers/$mangaId/$fileName';
    }
    return result;
  }

  String _titleOf(Map<String, dynamic> titleMap) {
    return (titleMap['pt-br'] ??
            titleMap['en'] ??
            titleMap.values.firstOrNull ??
            '')
        .toString();
  }

  double _similarity(String a, String b) {
    final na = _normalize(a);
    final nb = _normalize(b);
    if (na.isEmpty || nb.isEmpty) return 0;
    if (na == nb) return 1;
    if (na.contains(nb) || nb.contains(na)) return 0.8;
    return 0;
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
