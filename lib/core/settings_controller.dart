import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'l10n.dart';

/// Como exibir duas páginas lado a lado ("spread"), simulando um mangá físico.
enum DualPageMode {
  /// Ativa duas páginas quando a tela for larga o suficiente
  /// (dobrável aberto, tablet ou celular na horizontal).
  auto,

  /// Sempre mostra duas páginas por vez.
  always,

  /// Nunca mostra duas páginas (uma por vez).
  never,
}

class SettingsController extends ChangeNotifier {
  SettingsController._();

  static final SettingsController instance = SettingsController._();

  String _locale = 'pt';
  DualPageMode _dualPageMode = DualPageMode.auto;
  bool _coverAlone = true;
  File? _file;

  String get locale => _locale;

  DualPageMode get dualPageMode => _dualPageMode;

  /// Mostrar a primeira página (capa) sozinha, como num mangá impresso.
  bool get coverAlone => _coverAlone;

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
        _dualPageMode = _parseDualPageMode(data['dualPageMode']?.toString());
        _coverAlone = data['coverAlone'] as bool? ?? true;
      }
    } catch (_) {}
  }

  static DualPageMode _parseDualPageMode(String? value) {
    return switch (value) {
      'always' => DualPageMode.always,
      'never' => DualPageMode.never,
      _ => DualPageMode.auto,
    };
  }

  Future<void> setLocale(String value) async {
    if (_locale == value) return;
    _locale = value;
    notifyListeners();
    await _save();
  }

  Future<void> setDualPageMode(DualPageMode value) async {
    if (_dualPageMode == value) return;
    _dualPageMode = value;
    notifyListeners();
    await _save();
  }

  Future<void> setCoverAlone(bool value) async {
    if (_coverAlone == value) return;
    _coverAlone = value;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = _file;
      if (file != null) {
        file.parent.createSync(recursive: true);
        await file.writeAsString(jsonEncode({
          'locale': _locale,
          'dualPageMode': _dualPageMode.name,
          'coverAlone': _coverAlone,
        }));
      }
    } catch (_) {}
  }
}
