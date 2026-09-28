import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings_controller.dart';
import '../services/library_controller.dart';
import '../services/metadata_service.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MetadataService _metadata = MetadataService();

  List<CatalogEntry> _entries = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadTop();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTop() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _metadata.topManga(limit: 25);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _search(String query) async {
    final term = query.trim();
    if (term.isEmpty) {
      _loadTop();
      return;
    }
    setState(() {
      _query = term;
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _metadata.searchManga(term, limit: 25);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _select(CatalogEntry entry) async {
    final l10n = context.read<SettingsController>().l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.createFolderTitle),
        content: Text(l10n.createFolderMsg(entry.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.create),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final controller = context.read<LibraryController>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _creating = true);
    try {
      final serie = await controller.addFromCatalog(entry);
      if (!mounted) return;
      navigator.pop(serie);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.folderCreated(serie.title))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.folderCreateFailed('$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<SettingsController>().l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.catalogTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: l10n.catalogSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _search(_searchController.text),
                ),
                filled: true,
                fillColor: const Color(0xFFF1F3F4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_creating)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black38,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final l10n = context.read<SettingsController>().l10n;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_outlined,
                  size: 56, color: Color(0xFF9AA0A6)),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF5F6368)),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _query.isEmpty ? _loadTop : () => _search(_query),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(child: Text(l10n.noResults));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const Divider(height: 24),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return _CatalogTile(entry: entry, onTap: () => _select(entry));
      },
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({required this.entry, required this.onTap});

  final CatalogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 64,
              height: 94,
              child: entry.imageUrl.isEmpty
                  ? Container(
                      color: const Color(0xFFE8EAED),
                      child: const Icon(Icons.image_not_supported_outlined),
                    )
                  : Image.network(
                      entry.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: const Color(0xFFE8EAED),
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF202124),
                  ),
                ),
                if (entry.category.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1A73E8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  entry.description.isEmpty
                      ? 'Sem descrição disponível.'
                      : entry.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5F6368),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
