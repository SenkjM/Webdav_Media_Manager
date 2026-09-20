import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/library_track.dart';
import '../services/cache_service.dart';
import '../services/download_queue_service.dart';
import '../services/library_service.dart';
import '../services/tag_service.dart';
import '../utils/cover_image.dart';
import 'cover_art.dart';

/// Library cover that prefers full-resolution art when the audio file is local,
/// otherwise shows the 100×100 thumb only. Never auto-enqueues audio
/// downloads from cover resolution (tap the row to enqueue explicitly).
class LibraryCoverArt extends StatefulWidget {
  const LibraryCoverArt({
    super.key,
    required this.accountId,
    required this.remotePath,
    this.thumbPath,
    this.fileName,
    required this.size,
    this.borderRadius = 6,
    this.icon,
    this.enqueueIfMissing = false,
  });

  factory LibraryCoverArt.forTrack({
    Key? key,
    required LibraryTrack track,
    required double size,
    double borderRadius = 6,
    IconData? icon,
    bool enqueueIfMissing = false,
  }) {
    return LibraryCoverArt(
      key: key,
      accountId: track.accountId,
      // Virtual cue rows enqueue/check the real audio file, not #cue:N paths.
      remotePath: track.effectiveAudioRemotePath,
      thumbPath: track.coverPath,
      fileName: track.fileName,
      size: size,
      borderRadius: borderRadius,
      icon: icon,
      enqueueIfMissing: enqueueIfMissing && !track.isCueVirtual,
    );
  }

  final String accountId;
  final String remotePath;
  final String? thumbPath;
  final String? fileName;
  final double size;
  final double borderRadius;
  final IconData? icon;
  final bool enqueueIfMissing;

  @override
  State<LibraryCoverArt> createState() => _LibraryCoverArtState();
}

