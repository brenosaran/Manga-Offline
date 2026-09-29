import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/chapter.dart';
import '../models/serie.dart';
import '../models/volume_index.dart';
import '../objectbox.g.dart';
import '../core/settings_controller.dart';
import 'package:manga_offline/downloader/mangalivre_api.dart';
import 'archive_service.dart';
import 'chapter_download_service.dart';
import 'database_service.dart';
import 'mangadex_service.dart';
import 'metadata_service.dart';
import 'onepiece_service.dart';

class ImportReport {
  final List<Serie> imported = [];
  final Map<String, String> failed = {};
  final List<String> skipped = [];

  bool get hasIssues => failed.isNotEmpty || skipped.isNotEmpty;
}

/// Resultado do download de um volume inteiro.
class VolumeDownloadReport {
  VolumeDownloadReport({required this.downloaded, required this.failed});

  final int downloaded;
  final List<int> failed;
}

class ParsedChapter {
  ParsedChapter({
    required this.series,
    required this.number,
    required this.title,
  });

  final String series;
  final double number;
  final String title;
}

class LibraryController extends ChangeNotifier {
  LibraryController({
    DatabaseService? database,
    ArchiveService? archiveService,
    MetadataService? metadataService,
    MangaDexService? mangaDexService,
    OnePieceService? onePieceService,
  })  : _db = database ?? DatabaseService.instance,
        _archive = archiveService ?? ArchiveService(),
        _metadata = metadataService ?? MetadataService(),
        _dex = mangaDexService ?? MangaDexService(),
        _onePiece = onePieceService ?? OnePieceService();

  final DatabaseService _db;
  final ArchiveService _archive;
  final MetadataService _metadata;
  final MangaDexService _dex;
  final OnePieceService _onePiece;

  List<Serie> series = [];
  final Map<int, int> chapterCount = {};
  final Map<int, int> volumeCount = {};
  final Map<int, double> serieProgress = {};

  bool isLoading = true;
  String? errorMessage;
  ImportReport? lastImport;
  bool isSyncingVolumes = false;

  final Map<int, Map<int, int>> _chapterVolumeBySerie = {};

  static const Map<String, String> _accentMap = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    try {
      final loaded = _db.series.getAll();
      loaded.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      series = loaded;

      chapterCount.clear();
      volumeCount.clear();
      serieProgress.clear();
      final volumesBySerie = <int, Set<int>>{};
      final progressSum = <int, double>{};

      for (final chapter in _db.chapters.getAll()) {
        chapterCount[chapter.serieId] = (chapterCount[chapter.serieId] ?? 0) + 1;
        if (chapter.volume > 0) {
          volumesBySerie
              .putIfAbsent(chapter.serieId, () => <int>{})
              .add(chapter.volume);
        }
        progressSum[chapter.serieId] =
            (progressSum[chapter.serieId] ?? 0) + chapter.progress;
      }
      volumesBySerie.forEach((id, set) => volumeCount[id] = set.length);
      progressSum.forEach((id, sum) {
        final count = chapterCount[id] ?? 0;
        serieProgress[id] = count == 0 ? 0 : sum / count;
      });

      errorMessage = null;
    } catch (e) {
      errorMessage = 'Falha ao carregar a biblioteca: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  List<Chapter> chaptersOf(int serieId) {
    return _db.chapters.query(Chapter_.serieId.equals(serieId)).build().find();
  }

  Map<int, List<Chapter>> groupByVolume(List<Chapter> chapters) {
    final grouped = <int, List<Chapter>>{};
    for (final chapter in chapters) {
      grouped.putIfAbsent(chapter.volume, () => []).add(chapter);
    }
    return grouped;
  }

