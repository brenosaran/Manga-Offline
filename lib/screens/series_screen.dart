import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n.dart';
import '../core/settings_controller.dart';
import '../models/chapter.dart';
import '../models/serie.dart';
import '../services/library_controller.dart';
import 'reader_screen.dart';

class SeriesScreen extends StatefulWidget {
  const SeriesScreen({
    super.key,
    required this.serie,
    required this.controller,
  });

  final Serie serie;
  final LibraryController controller;

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  bool _ascending = true;
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    // Garante que volumes/arcos/ghosts sejam buscados ao abrir a série,
    // mesmo quando ainda não há nenhum capítulo baixado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.controller.expectedVolumes(widget.serie).isEmpty) {
        widget.controller.syncVolumesOnStart();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Observa o controller para refletir volumes/arcos/ghosts assim que o
    // sync terminar (antes, a tela só atualizava após um setState manual).
    context.watch<LibraryController>();
    final l10n = context.watch<SettingsController>().l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.serie.title),
        actions: [
          IconButton(
            tooltip: l10n.sortOrder(_ascending),
            icon: Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward),
            onPressed: () => setState(() => _ascending = !_ascending),
          ),
          IconButton(
            tooltip: l10n.removeMangaTitle,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDeleteSerie(l10n),
          ),
        ],
      ),
      body: _buildList(l10n),
    );
  }

  Widget _buildList(L10n l10n) {
    final chapters = widget.controller.chaptersOf(widget.serie.id);
    final grouped = widget.controller.groupByVolume(chapters);
    final volumes = <int>{
      ...grouped.keys,
      ...widget.controller.expectedVolumes(widget.serie),
    }.toList();

    if (volumes.isEmpty) {
      // Sem capítulos baixados: se o sync ainda está rodando, avisa; senão,
      // mantém o estado vazio. Assim que o sync termina, os ghosts aparecem.
      if (widget.controller.isSyncingVolumes) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                l10n.loadingChapters,
                style: const TextStyle(color: Color(0xFF5F6368)),
              ),
            ],
          ),
        );
      }
      return _buildEmpty(l10n);
    }

    volumes.sort((a, b) {
      if (a == 0) return 1;
      if (b == 0) return -1;
      return _ascending ? a.compareTo(b) : b.compareTo(a);
    });

    final tiles = <Widget>[];
    for (final volume in volumes) {
      final items = List<Chapter>.from(grouped[volume] ?? const <Chapter>[]);
      items.sort((a, b) =>
          _ascending ? a.number.compareTo(b.number) : b.number.compareTo(a.number));

      final expanded = _expanded.contains(volume);
      final missing = widget.controller.missingChapters(widget.serie, volume);
      tiles.add(_VolumeHeader(
        label: _volumeLabel(volume),
        count: items.length,
        missing: missing.length,
        coverPath: widget.controller.volumeCoverPath(widget.serie, volume) ??
            (items.isNotEmpty ? items.first.coverPath : null),
        arc: widget.controller.arcForVolume(widget.serie, volume),
        expanded: expanded,
        l10n: l10n,
        onToggle: () => setState(() {
          if (expanded) {
            _expanded.remove(volume);
          } else {
            _expanded.add(volume);
          }
        }),
        onDownload: () => _downloadVolume(volume),
        onDelete: () => _confirmDeleteVolume(volume, l10n),
      ));
      if (!expanded) continue;
      for (final chapter in items) {
        tiles.add(_ChapterTile(
          chapter: chapter,
          l10n: l10n,
          onTap: () => _openChapter(chapter),
          onDelete: () => _confirmDeleteChapter(chapter, l10n),
        ));
      }
      for (final number in missing) {
        tiles.add(_GhostTile(
          number: number,
          volume: volume,
          l10n: l10n,
          onDownload: () => _downloadGhost(volume, number),
          onImport: () => _importGhost(volume, number),
        ));
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: tiles,
    );
  }

  Widget _buildEmpty(L10n l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_outlined,
                size: 64, color: Color(0xFF9AA0A6)),
            const SizedBox(height: 12),
            Text(
              l10n.noChaptersHere,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF5F6368)),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.importHint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF9AA0A6)),
            ),
          ],
        ),
      ),
    );
  }

  /// Rótulo do volume no padrão "Nome da Obra - vol. N".
  String _volumeLabel(int volume) {
    if (volume <= 0) {
      return context.read<SettingsController>().l10n.noVolume;
    }
    return '${widget.serie.title} - vol. $volume';
  }

  Future<void> _openChapter(Chapter chapter) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          chapter: chapter,
          controller: widget.controller,
        ),
      ),
    );
    if (mounted) {
      widget.controller.refresh();
      setState(() {});
    }
  }

  Future<void> _importGhost(int volume, int number) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['cbz', 'zip'],
    );
    final path = file?.path;
    if (path == null || !mounted) return;
    setState(() {});
    await widget.controller.importGhostChapter(widget.serie, volume, number, path);
    if (mounted) setState(() {});
  }

  Future<void> _downloadGhost(int volume, int number) async {
    final l10n = context.read<SettingsController>().l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(l10n.ghostDownloading)),
            ],
          ),
        ),
      ),
    );

    var ok = false;
    String? error;
    try {
      await widget.controller.downloadGhostChapter(widget.serie, volume, number);
      ok = true;
    } catch (e) {
      error = e.toString();
    }

    if (mounted) navigator.pop();

    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? l10n.ghostDownloadDone(number)
                : l10n.ghostDownloadFailed(error ?? ''),
          ),
        ),
      );
      setState(() {});
    }
  }

  Future<void> _downloadVolume(int volume) async {
    final l10n = context.read<SettingsController>().l10n;
    final missing = widget.controller.missingChapters(widget.serie, volume);
    if (missing.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.volumeDownloadEmpty)),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final progress = ValueNotifier<int>(0);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (_, done, _) => Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(l10n.volumeDownloading(done, missing.length)),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    VolumeDownloadReport? report;
    String? error;
    try {
      report = await widget.controller.downloadVolume(
        widget.serie,
        volume,
        onProgress: (done, total, number) => progress.value = done,
      );
    } catch (e) {
      error = e.toString();
    }

    if (mounted) navigator.pop();

    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error != null
                ? l10n.volumeDownloadFailed(error)
                : l10n.volumeDownloadDone(
                    report!.downloaded,
                    report.failed.length,
                  ),
          ),
        ),
      );
      setState(() {});
    }
  }

  Future<bool> _confirm(L10n l10n, String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.remove),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _confirmDeleteChapter(Chapter chapter, L10n l10n) async {
    final ok = await _confirm(
      l10n,
      l10n.removeChapterTitle,
      l10n.removeChapterMsg(chapter.title),
    );
    if (!ok || !mounted) return;
    await widget.controller.deleteChapter(chapter);
    if (mounted) setState(() {});
  }

  Future<void> _confirmDeleteVolume(int volume, L10n l10n) async {
    final label = _volumeLabel(volume);
    final ok = await _confirm(
      l10n,
      l10n.removeVolumeTitle,
      l10n.removeVolumeMsg(label),
    );
    if (!ok || !mounted) return;
    await widget.controller.deleteVolume(widget.serie, volume);
    if (mounted) setState(() {});
  }

  Future<void> _confirmDeleteSerie(L10n l10n) async {
    final ok = await _confirm(
      l10n,
      l10n.removeMangaTitle,
      l10n.removeMangaMsg(widget.serie.title),
    );
    if (!ok || !mounted) return;
    final navigator = Navigator.of(context);
    await widget.controller.deleteSerie(widget.serie);
    if (mounted) navigator.pop();
  }
}

