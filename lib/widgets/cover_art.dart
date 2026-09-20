import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Square cover: file path and/or in-memory bytes, else music-note placeholder.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    this.path,
    this.bytes,
    required this.size,
    this.borderRadius = 6,
    this.icon,
  });

  final String? path;
  final Uint8List? bytes;
  final double size;
  final double borderRadius;
  final IconData? icon;

  bool get _hasBytes => bytes != null && bytes!.isNotEmpty;
  bool get _hasFile => path != null && path!.isNotEmpty && File(path!).existsSync();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: _hasBytes
            ? Image.memory(
                bytes!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    _hasFile ? _fileImage() : _placeholder(),
              )
            : _hasFile
                ? _fileImage()
                : _placeholder(),
      ),
    );
  }

  Widget _fileImage() {
    return Image.file(
      File(path!),
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => _placeholder(),
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
  const CoverBackdrop({super.key, this.path, this.bytes, required this.child});

  final String? path;
  final Uint8List? bytes;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hasBytes = bytes != null && bytes!.isNotEmpty;
    final hasFile =
        path != null && path!.isNotEmpty && File(path!).existsSync();
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.background),
        if (hasBytes)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Image.memory(
              bytes!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          )
        else if (hasFile)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Image.file(
              File(path!),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        if (hasBytes || hasFile)
          ColoredBox(color: Colors.white.withValues(alpha: 0.82)),
        child,
      ],
    );
  }
}
