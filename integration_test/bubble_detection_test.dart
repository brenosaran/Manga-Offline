import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:manga_offline/services/bubble_detector.dart';

/// Página real opcional, empurrada via `adb push` para a pasta externa do app.
/// Se não existir, o teste gera uma página sintética **com texto** (fonte
/// bitmap), que o detector reconhece como regiões de texto.
const String _pushedPage =
    '/sdcard/Android/data/br.com.mangaoffline.manga_offline/files/it_page.jpg';

img.Image _syntheticPage() {
  final page = img.Image(width: 748, height: 1200, numChannels: 3);
  img.fill(page, color: img.ColorRgb8(255, 255, 255));
  const text = 'THE ONE PIECE IS REAL';
  for (var by = 40; by < 1120; by += 180) {
    for (final bx in [30, 390]) {
      for (var line = 0; line < 5; line++) {
        img.drawString(
          page,
          text,
          font: img.arial24,
          x: bx,
          y: by + line * 28,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
    }
  }
  return page;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('detecta balões (modelo no aparelho)', (tester) async {
    expect(BubbleDetectionService.isSupported, isTrue,
        reason: 'o detector deve estar disponível em Android/iOS');

    final dir = Directory.systemTemp.createTempSync('bubbles_it');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final file = File('${dir.path}/000001.jpg');

    final real = File(_pushedPage);
    if (real.existsSync()) {
      file.writeAsBytesSync(real.readAsBytesSync());
    } else {
      file.writeAsBytesSync(img.encodeJpg(_syntheticPage()));
    }

    final stopwatch = Stopwatch()..start();
    final data = await BubbleDetectionService.detectAndCache(
      folderPath: dir.path,
      pagePaths: [file.path],
    );
    stopwatch.stop();

    expect(data, isNotNull, reason: 'a detecção deve retornar dados');
    final page = data!.pages['000001.jpg']!;
    final bubbles = page.bubbles;
    // ignore: avoid_print
    print('IT: página ${page.width}x${page.height} | '
        '${bubbles.length} caixas | ${stopwatch.elapsedMilliseconds} ms | '
        'primeiras: ${bubbles.take(4).map((b) => '(${b.x.round()},${b.y.round()},${b.w.round()}x${b.h.round()})').join(' ')}');

    expect(bubbles, isNotEmpty, reason: 'deve detectar ao menos uma caixa');
    expect(File('${dir.path}/bubbles.json').existsSync(), isTrue,
        reason: 'o cache bubbles.json deve ser gravado');
  });
}
