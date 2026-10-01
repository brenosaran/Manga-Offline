import 'dart:convert';

import 'package:http/http.dart' as http;

/// Consulta a **API pública do MALSync** (`https://api.malsync.moe`), que mantém
/// um grande mapeamento de IDs entre MyAnimeList, MangaDex e vários sites de
/// leitura. Serve como **fallback** para achar o id do MangaDex de uma obra
/// quando o `links.al` do MangaDex não resolve o vínculo com a AniList.
///
/// A API é indexada por **MAL id** (`GET /mal/manga/{malId}`); o MAL id da obra
/// vem da AniList (`MetadataService.anilistIdMal`).
class MalsyncService {
  MalsyncService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _base = 'https://api.malsync.moe';
  static const Map<String, String> _headers = {
    'User-Agent': 'MangaOffline/1.0 (flutter)',
  };

  /// Id do MangaDex (UUID) da obra a partir do [malId]. Retorna `null` se não
  /// houver mapeamento.
  Future<String?> mangadexIdForMal(int malId) async {
    try {
      final response = await _client
          .get(Uri.parse('$_base/mal/manga/$malId'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final sites = body['Sites'] as Map<String, dynamic>?;
      final mangadex = sites?['Mangadex'] as Map<String, dynamic>?;
      if (mangadex == null || mangadex.isEmpty) return null;
      for (final entry in mangadex.values) {
        if (entry is Map) {
          final id = entry['identifier']?.toString();
          if (id != null && id.isNotEmpty) return id;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
