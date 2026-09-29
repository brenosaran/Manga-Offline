import 'dart:io';

/// Resultado do processamento de um capítulo, independente da fonte.
class ChapterResult {
  ChapterResult({
    required this.number,
    required this.source,
    required this.file,
    required this.skipped,
    required this.pageCount,
    this.title,
  });

  /// Número do capítulo como texto, ex.: `1`, `10.5`.
  final String number;

  /// Fonte utilizada (`MangaDex` ou `MangaLivre`).
  final String source;
  final String? title;
  final File file;
  final bool skipped;
  final int pageCount;
}
