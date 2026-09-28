import 'dart:io';

import 'package:flutter/material.dart';

import '../models/serie.dart';

class SerieCard extends StatelessWidget {
  const SerieCard({
    super.key,
    required this.serie,
    required this.chapterCount,
    required this.volumeCount,
    required this.progress,
    required this.onTap,
    required this.onLongPress,
  });

  final Serie serie;
  final int chapterCount;
  final int volumeCount;
  final double progress;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _Cover(serie: serie),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            serie.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF202124),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _subtitle(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF5F6368)),
          ),
        ],
      ),
    );
  }

  String _subtitle() {
    if (chapterCount == 0) {
      return serie.category.isNotEmpty ? serie.category : 'Sem capítulos';
    }
    if (volumeCount > 0) {
      return '$chapterCount cap. · $volumeCount vol.';
    }
    return '$chapterCount capítulo(s)';
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.serie});

  final Serie serie;

  @override
  Widget build(BuildContext context) {
    final cover = serie.coverThumbPath;
    if (cover == null || !File(cover).existsSync()) {
      return Container(
        color: const Color(0xFFE8EAED),
        alignment: Alignment.center,
        child: const Icon(Icons.auto_stories_outlined,
            color: Color(0xFF9AA0A6)),
      );
    }
    return Image.file(
      File(cover),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => Container(
        color: const Color(0xFFE8EAED),
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined,
            color: Color(0xFF9AA0A6)),
      ),
    );
  }
}