class _VolumeHeader extends StatelessWidget {
  const _VolumeHeader({
    required this.label,
    required this.count,
    required this.missing,
    required this.onDelete,
    required this.onDownload,
    required this.expanded,
    required this.onToggle,
    required this.l10n,
    this.coverPath,
    this.arc,
  });

  final String label;
  final int count;
  final int missing;
  final VoidCallback onDelete;
  final VoidCallback onDownload;
  final bool expanded;
  final VoidCallback onToggle;
  final L10n l10n;
  final String? coverPath;
  final String? arc;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF1F3F4),
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _Thumb(path: coverPath, width: 38, height: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF202124),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(l10n.downloadedMissing(count, missing),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF5F6368))),
                    if (arc != null && arc!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          l10n.arc(arc!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF1A73E8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: const Color(0xFF5F6368),
              ),
              if (missing > 0)
                IconButton(
                  tooltip: l10n.downloadVolumeTooltip,
                  icon: const Icon(Icons.cloud_download_outlined, size: 20),
                  color: const Color(0xFF1A73E8),
                  onPressed: onDownload,
                ),
              IconButton(
                tooltip: l10n.removeVolumeTitle,
                icon: const Icon(Icons.delete_outline, size: 20),
                color: const Color(0xFF5F6368),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.chapter,
    required this.onTap,
    required this.onDelete,
    required this.l10n,
  });

  final Chapter chapter;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final number = chapter.number == chapter.number.roundToDouble()
        ? chapter.number.toInt().toString()
        : chapter.number.toString();
    return ListTile(
      leading: Stack(
        children: [
          _Thumb(path: chapter.coverPath, width: 44, height: 60),
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              color: const Color(0xCC1A73E8),
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        chapter.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        chapter.lastPageIndex > 0
            ? l10n.pageOf(chapter.lastPageIndex + 1, chapter.pageCount)
            : l10n.pages(chapter.pageCount),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: chapter.progress > 0
          ? SizedBox(
              width: 48,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: LinearProgressIndicator(
                  value: chapter.progress,
                  minHeight: 4,
                  backgroundColor: const Color(0xFFE8EAED),
                ),
              ),
            )
          : const Icon(Icons.chevron_left, color: Color(0xFF9AA0A6)),
      onTap: onTap,
      onLongPress: onDelete,
    );
  }
}

