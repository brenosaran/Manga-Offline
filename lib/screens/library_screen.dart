import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n.dart';
import '../core/settings_controller.dart';
import '../models/serie.dart';
import '../services/library_controller.dart';
import '../widgets/serie_card.dart';
import '../widgets/serie_details_sheet.dart';
import 'catalog_screen.dart';
import 'series_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _searching = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LibraryController>().syncVolumesOnStart();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['cbz', 'cbr', 'zip', 'rar'],
      );
      if (files.isEmpty) return;
      final paths = files.map((file) => file.path).whereType<String>().toList();
      if (paths.isEmpty) return;
      if (!mounted) return;

      final controller = context.read<LibraryController>();
      final report = await controller.importFiles(paths);
      if (!mounted) return;
      _showReport(report);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showReport(ImportReport report) {
    final messages = <String>[
      for (final entry in report.failed.entries)
        '${entry.key}: ${entry.value}',
      ...report.skipped,
    ];
    if (messages.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(messages.join('\n'))),
    );
  }

  Future<void> _openSeries(Serie serie) async {
    final controller = context.read<LibraryController>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeriesScreen(serie: serie, controller: controller),
      ),
    );
    if (mounted) controller.refresh();
  }

  Future<void> _openCatalog() async {
    final controller = context.read<LibraryController>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CatalogScreen()),
    );
    if (mounted) controller.refresh();
  }

  void _openDetails(Serie serie) {
    final controller = context.read<LibraryController>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SerieDetailsSheet(
        serie: serie,
        controller: controller,
        onOpen: () => _openSeries(serie),
        onDelete: () => _confirmDelete(serie),
      ),
    );
  }

  Future<void> _confirmDelete(Serie serie) async {
    final l10n = context.read<SettingsController>().l10n;
    final controller = context.read<LibraryController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.removeMangaTitle),
        content: Text(l10n.removeMangaMsg(serie.title)),
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
    if (confirmed == true) {
      await controller.deleteSerie(serie);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LibraryController>();
    final l10n = context.watch<SettingsController>().l10n;
    final series = _filtered(controller.series);

    return Scaffold(
      appBar: _searching ? _buildSearchBar(l10n) : _buildAppBar(l10n),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: _importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(l10n.import),
      ),
      body: _buildBody(controller, series, l10n),
    );
  }

  AppBar _buildAppBar(L10n l10n) {
    return AppBar(
      title: Text(l10n.library),
      actions: [
        IconButton(
          tooltip: l10n.addMangaCatalog,
          icon: const Icon(Icons.cloud_download_outlined),
          onPressed: _openCatalog,
        ),
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _searching = true),
        ),
      ],
    );
  }

  AppBar _buildSearchBar(L10n l10n) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => setState(() {
          _searching = false;
          _query = '';
          _searchController.clear();
        }),
      ),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n.searchHint,
          border: InputBorder.none,
        ),
        onChanged: (value) => setState(() => _query = value),
      ),
    );
  }

  List<Serie> _filtered(List<Serie> source) {
    if (_query.trim().isEmpty) return source;
    final term = _query.toLowerCase();
    return source.where((s) => s.title.toLowerCase().contains(term)).toList();
  }

  Widget _buildBody(
    LibraryController controller,
    List<Serie> series,
    L10n l10n,
  ) {
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(controller.errorMessage!, textAlign: TextAlign.center),
        ),
      );
    }
    if (controller.series.isEmpty) {
      return _buildEmptyState(l10n);
    }
    if (series.isEmpty) {
      return Center(child: Text(l10n.noResults));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 160).floor().clamp(2, 6);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 20,
            childAspectRatio: 0.56,
          ),
          itemCount: series.length,
          itemBuilder: (context, index) {
            final serie = series[index];
            return SerieCard(
              serie: serie,
              chapterCount: controller.chapterCount[serie.id] ?? 0,
              volumeCount: controller.volumeCount[serie.id] ?? 0,
              progress: controller.serieProgress[serie.id] ?? 0,
              onTap: () => _openSeries(serie),
              onLongPress: () => _openDetails(serie),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(L10n l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories_outlined,
                size: 72, color: Color(0xFF9AA0A6)),
            const SizedBox(height: 16),
            Text(
              l10n.emptyTitle,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: Color(0xFF202124),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.emptySubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF5F6368)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openCatalog,
              icon: const Icon(Icons.cloud_download_outlined),
              label: Text(l10n.addFromCatalog),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _importing ? null : _import,
              icon: const Icon(Icons.add),
              label: Text(l10n.importFiles),
            ),
          ],
        ),
      ),
    );
  }
}
