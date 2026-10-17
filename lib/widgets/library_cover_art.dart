import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/library_track.dart';
import '../services/cache_service.dart';
import '../services/task_queue_service.dart';
import '../services/library_service.dart';
import '../services/webdav_service.dart';
import '../services/stream_cover_reader.dart';
import '../services/accounts_service.dart';
import '../models/webdav_stream.dart';
import '../services/tag_service.dart';
import '../utils/cover_image.dart';
import 'cover_art.dart';

/// Library cover that prefers full-resolution art when the audio file is local,
/// otherwise shows the configured thumbnail only. Never auto-enqueues audio
/// downloads from cover resolution (tap the row to enqueue explicitly).
class LibraryCoverArt extends StatefulWidget {
  const LibraryCoverArt({
    super.key,
    required this.sourceName,
    required this.remotePath,
    this.libraryRemotePath,
    this.thumbPath,
    this.fileName,
    required this.size,
    this.borderRadius = 6,
    this.icon,
    this.enqueueIfMissing = false,
    this.coverRevision = 0,
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
      sourceName: track.sourceName,
      // Virtual cue rows enqueue/check the real audio file, not #cue:N paths.
      remotePath: track.effectiveAudioRemotePath,
      libraryRemotePath: track.remotePath,
      thumbPath: track.coverPath,
      fileName: track.fileName,
      size: size,
      borderRadius: borderRadius,
      icon: icon,
      enqueueIfMissing: enqueueIfMissing && !track.isCueVirtual,
      // rev/lastTagReadAt change on every tag/cover ingest, including re-scrapes
      // that rewrite the same cover file in place.
      coverRevision: track.rev ?? track.lastTagReadAt.millisecondsSinceEpoch,
    );
  }

  final String sourceName;
  final String remotePath;
  /// Library row path (may be CUE virtual); used when persisting browse thumbs.
  final String? libraryRemotePath;
  final String? thumbPath;
  final String? fileName;
  final double size;
  final double borderRadius;
  final IconData? icon;
  final bool enqueueIfMissing;

