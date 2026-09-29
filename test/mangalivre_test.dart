import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manga_offline/downloader/mangadex_downloader.dart'
    show DownloadOptions;
import 'package:manga_offline/downloader/mangalivre_api.dart';
import 'package:manga_offline/downloader/mangalivre_downloader.dart';
import 'package:path/path.dart' as p;

const _mangaPage = '''
<html><head>
<meta property="og:title" content="One Piece | Manga Livre - Leitor online" />
</head><body>
<a href="https://mangalivre.to/manga/one-piece-ptbr/capitulo-1/">Cap 1</a>
<a href="https://mangalivre.to/manga/one-piece-ptbr/capitulo-2/">Cap 2</a>
<a href="https://mangalivre.to/manga/one-piece-ptbr/capitulo-108/">Cap 108</a>
<a href="https://mangalivre.to/manga/one-piece-ptbr/capitulo-108-100/">Cap 108 alt</a>
<a href="https://mangalivre.to/manga/outro-manga/capitulo-500/">Outro</a>
</body></html>
''';

const _emptyChapterPage = '<html><body><p>sem imagens</p></body></html>';

const _chapterPage = '''
<html><body>
<img id="image-0" src=" https://mangalivre.to/wp-content/uploads/WP-manga/data/x/y/001.webp" class="wp-manga-chapter-img">
<img id="image-1" data-src="https://mangalivre.to/wp-content/uploads/WP-manga/data/x/y/002.webp" src="placeholder.gif" class="wp-manga-chapter-img">
</body></html>
''';

http.Response _html(String body) => http.Response.bytes(
      // UTF-8 para bater com o parser.
      const Utf8Encoder().convert(body),
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );

void main() {
  test('lista capítulos agrupando slugs alternativos por número', () async {
    final api = MangaLivreApi(
      client: MockClient((_) async => _html(_mangaPage)),
    );

    final chapters = await api.listChapters(
      'https://mangalivre.to/manga/one-piece-ptbr/',
    );

    expect(chapters.map((c) => c.number).toList(), [1, 2, 108]);
    final c108 = chapters.firstWhere((c) => c.number == 108);
    expect(c108.urls, [
      'https://mangalivre.to/manga/one-piece-ptbr/capitulo-108/',
      'https://mangalivre.to/manga/one-piece-ptbr/capitulo-108-100/',
    ]);
  });

  test('lê o título do mangá', () async {
    final api = MangaLivreApi(
      client: MockClient((_) async => _html(_mangaPage)),
    );
    expect(
      await api.getMangaTitle('https://mangalivre.to/manga/one-piece-ptbr/'),
      'One Piece',
    );
  });

  test('extrai as imagens do capítulo na ordem e limpa o src', () async {
    final api = MangaLivreApi(
      client: MockClient((_) async => _html(_chapterPage)),
    );

    final images = await api.chapterImages(
      'https://mangalivre.to/manga/one-piece-ptbr/capitulo-108/',
    );

    expect(images, [
      'https://mangalivre.to/wp-content/uploads/WP-manga/data/x/y/001.webp',
      'https://mangalivre.to/wp-content/uploads/WP-manga/data/x/y/002.webp',
    ]);
  });

  test('baixa capítulo do MangaLivre e usa o candidato com páginas', () async {
    final tmp = Directory.systemTemp.createTempSync('manga_offline_ml');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final imageHits = <String>[];
    final api = MangaLivreApi(
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.contains('/capitulo-108-100/')) return _html(_chapterPage);
        if (path.contains('/capitulo-108/')) return _html(_emptyChapterPage);
        if (path.startsWith('/wp-content/')) {
          imageHits.add(path);
          return http.Response.bytes([7, 7, 7], 200);
        }
        return http.Response('nope', 404);
      }),
    );

    final chapter = MangaLivreChapter(number: 108, urls: [
      'https://mangalivre.to/manga/one-piece-ptbr/capitulo-108/',
      'https://mangalivre.to/manga/one-piece-ptbr/capitulo-108-100/',
    ]);

    final downloader = MangaLivreDownloader(
      api: api,
      options: DownloadOptions(outDir: tmp.path, delayBetweenChapters: Duration.zero),
    );

    final result = await downloader.downloadChapter(chapter, mangaTitle: 'One Piece');
    expect(result.skipped, isFalse);
    expect(result.pageCount, 2);
    expect(imageHits.length, 2);
    expect(p.basename(result.file.path), 'One Piece - Cap 0108.cbz');

    final archive = ZipDecoder().decodeBytes(result.file.readAsBytesSync());
    expect(
      archive.files.where((f) => f.isFile).map((f) => f.name).toList(),
      ['0001.webp', '0002.webp'],
    );

    // Segunda vez deve pular.
    final again = await downloader.downloadChapter(chapter, mangaTitle: 'One Piece');
    expect(again.skipped, isTrue);
  });
}
