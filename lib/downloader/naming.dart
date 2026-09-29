import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Nome legível do capítulo, ex.: `0001` ou `0010.5`.
String formatChapterNumber(String chapter) {
  final value = chapter.trim();
  if (value.isEmpty) return '0000';
  final dot = value.indexOf('.');
  if (dot == -1) {
    final parsed = int.tryParse(value);
    return parsed == null ? value : parsed.toString().padLeft(4, '0');
  }
  final intPart = value.substring(0, dot);
  final fraction = value.substring(dot);
  final parsed = int.tryParse(intPart);
  final padded = parsed == null ? intPart : parsed.toString().padLeft(4, '0');
  return '$padded$fraction';
}

/// Monta o nome do arquivo `.cbz`, ex.: `One Piece - Cap 0001 - Romance dawn.cbz`.
String buildCbzFileName({
  required String mangaTitle,
  required String chapterNumber,
  String? chapterTitle,
}) {
  final buffer =
      StringBuffer('$mangaTitle - Cap ${formatChapterNumber(chapterNumber)}');
  if (chapterTitle != null && chapterTitle.isNotEmpty) {
    buffer.write(' - $chapterTitle');
  }
  return '${sanitizeFileName(buffer.toString())}.cbz';
}

/// Remove caracteres inválidos em nomes de arquivo do Windows.
String sanitizeFileName(String name) {
  var out = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  out = out.replaceAll(RegExp(r'[. ]+$'), '');
  const maxLength = 120;
  if (out.length > maxLength) out = out.substring(0, maxLength).trim();
  return out.isEmpty ? 'sem-titulo' : out;
}

/// Empacota imagens em um ZIP/CBZ, numerando as páginas para leitura correta.
Uint8List buildCbz(List<Uint8List> images, List<String> originalNames) {
  final archive = Archive();
  for (var i = 0; i < images.length; i++) {
    final ext = p.extension(originalNames[i]).toLowerCase();
    final name = '${(i + 1).toString().padLeft(4, '0')}$ext';
    archive.add(ArchiveFile.bytes(name, images[i]));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
