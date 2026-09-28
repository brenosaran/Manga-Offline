import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_offline/services/archive_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('extrai páginas de um .cbz em ordem natural', () async {
    final tmp = Directory.systemTemp.createTempSync('manga_offline_test');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final archive = Archive();
    for (final name in ['page10.png', 'page2.png', 'page1.png']) {
      archive.add(ArchiveFile.bytes(name, Uint8List.fromList([1, 2, 3, 4])));
    }
    final bytes = ZipEncoder().encode(archive);
    final cbz = File(p.join(tmp.path, 'capitulo.cbz'))
      ..writeAsBytesSync(bytes);

    final service = ArchiveService();
    expect(service.isSupportedFile(cbz.path), isTrue);
    expect(service.isRar(cbz.path), isFalse);

    final pages = await service.extractPages(
      archivePath: cbz.path,
      outputDir: p.join(tmp.path, 'out'),
    );

    expect(pages.length, 3);
    expect(p.basename(pages[0]), '000000.png');
    expect(p.basename(pages[1]), '000001.png');
    expect(p.basename(pages[2]), '000002.png');
  });

  test('rejeita arquivos .cbr com mensagem clara', () async {
    final service = ArchiveService();
    expect(service.isRar('volume.cbr'), isTrue);
    await expectLater(
      service.extractPages(archivePath: 'volume.cbr', outputDir: 'out'),
      throwsA(isA<MangaArchiveException>()),
    );
  });
}
