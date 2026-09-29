import 'dart:io';

import 'package:args/args.dart';
import 'package:manga_offline/downloader/mangadex_api.dart';
import 'package:manga_offline/downloader/mangadex_downloader.dart';
import 'package:manga_offline/downloader/mangalivre_api.dart';
import 'package:manga_offline/downloader/mangalivre_downloader.dart';

const String _defaultManga =
    'https://mangadex.org/title/a1c7c817-4e59-43b7-9365-09675a149a6f/one-piece';
const String _defaultMangaLivre =
    'https://mangalivre.to/manga/one-piece-ptbr/';

/// Um capítulo a baixar, vindo do MangaDex ou do MangaLivre.
class _Target {
  _Target({required this.number, this.md, this.ml});

  final int number;
  final ChapterInfo? md;
  final MangaLivreChapter? ml;

  String get source => md != null ? 'MangaDex' : 'MangaLivre';
  String get numberText =>
      md != null ? md!.chapter : number.toString();
  String? get title => md?.title;
}

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption('manga',
        abbr: 'm',
        defaultsTo: _defaultManga,
        help: 'ID ou URL do mangá no MangaDex.')
    ..addOption('mangalivre-url',
        defaultsTo: _defaultMangaLivre,
        help: 'URL do mangá no MangaLivre (usada como fallback).')
    ..addOption('lang',
        abbr: 'l',
        defaultsTo: 'pt-br',
        help: 'Código do idioma no MangaDex (ex.: pt-br, en).')
    ..addOption('source',
        defaultsTo: 'auto',
        allowed: ['auto', 'mangadex', 'mangalivre'],
        help: 'auto: MangaDex e usa MangaLivre no que faltar.')
    ..addOption('out',
        abbr: 'o',
        defaultsTo: 'downloads',
        help: 'Pasta de saída dos arquivos .cbz.')
    ..addOption('from',
        help: 'Baixar a partir deste número de capítulo (inclusive).')
    ..addOption('to',
        help: 'Baixar até este número de capítulo (inclusive).')
    ..addOption('limit',
        help: 'Baixar no máximo N capítulos (os primeiros da seleção).')
    ..addOption('retries',
        defaultsTo: '3', help: 'Tentativas extras por operação de rede.')
    ..addOption('image-concurrency',
        defaultsTo: '3', help: 'Imagens baixadas em paralelo por capítulo.')
    ..addOption('delay',
        defaultsTo: '1200',
        help: 'Milissegundos de pausa entre capítulos (respeita os sites).')
    ..addFlag('data-saver',
        defaultsTo: false,
        negatable: false,
        help: 'Usar imagens de menor qualidade (só MangaDex).')
    ..addFlag('force',
        defaultsTo: false,
        negatable: false,
        help: 'Re-baixar mesmo se o .cbz já existir.')
    ..addFlag('dry-run',
        defaultsTo: false,
        negatable: false,
        help: 'Apenas listar os capítulos, sem baixar nada.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Mostra esta ajuda.');

  final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    stderr.writeln('Erro: ${e.message}\n');
    stderr.writeln(_usage(parser));
    exitCode = 64;
    return;
  }

  if (args.flag('help')) {
    stdout.writeln(_usage(parser));
    return;
  }

  final source = args.option('source')!;
  final mangaId = MangadexApi.extractMangaId(args.option('manga')!);
  final mangaLivreUrl = args.option('mangalivre-url')!;
  final language = args.option('lang')!;
  final dryRun = args.flag('dry-run');

  final options = DownloadOptions(
    outDir: args.option('out')!,
    dataSaver: args.flag('data-saver'),
    retries: int.tryParse(args.option('retries')!) ?? 3,
    imageConcurrency: int.tryParse(args.option('image-concurrency')!) ?? 3,
    delayBetweenChapters:
        Duration(milliseconds: int.tryParse(args.option('delay')!) ?? 1200),
    force: args.flag('force'),
  );

  final mdApi = MangadexApi();
  final mlApi = MangaLivreApi();
  try {
    final targets = await _buildTargets(
      source: source,
      mangaId: mangaId,
      mangaLivreUrl: mangaLivreUrl,
      language: language,
      mdApi: mdApi,
      mlApi: mlApi,
    );
    if (targets.title == null) {
      stdout.writeln('Nada encontrado nos sites informados.');
      return;
    }
    final mangaTitle = targets.title!;
    final selected = _applyFilters(targets.items, args);

    final fromMd = selected.where((t) => t.source == 'MangaDex').length;
    final fromMl = selected.length - fromMd;
    stdout.writeln(
      '\nSelecionados ${selected.length} capítulos '
      '(MangaDex: $fromMd | MangaLivre: $fromMl).',
    );

    if (selected.isEmpty) {
      stdout.writeln('Nada para baixar com os filtros informados.');
      return;
    }

    if (dryRun) {
      stdout.writeln('\nCapítulos que seriam baixados:');
      for (final t in selected) {
        stdout.writeln('  [${t.source}] Cap ${formatChapterNumber(t.numberText)}'
            '${t.title == null || t.title!.isEmpty ? '' : ' - ${t.title}'}');
      }
      stdout.writeln('\nTotal: ${selected.length} capítulos.');
      return;
    }

    final mdDownloader = MangadexDownloader(api: mdApi, options: options);
    final mlDownloader = MangaLivreDownloader(api: mlApi, options: options);

    final started = DateTime.now();
    var done = 0;
    var skipped = 0;
    var failed = 0;
    final failures = <String>[];

    stdout.writeln('\nSalvando .cbz em: ${Directory(options.outDir).absolute.path}\n');

    for (var i = 0; i < selected.length; i++) {
      final target = selected[i];
      final label = '[${target.source}] Cap ${formatChapterNumber(target.numberText)}';
      stdout.write('[${i + 1}/${selected.length}] $label ... ');

      try {
        final result = target.md != null
            ? await mdDownloader.downloadChapter(target.md!,
                mangaTitle: mangaTitle)
            : await mlDownloader.downloadChapter(target.ml!,
                mangaTitle: mangaTitle);
        if (result.skipped) {
          skipped++;
          stdout.writeln('já existe, pulando.');
        } else {
          done++;
          stdout.writeln('ok (${result.pageCount} págs).');
        }
      } catch (e) {
        failed++;
        failures.add('$label: $e');
        stdout.writeln('FALHOU: $e');
      }

      if (i < selected.length - 1 &&
          options.delayBetweenChapters > Duration.zero) {
        await Future.delayed(options.delayBetweenChapters);
      }
    }

    stdout.writeln('\nResumo:');
    stdout.writeln('  baixados:   $done');
    stdout.writeln('  pulados:    $skipped');
    stdout.writeln('  falhas:     $failed');
    stdout.writeln('  tempo:      ${_formatDuration(DateTime.now().difference(started))}');
    if (failures.isNotEmpty) {
      stdout.writeln('\nFalhas:');
      for (final failure in failures) {
        stdout.writeln('  - $failure');
      }
      exitCode = 1;
    }
  } on MangadexException catch (e) {
    stderr.writeln('Erro do MangaDex: $e');
    exitCode = 1;
  } on MangaLivreException catch (e) {
    stderr.writeln('Erro do MangaLivre: $e');
    exitCode = 1;
  } finally {
    mdApi.dispose();
    mlApi.dispose();
  }
}

