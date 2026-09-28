# Manga Offline

Leitor de mangá/livro **offline** feito em **Flutter**, com foco em Android e Windows (desktop).

## Funcionalidades
- Biblioteca com capas e progresso de leitura.
- Importação de arquivos `.cbz` / `.zip`.
- Organização automática em **volumes** (pastas), usando metadados online.
- Capa própria de cada **capítulo** e capa colorida de cada **volume**.
- Informações online: descrição, categorias, **similares** e **arco/saga por volume** (One Piece).
- Leitura **da direita para a esquerda** (estilo mangá) e barra de progresso da direita para a esquerda.
- Navegação por **botão de volume** no Android.
- Colapsar/expandir volumes.
- Excluir capítulo, volume ou obra (apagando os arquivos).
- Placeholders ("fantasma") para capítulos faltantes, com importação manual.
- Interface e metadados em **Português** e **English**.

## Stack
Flutter/Dart · ObjectBox (banco local) · `http` · `archive` · `file_picker` · `provider`.
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

## Aviso
Este projeto é apenas um **leitor**. Ele **não** inclui nem baixa conteúdo protegido por direitos autorais; use apenas arquivos que você possui legalmente.
