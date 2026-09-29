import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'chapter_result.dart';
import 'mangadex_api.dart';
import 'naming.dart';
import 'support.dart';

export 'chapter_result.dart';
export 'naming.dart';
export 'support.dart';

/// Opções de execução dos downloaders.
class DownloadOptions {
  DownloadOptions({
    required this.outDir,
    this.dataSaver = false,
    this.retries = 3,
    this.imageConcurrency = 3,
    this.delayBetweenChapters = const Duration(milliseconds: 1200),
    this.force = false,
  });

  /// Pasta onde os `.cbz` serão gravados.
  final String outDir;

  /// Se true, baixa a versão leve das imagens (`data-saver`). Só MangaDex.
  final bool dataSaver;

  /// Tentativas extras para cada operação de rede.
  final int retries;

  /// Quantas imagens baixar em paralelo dentro de um capítulo.
  final int imageConcurrency;

  /// Pausa entre capítulos, para respeitar os limites dos sites.
  final Duration delayBetweenChapters;

  /// Re-baixa capítulos que já têm `.cbz` na pasta.
  final bool force;
}

/// Baixa capítulos do MangaDex e empacota cada um em um arquivo `.cbz`.
class MangadexDownloader {
  MangadexDownloader({required this.api, required this.options});

  final MangadexApi api;
  final DownloadOptions options;

  Future<ChapterResult> downloadChapter(
    ChapterInfo chapter, {
    required String mangaTitle,
  }) async {
    final dir = Directory(options.outDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final file = File(
      p.join(options.outDir, buildChapterFileName(mangaTitle, chapter)),
    );

    if (file.existsSync() && !options.force) {
      return ChapterResult(
        number: chapter.chapter,
        title: chapter.title,
        source: 'MangaDex',
        file: file,
        skipped: true,
        pageCount: chapter.pages,
      );
    }

    if (!chapter.isHosted) {
      throw MangadexException(
        'Capítulo ${displayChapter(chapter)} não está hospedado no MangaDex '
        '(link externo).',
      );
    }

    final server = await _retry(() => api.getAtHome(chapter.id));
    final names = options.dataSaver ? server.dataSaver : server.data;
    if (names.isEmpty) {
      throw MangadexException(
        'Capítulo ${displayChapter(chapter)} não tem páginas disponíveis.',
      );
    }

    final images = await _downloadImages(server, names.length);
    await writeCbz(file, images, names);

    return ChapterResult(
      number: chapter.chapter,
      title: chapter.title,
      source: 'MangaDex',
      file: file,
      skipped: false,
      pageCount: images.length,
    );
  }

  Future<List<Uint8List>> _downloadImages(
    AtHomeServer server,
    int count,
  ) async {
    final results = List<Uint8List?>.filled(count, null);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= count) return;
        final url = api.imageUrl(server, index, dataSaver: options.dataSaver);
        results[index] = await _retry(() => api.downloadBytes(url));
      }
    }

    await runPool(
      count: count,
      concurrency: options.imageConcurrency,
      worker: worker,
    );
    return results.map((bytes) => bytes!).toList();
  }

  Future<T> _retry<T>(Future<T> Function() action) => retryOperation(
        action,
        retries: options.retries,
      );
}

/// Rótulo curto usado em mensagens de log.
String displayChapter(ChapterInfo chapter) {
  final number = chapter.chapter.trim().isEmpty ? '?' : chapter.chapter.trim();
  final title = chapter.title;
  return title == null || title.isEmpty ? number : '$number - "$title"';
}

/// Monta o nome do arquivo `.cbz`, ex.: `One Piece - Cap 0001 - Romance dawn.cbz`.
String buildChapterFileName(String mangaTitle, ChapterInfo chapter) =>
    buildCbzFileName(
      mangaTitle: mangaTitle,
      chapterNumber: chapter.chapter,
      chapterTitle: chapter.title,
    );
