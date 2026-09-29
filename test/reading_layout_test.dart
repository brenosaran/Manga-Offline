import 'package:flutter_test/flutter_test.dart';
import 'package:manga_offline/core/reading_layout.dart';

void main() {
  group('buildSpreads', () {
    test('página única gera um spread por página', () {
      final spreads = buildSpreads(pageCount: 4, dual: false, coverAlone: true);
      expect(spreads.length, 4);
      expect(spreads.map((s) => s.pages).toList(), [
        [0],
        [1],
        [2],
        [3],
      ]);
    });

    test('página dupla emparelha as páginas', () {
      final spreads = buildSpreads(pageCount: 4, dual: true, coverAlone: false);
      expect(spreads.map((s) => s.pages).toList(), [
        [0, 1],
        [2, 3],
      ]);
    });

    test('capa sozinha deixa a primeira página isolada', () {
      final spreads = buildSpreads(pageCount: 5, dual: true, coverAlone: true);
      expect(spreads.map((s) => s.pages).toList(), [
        [0],
        [1, 2],
        [3, 4],
      ]);
    });

    test('última página ímpar fica sozinha', () {
      final spreads = buildSpreads(pageCount: 6, dual: true, coverAlone: true);
      expect(spreads.map((s) => s.pages).toList(), [
        [0],
        [1, 2],
        [3, 4],
        [5],
      ]);
    });

    test('capítulo vazio não gera spreads', () {
      expect(buildSpreads(pageCount: 0, dual: true, coverAlone: true), isEmpty);
    });
  });

  group('spreadIndexForPage', () {
    test('encontra o spread que contém a página', () {
      final spreads = buildSpreads(pageCount: 6, dual: true, coverAlone: true);
      expect(spreadIndexForPage(spreads, 0), 0);
      expect(spreadIndexForPage(spreads, 2), 1);
      expect(spreadIndexForPage(spreads, 5), 3);
    });
  });

  group('autoDualPage', () {
    test('celular estreito em retrato usa página única', () {
      expect(
        autoDualPage(width: 400, height: 900, hasDisplayFeature: false),
        isFalse,
      );
    });

    test('dobrável aberto (tela larga) usa página dupla', () {
      expect(
        autoDualPage(width: 855, height: 950, hasDisplayFeature: false),
        isTrue,
      );
    });

    test('celular na horizontal usa página dupla', () {
      expect(
        autoDualPage(width: 850, height: 400, hasDisplayFeature: false),
        isTrue,
      );
    });

    test('com dobra/vinco usa página dupla em tela média', () {
      expect(
        autoDualPage(width: 560, height: 900, hasDisplayFeature: true),
        isTrue,
      );
    });
  });
}
