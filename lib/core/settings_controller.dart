import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'l10n.dart';
import 'source_config.dart';

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

  /// Servidores de busca padrão (na ordem em que são tentados). O padrão já
  /// vem preenchido com os servidores configurados do projeto, para os testes
  /// de build funcionarem sem configuração manual.
  ///
  /// Isso é um recurso de **desenvolvimento** (a seção só aparece em builds de
  /// debug). O app é apenas uma ferramenta de leitura/agregação: os servidores
  /// são fornecidos pelo próprio usuário.
  static const List<SourceConfig> defaultSearchSources = <SourceConfig>[
    SourceConfig(url: 'https://mangadex.org', language: 'pt-br'),
    SourceConfig(url: 'https://mangalivre.to', language: 'pt-br'),
  ];

  String _locale = 'pt';
  DualPageMode _dualPageMode = DualPageMode.auto;
  bool _coverAlone = true;
  List<SourceConfig> _searchSources = List<SourceConfig>.of(defaultSearchSources);
  File? _file;

  String get locale => _locale;

  DualPageMode get dualPageMode => _dualPageMode;

  /// Mostrar a primeira página (capa) sozinha, como num mangá impresso.
  bool get coverAlone => _coverAlone;

  /// Lista configurada de servidores de busca (somente leitura).
  List<SourceConfig> get searchSources =>
      List<SourceConfig>.unmodifiable(_searchSources);

  /// Servidores **ativos**, na ordem de preferência (o primeiro é o preferido
  /// para o download; se falhar, tenta o próximo, e assim por diante).
  List<SourceConfig> get downloadSearchSources => <SourceConfig>[
        for (final source in _searchSources)
          if (source.enabled) source,
      ];

  /// `true` quando a lista está exatamente no padrão de fábrica.
  bool get searchSourcesIsDefault =>
      listEquals(_searchSources, defaultSearchSources);

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
        final rawSources = data['searchSources'];
        if (rawSources is List) {
          final parsed = <SourceConfig>[];
          for (final item in rawSources) {
            SourceConfig? config;
            if (item is Map) {
              config = SourceConfig.fromJson(item.cast<String, dynamic>());
            } else {
              final normalized = normalizeSearchSource(item.toString());
              if (normalized.isNotEmpty) {
                config = SourceConfig.fromLegacy(normalized);
              }
            }
            if (config != null && config.url.isNotEmpty) parsed.add(config);
          }
          if (parsed.isNotEmpty) _searchSources = parsed;
        }
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

  /// Acrescenta um servidor de busca (aceita `servidorpessoal.com` ou
  /// `https://servidorpessoal.com`). Ignora vazios e duplicados.
  Future<void> addSearchSource(String value, {String language = 'pt-br'}) async {
    final normalized = normalizeSearchSource(value);
    if (normalized.isEmpty) return;
    if (_searchSources.any((s) => s.url == normalized)) return;
    _searchSources = [
      ..._searchSources,
      SourceConfig(url: normalized, language: language),
    ];
    notifyListeners();
    await _save();
  }

  Future<void> removeSearchSource(String url) async {
    if (!_searchSources.any((s) => s.url == url)) return;
    _searchSources = _searchSources.where((s) => s.url != url).toList();
    notifyListeners();
    await _save();
  }

  /// Restaura a lista padrão (os servidores já configurados).
  Future<void> resetSearchSources() async {
    if (searchSourcesIsDefault) return;
    _searchSources = List<SourceConfig>.of(defaultSearchSources);
    notifyListeners();
    await _save();
  }

  /// Move um servidor na lista (arrastar para cima/baixo). O primeiro da lista
  /// é a preferência de download; se falhar, tenta o próximo, e assim por
  /// diante. Recebe os índices crus do `ReorderableListView`.
  Future<void> reorderSearchSource(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _searchSources.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    target = target.clamp(0, _searchSources.length - 1);
    if (target == oldIndex) return;
    final list = List<SourceConfig>.of(_searchSources);
    final item = list.removeAt(oldIndex);
    list.insert(target, item);
    _searchSources = list;
    notifyListeners();
    await _save();
  }

  /// Liga/desliga um servidor (sem removê-lo da lista).
  Future<void> setSearchSourceEnabled(String url, bool enabled) async {
    final index = _searchSources.indexWhere((s) => s.url == url);
    if (index < 0 || _searchSources[index].enabled == enabled) return;
    final list = List<SourceConfig>.of(_searchSources);
    list[index] = list[index].copyWith(enabled: enabled);
    _searchSources = list;
    notifyListeners();
    await _save();
  }

  /// Define o idioma preferido de um servidor.
  Future<void> setSearchSourceLanguage(String url, String language) async {
    final index = _searchSources.indexWhere((s) => s.url == url);
    if (index < 0 || _searchSources[index].language == language) return;
    final list = List<SourceConfig>.of(_searchSources);
    list[index] = list[index].copyWith(language: language);
    _searchSources = list;
    notifyListeners();
    await _save();
  }

  /// Normaliza um endereço de servidor: garante esquema `https://` quando
  /// ausente, remove barras finais e descarta entradas inválidas.
  static String normalizeSearchSource(String value) {
    var text = value.trim();
    if (text.isEmpty) return '';
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return '';
    return text.replaceAll(RegExp(r'/+$'), '');
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
          'searchSources': [
            for (final source in _searchSources) source.toJson(),
          ],
        }));
      }
    } catch (_) {}
  }
}