  /// Changes when the library row was re-ingested (new cover bytes may have
  /// overwritten the same file path).
  final int coverRevision;

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
    if (oldWidget.sourceName != widget.sourceName ||
        oldWidget.remotePath != widget.remotePath ||
        oldWidget.thumbPath != widget.thumbPath ||
        oldWidget.coverRevision != widget.coverRevision) {
      _resolved = false;
      _fullBytes = null;
      _displayPath = null;
      _scheduleResolve();
    }
  }

  void _scheduleResolve() {
    final id = '${widget.sourceName}\u0000${widget.remotePath}';
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
    final downloads = context.read<TaskQueueService>();
    final covers = library.covers;
    await covers.init();

    final local = cache.hasLocalFile(
      widget.remotePath,
      sourceName: widget.sourceName,
    );

    if (!local) {
      if (widget.enqueueIfMissing) {
        unawaited(
          downloads.ensureQueued(
            widget.sourceName,
            widget.remotePath,
            fileName: widget.fileName,
          ),
        );
      }
      // §17.6 list cover bucket: Range-fetch cover into covers/ without audio.
      final thumb = widget.thumbPath;
      final needBrowse = thumb == null || thumb.isEmpty;
      if (needBrowse) {
        unawaited(_fetchBrowseCover());
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
      widget.sourceName,
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
        .fileForRemote(widget.remotePath, sourceName: widget.sourceName)
        .path;
    final tags = await TagService().readFromFile(localPath);
    final bytes = tags.coverBytes;
    if (bytes != null && bytes.isNotEmpty) {
      unawaited(
        covers.saveFull(
          sourceName: widget.sourceName,
          remotePath: widget.remotePath,
          bytes: bytes,
        ),
      );
      // Also ensure thumb exists for offline placeholder.
      if (widget.thumbPath == null) {
        unawaited(
          covers.saveThumb(
            sourceName: widget.sourceName,
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


  /// Persist a list-browse thumb under covers/ via Range tags (no audio cache).
  Future<void> _fetchBrowseCover() async {
    if (!mounted) return;
    final library = context.read<LibraryService>();
    final accounts = context.read<AccountsService>();
    final webDav = context.read<WebDavService>();
    final accountId = accounts.idForSource(widget.sourceName);
    if (accountId == null) return;
    try {
      final source = await webDav.resolveStreamSource(
        remotePath: widget.remotePath,
        name: widget.fileName ?? widget.remotePath.split('/').last,
        accountId: accountId,
        kind: StreamKind.music,
      );
      if (source == null || source.uri.isEmpty) return;
      final tags = await StreamCoverReader().extractTags(source);
      final bytes = tags?.coverBytes;
      if (bytes == null || bytes.isEmpty) return;
      final coverKey = widget.libraryRemotePath ?? widget.remotePath;
      final path = await library.covers.saveThumb(
        sourceName: widget.sourceName,
        remotePath: coverKey,
        bytes: bytes,
      );
      if (path == null) return;
      await library.updateCoverPath(
        sourceName: widget.sourceName,
        remotePath: coverKey,
        coverPath: path,
      );
      if (!mounted) return;
      setState(() {
        _displayPath = path;
      });
    } catch (_) {
      // Silent: list scroll must not surface cover probe errors.
    }
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
      revision: widget.coverRevision,
    );
  }
}

/// Pick the best cover source among album/artist tracks for grid tiles.
///
/// Within each tier (local audio → any saved thumb) the most recently
/// tag-read row wins, so re-scraping one track actually updates the group art
/// instead of keeping an older sibling's cover.
LibraryTrack? pickCoverTrack(List<LibraryTrack> tracks, CacheService cache) {
  LibraryTrack? newestLocal;
  LibraryTrack? newestThumb;
  for (final t in tracks) {
    final local = cache.hasLocalFile(t.remotePath, sourceName: t.sourceName);
    if (local) {
      if (newestLocal == null ||
          t.lastTagReadAt.isAfter(newestLocal.lastTagReadAt)) {
        newestLocal = t;
      }
      continue;
    }
    final p = t.coverPath;
    if (p != null && p.isNotEmpty) {
      if (newestThumb == null ||
          t.lastTagReadAt.isAfter(newestThumb.lastTagReadAt)) {
        newestThumb = t;
      }
    }
  }
  if (newestLocal != null) return newestLocal;
  if (newestThumb != null) return newestThumb;
  return tracks.isEmpty ? null : tracks.first;
}

/// Now-playing cover: prefer full-res / embedded art; fall back to library
/// or stream [coverPath] so streaming matches MiniPlayer after Range ingest.
class PlayerCoverArt extends StatefulWidget {
  const PlayerCoverArt({
    super.key,
    required this.sourceName,
    required this.remotePath,
    this.localAudioPath,
    this.coverPath,
    this.fileName,
    required this.size,
    this.borderRadius = 8,
    this.icon,
    this.coverRevision = 0,
  });

  final String sourceName;

  /// Prefer effective audio remote path (not CUE virtual `#cue:N`).
  final String remotePath;
  final String? localAudioPath;

  /// Library / stream thumb (or any known cover file). Used when full-res is
  /// not ready yet so the full player matches MiniPlayer after Range ingest.
  final String? coverPath;
  final String? fileName;
  final double size;
  final double borderRadius;
  final IconData? icon;

  /// Bumped when the library row / queue metadata changed (cover re-ingest).
  final int coverRevision;

  @override
  State<PlayerCoverArt> createState() => _PlayerCoverArtState();
}

class _PlayerCoverArtState extends State<PlayerCoverArt> {
  String? _displayPath;
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
    if (oldWidget.sourceName != widget.sourceName ||
        oldWidget.remotePath != widget.remotePath ||
        oldWidget.localAudioPath != widget.localAudioPath ||
        oldWidget.coverPath != widget.coverPath ||
        oldWidget.coverRevision != widget.coverRevision) {
      _resolved = false;
      _displayPath = null;
      _bytes = null;
      _schedule();
    }
  }

  void _schedule() {
    final id =
        '${widget.sourceName}\u0000${widget.remotePath}\u0000'
        '${widget.localAudioPath ?? ''}\u0000${widget.coverPath ?? ''}';
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

    // 1) Full-res bucket (also written by Range / stream ingest).
    final fullPath = await covers.fullCoverPath(
      widget.sourceName,
      widget.remotePath,
    );
    if (fullPath != null) {
      if (!mounted) return;
      setState(() {
        _displayPath = fullPath;
        _bytes = null;
        _resolved = true;
      });
      return;
    }

    final localPath =
        widget.localAudioPath ??
        (cache.hasLocalFile(widget.remotePath, sourceName: widget.sourceName)
            ? cache
                  .fileForRemote(
                    widget.remotePath,
                    sourceName: widget.sourceName,
                  )
                  .path
            : null);

    // 2) Embedded art from local audio.
    if (localPath != null) {
      final tags = await TagService().readFromFile(localPath);
      final bytes = tags.coverBytes;
      if (bytes != null && bytes.isNotEmpty) {
        unawaited(
          covers.saveFull(
            sourceName: widget.sourceName,
            remotePath: widget.remotePath,
            bytes: bytes,
          ),
        );
        if (!mounted) return;
        setState(() {
          _displayPath = null;
          _bytes = bytes;
          _resolved = true;
        });
        return;
      }
    }

    // 3) Library / stream cover file (thumb or prefetch) — match MiniPlayer.
    final known = widget.coverPath;
    if (known != null && known.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _displayPath = known;
        _bytes = null;
        _resolved = true;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _displayPath = null;
      _bytes = null;
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CoverArt(
      path: _displayPath,
      bytes: _bytes,
      size: widget.size,
      borderRadius: widget.borderRadius,
      icon: widget.icon ?? Icons.album,
      revision: widget.coverRevision,
    );
  }
}