/// Reúne os capítulos disponíveis conforme a fonte escolhida.
Future<_TargetBundle> _buildTargets({
  required String source,
  required String mangaId,
  required String mangaLivreUrl,
  required String language,
  required MangadexApi mdApi,
  required MangaLivreApi mlApi,
}) async {
  final mdByNumber = <int, ChapterInfo>{};
  final mlByNumber = <int, MangaLivreChapter>{};
  String? title;

  if (source == 'mangadex' || source == 'auto') {
    stdout.writeln('Buscando dados no MangaDex...');
    final manga = await mdApi.getManga(mangaId);
    title = manga.title;
    stdout.writeln('MangaDex: ${manga.title} (${manga.id})');

    stdout.writeln('Buscando capítulos em "$language" no MangaDex...');
    final chapters = await mdApi.getChapters(
      mangaId: mangaId,
      language: language,
      onProgress: (fetched, total) {
        if (total > 0) stdout.write('\r  capítulos: $fetched/$total');
      },
    );
    if (!stdout.hasTerminal) stdout.writeln();
    final hosted = chapters.where((c) => c.isHosted);
    for (final chapter in hosted) {
      final n = int.tryParse(chapter.chapter.split('.').first);
      if (n != null) mdByNumber.putIfAbsent(n, () => chapter);
    }
    stdout.writeln(
      'MangaDex: ${chapters.length} em pt-br, sendo ${mdByNumber.length} '
      'hospedados (baixáveis).',
    );
  }

  if (source == 'mangalivre' || source == 'auto') {
    stdout.writeln('Buscando capítulos no MangaLivre...');
    final mlTitle = await mlApi.getMangaTitle(mangaLivreUrl);
    title ??= mlTitle;
    final chapters = await mlApi.listChapters(mangaLivreUrl);
    for (final chapter in chapters) {
      mlByNumber[chapter.number] = chapter;
    }
    stdout.writeln('MangaLivre: ${chapters.length} capítulos listados.');
  }

  final numbers = <int>{
    if (source != 'mangalivre') ...mdByNumber.keys,
    if (source != 'mangadex') ...mlByNumber.keys,
  }.toList()
    ..sort();

  final items = <_Target>[];
  for (final n in numbers) {
    if (source != 'mangalivre' && mdByNumber.containsKey(n)) {
      items.add(_Target(number: n, md: mdByNumber[n]));
    } else if (mlByNumber.containsKey(n)) {
      items.add(_Target(number: n, ml: mlByNumber[n]));
    }
  }

  return _TargetBundle(title: title, items: items);
}

