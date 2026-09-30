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

    test('balões empilhados (mesmo x) são lidos de cima para baixo', () {
      final ordered = orderRtl([
        [100, 500, 60, 60],
        [100, 100, 60, 60],
      ]);
      expect(ordered, [
        [100, 100, 60, 60],
        [100, 500, 60, 60],
      ]);
    });

    test('balões conectados lado a lado: o da direita vem primeiro', () {
      final ordered = orderRtl([
        [50, 200, 80, 80],
        [240, 205, 80, 80],
      ]);
      expect(ordered.first, [240, 205, 80, 80]);
      expect(ordered.last, [50, 200, 80, 80]);
    });

    test('linhas mistas: RTL no topo e depois a linha de baixo', () {
      final ordered = orderRtl([
        [300, 20, 50, 50],
        [20, 600, 50, 50],
        [60, 25, 50, 50],
        [400, 610, 50, 50],
      ]);
      expect(ordered, [
        [300, 20, 50, 50],
        [60, 25, 50, 50],
        [400, 610, 50, 50],
        [20, 600, 50, 50],
      ]);
    });

    test('escada: coluna alta à direita vem antes dos balões à esquerda', () {
      // O agrupamento por "faixas" antigo ordenava B antes de A (centros em
      // linhas diferentes); o corte XY recursivo respeita a coluna da direita.
      final ordered = orderRtl([
        [600, 10, 40, 200], // A: coluna à direita
        [10, 10, 40, 40], // B: topo-esquerda
        [10, 300, 40, 40], // C: base-esquerda
      ]);
      expect(ordered, [
        [600, 10, 40, 200],
        [10, 10, 40, 40],
        [10, 300, 40, 40],
      ]);
    });
  });
}
