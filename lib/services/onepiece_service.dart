import 'dart:convert';

import 'package:http/http.dart' as http;

/// API pública (não oficial) com arcos/sagas de One Piece.
/// O locale vai no caminho: `/v2/sagas/<locale>`.
class OnePieceService {
  OnePieceService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _base = 'https://api.api-onepiece.com/v2';

  /// Nomes de saga que a API devolve fora do inglês (ex.: francês) e a
  /// tradução inglesa usada no app.
  static const Map<String, String> _sagaEnglishNames = {
    'iledeshommespoissons': 'Fish-Man Island',
  };

  Future<Map<int, String>> volumeSagas({String locale = 'en'}) async {
    final response = await _client
        .get(Uri.parse('$_base/sagas/$locale'))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return {};
    final list = jsonDecode(response.body) as List;
    final map = <int, String>{};
    for (final item in list) {
      if (item is! Map) continue;
      final title = englishSagaName(item['title']?.toString() ?? '');
      final range = item['saga_volume']?.toString() ?? '';
      if (title.isEmpty || range.isEmpty) continue;
      final closed =
          RegExp(r'(\d+)\s*(?:à|a|-|–|to)\s*(\d+)').firstMatch(range);
      if (closed != null) {
        final start = int.parse(closed.group(1)!);
        final end = int.parse(closed.group(2)!);
        for (var volume = start; volume <= end; volume++) {
          map[volume] = title;
        }
        continue;
      }
      // Faixa aberta, ex.: "81 à ?" (a API não informa o fim) — vale do
      // início até o fim dos volumes conhecidos.
      final open =
          RegExp(r'(\d+)\s*(?:à|a|-|–|to)\s*\?').firstMatch(range);
      if (open != null) {
        final start = int.parse(open.group(1)!);
        for (var volume = start; volume < start + 1000; volume++) {
          map[volume] = title;
        }
        continue;
      }
      final single = int.tryParse(range.trim());
      if (single != null) map[single] = title;
    }
    return map;
  }

  /// Mapa **capítulo → volume** a partir de `/v2/chapters/<locale>`.
  ///
  /// A API do One Piece cobre **todos os capítulos** e volumes (1–115),
  /// servindo para **preencher as lacunas** que o MangaDex tem (ex.: One Piece
  /// não tem os volumes 8–60 no `aggregate`).
  Future<Map<int, int>> chapterVolumes({String locale = 'en'}) async {
    final response = await _client
        .get(Uri.parse('$_base/chapters/$locale'))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) return {};
    final list = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    final map = <int, int>{};
    for (final item in list) {
      if (item is! Map) continue;
      final chapter = int.tryParse(item['id']?.toString() ?? '');
      final tome = item['tome'];
      final volume = tome is Map
          ? int.tryParse(
              (tome['tome_number']?.toString() ?? '')
                  .replaceAll(RegExp(r'[^0-9]'), ''),
            )
          : null;
      if (chapter != null && volume != null && volume > 0) {
        map[chapter] = volume;
      }
    }
    return map;
  }

  /// Traduz nomes de saga que a API traz em outro idioma para o inglês.
  String englishSagaName(String title) {
    return _sagaEnglishNames[_normalizeKey(title)] ?? title;
  }

  String _normalizeKey(String input) {
    const accents = {
      'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(accents[ch] ?? ch);
    }
    return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
