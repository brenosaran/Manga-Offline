import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manga_offline/downloader/mangadex_api.dart';
import 'package:manga_offline/downloader/mangadex_downloader.dart';
import 'package:path/path.dart' as p;

void main() {
  group('nomes e formatação', () {
    test('formata números de capítulo com zeros à esquerda', () {
      expect(formatChapterNumber('1'), '0001');
      expect(formatChapterNumber('62'), '0062');
      expect(formatChapterNumber('10.5'), '0010.5');
      expect(formatChapterNumber(''), '0000');
    });

    test('sanitiza caracteres inválidos do Windows', () {
      expect(sanitizeFileName('a:b/c\\d?e*f|g"h<i>j'), 'a_b_c_d_e_f_g_h_i_j');
      expect(sanitizeFileName('  nome   com   espaços  '), 'nome com espaços');
      expect(sanitizeFileName('fim... '), 'fim');
    });

    test('monta o nome do arquivo .cbz', () {
      final chapter = ChapterInfo(
        id: 'x',
        chapter: '1',
        language: 'pt-br',
        pages: 53,
        isUnavailable: false,
        title: 'Romance dawn',
      );
      expect(
        buildChapterFileName('One Piece', chapter),
        'One Piece - Cap 0001 - Romance dawn.cbz',
      );
    });

    test('extrai o id de uma URL do MangaDex', () {
      expect(
        MangadexApi.extractMangaId(
          'https://mangadex.org/title/a1c7c817-4e59-43b7-9365-09675a149a6f/one-piece',
        ),
        'a1c7c817-4e59-43b7-9365-09675a149a6f',
      );
      expect(MangadexApi.extractMangaId('  abc-def  '), 'abc-def');
    });

    test('ordena capítulos numericamente', () {
      final list = ['10', '2', '1', '10.5', ''];
      list.sort(compareChapters);
      expect(list, ['1', '2', '10', '10.5', '']);
    });
  });

  test('buildCbz gera um zip válido com páginas numeradas', () {
    final bytes = buildCbz(
      [
        Uint8List.fromList([1, 1, 1]),
        Uint8List.fromList([2, 2, 2]),
      ],
      ['001.jpg', '002.jpg'],
    );

    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.where((f) => f.isFile).map((f) => f.name).toList();
    expect(names, ['0001.jpg', '0002.jpg']);
  });

  group('MangadexApi com MockClient', () {
    test('pagina o feed e marca capítulos hospedados', () async {
      final api = MangadexApi(
        apiBaseUrl: 'https://api.test',
        client: MockClient((request) async {
          expect(request.url.path, '/manga/mid/feed');
          return _jsonResponse({
            'result': 'ok',
            'data': [
              _chapterJson('b', '2', pages: 20),
              _chapterJson('a', '1', pages: 53),
              _chapterJson('c', '1', pages: 0, externalUrl: 'https://x'),
            ],
            'total': 3,
          });
        }),
      );

      final chapters = await api.getChapters(mangaId: 'mid', language: 'pt-br');
      expect(chapters.map((c) => c.chapter).toList(), ['1', '1', '2']);
      expect(
        chapters.where((c) => c.isHosted).map((c) => c.id).toSet(),
        {'a', 'b'},
      );
    });

    test('baixa um capítulo e grava o .cbz', () async {
      final tmp = Directory.systemTemp.createTempSync('manga_offline_dl');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final imageRequests = <String>[];
      final api = MangadexApi(
        apiBaseUrl: 'https://api.test',
        client: MockClient((request) async {
          final path = request.url.path;
          if (path.contains('/at-home/server/')) {
            return _jsonResponse({
              'result': 'ok',
              'baseUrl': 'https://uploads.test',
              'chapter': {
                'hash': 'abc',
                'data': ['p1.png', 'p2.png'],
                'dataSaver': ['s1.png', 's2.png'],
              },
            });
          }
          if (path.startsWith('/data/')) {
            imageRequests.add(path);
            return http.Response.bytes([9, 9, 9, 9], 200);
          }
          if (path.endsWith('/feed')) {
            return _jsonResponse({
              'result': 'ok',
              'data': [_chapterJson('a', '1', pages: 2)],
              'total': 1,
            });
          }
          return http.Response('not found', 404);
        }),
      );

      final downloader = MangadexDownloader(
        api: api,
        options: DownloadOptions(
          outDir: tmp.path,
          delayBetweenChapters: Duration.zero,
        ),
      );
      final chapter = (await api.getChapters(mangaId: 'mid', language: 'pt-br'))
          .first;

      final result = await downloader.downloadChapter(chapter, mangaTitle: 'One Piece');
      expect(result.skipped, isFalse);
      expect(result.pageCount, 2);
      expect(result.file.existsSync(), isTrue);
      expect(p.basename(result.file.path), 'One Piece - Cap 0001 - Romance dawn.cbz');
      expect(imageRequests.length, 2);

      final archive = ZipDecoder().decodeBytes(result.file.readAsBytesSync());
      expect(archive.files.where((f) => f.isFile).length, 2);

      // Segunda execução deve pular o que já existe.
      final again = await downloader.downloadChapter(chapter, mangaTitle: 'One Piece');
      expect(again.skipped, isTrue);
    });
  });
}

http.Response _jsonResponse(Object body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _chapterJson(
  String id,
  String chapter, {
  required int pages,
  String? externalUrl,
}) {
  return {
    'id': id,
    'type': 'chapter',
    'attributes': {
      'chapter': chapter,
      'volume': null,
      'title': id == 'a' && chapter == '1' ? 'Romance dawn' : 'Capítulo $chapter',
      'translatedLanguage': 'pt-br',
      'externalUrl': externalUrl,
      'pages': pages,
      'isUnavailable': false,
    },
  };
}
