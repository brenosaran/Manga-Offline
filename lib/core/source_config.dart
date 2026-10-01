/// Um servidor/site de busca configurado pelo usuário.
///
/// O app é uma **ferramenta de leitura/agregação**: os servidores são
/// fornecidos pelo próprio usuário. Cada um tem um **idioma** preferido e
/// pode ser desativado sem remover da lista.
class SourceConfig {
  const SourceConfig({
    required this.url,
    this.language = 'pt-br',
    this.enabled = true,
  });

  /// URL base do servidor, ex.: `https://mangalivre.to`.
  final String url;

  /// Idioma preferido nesse servidor, ex.: `pt-br`, `en`.
  final String language;

  /// Se `false`, o servidor é ignorado no download (mas continua na lista).
  final bool enabled;

  SourceConfig copyWith({String? url, String? language, bool? enabled}) =>
      SourceConfig(
        url: url ?? this.url,
        language: language ?? this.language,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'language': language,
        'enabled': enabled,
      };

  factory SourceConfig.fromJson(Map<String, dynamic> json) => SourceConfig(
        url: json['url']?.toString() ?? '',
        language: json['language']?.toString() ?? 'pt-br',
        enabled: json['enabled'] as bool? ?? true,
      );

  /// Compatibilidade com o formato antigo (lista de strings).
  factory SourceConfig.fromLegacy(String url) => SourceConfig(url: url);

  @override
  bool operator ==(Object other) =>
      other is SourceConfig &&
      other.url == url &&
      other.language == language &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(url, language, enabled);
}
