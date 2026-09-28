import 'dart:convert';

import 'package:http/http.dart' as http;

/// API pública (não oficial) com arcos/sagas de One Piece.
/// O locale vai no caminho: `/v2/sagas/<locale>`.
class OnePieceService {
  OnePieceService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _base = 'https://api.api-onepiece.com/v2';

  Future<Map<int, String>> volumeSagas({String locale = 'en'}) async {
    final response = await _client
        .get(Uri.parse('$_base/sagas/$locale'))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return {};
    final list = jsonDecode(response.body) as List;
    final map = <int, String>{};
    for (final item in list) {
      if (item is! Map) continue;
      final title = item['title']?.toString() ?? '';
      final range = item['saga_volume']?.toString() ?? '';
      if (title.isEmpty || range.isEmpty) continue;
      final match =
          RegExp(r'(\d+)\s*(?:à|a|-|–|to)\s*(\d+)').firstMatch(range);
      if (match == null) {
        final single = int.tryParse(range.trim());
        if (single != null) map[single] = title;
        continue;
      }
      final start = int.parse(match.group(1)!);
      final end = int.parse(match.group(2)!);
      for (var volume = start; volume <= end; volume++) {
        map[volume] = title;
      }
    }
    return map;
  }
}
