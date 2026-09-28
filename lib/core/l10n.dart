class L10n {
  const L10n();

  String get code => 'pt';
  String get metadataLanguage => 'pt-br';

  String get appTitle => 'Mangá Offline';
  String get library => 'Biblioteca';
  String get settings => 'Configurações';

  String get searchHint => 'Pesquisar na biblioteca';
  String get import => 'Importar';
  String get importFiles => 'Importar arquivos';
  String get addFromCatalog => 'Adicionar do catálogo';
  String get addMangaCatalog => 'Adicionar mangá (catálogo)';

  String get emptyTitle => 'Sua biblioteca está vazia';
  String get emptySubtitle =>
      'Adicione um mangá pelo catálogo ou importe arquivos .cbz.';
  String get noResults => 'Nenhum resultado.';
  String get loadError => 'Falha ao carregar a biblioteca';

  String get cancel => 'Cancelar';
  String get remove => 'Remover';
  String get create => 'Criar';
  String get open => 'Abrir';
  String get similar => 'Similares';
  String get similarEmpty =>
      'Sem sugestões (precisa de internet para carregar).';
  String get noChapters => 'Sem capítulos';
  String get noChaptersHere => 'Nenhum capítulo aqui.';
  String get importHint =>
      'Importe arquivos .cbz (ex.: "One Piece - Cap 0001.cbz") que a organização em volumes é automática.';

  String sortOrder(bool ascending) =>
      ascending ? 'Ordem crescente' : 'Ordem decrescente';

  String get removeMangaTitle => 'Remover mangá';
  String removeMangaMsg(String title) =>
      'Remover "$title" e apagar TODOS os arquivos (capítulos e volumes)?';
  String get removeVolumeTitle => 'Remover volume';
  String removeVolumeMsg(String label) =>
      'Remover o $label, todos os capítulos dele e apagar os arquivos?';
  String get removeChapterTitle => 'Remover capítulo';
  String removeChapterMsg(String title) =>
      'Remover "$title" e apagar os arquivos dele?';

  String get noVolume => 'Sem volume';
  String chapterCount(int n) => n == 1 ? '1 capítulo' : '$n capítulos';
  String downloadedMissing(int downloaded, int missing) =>
      '$downloaded baixado(s) · $missing faltando';
  String pages(int n) => '$n páginas';
  String pageOf(int a, int b) => 'Página $a de $b';
  String arc(String name) => 'Arco: $name';

  String get readerVolumeHint => 'Volume: ↑ volta · ↓ avança';
  String readerPageOf(int a, int b) => 'Página $a de $b';

  String get catalogTitle => 'Adicionar mangá';
  String get catalogSearchHint => 'Pesquisar mangá (ex.: One Piece)';
  String get catalogError => 'Falha ao buscar catálogo';
  String get retry => 'Tentar de novo';
  String get createFolderTitle => 'Criar pasta';
  String createFolderMsg(String title) =>
      'Criar a pasta de "$title" no app e salvar a imagem, a descrição e a categoria para uso offline?';
  String folderCreated(String title) => 'Pasta criada para "$title".';
  String folderCreateFailed(String error) => 'Falha ao criar a pasta: $error';

  String get ghost => 'Não baixado';
  String get importThisFile => 'Importar arquivo';
  String get ghostHint =>
      'Capítulo que existe na obra mas ainda não está no app. Toque para importar um arquivo.';

  String get readingSection => 'Leitura';
  String get volumeButtonTitle => 'Botão de volume';
  String get volumeButtonSubtitle => 'Usar volume ↑/↓ para virar página';
  String get keepScreenOnTitle => 'Manter tela acesa';
  String get keepScreenOnSubtitle => 'Evitar que a tela apague durante a leitura';
  String get aiSection => 'Inteligência artificial';
  String get bubbleZoom => 'Bubble Zoom';
  String get bubbleZoomSubtitle => 'Detecção de balões e zoom — em desenvolvimento';
  String get aboutSection => 'Sobre';
  String get version => 'Versão 1.0.0 · leitura offline de .cbz/.zip';
  String get supportedFormats => 'Formatos suportados';
  String get supportedFormatsValue =>
      '.cbz e .zip (JPG, PNG, WebP, GIF, BMP)';
  String get languageTitle => 'Idioma';
  String get languageSubtitle => 'Idioma da interface e dos metadados';
  String get languagePortuguese => 'Português';
  String get languageEnglish => 'English';

  String get loading => 'Carregando...';
}

class PtBr extends L10n {
  const PtBr();
}

