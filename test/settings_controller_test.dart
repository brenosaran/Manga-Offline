import 'package:flutter_test/flutter_test.dart';
import 'package:manga_offline/core/settings_controller.dart';
import 'package:manga_offline/core/source_config.dart';

void main() {
  group('SettingsController.searchSources', () {
    test('padrão traz os servidores já configurados', () {
      final settings = SettingsController.instance;
      expect(settings.searchSourcesIsDefault, isTrue);
      final urls = settings.searchSources.map((s) => s.url).toList();
      expect(urls, contains('https://mangadex.org'));
      expect(urls, contains('https://mangalivre.to'));
    });

    test('normalizeSearchSource adiciona https e remove barra final', () {
      expect(
        SettingsController.normalizeSearchSource('servidorpessoal.com'),
        'https://servidorpessoal.com',
      );
      expect(
        SettingsController.normalizeSearchSource('https://servidorpessoal.com/'),
        'https://servidorpessoal.com',
      );
      expect(
        SettingsController.normalizeSearchSource('http://a.b/'),
        'http://a.b',
      );
    });

    test('normalizeSearchSource descarta entradas vazias/inválidas', () {
      expect(SettingsController.normalizeSearchSource('   '), '');
      expect(SettingsController.normalizeSearchSource(''), '');
    });
  });

  group('SettingsController.downloadSearchSources', () {
    test('ignora servidores desativados (sem removê-los)', () async {
      final settings = SettingsController.instance;
      await settings.resetSearchSources();

      await settings.setSearchSourceEnabled('https://mangadex.org', false);
      expect(
        settings.searchSources.map((s) => s.url),
        contains('https://mangadex.org'),
      );
      expect(
        settings.downloadSearchSources.map((s) => s.url),
        isNot(contains('https://mangadex.org')),
      );

      await settings.setSearchSourceEnabled('https://mangadex.org', true);
      expect(
        settings.downloadSearchSources.map((s) => s.url),
        contains('https://mangadex.org'),
      );
      await settings.resetSearchSources();
    });
  });

  group('SettingsController.reorderSearchSource', () {
    test('move o site e o primeiro vira a preferência de download', () async {
      final settings = SettingsController.instance;
      await settings.resetSearchSources();
      expect(settings.searchSources.first.url, 'https://mangadex.org');

      // Arrasta o 1º para o fim (índices crus do ReorderableListView).
      await settings.reorderSearchSource(0, settings.searchSources.length);
      expect(settings.searchSources.first.url, 'https://mangalivre.to');
      expect(settings.searchSources.last.url, 'https://mangadex.org');
      expect(settings.downloadSearchSources.first.url, 'https://mangalivre.to');

      // Arrasta de volta para o topo.
      await settings.reorderSearchSource(1, 0);
      expect(settings.searchSources.first.url, 'https://mangadex.org');

      await settings.resetSearchSources();
    });
  });

  group('SettingsController.addSearchSource', () {
    test('guarda o idioma e ignora duplicados', () async {
      final settings = SettingsController.instance;
      await settings.resetSearchSources();

      await settings.addSearchSource('servidorpessoal.com', language: 'en');
      final added = settings.searchSources.last;
      expect(added.url, 'https://servidorpessoal.com');
      expect(added.language, 'en');
      expect(added.enabled, isTrue);

      final count = settings.searchSources.length;
      await settings.addSearchSource('https://servidorpessoal.com');
      expect(settings.searchSources.length, count);

      await settings.resetSearchSources();
    });
  });

  group('SourceConfig', () {
    test('serializa e desserializa preservando os campos', () {
      const source = SourceConfig(
        url: 'https://site.com',
        language: 'es',
        enabled: false,
      );
      final json = source.toJson();
      expect(SourceConfig.fromJson(json), source);
    });

    test('formato antigo (string) vira pt-br ativo', () {
      final legacy = SourceConfig.fromLegacy('https://site.com');
      expect(legacy.language, 'pt-br');
      expect(legacy.enabled, isTrue);
    });
  });
}
