import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n.dart';
import '../core/settings_controller.dart';

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
