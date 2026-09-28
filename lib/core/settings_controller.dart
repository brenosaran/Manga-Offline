import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'l10n.dart';

class SettingsController extends ChangeNotifier {
  SettingsController._();

  static final SettingsController instance = SettingsController._();

  String _locale = 'pt';
  File? _file;

  String get locale => _locale;

  L10n get l10n => _locale == 'en' ? const En() : const PtBr();

  String get metadataLanguage => l10n.metadataLanguage;

  Future<void> load() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      _file = File(p.join(docs.path, 'manga_offline', 'settings.json'));
      if (_file!.existsSync()) {
        final data =
            jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        _locale = data['locale']?.toString() ?? 'pt';
      }
    } catch (_) {}
  }

  Future<void> setLocale(String value) async {
    if (_locale == value) return;
    _locale = value;
    notifyListeners();
    try {
      final file = _file;
      if (file != null) {
        file.parent.createSync(recursive: true);
        await file.writeAsString(jsonEncode({'locale': _locale}));
      }
    } catch (_) {}
  }
}