class _LibraryCoverArtState extends State<LibraryCoverArt> {
  String? _displayPath;
  Uint8List? _fullBytes;
  bool _resolved = false;
  String? _identity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleResolve();
  }

  @override
  void didUpdateWidget(covariant LibraryCoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.remotePath != widget.remotePath ||
        oldWidget.thumbPath != widget.thumbPath) {
      _resolved = false;
      _fullBytes = null;
      _displayPath = null;
      _scheduleResolve();
    }
  }

  void _scheduleResolve() {
    final id = '${widget.accountId}\u0000${widget.remotePath}';
    if (_resolved && _identity == id) return;
    _identity = id;
    // Defer so we don't call ensureQueued synchronously during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_resolve());
    });
  }

  Future<void> _resolve() async {
    final cache = context.read<CacheService>();
    final library = context.read<LibraryService>();
    final downloads = context.read<DownloadQueueService>();
    final covers = library.covers;
    await covers.init();

    final local = cache.hasLocalFile(
      widget.remotePath,
      accountId: widget.accountId,
    );

    if (!local) {
      if (widget.enqueueIfMissing) {
        unawaited(
          downloads.ensureQueued(
            widget.accountId,
            widget.remotePath,
            fileName: widget.fileName,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _displayPath = resolveLibraryCoverPath(
          audioIsLocal: false,
          fullCoverPath: null,
          thumbPath: widget.thumbPath,
        );
        _fullBytes = null;
        _resolved = true;
      });
      return;
    }

    // Local audio: prefer saved full cover, else extract from tags.
    final fullPath = await covers.fullCoverPath(
      widget.accountId,
      widget.remotePath,
    );
    if (fullPath != null) {
      if (!mounted) return;
      setState(() {
        _displayPath = resolveLibraryCoverPath(
          audioIsLocal: true,
          fullCoverPath: fullPath,
          thumbPath: widget.thumbPath,
        );
        _fullBytes = null;
        _resolved = true;
      });
      return;
    }

    final localPath = cache
        .fileForRemote(widget.remotePath, accountId: widget.accountId)
        .path;
    final tags = await TagService().readFromFile(localPath);
    final bytes = tags.coverBytes;
    if (bytes != null && bytes.isNotEmpty) {
      unawaited(
        covers.saveFull(
          accountId: widget.accountId,
          remotePath: widget.remotePath,
          bytes: bytes,
        ),
      );
      // Also ensure thumb exists for offline placeholder.
      if (widget.thumbPath == null) {
        unawaited(
          covers.saveThumb(
            accountId: widget.accountId,
            remotePath: widget.remotePath,
            bytes: bytes,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _fullBytes = bytes;
        _displayPath = widget.thumbPath;
        _resolved = true;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _displayPath = widget.thumbPath;
      _fullBytes = null;
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // While resolving, show thumb immediately (no flash of placeholder).
    final path = _displayPath ?? widget.thumbPath;
    return CoverArt(
      path: path,
      bytes: _fullBytes,
      size: widget.size,
      borderRadius: widget.borderRadius,
      icon: widget.icon,
    );
  }
}

/// Pick the best cover source among album/artist tracks for grid tiles.
LibraryTrack? pickCoverTrack(
  List<LibraryTrack> tracks,
  CacheService cache,
) {
  // Prefer a track that is local (full art available).
  for (final t in tracks) {
    if (cache.hasLocalFile(t.remotePath, accountId: t.accountId)) {
      return t;
    }
  }
  // Else first with a thumb on disk.
  for (final t in tracks) {
    final p = t.coverPath;
    if (p != null && p.isNotEmpty) {
      return t;
    }
  }
  return tracks.isEmpty ? null : tracks.first;
}

/// Now-playing cover: NEVER uses the 100×100 thumb.
///
/// When the audio file is local, shows original embedded / full-res art only.
/// While downloading (no local file), shows a placeholder — no thumb, no
/// "waiting for cache" caption (that belongs on the bottom play bar).
class PlayerCoverArt extends StatefulWidget {
  const PlayerCoverArt({
    super.key,
    required this.accountId,
    required this.remotePath,
    this.localAudioPath,
    this.fileName,
    required this.size,
    this.borderRadius = 8,
    this.icon,
  });

  final String accountId;
  /// Prefer effective audio remote path (not CUE virtual `#cue:N`).
  final String remotePath;
  final String? localAudioPath;
  final String? fileName;
  final double size;
  final double borderRadius;
  final IconData? icon;

  @override
  State<PlayerCoverArt> createState() => _PlayerCoverArtState();
}

class _PlayerCoverArtState extends State<PlayerCoverArt> {
  String? _fullPath;
  Uint8List? _bytes;
  bool _resolved = false;
  String? _identity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant PlayerCoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.remotePath != widget.remotePath ||
        oldWidget.localAudioPath != widget.localAudioPath) {
      _resolved = false;
      _fullPath = null;
      _bytes = null;
      _schedule();
    }
  }

  void _schedule() {
    final id =
        '${widget.accountId}\u0000${widget.remotePath}\u0000${widget.localAudioPath ?? ''}';
    if (_resolved && _identity == id) return;
    _identity = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_resolve());
    });
  }

  Future<void> _resolve() async {
    final cache = context.read<CacheService>();
    final library = context.read<LibraryService>();
    final covers = library.covers;
    await covers.init();

    final localPath = widget.localAudioPath ??
        (cache.hasLocalFile(widget.remotePath, accountId: widget.accountId)
            ? cache
                .fileForRemote(widget.remotePath, accountId: widget.accountId)
                .path
            : null);

    if (localPath == null) {
      // Not playable yet — placeholder only (never thumb).
      if (!mounted) return;
      setState(() {
        _fullPath = null;
        _bytes = null;
        _resolved = true;
      });
      return;
    }

    final fullPath =
        await covers.fullCoverPath(widget.accountId, widget.remotePath);
    if (fullPath != null) {
      if (!mounted) return;
      setState(() {
        _fullPath = fullPath;
        _bytes = null;
        _resolved = true;
      });
      return;
    }

    final tags = await TagService().readFromFile(localPath);
    final bytes = tags.coverBytes;
    if (bytes != null && bytes.isNotEmpty) {
      unawaited(
        covers.saveFull(
          accountId: widget.accountId,
          remotePath: widget.remotePath,
          bytes: bytes,
        ),
      );
      if (!mounted) return;
      setState(() {
        _fullPath = null;
        _bytes = bytes;
        _resolved = true;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _fullPath = null;
      _bytes = null;
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Hard rule: never pass a thumb path here.
    return CoverArt(
      path: _fullPath,
      bytes: _bytes,
      size: widget.size,
      borderRadius: widget.borderRadius,
      icon: widget.icon ?? Icons.album,
    );
  }
}
