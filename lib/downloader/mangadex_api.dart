import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Erro de comunicação/contrato com a API do MangaDex.
class MangadexException implements Exception {
  MangadexException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? message : '[$statusCode] $message';
}

/// Dados básicos do mangá.
class MangaInfo {
  MangaInfo({required this.id, required this.title});

  final String id;
  final String title;
}

/// Um capítulo retornado pelo feed do MangaDex.
class ChapterInfo {
  ChapterInfo({
    required this.id,
    required this.chapter,
    required this.language,
    required this.pages,
    required this.isUnavailable,
    this.volume,
    this.title,
    this.externalUrl,
  });

  final String id;

  /// Número do capítulo como texto (pode ser vazio em one-shots).
  final String chapter;
  final String? volume;
  final String? title;

  /// Código do idioma da tradução (ex.: `pt-br`).
  final String language;

  /// Quando preenchido, o capítulo não está hospedado no MangaDex.
  final String? externalUrl;

  /// Quantidade de páginas hospedadas (0 quando externo).
  final int pages;
  final bool isUnavailable;

  /// Só é possível baixar capítulos efetivamente hospedados no MangaDex.
  bool get isHosted => !isUnavailable && externalUrl == null && pages > 0;

  /// Número do capítulo convertido para ordenação.
  double get number => double.tryParse(chapter.replaceAll(',', '.')) ?? double.nan;
}

/// Resposta de `/at-home/server/{id}`: onde e quais páginas baixar.
class AtHomeServer {
  AtHomeServer({
    required this.baseUrl,
    required this.hash,
    required this.data,
    required this.dataSaver,
  });

  final String baseUrl;
  final String hash;
  final List<String> data;
  final List<String> dataSaver;
}

/// Cliente fino da API pública do MangaDex.
class MangadexApi {
  MangadexApi({
    http.Client? client,
    this.userAgent = 'MangaOffline/1.0',
    this.apiBaseUrl = 'https://api.mangadex.org',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String userAgent;
  final String apiBaseUrl;

  static final RegExp _uuid = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  );

  /// Aceita tanto o UUID puro quanto uma URL de título do MangaDex.
  static String extractMangaId(String input) {
    final match = _uuid.firstMatch(input);
    return match != null ? match.group(0)! : input.trim();
  }

  Map<String, String> get _jsonHeaders => {
        'User-Agent': userAgent,
        'Accept': 'application/json',
      };

  Future<Map<String, dynamic>> _getJson(Uri uri, {int maxRetries = 4}) async {
    var attempt = 0;
    while (true) {
      attempt++;
      final http.Response res;
      try {
        res = await _client.get(uri, headers: _jsonHeaders);
      } catch (e) {
        if (attempt <= maxRetries) {
          await Future.delayed(Duration(milliseconds: 400 * attempt));
          continue;
        }
        throw MangadexException('Falha de rede em ${uri.path}: $e');
      }

      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }

      final retryable = res.statusCode == 429 || res.statusCode >= 500;
      if (retryable && attempt <= maxRetries) {
        final retryAfter = int.tryParse(res.headers['retry-after'] ?? '');
        await Future.delayed(
          retryAfter != null
              ? Duration(seconds: retryAfter)
              : Duration(milliseconds: 500 * attempt),
        );
        continue;
      }

      throw MangadexException(
        'Requisição a ${uri.path} falhou: ${res.body}',
        statusCode: res.statusCode,
      );
    }
  }

  Future<MangaInfo> getManga(String mangaId) async {
    final data = await _getJson(Uri.parse('$apiBaseUrl/manga/$mangaId'));
    final attributes =
        (data['data'] as Map).cast<String, dynamic>()['attributes']
            as Map<String, dynamic>;
    return MangaInfo(id: mangaId, title: _pickTitle(attributes, mangaId));
  }