class En extends L10n {
  const En();

  @override
  String get code => 'en';
  @override
  String get metadataLanguage => 'en';

  @override
  String get appTitle => 'Manga Offline';
  @override
  String get library => 'Library';
  @override
  String get settings => 'Settings';

  @override
  String get searchHint => 'Search library';
  @override
  String get import => 'Import';
  @override
  String get importFiles => 'Import files';
  @override
  String get addFromCatalog => 'Add from catalog';
  @override
  String get addMangaCatalog => 'Add manga (catalog)';

  @override
  String get emptyTitle => 'Your library is empty';
  @override
  String get emptySubtitle =>
      'Add a manga from the catalog or import .cbz files.';
  @override
  String get noResults => 'No results.';
  @override
  String get loadError => 'Failed to load the library';

  @override
  String get cancel => 'Cancel';
  @override
  String get remove => 'Remove';
  @override
  String get create => 'Create';
  @override
  String get open => 'Open';
  @override
  String get similar => 'Similar';
  @override
  String get similarEmpty => 'No suggestions (needs internet).';
  @override
  String get noChapters => 'No chapters';
  @override
  String get noChaptersHere => 'No chapters here.';
  @override
  String get importHint =>
      'Import .cbz files (e.g. "One Piece - Cap 0001.cbz"); volume organization is automatic.';

  @override
  String sortOrder(bool ascending) =>
      ascending ? 'Ascending order' : 'Descending order';

  @override
  String get removeMangaTitle => 'Remove manga';
  @override
  String removeMangaMsg(String title) =>
      'Remove "$title" and delete ALL files (chapters and volumes)?';
  @override
  String get removeVolumeTitle => 'Remove volume';
  @override
  String removeVolumeMsg(String label) =>
      'Remove $label, all its chapters and delete the files?';
  @override
  String get removeChapterTitle => 'Remove chapter';
  @override
  String removeChapterMsg(String title) =>
      'Remove "$title" and delete its files?';

  @override
  String get noVolume => 'No volume';
  @override
  String chapterCount(int n) => n == 1 ? '1 chapter' : '$n chapters';
  @override
  String downloadedMissing(int downloaded, int missing) =>
      '$downloaded downloaded · $missing missing';
  @override
  String pages(int n) => '$n pages';
  @override
  String pageOf(int a, int b) => 'Page $a of $b';
  @override
  String arc(String name) => 'Arc: $name';

  @override
  String get readerVolumeHint => 'Volume: ↑ back · ↓ next';
  @override
  String readerPageOf(int a, int b) => 'Page $a of $b';

  @override
  String get catalogTitle => 'Add manga';
  @override
  String get catalogSearchHint => 'Search manga (e.g. One Piece)';
  @override
  String get catalogError => 'Failed to load the catalog';
  @override
  String get retry => 'Try again';
  @override
  String get createFolderTitle => 'Create folder';
  @override
  String createFolderMsg(String title) =>
      'Create the folder for "$title" and save the cover, description and category for offline use?';
  @override
  String folderCreated(String title) => 'Folder created for "$title".';
  @override
  String folderCreateFailed(String error) => 'Failed to create folder: $error';

  @override
  String get ghost => 'Not downloaded';
  @override
  String get importThisFile => 'Import file';
  @override
  String get ghostHint =>
      'Chapter exists in the series but is not in the app yet. Tap to import a file.';

  @override
  String get readingSection => 'Reading';
  @override
  String get volumeButtonTitle => 'Volume buttons';
  @override
  String get volumeButtonSubtitle => 'Use volume ↑/↓ to turn pages';
  @override
  String get keepScreenOnTitle => 'Keep screen on';
  @override
  String get keepScreenOnSubtitle => 'Prevent the screen from turning off';
  @override
  String get aiSection => 'Artificial intelligence';
  @override
  String get bubbleZoom => 'Bubble Zoom';
  @override
  String get bubbleZoomSubtitle => 'Speech-bubble detection and zoom — in progress';
  @override
  String get aboutSection => 'About';
  @override
  String get version => 'Version 1.0.0 · offline .cbz/.zip reader';
  @override
  String get supportedFormats => 'Supported formats';
  @override
  String get supportedFormatsValue => '.cbz and .zip (JPG, PNG, WebP, GIF, BMP)';
  @override
  String get languageTitle => 'Language';
  @override
  String get languageSubtitle => 'Interface and metadata language';
  @override
  String get languagePortuguese => 'Português';
  @override
  String get languageEnglish => 'English';

  @override
  String get loading => 'Loading...';
}
