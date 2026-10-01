import 'package:manga_offline/downloader/mangadex_api.dart';
import 'package:manga_offline/downloader/mangadex_downloader.dart';
import 'package:manga_offline/downloader/mangalivre_api.dart';
import 'package:manga_offline/downloader/mangalivre_downloader.dart';

import '../core/settings_controller.dart';
import 'mangadex_service.dart';

/// Erro ao tentar baixar um capítulo que não foi encontrado nas fontes.
class ChapterDownloadException implements Exception {
  ChapterDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Baixa um capítulo avulso para a biblioteca, usando a **mesma lógica** do
/// baixador de linha de comando (`bin/download_mangadex.dart` / `test/`):
///
/// 1. tenta o **MangaDex** (fonte principal);
/// 2. se o capítulo não existir lá, cai para o **MangaLivre** (fallback).
///
/// O capítulo é localizado casando o **número** informado pelo fantasma
/// (ghost) com o número do capítulo em cada fonte — o mesmo padrão de
/// numeração usado pelo baixador (`formatChapterNumber`, ex.: `0004`).
class ChapterDownloadService {
  ChapterDownloadService({
    MangadexApi? mangadexApi,
    MangaLivreApi? mangaLivreApi,
    MangaDexService? mangadexService,
  })  : _dexApi = mangadexApi ?? MangadexApi(),
        _mlApi = mangaLivreApi ?? MangaLivreApi(),
        _dexService = mangadexService ?? MangaDexService();

  final MangadexApi _dexApi;
  final MangaLivreApi _mlApi;
  final MangaDexService _dexService;

  /// Host padrão do fallback (mesmo do baixador).
  static const String mangaLivreHost = 'https://mangalivre.to';

  /// Tenta baixar o [number] da obra [title] para [outDir].
  ///
  /// A ordem/filtro das fontes vem da lista de **servidores de busca**
  /// configurada em `Configurações → Desenvolvedor` (padrão: os servidores já
  /// configurados do projeto). Cada entrada reconhecida é tentada na ordem da
  /// lista; entradas sem adaptador são registradas e ignoradas.
  ///
  /// Retorna o [ChapterResult] com o `.cbz` gravado. Lança
  /// [ChapterDownloadException] se não encontrar o capítulo em nenhuma fonte.
  Future<ChapterResult> downloadChapter({
    required String title,
    required int number,
    required String outDir,
    String? mangadexId,
    String language = 'pt-br',
  }) async {
    final options = DownloadOptions(
      outDir: outDir,
      delayBetweenChapters: Duration.zero,
    );

    final errors = <String>[];
    final sources = SettingsController.instance.downloadSearchSources;
    if (sources.isEmpty) {
      throw ChapterDownloadException(
        'Nenhum servidor de busca ativo (Configurações → Desenvolvedor).',
      );
    }

    for (final source in sources) {
      final url = source.url;
      final host = _hostOf(url);
      try {
        if (host.contains('mangadex')) {
          final result = await _downloadFromMangadex(
            title: title,
            number: number,
            options: options,
            mangadexId: mangadexId,
            language: source.language.isNotEmpty ? source.language : language,
            errors: errors,
          );
          if (result != null) return result;
        } else if (host.contains('mangalivre')) {
          final result = await _downloadFromMangaLivre(
            title: title,
            number: number,
            options: options,
            errors: errors,
          );
          if (result != null) return result;
        } else {
          errors.add('$url: sem adaptador nativo disponível.');
        }
      } catch (e) {
        errors.add('$url: $e');
      }
    }

    throw ChapterDownloadException(
      'Não foi possível baixar o capítulo $number de "$title". '
      '${errors.join(' | ')}',
    );
  }

  Future<ChapterResult?> _downloadFromMangadex({
    required String title,
    required int number,
    required DownloadOptions options,
    required String? mangadexId,
    required String language,
    required List<String> errors,
  }) async {
    final id = (mangadexId != null && mangadexId.isNotEmpty)
        ? mangadexId
        : await _resolveMangadexId(title);
    if (id == null || id.isEmpty) {
      errors.add('MangaDex: obra "$title" não encontrada.');
      return null;
    }
    // Tenta o idioma configurado do servidor e, se não houver o capítulo nele,
    // cai para o inglês antes de passar ao próximo servidor.
    final languages = <String>{
      if (language.isNotEmpty) language,
      'en',
    }.toList();
    for (final lang in languages) {
      final chapters = await _dexApi.getChapters(mangaId: id, language: lang);
      final target = pickMangadexChapter(chapters, number);
      if (target != null) {
        final downloader = MangadexDownloader(api: _dexApi, options: options);
        return downloader.downloadChapter(target, mangaTitle: title);
      }
    }
    errors.add('MangaDex: capítulo $number não encontrado.');
    return null;
  }

  Future<ChapterResult?> _downloadFromMangaLivre({
    required String title,
    required int number,
    required DownloadOptions options,
    required List<String> errors,
  }) async {
    // Procura a URL real da obra no site (mais robusto que montar o slug);
    // se a busca falhar, cai no slug direto.
    String? url;
    try {
      url = await _mlApi.searchMangaUrl(
        ChapterDownloadService.mangaLivreHost,
        title,
      );
    } catch (_) {}
    url ??= mangaLivreUrlFor(title);
    final chapters = await _mlApi.listChapters(url);
    final target = pickMangaLivreChapter(chapters, number);
    if (target == null) {
      errors.add('MangaLivre: capítulo $number não encontrado.');
      return null;
    }
    final downloader = MangaLivreDownloader(api: _mlApi, options: options);
    return downloader.downloadChapter(target, mangaTitle: title);
  }

  /// Extrai o host de uma entrada configurada (aceita com ou sem esquema).
  static String _hostOf(String source) {
    final uri = Uri.tryParse(source.contains('://') ? source : 'https://$source');
    return (uri?.host ?? source).toLowerCase();
  }

  Future<String?> _resolveMangadexId(String title) async {
    try {
      final match = await _dexService.findByTitle(title);
      return match?.id;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _dexApi.dispose();
    _mlApi.dispose();
  }
}

/// Escolhe, no feed do MangaDex, o capítulo hospedado com o [number] pedido.
///
/// Ignora capítulos externos/indisponíveis e casa pela parte inteira do
/// número (`"10.5"` casa com `10`, mesma regra do baixador).
ChapterInfo? pickMangadexChapter(List<ChapterInfo> chapters, int number) {
  for (final chapter in chapters) {
    if (!chapter.isHosted) continue;
    final intPart = chapter.chapter.split('.').first.trim();
    if (int.tryParse(intPart) == number) return chapter;
  }
  return null;
}

/// Escolhe, na listagem do MangaLivre, o capítulo com o [number] pedido.
MangaLivreChapter? pickMangaLivreChapter(
  List<MangaLivreChapter> chapters,
  int number,
) {
  for (final chapter in chapters) {
    if (chapter.number == number) return chapter;
  }
  return null;
}

/// Monta a URL do mangá no MangaLivre a partir do título,
/// ex.: `One Piece` → `https://mangalivre.to/manga/one-piece/`.
///
/// É só um **fallback**: o fluxo normal usa [MangaLivreApi.searchMangaUrl]
/// para achar a URL exata da obra.
String mangaLivreUrlFor(String title) {
  return '${ChapterDownloadService.mangaLivreHost}/manga/${slugifyTitle(title)}/';
}

/// Converte um título em slug simples (sem acentos), ex.: `One Piece`.
String slugifyTitle(String input) {
  const accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(accents[ch] ?? ch);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