  String _pickTitle(Map<String, dynamic> attributes, String fallback) {
    final title = (attributes['title'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final lang in ['pt-br', 'pt', 'en', 'ja-ro']) {
      final value = title[lang];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    for (final value in title.values) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    for (final entry in (attributes['altTitles'] as List? ?? const [])) {
      final map = (entry as Map).cast<String, dynamic>();
      for (final lang in ['pt-br', 'pt', 'en']) {
        final value = map[lang];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    }
    return fallback;
  }

  /// Busca todos os capítulos de um idioma, paginando até o fim.
  Future<List<ChapterInfo>> getChapters({
    required String mangaId,
    required String language,
    int pageSize = 100,
    void Function(int fetched, int total)? onProgress,
  }) async {
    final all = <ChapterInfo>[];
    var offset = 0;
    var total = 0;
    while (true) {
      final uri = Uri.parse('$apiBaseUrl/manga/$mangaId/feed').replace(
        queryParameters: {
          'limit': '$pageSize',
          'offset': '$offset',
          'translatedLanguage[]': language,
          'order[chapter]': 'asc',
          'includes[]': 'scanlation_group',
        },
      );
      final data = await _getJson(uri);
      total = (data['total'] as num?)?.toInt() ?? 0;
      final list = (data['data'] as List?) ?? const [];
      for (final item in list) {
        final map = (item as Map).cast<String, dynamic>();
        final attr = (map['attributes'] as Map).cast<String, dynamic>();
        all.add(
          ChapterInfo(
            id: map['id'] as String,
            chapter: (attr['chapter'] as String?) ?? '',
            volume: attr['volume'] as String?,
            title: (attr['title'] as String?)?.trim(),
            language: (attr['translatedLanguage'] as String?) ?? language,
            externalUrl: attr['externalUrl'] as String?,
            pages: (attr['pages'] as num?)?.toInt() ?? 0,
            isUnavailable: (attr['isUnavailable'] as bool?) ?? false,
          ),
        );
      }
      onProgress?.call(all.length, total);
      offset += list.length;
      if (list.isEmpty || all.length >= total) break;
    }
    all.sort((a, b) => compareChapters(a.chapter, b.chapter));
    return all;
  }

  Future<AtHomeServer> getAtHome(String chapterId) async {
    final data = await _getJson(Uri.parse('$apiBaseUrl/at-home/server/$chapterId'));
    final baseUrl = data['baseUrl'] as String;
    final chapter = (data['chapter'] as Map).cast<String, dynamic>();
    return AtHomeServer(
      baseUrl: baseUrl,
      hash: chapter['hash'] as String,
      data: ((chapter['data'] as List?) ?? const []).cast<String>(),
      dataSaver: ((chapter['dataSaver'] as List?) ?? const []).cast<String>(),
    );
  }

  /// Monta a URL de uma página. [dataSaver] usa a versão leve.
  String imageUrl(AtHomeServer server, int index, {required bool dataSaver}) {
    final names = dataSaver ? server.dataSaver : server.data;
    final quality = dataSaver ? 'data-saver' : 'data';
    return '${server.baseUrl}/$quality/${server.hash}/${names[index]}';
  }

  Future<Uint8List> downloadBytes(String url, {int maxRetries = 4}) async {
    var attempt = 0;
    while (true) {
      attempt++;
      final http.Response res;
      try {
        res = await _client.get(Uri.parse(url), headers: {'User-Agent': userAgent});
      } catch (e) {
        if (attempt <= maxRetries) {
          await Future.delayed(Duration(milliseconds: 400 * attempt));
          continue;
        }
        throw MangadexException('Falha de rede ao baixar $url: $e');
      }
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        return res.bodyBytes;
      }
      if ((res.statusCode == 429 || res.statusCode >= 500) && attempt <= maxRetries) {
        await Future.delayed(Duration(milliseconds: 400 * attempt));
        continue;
      }
      throw MangadexException(
        'Imagem indisponível ($url)',
        statusCode: res.statusCode,
      );
    }
  }

  void dispose() => _client.close();
}

/// Compara capítulos por número, colocando os sem número no fim.
int compareChapters(String a, String b) {
  final na = double.tryParse(a.replaceAll(',', '.'));
  final nb = double.tryParse(b.replaceAll(',', '.'));
  if (na == null && nb == null) return a.compareTo(b);
  if (na == null) return 1;
  if (nb == null) return -1;
  return na.compareTo(nb);
}
