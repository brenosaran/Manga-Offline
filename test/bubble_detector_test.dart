import 'package:flutter_test/flutter_test.dart';
import 'package:manga_offline/services/bubble_detector.dart';

void main() {
  group('nms', () {
    test('remove duplicatas sobrepostas mantendo a de maior confiança', () {
      final boxes = <List<double>>[
        [100, 100, 50, 50], // A
        [102, 101, 50, 50], // B (quase igual a A)
        [300, 100, 50, 50], // C
      ];
      final scores = <double>[0.9, 0.8, 0.7];
      final kept = nms(boxes, scores, 0.45);
      expect(kept.length, 2);
      expect(kept[0], boxes[0]); // maior confiança
      expect(kept[1], boxes[2]);
    });

    test('não remove caixas sem sobreposição', () {
      final boxes = <List<double>>[
        [10, 10, 20, 20],
        [500, 500, 20, 20],
      ];
      expect(nms(boxes, [0.9, 0.85], 0.45).length, 2);
    });
  });

  group('orderRtl', () {
    test('ordena de cima para baixo e da direita para a esquerda', () {
      final boxes = <List<double>>[
        [50, 10, 40, 40], // topo-esquerda
        [100, 300, 40, 40], // baixo
        [200, 10, 40, 40], // topo-direita
      ];
      final ordered = orderRtl(boxes);
      expect(ordered, [
        [200, 10, 40, 40],
        [50, 10, 40, 40],
        [100, 300, 40, 40],
      ]);
    });

    test('lista vazia permanece vazia', () {
      expect(orderRtl(const []), isEmpty);
    });
  });
}
