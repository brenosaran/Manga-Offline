import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'chapter_result.dart';
import 'mangadex_downloader.dart' show DownloadOptions;
import 'mangalivre_api.dart';
import 'naming.dart';
import 'support.dart';

/// Baixa capítulos do MangaLivre e empacota cada um em um arquivo `.cbz`.
class MangaLivreDownloader {
  MangaLivreDownloader({required this.api, required this.options});

  final MangaLivreApi api;
  final DownloadOptions options;

  Future<ChapterResult> downloadChapter(
    MangaLivreChapter chapter, {
    required String mangaTitle,
  }) async {
    final dir = Directory(options.outDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final file = File(
      p.join(
        options.outDir,
        buildCbzFileName(
          mangaTitle: mangaTitle,
          chapterNumber: chapter.number.toString(),
        ),
      ),
    );

    if (file.existsSync() && !options.force) {
      return ChapterResult(
        number: chapter.number.toString(),
        source: 'MangaLivre',
        file: file,
        skipped: true,
        pageCount: 0,
      );
    }

    final imageUrls = await _resolveImageUrls(chapter);
    if (imageUrls.isEmpty) {
      throw MangaLivreException(
        'Capítulo ${chapter.number}: nenhuma página encontrada.',
      );
    }

    final images = await _downloadImages(imageUrls);
    await writeCbz(file, images, imageUrls);

    return ChapterResult(
      number: chapter.number.toString(),
      source: 'MangaLivre',
      file: file,
      skipped: false,
      pageCount: images.length,
    );
  }

  /// Tenta as URLs candidatas até achar uma que tenha páginas de verdade
  /// (o site às vezes tem uma URL "vazia" e outra com o conteúdo).
  Future<List<String>> _resolveImageUrls(MangaLivreChapter chapter) async {
    Object? lastError;
    for (final url in chapter.urls) {
      try {
        final images = await retryOperation(
          () => api.chapterImages(url),
          retries: options.retries,
        );
        if (images.isNotEmpty) return images;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) {
      throw MangaLivreException(
        'Capítulo ${chapter.number}: $lastError',
      );
    }
    return const [];
  }

  Future<List<Uint8List>> _downloadImages(List<String> urls) async {
    final results = List<Uint8List?>.filled(urls.length, null);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= urls.length) return;
        results[index] = await retryOperation(
          () => api.downloadBytes(urls[index]),
          retries: options.retries,
        );
      }
    }

    await runPool(
      count: urls.length,
      concurrency: options.imageConcurrency,
      worker: worker,
    );
    return results.map((bytes) => bytes!).toList();
  }
}
