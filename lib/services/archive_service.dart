import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

class MangaArchiveException implements Exception {
  MangaArchiveException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ArchiveService {
  static const Set<String> supportedExtensions = {'.cbz', '.zip', '.cbr', '.rar'};

  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.avif',
  };

  bool isSupportedFile(String path) =>
      supportedExtensions.contains(p.extension(path).toLowerCase());

  bool isRar(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.cbr' || ext == '.rar';
  }

  Future<List<String>> extractPages({
    required String archivePath,
    required String outputDir,
  }) async {
    if (isRar(archivePath)) {
      throw MangaArchiveException(
        'Arquivos .cbr/.rar ainda não são suportados. Converta para .cbz ou '
        '.zip (é só renomear/reecompactar mantendo as imagens).',
      );
    }

    final bytes = await File(archivePath).readAsBytes();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw MangaArchiveException('Não foi possível abrir o arquivo: $e');
    }

    final images = archive.files
        .where((f) => f.isFile && _isImage(f.name))
        .toList()
      ..sort((a, b) => _naturalCompare(a.name, b.name));

    if (images.isEmpty) {
      throw MangaArchiveException('Nenhuma imagem encontrada dentro do arquivo.');
    }

    final dir = Directory(outputDir);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    dir.createSync(recursive: true);

    final paths = <String>[];
    for (var i = 0; i < images.length; i++) {
      final file = images[i];
      final Uint8List? data = file.readBytes();
      if (data == null || data.isEmpty) continue;
      final ext = _imageExtension(file.name);
      final target = p.join(outputDir, '${_pad(i)}$ext');
      await File(target).writeAsBytes(data, flush: false);
      paths.add(target);
    }

    if (paths.isEmpty) {
      throw MangaArchiveException('As imagens do arquivo estão vazias ou corrompidas.');
    }

    return paths;
  }

  bool _isImage(String name) {
    final ext = p.extension(name).toLowerCase();
    return _imageExtensions.contains(ext);
  }

  String _imageExtension(String name) {
    final ext = p.extension(name).toLowerCase();
    return ext == '.jpeg' ? '.jpg' : ext;
  }

  String _pad(int value) => value.toString().padLeft(6, '0');

  int _naturalCompare(String a, String b) {
    final regex = RegExp(r'(\d+)|(\D+)');
    final matchesA = regex.allMatches(a.toLowerCase()).toList();
    final matchesB = regex.allMatches(b.toLowerCase()).toList();
    final count = matchesA.length < matchesB.length
        ? matchesA.length
        : matchesB.length;

    for (var i = 0; i < count; i++) {
      final partA = matchesA[i].group(0)!;
      final partB = matchesB[i].group(0)!;
      final numA = int.tryParse(partA);
      final numB = int.tryParse(partB);

      int result;
      if (numA != null && numB != null) {
        result = numA.compareTo(numB);
      } else {
        result = partA.compareTo(partB);
      }
      if (result != 0) return result;
    }

    return matchesA.length.compareTo(matchesB.length);
  }
}