  Future<Directory> _libraryRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'manga_offline', 'library'));
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }
    return root;
  }

  String _slug(String input) {
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_accentMap[ch] ?? ch);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  String _sanitize(String input) =>
      input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '').trim();

  String _chapterNumber(double number) {
    if (number == number.roundToDouble()) {
      return number.toInt().toString().padLeft(4, '0');
    }
    return number.toString().replaceAll('.', '_').padLeft(6, '0');
  }

  String _chapterStem(Serie serie, Chapter chapter) =>
      '${_sanitize(serie.title)} - ${_chapterNumber(chapter.number)}';

  String _volumeFolder(Serie serie, int volume) =>
      '${_sanitize(serie.title)} - Vol ${volume.toString().padLeft(4, '0')}';

  ParsedChapter? parseChapterName(String baseTitle) {
    final match = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(baseTitle);
    if (match == null) return null;
    final number = double.parse(match.group(1)!.replaceAll(',', '.'));
    var name = baseTitle.substring(0, match.start);
    name = name
        .replaceAll(RegExp(r'\bcap(?:[íi]tulo)?\.?\s*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\-–—:\.\s]+$'), '')
        .trim();
    if (name.isEmpty) name = baseTitle;
    return ParsedChapter(series: name, number: number, title: baseTitle);
  }

  Serie _findOrCreateSerie(String title) {
    final normalized = _normalize(title);
    for (final serie in _db.series.getAll()) {
      if (_normalize(serie.title) == normalized) return serie;
    }
    final serie = Serie(title: title);
    serie.id = _db.series.put(serie);
    return serie;
  }

  Future<Directory> _ensureSerieFolder(Serie serie) async {
    if (serie.folderPath.isEmpty || !Directory(serie.folderPath).existsSync()) {
      final root = await _libraryRoot();
      final dir = Directory(p.join(root.path, '${_slug(serie.title)}-${serie.id}'));
      dir.createSync(recursive: true);
      serie.folderPath = dir.path;
      _db.series.put(serie);
    }
    return Directory(serie.folderPath);
  }

  Future<Serie> addFromCatalog(CatalogEntry entry) async {
    final serie = Serie(
      title: entry.title,
      description: entry.description,
      category: entry.category,
      sourceId: entry.id,
      sourceUrl: entry.id.isEmpty
          ? null
          : 'https://anilist.co/manga/${entry.id}',
      kind: entry.kind.toLowerCase() == 'manga' ? 'manga' : 'livro',
    );
    serie.id = _db.series.put(serie);

    final dir = await _ensureSerieFolder(serie);

    try {
      if (entry.imageUrl.isNotEmpty) {
        final bytes = await _metadata.downloadImage(entry.imageUrl);
        final cover = File(p.join(dir.path, 'cover.jpg'));
        await cover.writeAsBytes(bytes, flush: true);
        serie.coverThumbPath = cover.path;
        _db.series.put(serie);
      }
    } catch (_) {}

    await load();
    // Busca volumes/arcos logo após adicionar, para já listar os ghosts.
    _syncVolumes();
    return serie;
  }

  Future<ImportReport> importFiles(List<String> paths) async {    final report = ImportReport();

    for (final path in paths) {
      if (!_archive.isSupportedFile(path)) {
        report.skipped.add(p.basename(path));
        continue;
      }
      final base = p.basenameWithoutExtension(path);
      final parsed = parseChapterName(base);
      if (parsed == null) {
        report.skipped.add(p.basename(path));
        continue;
      }

      try {
        final serie = _findOrCreateSerie(parsed.series);
        await _ensureSerieFolder(serie);

        final chapter = Chapter(
          serieId: serie.id,
          title: base,
          number: parsed.number,
        );
        chapter.id = _db.chapters.put(chapter);

        final map = await _volumeMapFor(serie);
        chapter.volume = map[parsed.number.round()] ?? 0;

        await _placeChapter(serie, chapter, sourceCbz: path, extract: true);
        _db.chapters.put(chapter);

        if (!report.imported.any((s) => s.id == serie.id)) {
          report.imported.add(serie);
        }
      } catch (e) {
        report.failed[p.basename(path)] = e.toString();
      }
    }

    lastImport = report;
    await load();
    _syncVolumes();
    return report;
  }

  Future<Map<int, int>> _volumeMapFor(Serie serie) async {
    final dexId = serie.dexId;
    if (dexId == null || dexId.isEmpty) return {};
    final index = _db.volumeIndexes
        .query(VolumeIndex_.dexId.equals(dexId))
        .build()
        .findFirst();
    if (index == null) return {};
    try {
      final decoded = jsonDecode(index.data) as Map<String, dynamic>;
      return decoded.map((key, value) =>
          MapEntry(int.parse(key), (value as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _placeChapter(
    Serie serie,
    Chapter chapter, {
    String? sourceCbz,
    bool extract = false,
  }) async {
    final seriesDir = await _ensureSerieFolder(serie);
    final targetParent = chapter.volume > 0
        ? Directory(p.join(seriesDir.path, _volumeFolder(serie, chapter.volume)))
        : seriesDir;
    if (!targetParent.existsSync()) targetParent.createSync(recursive: true);

    final stem = _chapterStem(serie, chapter);
    final contentDir = Directory(p.join(targetParent.path, stem));

    final oldPath = chapter.folderPath;
    final shouldMove = oldPath.isNotEmpty &&
        p.normalize(oldPath) != p.normalize(contentDir.path) &&
        !p.isWithin(oldPath, contentDir.path) &&
        !p.isWithin(contentDir.path, oldPath) &&
        Directory(oldPath).existsSync();
    if (shouldMove) {
      _moveDirectory(oldPath, contentDir.path);
    } else if (!contentDir.existsSync()) {
      contentDir.createSync(recursive: true);
    }

    final targetCbz = p.join(contentDir.path, '$stem.cbz');
    if (sourceCbz != null && File(sourceCbz).existsSync()) {
      if (p.normalize(sourceCbz) != p.normalize(targetCbz)) {
        File(sourceCbz).copySync(targetCbz);
      }
      chapter.cbzPath = targetCbz;
    } else if (chapter.cbzPath != null) {
      final movedCbz = p.join(contentDir.path, p.basename(chapter.cbzPath!));
      if (File(movedCbz).existsSync()) {
        chapter.cbzPath = movedCbz;
      } else if (p.normalize(chapter.cbzPath!) != p.normalize(targetCbz) &&
          File(chapter.cbzPath!).existsSync()) {
        _moveFile(chapter.cbzPath!, targetCbz);
        chapter.cbzPath = targetCbz;
      }
    }

    final imagesDir = p.join(contentDir.path, 'images');
    if (extract && chapter.cbzPath != null) {
      chapter.pagePaths = await _archive.extractPages(
        archivePath: chapter.cbzPath!,
        outputDir: imagesDir,
      );
    } else if (chapter.pagePaths.isNotEmpty) {
      chapter.pagePaths = chapter.pagePaths
          .map((file) => p.join(imagesDir, p.basename(file)))
          .toList();
    }
    chapter.folderPath = contentDir.path;
  }

  void _moveFile(String from, String to) {
    try {
      File(from).renameSync(to);
    } catch (_) {
      File(from).copySync(to);
      try {
        File(from).deleteSync();
      } catch (_) {}
    }
  }

  void _moveDirectory(String from, String to) {
    final target = Directory(to);
    if (target.existsSync()) target.deleteSync(recursive: true);
    try {
      Directory(from).renameSync(to);
    } catch (_) {
      target.createSync(recursive: true);
      for (final entity in Directory(from).listSync()) {
        final dest = p.join(to, p.basename(entity.path));
        if (entity is File) {
          entity.copySync(dest);
        } else if (entity is Directory) {
          _moveDirectory(entity.path, dest);
        }
      }
      try {
        Directory(from).deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  Future<bool> _enrichSerie(Serie serie) async {
    final coverMissing = serie.coverThumbPath == null ||
        !File(serie.coverThumbPath!).existsSync();
    final categoryMissing = serie.category.trim().isEmpty;
    var descriptionMissing = serie.description.trim().isEmpty;
    final language = SettingsController.instance.metadataLanguage;

    var changed = false;

    if (descriptionMissing && serie.dexId != null && serie.dexId!.isNotEmpty) {
      try {
        final localized =
            await _dex.localizedDescription(serie.dexId!, language);
        if (localized != null && localized.isNotEmpty) {
          serie.description = localized;
          descriptionMissing = false;
          changed = true;
        }
      } catch (_) {}
    }

    if (!coverMissing && !categoryMissing && !descriptionMissing) {
      if (changed) _db.series.put(serie);
      return changed;
    }

    final results = await _metadata.searchManga(serie.title, limit: 5);
    if (results.isEmpty) {
      if (changed) _db.series.put(serie);
      return changed;
    }
    final entry = _bestMetadataMatch(serie.title, results);
    if (entry == null) {
      if (changed) _db.series.put(serie);
      return changed;
    }

    if (categoryMissing && entry.category.isNotEmpty) {
      serie.category = entry.category;
      changed = true;
    }
    if (descriptionMissing && entry.description.isNotEmpty) {
      serie.description = entry.description;
      changed = true;
    }
    if (serie.sourceId == null && entry.id.isNotEmpty) {
      serie.sourceId = entry.id;
      serie.sourceUrl = 'https://anilist.co/manga/${entry.id}';
      changed = true;
    }
    if (coverMissing && entry.imageUrl.isNotEmpty) {
      try {
        final dir = await _ensureSerieFolder(serie);
        final bytes = await _metadata.downloadImage(entry.imageUrl);
        final cover = File(p.join(dir.path, 'cover.jpg'));
        await cover.writeAsBytes(bytes, flush: true);
        serie.coverThumbPath = cover.path;
        changed = true;
      } catch (_) {}
    }

    if (changed) _db.series.put(serie);
    return changed;
  }

  CatalogEntry? _bestMetadataMatch(String title, List<CatalogEntry> entries) {
    final target = _normalize(title);
    CatalogEntry? best;
    var bestScore = -1.0;
    for (final entry in entries) {
      final candidate = _normalize(entry.title);
      double score;
      if (candidate == target) {
        score = 1.0;
      } else if (target.isNotEmpty &&
          (candidate.contains(target) || target.contains(candidate))) {
        score = 0.8;
      } else {
        score = 0.0;
      }
      if (score > bestScore) {
        bestScore = score;
        best = entry;
      }
    }
    return bestScore >= 0.8 ? best : null;
  }

  Future<void> _syncVolumes() async {
    if (isSyncingVolumes) return;
    isSyncingVolumes = true;
    notifyListeners();
    var changed = false;
    try {
      for (final serie in _db.series.getAll()) {
        final chapters =
            _db.chapters.query(Chapter_.serieId.equals(serie.id)).build().find();

        var dexId = serie.dexId;
        if (dexId == null || dexId.isEmpty) {
          try {
            final match = await _dex.findByTitle(serie.title);
            if (match != null) {
              dexId = match.id;
              serie.dexId = dexId;
              _db.series.put(serie);
            }
          } catch (_) {}
        }

        try {
          if (await _enrichSerie(serie)) changed = true;
        } catch (_) {}
        try {
          if (await _syncArcs(serie)) changed = true;
        } catch (_) {}

        // Mapa capítulo→volume. Sem `dexId`, ainda montamos a lista de
        // capítulos pelo MangaLivre (volumes viram 0 = "Sem volume").
        final map = <int, int>{};
        if (dexId != null && dexId.isNotEmpty) {
          try {
            map.addAll(await _dex.chapterVolumes(dexId));
          } catch (_) {}
          await _fillVolumeGaps(serie, map);
        }
        await _fillMangaLivreGaps(serie, map);
        _chapterVolumeBySerie[serie.id] = map;

        if (dexId == null || dexId.isEmpty) continue;

        try {
          final data =
              jsonEncode(map.map((k, v) => MapEntry(k.toString(), v)));
          final existing = _db.volumeIndexes
              .query(VolumeIndex_.dexId.equals(dexId))
              .build()
              .findFirst();
          if (existing == null) {
            _db.volumeIndexes.put(VolumeIndex(dexId: dexId, data: data));
          } else {
            existing.data = data;
            existing.updatedAt = DateTime.now();
            _db.volumeIndexes.put(existing);
          }

          for (final chapter in chapters) {
            final volume = map[chapter.number.round()] ?? 0;
            if (volume != chapter.volume) {
              chapter.volume = volume;
              await _placeChapter(serie, chapter);
              _db.chapters.put(chapter);
              changed = true;
            }
          }

          try {
            if (await _syncVolumeCovers(serie, dexId, map.values.toSet())) {
              changed = true;
            }
          } catch (_) {}
        } catch (_) {}
      }
    } finally {
      isSyncingVolumes = false;
      if (changed) {
        await load();
      } else {
        notifyListeners();
      }
    }
  }

  /// Preenche lacunas do mapa capítulo→volume do MangaDex.
  ///
  /// O `aggregate` do MangaDex não tem o volume de vários capítulos de One
  /// Piece (ex.: volumes 8–60). Para One Piece, usamos a **One Piece API**
  /// (`/v2/chapters`) — que cobre todos os volumes — sem sobrescrever os
  /// valores já vindos do MangaDex.
  Future<void> _fillVolumeGaps(Serie serie, Map<int, int> map) async {
    if (!_normalize(serie.title).contains('onepiece')) return;
    try {
      final opMap = await _onePiece.chapterVolumes();
      for (final entry in opMap.entries) {
        map.putIfAbsent(entry.key, () => entry.value);
      }
    } catch (_) {}
  }

  /// Complementa a lista de capítulos com o **MangaLivre**.
  ///
  /// O MangaLivre **não** expõe o volume dos capítulos (nem no HTML nem em
  /// outra rota), então aqui ele serve para garantir que **nenhum capítulo
  /// existente fique de fora**: os capítulos que o MangaDex não conhece entram
  /// com volume **0** (grupo "Sem volume"), em vez de serem omitidos.
  Future<void> _fillMangaLivreGaps(Serie serie, Map<int, int> map) async {
    final api = MangaLivreApi();
    try {
      final chapters = await api.listChapters(mangaLivreUrlFor(serie.title));
      for (final chapter in chapters) {
        map.putIfAbsent(chapter.number, () => 0);
      }
    } catch (_) {
    } finally {
      api.dispose();
    }
  }

  Future<bool> _syncArcs(Serie serie) async {
    if (!_normalize(serie.title).contains('onepiece')) return false;
    try {
      final map = await _onePiece.volumeSagas();
      if (map.isEmpty) return false;
      serie.arcsJson =
          jsonEncode(map.map((k, v) => MapEntry(k.toString(), v)));
      _db.series.put(serie);
      return true;
    } catch (_) {
      return false;
    }
  }

  Map<int, String> _arcMap(Serie serie) {
    if (serie.arcsJson.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(serie.arcsJson) as Map<String, dynamic>;
      return decoded.map((k, v) =>
          MapEntry(int.parse(k), _onePiece.englishSagaName(v.toString())));
    } catch (_) {
      return {};
    }
  }

  String? arcForVolume(Serie serie, int volume) {
    if (volume <= 0) return null;
    // Lê a versão mais recente do banco: o objeto `serie` da tela pode estar
    // desatualizado e não ter os arcos recém-sincronizados.
    final current = _db.series.get(serie.id) ?? serie;
    return _arcMap(current)[volume];
  }
  Future<bool> _syncVolumeCovers(
    Serie serie,
    String dexId,
    Set<int> volumes,
  ) async {
    final present = volumes.where((v) => v > 0).toSet();
    if (present.isEmpty) return false;
    final urls = await _dex.volumeCoverUrls(dexId);
    if (urls.isEmpty) return false;

    final seriesDir = await _ensureSerieFolder(serie);
    var downloaded = false;
    for (final volume in present) {
      final url = urls[volume];
      if (url == null) continue;
      final dir = Directory(p.join(seriesDir.path, _volumeFolder(serie, volume)));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final cover = File(p.join(dir.path, 'cover.jpg'));
      if (cover.existsSync()) continue;
      try {
        final bytes = await _metadata.downloadImage(url);
        await cover.writeAsBytes(bytes, flush: true);
        downloaded = true;
      } catch (_) {}
    }
    return downloaded;
  }

  Set<int> expectedVolumes(Serie serie) {
    final map = _chapterVolumeBySerie[serie.id];
    if (map == null) return {};
    // Inclui o volume 0 ("Sem volume") para não esconder capítulos cujo
    // volume é desconhecido (ex.: vindos do MangaLivre).
    return map.values.toSet();
  }

  List<int> missingChapters(Serie serie, int volume) {
    final map = _chapterVolumeBySerie[serie.id];
    if (map == null) return const [];
    final expected = map.entries
        .where((e) => e.value == volume)
        .map((e) => e.key)
        .toList()
      ..sort();
    final present = chaptersOf(serie.id)
        .where((c) => c.volume == volume)
        .map((c) => c.number.round())
        .toSet();
    return expected.where((n) => !present.contains(n)).toList();
  }

  Future<void> importGhostChapter(
    Serie serie,
    int volume,
    int number,
    String path,
  ) async {
    final chapter = Chapter(
      serieId: serie.id,
      title: '${serie.title} - Cap ${number.toString().padLeft(4, '0')}',
      number: number.toDouble(),
      volume: volume,
    );
    chapter.id = _db.chapters.put(chapter);
    await _placeChapter(serie, chapter, sourceCbz: path, extract: true);
    _db.chapters.put(chapter);
    await load();
  }

  /// Baixa um capítulo fantasma (faltante) pela internet usando a lógica do
  /// baixador e o adiciona à biblioteca. Tenta o MangaDex e, se não achar,
  /// cai para o MangaLivre. Retorna `true` quando o arquivo foi importado.
  Future<bool> downloadGhostChapter(
    Serie serie,
    int volume,
    int number,
  ) async {
    final service = ChapterDownloadService();
    try {
      final tempDir = await _downloadTempDir();
      final result = await service.downloadChapter(
        title: serie.title,
        number: number,
        outDir: tempDir.path,
        mangadexId: serie.dexId,
      );
      await importGhostChapter(serie, volume, number, result.file.path);
      try {
        if (result.file.existsSync()) result.file.deleteSync();
      } catch (_) {}
      return true;
    } finally {
      service.dispose();
    }
  }

  Future<Directory> _downloadTempDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'manga_offline', 'downloads'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Baixa **todos** os capítulos faltantes de um volume e os adiciona à
  /// biblioteca, um a um (MangaDex → fallback MangaLivre).
  Future<VolumeDownloadReport> downloadVolume(
    Serie serie,
    int volume, {
    void Function(int done, int total, int number)? onProgress,
  }) async {
    final missing = missingChapters(serie, volume);
    var downloaded = 0;
    final failed = <int>[];
    for (var i = 0; i < missing.length; i++) {
      final number = missing[i];
      onProgress?.call(i, missing.length, number);
      try {
        await downloadGhostChapter(serie, volume, number);
        downloaded++;
      } catch (_) {
        failed.add(number);
      }
      if (i < missing.length - 1) {
        await Future.delayed(const Duration(milliseconds: 700));
      }
    }
    await load();
    return VolumeDownloadReport(downloaded: downloaded, failed: failed);
  }

  String? volumeCoverPath(Serie serie, int volume) {
    if (volume <= 0 || serie.folderPath.isEmpty) return null;
    final file = File(
        p.join(serie.folderPath, _volumeFolder(serie, volume), 'cover.jpg'));
    return file.existsSync() ? file.path : null;
  }

  Future<List<CatalogEntry>> ensureRecommendations(Serie serie) async {
    if (serie.recommendationsJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(serie.recommendationsJson) as List;
        return decoded
            .map((e) => CatalogEntry.fromCache(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    var sourceId = serie.sourceId;
    if (sourceId == null || sourceId.isEmpty) {
      try {
        await _enrichSerie(serie);
      } catch (_) {}
      sourceId = serie.sourceId;
    }
    if (sourceId == null || sourceId.isEmpty) return [];

    try {
      final items = await _metadata.recommendations(sourceId, limit: 12);
      serie.recommendationsJson =
          jsonEncode(items.map((e) => e.toJson()).toList());
      _db.series.put(serie);
      refresh();
      return items;
    } catch (_) {
      return [];
    }
  }

  void syncVolumesOnStart() {
    if (series.isEmpty) return;
    _syncVolumes();
  }

  Future<void> saveChapterProgress(Chapter chapter, int pageIndex) async {
    chapter.lastPageIndex = pageIndex;
    // Escrita assíncrona: não bloqueia a UI durante a virada de página.
    await _db.chapters.putAsync(chapter);
    final serie = series.where((s) => s.id == chapter.serieId).firstOrNull;
    if (serie != null) {
      final chapters = chaptersOf(serie.id);
      if (chapters.isNotEmpty) {
        serieProgress[serie.id] =
            chapters.map((c) => c.progress).reduce((a, b) => a + b) /
                chapters.length;
      }
    }
    // Sem notifyListeners aqui: o refresh acontece ao voltar do leitor.
  }

  void refresh() => notifyListeners();

  void _deleteFolder(String? path) {
    if (path == null || path.isEmpty) return;
    final folder = Directory(path);
    if (folder.existsSync()) {
      try {
        folder.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> deleteChapter(Chapter chapter) async {
    _deleteFolder(chapter.folderPath);
    _db.chapters.remove(chapter.id);
    await load();
  }

  Future<void> deleteVolume(Serie serie, int volume) async {
    final chapters =
        chaptersOf(serie.id).where((c) => c.volume == volume).toList();
    for (final chapter in chapters) {
      _deleteFolder(chapter.folderPath);
      _db.chapters.remove(chapter.id);
    }
    if (volume > 0 && serie.folderPath.isNotEmpty) {
      _deleteFolder(p.join(serie.folderPath, _volumeFolder(serie, volume)));
    }
    await load();
  }

  Future<void> deleteSerie(Serie serie) async {
    final chapters =
        _db.chapters.query(Chapter_.serieId.equals(serie.id)).build().find();
    _db.chapters.removeMany(chapters.map((c) => c.id).toList());
    _deleteFolder(serie.folderPath);
    _db.series.remove(serie.id);
    await load();
  }
}
