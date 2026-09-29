import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:path/path.dart' as p;

/// Caixa de um balão/caixa de texto numa página, em pixels da imagem.
class BubbleBox {
  const BubbleBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final double x;
  final double y;
  final double w;
  final double h;

  Rect get rect => Rect.fromLTWH(x, y, w, h);

  factory BubbleBox.fromJson(Map<String, dynamic> json) => BubbleBox(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
      );
}

/// Página com dimensões e lista de balões já ordenados no sentido de leitura
/// (da direita para a esquerda, de cima para baixo).
class BubblePage {
  const BubblePage({
    required this.width,
    required this.height,
    required this.bubbles,
  });

  final int width;
  final int height;
  final List<BubbleBox> bubbles;

  factory BubblePage.fromJson(Map<String, dynamic> json) => BubblePage(
        width: (json['w'] as num).toInt(),
        height: (json['h'] as num).toInt(),
        bubbles: [
          for (final b in (json['bubbles'] as List<dynamic>? ?? const []))
            BubbleBox.fromJson(b as Map<String, dynamic>),
        ],
      );
}

/// Caixas de balões de um capítulo, carregadas de `bubbles.json` (gerado fora
/// do app, no pré-processamento). A chave do mapa é o **nome do arquivo** da
/// imagem (ex.: `000001.jpg`).
class BubbleData {
  const BubbleData(this.pages);

  final Map<String, BubblePage> pages;

  BubblePage? pageFor(String pagePath) => pages[p.basename(pagePath)];

  /// Versão do cache `bubbles.json`. Deve ser incrementada quando o modelo de
  /// detecção mudar, para o cache antigo ser ignorado e regerado.
  static const int currentVersion = 2;

  static BubbleData fromJson(Map<String, dynamic> root) {
    final pages = <String, BubblePage>{};
    final raw = root['pages'] as Map<String, dynamic>? ?? const {};
    raw.forEach((key, value) {
      pages[key] = BubblePage.fromJson(value as Map<String, dynamic>);
    });
    return BubbleData(pages);
  }

  static Future<BubbleData?> load(String folderPath) async {
    final file = File(p.join(folderPath, 'bubbles.json'));
    if (!await file.exists()) return null;
    try {
      final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if ((root['version'] as num?)?.toInt() != currentVersion) return null;
      return fromJson(root);
    } catch (_) {
      return null;
    }
  }
}