class _GhostTile extends StatelessWidget {
  const _GhostTile({
    required this.number,
    required this.volume,
    required this.onDownload,
    required this.onImport,
    required this.l10n,
  });

  final int number;
  final int volume;
  final VoidCallback onDownload;
  final VoidCallback onImport;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFBDBDBD)),
          color: const Color(0xFFF1F3F4),
        ),
        alignment: Alignment.center,
        child: Text(
          '$number',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF9AA0A6),
          ),
        ),
      ),
      title: Text(
        l10n.ghost,
        style: const TextStyle(
          fontSize: 14,
          fontStyle: FontStyle.italic,
          color: Color(0xFF9AA0A6),
        ),
      ),
      subtitle: Text(
        l10n.ghostHint,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: Color(0xFF9AA0A6)),
      ),
      trailing: IconButton(
        tooltip: l10n.importThisFile,
        icon: const Icon(Icons.upload_file_outlined),
        color: const Color(0xFF5F6368),
        onPressed: onImport,
      ),
      onTap: onDownload,
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path, required this.width, required this.height});

  final String? path;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final file = path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: height,
        child: (file == null || file.isEmpty || !File(file).existsSync())
            ? Container(
                color: const Color(0xFFE8EAED),
                alignment: Alignment.center,
                child: const Icon(Icons.image_outlined,
                    size: 18, color: Color(0xFF9AA0A6)),
              )
            : Image.file(
                File(file),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, _, _) => Container(
                  color: const Color(0xFFE8EAED),
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined,
                      size: 18, color: Color(0xFF9AA0A6)),
                ),
              ),
      ),
    );
  }
}
