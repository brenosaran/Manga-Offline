/// Montagem de "spreads" (páginas exibidas juntas) para o leitor.
///
/// Num mangá a leitura é da direita para a esquerda, então um par de páginas
/// [a, b] (a < b) deve ser desenhado com [a] à direita e [b] à esquerda.
class PageSpread {
  const PageSpread(this.pages);

  /// Índices das páginas do capítulo, em ordem crescente.
  final List<int> pages;

  int get firstPage => pages.first;
  int get lastPage => pages.last;
  bool get isSingle => pages.length == 1;
}

/// Divide as páginas do capítulo em spreads.
///
/// - [dual] falso: uma página por vez.
/// - [dual] verdadeiro: pares [i, i+1]; sobra final fica sozinha.
/// - [coverAlone]: quando em [dual], a primeira página (capa) aparece sozinha.
List<PageSpread> buildSpreads({
  required int pageCount,
  required bool dual,
  required bool coverAlone,
}) {
  if (pageCount <= 0) return const [];
  if (!dual) {
    return [for (var i = 0; i < pageCount; i++) PageSpread([i])];
  }

  final spreads = <PageSpread>[];
  var i = 0;
  if (coverAlone) {
    spreads.add(const PageSpread([0]));
    i = 1;
  }
  while (i < pageCount) {
    if (i + 1 < pageCount) {
      spreads.add(PageSpread([i, i + 1]));
      i += 2;
    } else {
      spreads.add(PageSpread([i]));
      i += 1;
    }
  }
  return spreads;
}

/// Índice do spread que contém [page]; 0 se não encontrado.
int spreadIndexForPage(List<PageSpread> spreads, int page) {
  for (var i = 0; i < spreads.length; i++) {
    if (spreads[i].pages.contains(page)) return i;
  }
  return 0;
}

/// Decide se a tela atual comporta duas páginas, no modo automático.
///
/// Ativa em telas largas (dobrável aberto, ex.: Galaxy Fold, tablets),
/// quando há vinco/dobradiça (display feature) ou na horizontal.
bool autoDualPage({
  required double width,
  required double height,
  required bool hasDisplayFeature,
}) {
  final landscape = width > height;
  return width >= 700 ||
      (hasDisplayFeature && width >= 500) ||
      (landscape && width >= 600);
}
