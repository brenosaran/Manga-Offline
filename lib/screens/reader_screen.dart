import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/bubble_data.dart';
import '../core/reading_layout.dart';
import '../core/settings_controller.dart';
import '../models/chapter.dart';
import '../services/library_controller.dart';
import '../services/volume_button_service.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.chapter,
    required this.controller,
  });

  final Chapter chapter;
  final LibraryController controller;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final VolumeButtonService _volume = VolumeButtonService();
  final FocusNode _focusNode = FocusNode();
  final TransformationController _transform = TransformationController();
  PageController _pageController = PageController();
  late int _currentPage;
  int _currentIndex = 0;
  bool _chromeVisible = true;
  bool _dual = false;
  bool _coverAlone = true;
  bool _initialized = false;
  List<PageSpread> _spreads = const [];
  BubbleData? _bubbleData;
  int _bubbleIndex = -1;

  int get _pageCount => widget.chapter.pagePaths.length;

  int get _spreadCount => _spreads.length;

  @override
  void initState() {
    super.initState();
    final maxIndex = _pageCount > 0 ? _pageCount - 1 : 0;
    _currentPage = widget.chapter.lastPageIndex.clamp(0, maxIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _focusNode.requestFocus();
      await _volume.enable(onNext: _nextBubble, onPrevious: _previousBubble);
    });
    _loadBubbles();
  }

  @override
  void dispose() {
    widget.controller.saveChapterProgress(widget.chapter, _currentPage);
    _volume.disable();
    _pageController.dispose();
    _transform.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Recalcula o modo (página única/dupla) conforme a tela atual.
  void _syncLayout() {
    final settings = context.watch<SettingsController>();
    final dual = _shouldUseDual(settings.dualPageMode);
    final coverAlone = settings.coverAlone;
    if (!_initialized || dual != _dual || coverAlone != _coverAlone) {
      _rebuildLayout(dual: dual, coverAlone: coverAlone);
    }
  }

  bool _shouldUseDual(DualPageMode mode) {
    switch (mode) {
      case DualPageMode.always:
        return true;
      case DualPageMode.never:
        return false;
      case DualPageMode.auto:
        final media = MediaQuery.of(context);
        return autoDualPage(
          width: media.size.width,
          height: media.size.height,
          hasDisplayFeature: media.displayFeatures.isNotEmpty,
        );
    }
  }

  void _rebuildLayout({required bool dual, required bool coverAlone}) {
    _dual = dual;
    _coverAlone = coverAlone;
    _spreads = buildSpreads(
      pageCount: _pageCount,
      dual: dual,
      coverAlone: coverAlone,
    );
    _currentIndex = spreadIndexForPage(_spreads, _currentPage);
    final old = _pageController;
    _pageController = PageController(initialPage: _currentIndex);
    if (_initialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    _initialized = true;
  }

  void _nextPage() {
    if (_currentIndex >= _spreadCount - 1) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _previousPage() {
    if (_currentIndex <= 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _jumpTo(int index) {
    if (index < 0 || index >= _spreadCount) return;
    _pageController.jumpToPage(index);
  }

  /// Carrega as caixas de balões pré-processadas (arquivo `bubbles.json` no
  /// diretório do capítulo), se existirem.
  Future<void> _loadBubbles() async {
    final data = await BubbleData.load(widget.chapter.folderPath);
    if (!mounted) return;
    setState(() => _bubbleData = data);
  }

  bool get _singlePage =>
      _spreads.isNotEmpty && _spreads[_currentIndex].isSingle;

  BubblePage? get _currentBubblePage {
    if (_currentPage < 0 || _currentPage >= _pageCount) return null;
    return _bubbleData?.pageFor(widget.chapter.pagePaths[_currentPage]);
  }

  List<BubbleBox> get _currentBubbles => _currentBubblePage?.bubbles ?? const [];

  void _resetZoom() {
    _transform.value = Matrix4.identity();
  }

  /// Avança pelo próximo balão; ao terminar os balões, vira a página.
  void _nextBubble() {
    if (!_singlePage) {
      _nextPage();
      return;
    }
    final bubbles = _currentBubbles;
    if (bubbles.isNotEmpty && _bubbleIndex < bubbles.length - 1) {
      setState(() => _bubbleIndex++);
      _zoomToBubble(bubbles[_bubbleIndex]);
      return;
    }
    _turnPage(1);
  }

  /// Volta pelo balão anterior; no início, volta para a página inteira e depois
  /// para a página anterior.
  void _previousBubble() {
    if (!_singlePage) {
      _previousPage();
      return;
    }
    final bubbles = _currentBubbles;
    if (bubbles.isNotEmpty && _bubbleIndex > 0) {
      setState(() => _bubbleIndex--);
      _zoomToBubble(bubbles[_bubbleIndex]);
      return;
    }
    if (_bubbleIndex == 0) {
      setState(() => _bubbleIndex = -1);
      _resetZoom();
      return;
    }
    _turnPage(-1);
  }

  void _turnPage(int direction) {
    setState(() => _bubbleIndex = -1);
    _resetZoom();
    if (direction > 0) {
      _nextPage();
    } else {
      _previousPage();
    }
  }

  /// Dá zoom no balão [box], mapeando as coordenadas da imagem para a tela.
  void _zoomToBubble(BubbleBox box) {
    final page = _currentBubblePage;
    if (page == null) return;
    final size = MediaQuery.of(context).size;
    final vw = size.width;
    final vh = size.height;
    final iw = page.width.toDouble();
    final ih = page.height.toDouble();
    if (iw <= 0 || ih <= 0) return;

    final ar = iw / ih;
    double dispW;
    double dispH;
    if (vw / vh > ar) {
      dispH = vh;
      dispW = vh * ar;
    } else {
      dispW = vw;
      dispH = vw / ar;
    }
    final s = dispW / iw;
    final offX = (vw - dispW) / 2;
    final offY = (vh - dispH) / 2;
    final bx = (box.x + box.w / 2) * s + offX;
    final by = (box.y + box.h / 2) * s + offY;
    final bubbleW = box.w * s;
    final bubbleH = box.h * s;
    if (bubbleW <= 0 || bubbleH <= 0) return;

    var k = math.min(vw / bubbleW, vh / bubbleH);
    k = k.clamp(1.0, 6.0);
    final tx = vw / 2 - k * bx;
    final ty = vh / 2 - k * by;
    _transform.value = Matrix4.translationValues(tx, ty, 0) *
        Matrix4.diagonal3Values(k, k, 1);
  }

  void _onTapUp(TapUpDetails details) {
    final size = MediaQuery.of(context).size;
    if (_bubbleIndex >= 0) {
      setState(() => _bubbleIndex = -1);
      _resetZoom();
      return;
    }
    final dx = details.localPosition.dx;
    final zone = size.width * 0.30;
    if (dx < zone) {
      _turnPage(-1);
    } else if (dx > size.width - zone) {
      _turnPage(1);
    } else {
      _toggleChrome();
    }
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space) {
      _nextPage();
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp) {
      _previousPage();
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
    }
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
  }

  String _progressLabel(BuildContext context) {
    final l10n = context.read<SettingsController>().l10n;
    if (_currentIndex < 0 || _currentIndex >= _spreadCount) return '';
    final spread = _spreads[_currentIndex];
    if (spread.isSingle) {
      return l10n.readerPageOf(spread.firstPage + 1, _pageCount);
    }
    return l10n.readerSpreadOf(
      spread.firstPage + 1,
      spread.lastPage + 1,
      _pageCount,
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncLayout();
    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: _onTapUp,
          child: Stack(
            children: [
              _buildPages(),
              _buildTopBar(context),
              _buildBottomBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPages() {
    final l10n = context.read<SettingsController>().l10n;
    if (_pageCount == 0) {
      return Center(
        child: Text(
          l10n.noChapters,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _spreadCount,
      reverse: true,
      onPageChanged: (index) {
        setState(() {
          _currentIndex = index;
          _currentPage = _spreads[index].firstPage;
          _bubbleIndex = -1;
        });
        _resetZoom();
        widget.controller.saveChapterProgress(widget.chapter, _currentPage);
      },
      itemBuilder: (context, index) => _buildSpread(_spreads[index]),
    );
  }

  Widget _buildSpread(PageSpread spread) {
    if (spread.isSingle) {
      return _buildViewer(_buildPageImage(spread.firstPage));
    }
    // Leitura oriental (mangá): página inicial à direita, seguinte à esquerda.
    final first = spread.firstPage;
    final second = spread.pages[1];
    return _buildViewer(
      Row(
        children: [
          Expanded(child: _buildPageImage(second)),
          Expanded(child: _buildPageImage(first)),
        ],
      ),
    );
  }

  Widget _buildViewer(Widget child) {
    return InteractiveViewer(
      transformationController: _transform,
      minScale: 1,
      maxScale: 6,
      child: child,
    );
  }

  Widget _buildPageImage(int index) {
    return Center(
      child: Image.file(
        File(widget.chapter.pagePaths[index]),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const Center(
          child: Icon(Icons.broken_image_outlined,
              color: Colors.white38, size: 48),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      top: _chromeVisible ? 0 : -120,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(
                  widget.chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '${_currentIndex + 1}/$_spreadCount',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final l10n = context.read<SettingsController>().l10n;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      bottom: _chromeVisible ? 0 : -160,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_spreadCount > 1)
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Slider(
                    value: _currentIndex.toDouble(),
                    min: 0,
                    max: (_spreadCount - 1).toDouble(),
                    onChanged: (value) => _jumpTo(value.round()),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.readerVolumeHint,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    Text(
                      _progressLabel(context),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
