import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Square cover: [Image.file] when path exists, else music-note on elevated tile.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    this.path,
    required this.size,
    this.borderRadius = 6,
    this.icon,
  });

  final String? path;
  final double size;
  final double borderRadius;
  final IconData? icon;

  bool get _hasFile => path != null && File(path!).existsSync();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: _hasFile
            ? Image.file(
                File(path!),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return ColoredBox(
      color: AppColors.elevatedHigh,
      child: Center(
        child: Icon(
          icon ?? Icons.music_note,
          size: size * 0.45,
          color: AppColors.mutedText,
        ),
      ),
    );
  }
}

/// Soft light wash over blurred cover used as Now Playing backdrop.
class CoverBackdrop extends StatelessWidget {
  const CoverBackdrop({super.key, this.path, required this.child});

  final String? path;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final has =
        path != null && path!.isNotEmpty && File(path!).existsSync();
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.background),
        if (has)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Image.file(
              File(path!),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
            ),
          ),
        if (has)
          ColoredBox(color: Colors.white.withValues(alpha: 0.82)),
        child,
      ],
    );
  }
}