class _TargetBundle {
  _TargetBundle({required this.title, required this.items});

  final String? title;
  final List<_Target> items;
}

/// Aplica `--from`, `--to` e `--limit` sobre a lista de capítulos.
List<_Target> _applyFilters(List<_Target> chapters, ArgResults args) {
  final from = _parseInt(args.option('from'), '--from');
  final to = _parseInt(args.option('to'), '--to');
  var list = chapters;

  if (from != null || to != null) {
    list = list.where((c) {
      if (from != null && c.number < from) return false;
      if (to != null && c.number > to) return false;
      return true;
    }).toList();
  }

  final limit = _parseInt(args.option('limit'), '--limit');
  if (limit != null && list.length > limit) {
    list = list.sublist(0, limit);
  }
  return list;
}

int? _parseInt(String? value, String flag) {
  if (value == null) return null;
  final parsed = int.tryParse(value);
  if (parsed == null) {
    throw FormatException('$flag precisa ser um número inteiro.');
  }
  return parsed;
}

String _formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
}

String _usage(ArgParser parser) => '''
Baixador de capítulos em .cbz (MangaDex + fallback MangaLivre).

Uso: dart run bin/download_mangadex.dart [opções]

${parser.usage}

Fontes:
  auto        Usa o MangaDex e cai para o MangaLivre no que faltar (padrão).
  mangadex    Somente MangaDex.
  mangalivre  Somente MangaLivre.

Exemplos:
  dart run bin/download_mangadex.dart --dry-run
  dart run bin/download_mangadex.dart --from 63 --to 70
  dart run bin/download_mangadex.dart --limit 5 --out "C:\\Mangas\\One Piece"
''';
