import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n.dart';
import '../core/settings_controller.dart';

/// Idiomas oferecidos por servidor (filtro/preferência de idioma).
const List<String> _languages = <String>['pt-br', 'en', 'es', 'fr', 'ja'];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _volumeNavigation = true;
  bool _keepScreenOn = true;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final l10n = settings.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          _SectionHeader(l10n.languageTitle),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(l10n.languageTitle),
            subtitle: Text(l10n.languageSubtitle),
            trailing: DropdownButton<String>(
              value: settings.locale,
              onChanged: (value) {
                if (value != null) settings.setLocale(value);
              },
              items: [
                DropdownMenuItem(value: 'pt', child: Text(l10n.languagePortuguese)),
                DropdownMenuItem(value: 'en', child: Text(l10n.languageEnglish)),
              ],
            ),
          ),
          const Divider(height: 1),
          _SectionHeader(l10n.readingSection),
          SwitchListTile(
            value: _volumeNavigation,
            onChanged: (value) => setState(() => _volumeNavigation = value),
            title: Text(l10n.volumeButtonTitle),
            subtitle: Text(l10n.volumeButtonSubtitle),
          ),
          SwitchListTile(
            value: _keepScreenOn,
            onChanged: (value) => setState(() => _keepScreenOn = value),
            title: Text(l10n.keepScreenOnTitle),
            subtitle: Text(l10n.keepScreenOnSubtitle),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: Text(l10n.dualPageTitle),
            subtitle: Text(l10n.dualPageSubtitle),
            trailing: DropdownButton<DualPageMode>(
              value: settings.dualPageMode,
              onChanged: (value) {
                if (value != null) settings.setDualPageMode(value);
              },
              items: [
                for (final mode in DualPageMode.values)
                  DropdownMenuItem(
                    value: mode,
                    child: Text(_dualPageLabel(l10n, mode)),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            value: settings.coverAlone,
            onChanged: (value) => settings.setCoverAlone(value),
            title: Text(l10n.coverAloneTitle),
            subtitle: Text(l10n.coverAloneSubtitle),
          ),
          const Divider(height: 1),
          _SectionHeader(l10n.aiSection),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: Text(l10n.bubbleZoom),
            subtitle: Text(l10n.bubbleZoomSubtitle),
            trailing: const Chip(label: Text('Fase 5–7')),
          ),
          const Divider(height: 1),
          _SectionHeader(l10n.aboutSection),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.appTitle),
            subtitle: Text(l10n.version),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(l10n.supportedFormats),
            subtitle: Text(l10n.supportedFormatsValue),
          ),
          ...[
            const Divider(height: 1),
            _SectionHeader(l10n.devSection),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(l10n.searchSourcesTitle),
              subtitle: Text(l10n.searchSourcesSubtitle),
            ),
            if (settings.searchSources.isEmpty)
              ListTile(
                leading: const Icon(Icons.warning_amber_outlined),
                title: Text(l10n.searchSourcesEmpty),
              ),
            if (settings.searchSources.isNotEmpty)
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: settings.reorderSearchSource,
                children: [
                  for (var i = 0; i < settings.searchSources.length; i++)
                    ListTile(
                      key: ValueKey(settings.searchSources[i].url),
                      dense: true,
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle),
                      ),
                      title: Text('${i + 1}. ${settings.searchSources[i].url}'),
                      subtitle: DropdownButton<String>(
                        value: settings.searchSources[i].language,
                        isDense: true,
                        underline: const SizedBox.shrink(),
                        onChanged: (value) {
                          if (value != null) {
                            settings.setSearchSourceLanguage(
                              settings.searchSources[i].url,
                              value,
                            );
                          }
                        },
                        items: [
                          for (final lang in _languages)
                            DropdownMenuItem(value: lang, child: Text(lang)),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: settings.searchSources[i].enabled,
                            onChanged: (value) =>
                                settings.setSearchSourceEnabled(
                              settings.searchSources[i].url,
                              value,
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.remove,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => settings.removeSearchSource(
                              settings.searchSources[i].url,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            _SearchSourceField(
              hint: l10n.searchSourcesHint,
              label: l10n.searchSourcesAdd,
              onAdd: (url, language) =>
                  settings.addSearchSource(url, language: language),
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: Text(l10n.searchSourcesReset),
              enabled: !settings.searchSourcesIsDefault,
              onTap: settings.searchSourcesIsDefault
                  ? null
                  : settings.resetSearchSources,
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchSourceField extends StatefulWidget {
  const _SearchSourceField({
    required this.hint,
    required this.label,
    required this.onAdd,
  });

  final String hint;
  final String label;
  final Future<void> Function(String url, String language) onAdd;

  @override
  State<_SearchSourceField> createState() => _SearchSourceFieldState();
}

class _SearchSourceFieldState extends State<_SearchSourceField> {
  final TextEditingController _controller = TextEditingController();
  String _language = 'pt-br';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    await widget.onAdd(value, _language);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: _language,
            onChanged: (value) {
              if (value != null) setState(() => _language = value);
            },
            items: [
              for (final lang in _languages)
                DropdownMenuItem(value: lang, child: Text(lang)),
            ],
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _submit, child: Text(widget.label)),
        ],
      ),
    );
  }
}

String _dualPageLabel(L10n l10n, DualPageMode mode) {
  return switch (mode) {
    DualPageMode.auto => l10n.dualPageAuto,
    DualPageMode.always => l10n.dualPageAlways,
    DualPageMode.never => l10n.dualPageNever,
  };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1A73E8),
        ),
      ),
    );
  }
}
