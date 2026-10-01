import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manga_offline/services/malsync_service.dart';
import 'package:manga_offline/services/mangadex_service.dart';
import 'package:manga_offline/services/metadata_service.dart';

/// Corpo de busca do MangaDex com dois candidatos: o correto traz
/// `links.al = "30013"`; o outro (mais popular por título) não.
const _mangadexSearch = '''
{
  "result": "ok",
  "data": [
    {
      "id": "00000000-0000-0000-0000-000000000000",
      "attributes": {
        "title": { "en": "One Piece (falso)" },
        "links": { "al": "99999", "mal": "99999" }
      }
    },
    {
      "id": "a1c7c817-4e59-43b7-9365-09675a149a6f",
      "attributes": {
        "title": { "en": "One Piece" },
        "links": { "al": "30013", "mal": "13" }
      }
    }
  ]
}
''';

MangaDexService _dexWith(String body, {int status = 200}) {
  return MangaDexService(
    client: MockClient((request) async => http.Response(body, status)),
  );
}

void main() {
  group('MangaDexService', () {
    test('searchMatches extrai o links.al de cada candidato', () async {
      final matches = await _dexWith(_mangadexSearch).searchMatches('One Piece');
      expect(matches, hasLength(2));
      expect(matches[1].id, 'a1c7c817-4e59-43b7-9365-09675a149a6f');
      expect(matches[1].anilistId, '30013');
    });

    test('findByAnilistId casa pelo links.al (e não pelo 1º por relevância)',
        () async {
      final match = await _dexWith(_mangadexSearch).findByAnilistId(
        title: 'One Piece',
        anilistId: '30013',
      );
      expect(match?.id, 'a1c7c817-4e59-43b7-9365-09675a149a6f');
    });

    test('findByAnilistId devolve null quando nenhum links.al casa', () async {
      final match = await _dexWith(_mangadexSearch).findByAnilistId(
        title: 'One Piece',
        anilistId: 'nao-existe',
      );
      expect(match, isNull);
    });

    test('findByTitle usa semelhança de título como fallback', () async {
      final match = await _dexWith(_mangadexSearch).findByTitle('One Piece');
      expect(match, isNotNull);
      expect(match!.id, 'a1c7c817-4e59-43b7-9365-09675a149a6f');
    });
  });

  group('MalsyncService', () {
    test('mangadexIdForMal lê Sites.Mangadex[*].identifier', () async {
      const body = '''
{
  "id": 13,
  "type": "manga",
  "title": "One Piece",
  "Sites": {
    "Mangadex": {
      "a1c7c817-4e59-43b7-9365-09675a149a6f": {
        "id": 38,
        "identifier": "a1c7c817-4e59-43b7-9365-09675a149a6f"
      }
    }
  }
}
''';
      final service = MalsyncService(
        client: MockClient((request) async {
          expect(request.url.path, '/mal/manga/13');
          return http.Response(body, 200);
        }),
      );
      expect(
        await service.mangadexIdForMal(13),
        'a1c7c817-4e59-43b7-9365-09675a149a6f',
      );
    });

    test('devolve null quando não há MangaDex no mapeamento', () async {
      final service = MalsyncService(
        client: MockClient((_) async => http.Response('{"Sites":{}}', 200)),
      );
      expect(await service.mangadexIdForMal(13), isNull);
    });
  });

  group('MetadataService.anilistIdMal', () {
    test('lê o idMal da AniList', () async {
      final service = MetadataService(
        client: MockClient((request) async {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          expect(sent['variables'], {'id': 30013});
          return http.Response(
            '{"data":{"Media":{"id":30013,"idMal":13}}}',
            200,
          );
        }),
      );
      expect(await service.anilistIdMal('30013'), 13);
    });

    test('devolve null para id não numérico', () async {
      final service = MetadataService(
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(await service.anilistIdMal('abc'), isNull);
    });
  });
}
