// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/manga.dart';
import '../services/cache_service.dart';

/// Local manga cover thumb (manga_cache/covers) or placeholder.
class MangaCoverArt extends StatelessWidget {
  const MangaCoverArt({
    super.key,
    required this.manga,
    this.size = 48,
    this.borderRadius = 8,
  });

  final Manga manga;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheService>();
    File? cover;
    try {
      cover = cache.mangaCoverFile(manga.id);
    } catch (_) {
      cover = null;
    }
    final scheme = Theme.of(context).colorScheme;
    final hasFile =
        cover != null && cover.existsSync() && cover.lengthSync() > 0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: hasFile
            ? Image.file(
                cover,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, _, _) => _placeholder(scheme),
              )
            : _placeholder(scheme),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Icon(
        Icons.menu_book_outlined,
        color: scheme.onSurfaceVariant,
        size: size * 0.45,
      ),
    );
  }
}
