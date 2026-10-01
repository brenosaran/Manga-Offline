import 'package:flutter_test/flutter_test.dart';
import 'package:manga_offline/downloader/mangadex_api.dart';
import 'package:manga_offline/downloader/mangalivre_api.dart';
import 'package:manga_offline/services/chapter_download_service.dart';

ChapterInfo _dex({
  String chapter = '1',
  int pages = 10,
  String? externalUrl,
  bool isUnavailable = false,
}) {
  return ChapterInfo(
    id: 'id-$chapter',
    chapter: chapter,
    language: 'pt-br',
    pages: pages,
    isUnavailable: isUnavailable,
    externalUrl: externalUrl,
  );
}

void main() {
  group('pickMangadexChapter', () {
    test('encontra o capítulo hospedado pelo número', () {
      final chapters = [_dex(chapter: '1'), _dex(chapter: '4')];
      expect(pickMangadexChapter(chapters, 4)?.chapter, '4');
    });

    test('ignora capítulos externos/indisponíveis', () {
      final chapters = [
        _dex(chapter: '4', externalUrl: 'https://x'),
        _dex(chapter: '4', pages: 0),
        _dex(chapter: '4'),
      ];
      expect(pickMangadexChapter(chapters, 4)?.chapter, '4');
    });

    test('casa a parte inteira de números decimais', () {
      final chapters = [_dex(chapter: '10.5')];
      expect(pickMangadexChapter(chapters, 10)?.chapter, '10.5');
    });

    test('retorna null quando não encontra', () {
      expect(pickMangadexChapter([_dex(chapter: '1')], 9), isNull);
    });
  });

  group('pickMangaLivreChapter', () {
    test('encontra pelo número', () {
      final chapters = [
        MangaLivreChapter(number: 3, urls: ['a']),
        MangaLivreChapter(number: 4, urls: ['b']),
      ];
      expect(pickMangaLivreChapter(chapters, 4)?.number, 4);
    });

    test('retorna null quando não encontra', () {
      expect(
        pickMangaLivreChapter([MangaLivreChapter(number: 1, urls: ['a'])], 7),
        isNull,
      );
    });
  });

  group('mangaLivreUrlFor', () {
    test('monta a URL no padrão do site (sem sufixo -ptbr)', () {
      expect(
        mangaLivreUrlFor('One Piece'),
        'https://mangalivre.to/manga/one-piece/',
      );
    });

    test('remove acentos e caracteres especiais', () {
      expect(slugifyTitle('Dandadan!'), 'dandadan');
      expect(slugifyTitle('Mangá Ação'), 'manga-acao');
    });
  });
}
