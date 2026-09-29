import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Erro ao acessar/raspar o MangaLivre.
class MangaLivreException implements Exception {
  MangaLivreException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? message : '[$statusCode] $message';
}

/// Capítulo do MangaLivre. Um número pode ter mais de uma URL candidata:
/// o site às vezes usa slugs como `capitulo-108-100`.
class MangaLivreChapter {
  MangaLivreChapter({required this.number, required this.urls});

  final int number;
  final List<String> urls;
}

/// Raspador do site (tema WordPress "Madara").
class MangaLivreApi {
  MangaLivreApi({http.Client? client, this.userAgent = _defaultUserAgent})
      : _client = client ?? http.Client();

  static const _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  final http.Client _client;
  final String userAgent;

  Map<String, String> get _headers => {
        'User-Agent': userAgent,
        'Accept': 'text/html,application/xhtml+xml',
      };

  Future<String> _getHtml(String url, {int maxRetries = 4}) async {
    var attempt = 0;
    while (true) {
      attempt++;
      final http.Response res;
      try {
        res = await _client.get(Uri.parse(url), headers: _headers);
      } catch (e) {
        if (attempt <= maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        throw MangaLivreException('Falha de rede em $url: $e');
      }

      if (res.statusCode == 200) {
        return utf8Decode(res.bodyBytes);
      }
      if ((res.statusCode == 429 || res.statusCode >= 500) &&
          attempt <= maxRetries) {
        await Future.delayed(Duration(milliseconds: 600 * attempt));
        continue;
      }
      throw MangaLivreException(
        'Não foi possível abrir $url',
        statusCode: res.statusCode,
      );
    }
  }

  /// Lê o título do mangá a partir do `og:title` ou do `<title>`.
  Future<String> getMangaTitle(String mangaUrl) async {
    final html = await _getHtml(mangaUrl);
    final og =
        RegExp(r'<meta property="og:title" content="([^"]+)"').firstMatch(html);
    if (og != null) {
      final value = _stripSiteSuffix(_decodeEntities(og.group(1)!));
      if (value.isNotEmpty) return value;
    }
    final title = RegExp(r'<title>([^<]*)</title>').firstMatch(html);
    if (title != null) {
      final value = _stripSiteSuffix(_decodeEntities(title.group(1)!));
      if (value.isNotEmpty) return value;
    }
    return 'Manga';
  }

  String _stripSiteSuffix(String value) => value.split('|').first.trim();

  /// Lista os capítulos encontrados na página do mangá.
  Future<List<MangaLivreChapter>> listChapters(String mangaUrl) async {
    final html = await _getHtml(mangaUrl);
    final base = Uri.parse(mangaUrl);
    final path = base.path.endsWith('/') ? base.path : '${base.path}/';
    final re = RegExp(
      RegExp.escape(path) + r'capitulo-([0-9]+(?:-[0-9]+)?)/?',
    );

    final byNumber = <int, List<String>>{};
    for (final match in re.allMatches(html)) {
      final slug = match.group(1)!;
      final number = int.tryParse(slug.split('-').first);
      if (number == null) continue;
      final url = '${base.scheme}://${base.host}${path}capitulo-$slug/';
      final urls = byNumber.putIfAbsent(number, () => <String>[]);
      if (!urls.contains(url)) urls.add(url);
    }

    return byNumber.entries
        .map((e) => MangaLivreChapter(number: e.key, urls: e.value))
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));
  }

  /// URLs das imagens de um capítulo, na ordem das páginas.
  Future<List<String>> chapterImages(String chapterUrl) async {
    final html = await _getHtml(chapterUrl);
    final imgTag = RegExp(
      r'<img[^>]*wp-manga-chapter-img[^>]*>',
      caseSensitive: false,
    );
    final imageUrl = RegExp(r'\.(jpg|jpeg|png|webp|gif)(\?|$)', caseSensitive: false);

    final images = <String>[];
    for (final match in imgTag.allMatches(html)) {
      final tag = match.group(0)!;
      for (final attr in const ['data-src', 'src', 'data-lazy-src']) {
        final m = RegExp('$attr="\\s*([^"]+)"').firstMatch(tag);
        if (m == null) continue;
        final url = _decodeEntities(m.group(1)!.trim());
        if (url.isEmpty || !imageUrl.hasMatch(url)) continue;
        images.add(url);
        break;
      }
    }
    return images;
  }

  Future<Uint8List> downloadBytes(String url, {int maxRetries = 4}) async {
    var attempt = 0;
    while (true) {
      attempt++;
      final http.Response res;
      try {
        res =
            await _client.get(Uri.parse(url), headers: {'User-Agent': userAgent});
      } catch (e) {
        if (attempt <= maxRetries) {
          await Future.delayed(Duration(milliseconds: 400 * attempt));
          continue;
        }
        throw MangaLivreException('Falha de rede ao baixar $url: $e');
      }
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        return res.bodyBytes;
      }
      if ((res.statusCode == 429 || res.statusCode >= 500) &&
          attempt <= maxRetries) {
        await Future.delayed(Duration(milliseconds: 400 * attempt));
        continue;
      }
      throw MangaLivreException('Imagem indisponível ($url)',
          statusCode: res.statusCode);
    }
  }

  void dispose() => _client.close();
}

/// Decodifica o HTML como UTF-8 tolerando bytes inválidos.
String utf8Decode(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

String _decodeEntities(String input) => input
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ');
