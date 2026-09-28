import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n.dart';
import '../core/settings_controller.dart';
import '../models/serie.dart';
import '../services/library_controller.dart';
import '../services/metadata_service.dart';

class SerieDetailsSheet extends StatefulWidget {
  const SerieDetailsSheet({
    super.key,
    required this.serie,
    required this.controller,
    required this.onOpen,
    required this.onDelete,
  });

  final Serie serie;
  final LibraryController controller;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  State<SerieDetailsSheet> createState() => _SerieDetailsSheetState();
}

class _SerieDetailsSheetState extends State<SerieDetailsSheet> {
  List<CatalogEntry> _similar = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.controller.ensureRecommendations(widget.serie);
    if (!mounted) return;
    setState(() {
      _similar = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final serie = widget.serie;
    final l10n = context.watch<SettingsController>().l10n;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Cover(path: serie.coverThumbPath),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        serie.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF202124),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        serie.kind.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF5F6368)),
                      ),
                      if (serie.category.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: serie.category
                              .split('·')
                              .map((c) => c.trim())
                              .where((c) => c.isNotEmpty)
                              .map((c) => Chip(
                                    label: Text(c,
                                        style: const TextStyle(fontSize: 11)),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (serie.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                serie.description,
                style: const TextStyle(
                    fontSize: 13, height: 1.4, color: Color(0xFF3C4043)),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              l10n.similar,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF202124),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(height: 170, child: _buildSimilar(l10n)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpen();
                    },
                    icon: const Icon(Icons.menu_book_outlined),
                    label: Text(l10n.open),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onDelete();
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.remove),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimilar(L10n l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_similar.isEmpty) {
      return Center(
        child: Text(
          l10n.similarEmpty,
          style: const TextStyle(fontSize: 12, color: Color(0xFF9AA0A6)),
        ),
      );
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _similar.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        final item = _similar[index];
        return SizedBox(
          width: 92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 92,
                  height: 130,
                  child: item.imageUrl.isEmpty
                      ? Container(color: const Color(0xFFE8EAED))
                      : Image.network(
                          item.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              Container(color: const Color(0xFFE8EAED)),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, height: 1.15),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final file = path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 92,
        height: 130,
        child: (file == null || !File(file).existsSync())
            ? Container(
                color: const Color(0xFFE8EAED),
                alignment: Alignment.center,
                child: const Icon(Icons.auto_stories_outlined,
                    color: Color(0xFF9AA0A6)),
              )
            : Image.file(File(file), fit: BoxFit.cover),
      ),
    );
  }
}
