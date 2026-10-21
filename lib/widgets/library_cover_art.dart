import 'dart:async';
import 'dart:io';
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
import '../services/audio_player_service.dart';
import '../models/webdav_stream.dart';
import '../services/tag_service.dart';
import 'cover_art.dart';

/// Library cover: resampled thumb by default. Local audio art is read from the
/// audio file's tags (never persisted); the full player screen Range-reads the
/// embedded cover for streaming tracks. Never auto-enqueues audio downloads
/// from cover resolution (tap the row to enqueue explicitly).
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
  Uint8List? _bytes;
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
      _bytes = null;
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
        _displayPath = thumb;
        _bytes = null;
        _resolved = true;
      });
      return;
    }

    // Local audio: default to the resampled thumb. If it is missing (legacy row
    // after the original-art cache cleanup), rebuild it from the audio tags so
    // the cover survives audio-cache deletion without a separate full copy.
    final thumb = widget.thumbPath;
    if (thumb != null && thumb.isNotEmpty && File(thumb).existsSync()) {
      if (!mounted) return;
      setState(() {
        _displayPath = thumb;
        _bytes = null;
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
      final saved = await covers.saveThumb(
        sourceName: widget.sourceName,
        remotePath: widget.libraryRemotePath ?? widget.remotePath,
        bytes: bytes,
      );
      if (saved != null) {
        await library.updateCoverPath(
          sourceName: widget.sourceName,
          remotePath: widget.libraryRemotePath ?? widget.remotePath,
          coverPath: saved,
        );
      }
      if (!mounted) return;
      setState(() {
        _displayPath = saved ?? thumb;
        _bytes = saved == null ? bytes : null;
        _resolved = true;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _displayPath = thumb;
      _bytes = null;
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
      bytes: _bytes,
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
    this.rangeOnlyWhenMissing = false,
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

  /// MiniPlayer only needs a fallback: when a thumb exists, skip the Range
  /// request. The full player always fetches the original.
  final bool rangeOnlyWhenMissing;

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

    // Local audio: read the original art from the file's tags on demand. It is
    // not persisted separately; only the resampled thumb lives in covers/.
    if (localPath != null) {
      final tags = await TagService().readFromFile(localPath);
      final bytes = tags.coverBytes;
      if (bytes != null && bytes.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _displayPath = null;
          _bytes = bytes;
          _resolved = true;
        });
        return;
      }
      // Local audio without embedded art: keep the resampled thumb. No Range
      // request needed, the bytes are already on disk.
      if (!mounted) return;
      setState(() {
        _displayPath = widget.coverPath;
        _bytes = null;
        _resolved = true;
      });
      return;
    }

    // Streaming: show the resampled thumb first, then Range-read the embedded
    // original (memory only; one request at a time through AudioPlayerService,
    // sharing the music network window).
    if (!mounted) return;
    setState(() {
      _displayPath = widget.coverPath;
      _bytes = null;
      _resolved = true;
    });
    if (widget.rangeOnlyWhenMissing &&
        (widget.coverPath?.isNotEmpty ?? false)) {
      return;
    }
    unawaited(_loadRangeCover());
  }

  Future<void> _loadRangeCover() async {
    final remotePath = widget.remotePath;
    final revision = widget.coverRevision;
    final player = context.read<AudioPlayerService>();
    final bytes = await player.networkCoverBytes(
      sourceName: widget.sourceName,
      remotePath: remotePath,
      fileName: widget.fileName ?? remotePath.split('/').last,
    );
    if (!mounted ||
        bytes == null ||
        bytes.isEmpty ||
        widget.remotePath != remotePath ||
        widget.coverRevision != revision) {
      return;
    }
    setState(() {
      _displayPath = null;
      _bytes = bytes;
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
