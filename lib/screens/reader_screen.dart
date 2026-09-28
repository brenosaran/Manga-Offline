import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
  late final PageController _pageController;
  late int _currentIndex;
  bool _chromeVisible = true;

  int get _pageCount => widget.chapter.pagePaths.length;

  @override
  void initState() {
    super.initState();
    final maxIndex = _pageCount > 0 ? _pageCount - 1 : 0;
    _currentIndex = widget.chapter.lastPageIndex.clamp(0, maxIndex);
    _pageController = PageController(initialPage: _currentIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _focusNode.requestFocus();
      await _volume.enable(onNext: _nextPage, onPrevious: _previousPage);
    });
  }

  @override
  void dispose() {
    widget.controller
        .saveChapterProgress(widget.chapter, _currentIndex);
    _volume.disable();
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentIndex >= _pageCount - 1) return;
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
    if (index < 0 || index >= _pageCount) return;
    _pageController.jumpToPage(index);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _toggleChrome,
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
      itemCount: _pageCount,
      reverse: true,
      onPageChanged: (index) {
        setState(() => _currentIndex = index);
        widget.controller.saveChapterProgress(widget.chapter, index);
      },
      itemBuilder: (context, index) {
        return InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(
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
          ),
        );
      },
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
                  '${_currentIndex + 1}/$_pageCount',
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
              if (_pageCount > 1)
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Slider(
                    value: _currentIndex.toDouble(),
                    min: 0,
                    max: (_pageCount - 1).toDouble(),
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
                      l10n.readerPageOf(_currentIndex + 1, _pageCount),
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
