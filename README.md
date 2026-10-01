# Manga Offline

Ferramenta **offline** de leitura e agregação de mangá/webcomic e imagens, feita em **Flutter**, para **Android** e **Windows (desktop)**. Funciona como um **leitor/agregador local**: organiza a sua biblioteca, abre arquivos de imagem que você já possui e oferece uma leitura confortável, sem depender de internet.

## Funcionalidades
- Biblioteca local com capas e progresso de leitura.
- Importação de arquivos `.cbz` / `.zip` e organização automática em **obras e volumes**.
- Leitura **da direita para a esquerda** (estilo mangá), com barra de progresso invertida e modo imersivo.
- **Detecção offline de balões de fala** (modelo `.tflite`) e **_Bubble Zoom_** no estilo Google Livros — o balão é recortado e ampliado sobre a página.
- **Página dupla (spread)** em telas largas/dobráveis, com capa sozinha.
- Navegação por **botão de volume** no Android (e teclado no desktop).
- Metadados online opcionais (capa, descrição, categorias, **similares** e **arco/saga**).
- Placeholders de capítulos ausentes, com **importação manual** de um arquivo do dispositivo e **lista de servidores de busca** configurável (em builds de debug, em *Configurações → Desenvolvedor*).
- Exclusão em **3 níveis** (capítulo / volume / obra), apagando os arquivos.
- Interface e metadados em **Português** e **English**.

## Stack
Flutter/Dart · **ObjectBox** (banco local) · **`tflite_flutter` + `image`** (IA local) · `http` · `archive` · `file_picker` · `provider`.
Metadados: AniList, MangaDex e One Piece API (arcos/sagas).

## Como compilar
```bash
flutter pub get

# Android
flutter build apk --debug

# Windows (desktop)
flutter build windows --debug
```

Para gerar o código do ObjectBox (após mudar modelos):
```bash
dart run build_runner build --force-jit
```

Também há builds automatizados via **GitHub Actions** (`.github/workflows/release.yml`), disparados em tags `v*`.

## Privacidade e uso responsável
Este projeto é um **leitor / ferramenta de leitura e extração** — ele **não hospeda, não distribui e não oferece catálogo** de conteúdo protegido. A importação de arquivos usa apenas arquivos que você já possui; qualquer recurso opcional de download atende somente a **servidores privados configurados pelo usuário**. O conteúdo utilizado é de sua responsabilidade — use apenas arquivos que você possui ou tem o direito de acessar.
