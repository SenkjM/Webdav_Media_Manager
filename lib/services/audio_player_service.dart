import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../models/play_open_mode.dart';
import '../models/playable_media.dart';
import '../models/queue_task.dart';
import '../models/webdav_item.dart';
import '../models/webdav_stream.dart';
import '../utils/l10n_host.dart';
import '../utils/task_error.dart';
import 'accounts_service.dart';
import 'cache_service.dart';
import 'library_service.dart';
import 'playlist_service.dart';
import 'music_audio_handler.dart';
import 'music_prefetch_service.dart';
import 'stream_window.dart';
import 'notification_permission_service.dart';
import 'settings_service.dart';
import 'tag_service.dart';
import 'task_queue_service.dart';
import 'webdav_service.dart';

/// Unified music player: local cache and stream share one queue, MiniPlayer,
/// [PlayerScreen], and media notification.
///
/// [playTrack] resolves each row to a [PlayableMedia] (file if present, else
/// stream URL + headers). Prefetch + tag ingest run on the same service.
class AudioPlayerService extends ChangeNotifier {
  AudioPlayerService({
    required TaskQueueService taskQueue,
    required MusicAudioHandler handler,
    required WebDavService webDav,
    required CacheService cache,
    required SettingsService settings,
    required LibraryService library,
    required AccountsService accounts,
    PlaylistService? playlists,
    NotificationPermissionService? notificationPermission,
  }) : _taskQueue = taskQueue,
       _notifications = notificationPermission,
       _handler = handler,
       _webDav = webDav,
       _cache = cache,
       _settings = settings,
       _library = library,
       _accounts = accounts,
       _playlists = playlists {
    _handler.resolvePlayable = resolvePlayable;
    _posSub = _handler.positionStream.listen((p) {
      _position = p;
      notifyListeners();
    });
    _durSub = _handler.durationStream.listen((d) {
      _duration = d;
      notifyListeners();
    });
    _stateSub = _handler.playbackState.listen((s) {
      _playing = s.playing;
      _processingState = s.processingState;
      notifyListeners();
    });
    _mediaSub = _handler.mediaItem.listen((item) {
      _applyMediaItemTags(item);
      notifyListeners();
    });
    _settings.addListener(_onSettings);
  }

  final TaskQueueService _taskQueue;
  final NotificationPermissionService? _notifications;
  final MusicAudioHandler _handler;
  final WebDavService _webDav;
  final CacheService _cache;
  final SettingsService _settings;
  final LibraryService _library;
  final AccountsService _accounts;
  final PlaylistService? _playlists;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<MediaItem?>? _mediaSub;

  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  AudioProcessingState _processingState = AudioProcessingState.idle;
  String? _error;
  MusicPrefetchService? _prefetch;
  bool _notificationPrompted = false;
  PlayOpenMode _playOpenMode = PlayOpenMode.cache;

  MusicAudioHandler get handler => _handler;

  TrackInfo? get current => _handler.currentTrack;
  String? get currentRemotePath => current?.remotePath;
  String? get currentSourceName => current?.sourceName;
  List<TrackInfo> get queue => _handler.tracks;
  int get index => _handler.index;
  Duration get position => _position;
  Duration? get duration => _duration;
  bool get playing => _playing;
  String? get error => _error;
  AudioProcessingState get processingState => _processingState;

  /// True when music owns the session (not video). MiniPlayer uses this.
  bool get isMusicSession =>
      !_handler.isVideoMode && current != null;

  /// Status bar: only music_cache counts as 缓存; prefetch_cache alone = 串流.
  bool? get isPlayingLocal {
    if (current == null) return null;
    final path = current?.localPath;
    if (path != null && path.isNotEmpty && _cache.isMusicCachePath(path)) {
      return true;
    }
    // Stream URL, or a prefetch_cache file used for streaming.
    final flag = _handler.currentPlayableIsLocal;
    if (flag == null) return null;
    return false;
  }

  PlayOpenMode get playOpenMode => _playOpenMode;

  void _onSettings() => _prefetch?.nudge();

  /// Resolve playable for [track] under [_playOpenMode] (or [mode] override).
  ///
  /// Cache mode: music_cache only; missing → enqueue and wait. Never
  /// silent-streams.
  /// Stream mode: music_cache if present; else prefetch file or stream URL.
  Future<PlayableMedia?> resolvePlayable(
    TrackInfo track, {
    PlayOpenMode? mode,
  }) async {
    final openMode = mode ?? _playOpenMode;
    final audioRemote = track.effectiveAudioRemotePath;

    // Prefer explicit localPath only when it is music_cache (or any file in
    // stream mode — prefetch temp files are allowed for playback).
    final existing = track.localPath;
    if (existing != null && File(existing).existsSync()) {
      if (openMode == PlayOpenMode.stream || _cache.isMusicCachePath(existing)) {
        return PlayableMedia.file(existing);
      }
    }

    final cached = await _cache.localPathIfCached(
      audioRemote,
      sourceName: track.sourceName,
    );
    if (cached != null) {
      track.localPath = cached;
      return PlayableMedia.file(cached);
    }

    final task = _taskQueue.taskForRemote(track.sourceName, audioRemote);
    if (task != null &&
        task.status == TaskStatus.completed &&
        task.localPath != null &&
        File(task.localPath!).existsSync() &&
        _cache.isMusicCachePath(task.localPath!)) {
      track.localPath = task.localPath;
      return PlayableMedia.file(task.localPath!);
    }

    if (openMode == PlayOpenMode.cache) {
      // Enqueue into music_cache and wait — never silent-stream.
      final path = await _taskQueue.ensureCachedAndWait(
        track.sourceName,
        audioRemote,
        fileName: track.fileName,
      );
      if (path != null) {
        track.localPath = path;
        return PlayableMedia.file(path);
      }
      return null;
    }

    // Stream mode: temporary prefetch_cache OK.
    final prefetch = _prefetch;
    if (prefetch != null) {
      final path = await prefetch.cachedAudioPath(track);
      if (path != null) {
        track.localPath = path;
        return PlayableMedia.file(path);
      }
    } else if (track.accountId.isNotEmpty) {
      final path = await MusicPrefetchService(
        webDav: _webDav,
        tracks: () => const [],
        currentIndex: () => -1,
        backward: () => 0,
        forward: () => 0,
        sidecarEnabled: () => false,
        sidecarNames: () => '',
        libraryCover: (_) => null,
        namesFor: (_) => null,
        listNames: (_) async => const [],
        isActive: () => false,
      ).cachedAudioPath(track);
      if (path != null) {
        track.localPath = path;
        return PlayableMedia.file(path);
      }
    }

    final accountId = track.accountId.isNotEmpty
        ? track.accountId
        : (_accounts.idForSource(track.sourceName) ?? '');
    if (accountId.isEmpty) return null;
    final source = await _webDav.resolveStreamSource(
      remotePath: audioRemote,
      name: track.fileName,
      accountId: accountId,
      kind: StreamKind.music,
    );
    if (source == null || source.uri.isEmpty) return null;
    return PlayableMedia.stream(uri: source.uri, headers: source.headers);
  }

  /// Play [track]; [playlist] becomes the unified queue (local and/or stream).
  ///
  /// [mode] overrides the default from settings. [forceStream] is a one-shot
  /// stream open that does not change the saved default.
  Future<void> playTrack(
    TrackInfo track, {
    List<TrackInfo>? playlist,
    PlayOpenMode? mode,
    bool forceStream = false,
  }) async {
    _error = null;
    _playOpenMode = forceStream
        ? PlayOpenMode.stream
        : (mode ??
            (_settings.musicDefaultStream
                ? PlayOpenMode.stream
                : PlayOpenMode.cache));
    final list = <TrackInfo>[];
    if (playlist != null && playlist.isNotEmpty) {
      list.addAll(playlist);
    } else {
      list.addAll(_handler.tracks);
    }
    var idx = list.indexWhere(
      (t) =>
          t.remotePath == track.remotePath && t.sourceName == track.sourceName,
    );
    if (idx < 0) {
      list.add(track);
      idx = list.length - 1;
    } else {
      list[idx] = track;
    }

    for (var i = 0; i < list.length; i++) {
      final t = list[i];
      if (t.accountId.isEmpty) {
        final id = _accounts.idForSource(t.sourceName) ?? '';
        if (id.isNotEmpty) {
          list[i] = _withAccountId(t, id);
        }
      }
    }
    if (list[idx].accountId.isEmpty) {
      _error = L10nHost.current.svcNoLocalCache;
      notifyListeners();
      return;
    }

    notifyListeners();
    await _ensureNotificationPermission();
    await _loadAndPlay(list, idx);
  }

  TrackInfo _withAccountId(TrackInfo t, String accountId) {
    return TrackInfo(
      sourceName: t.sourceName,
      accountId: accountId,
      remotePath: t.remotePath,
      fileName: t.fileName,
      localPath: t.localPath,
      title: t.title,
      artist: t.artist,
      albumArtist: t.albumArtist,
      album: t.album,
      duration: t.duration,
      trackNumber: t.trackNumber,
      trackTotal: t.trackTotal,
      discNumber: t.discNumber,
      discTotal: t.discTotal,
      year: t.year,
      genre: t.genre,
      bitrate: t.bitrate,
      sampleRate: t.sampleRate,
      coverPath: t.coverPath,
      cueRemotePath: t.cueRemotePath,
      cueTrackIndex: t.cueTrackIndex,
      audioRemotePath: t.audioRemotePath,
      clipStart: t.clipStart,
      clipEnd: t.clipEnd,
      cacheGroupId: t.cacheGroupId,
    );
  }

  Future<void> _ensureNotificationPermission() async {
    final svc = _notifications;
    if (svc == null || _notificationPrompted) return;
    _notificationPrompted = true;
    if (!svc.loaded) {
      await svc.refresh();
    }
    if (!svc.isGranted) {
      await svc.request();
    }
  }

  Future<void> _loadAndPlay(List<TrackInfo> playlist, int index) async {
    _error = null;
    notifyListeners();
    try {
      // Video and music never share the session: reclaim ends video mode.
      // Do not resume a stale stream session afterward — loadAndPlay replaces
      // the music queue entirely.
      if (_handler.isVideoMode) {
        await _handler.exitVideoMode();
      }
      final track = playlist[index];
      final playable = await resolvePlayable(track);
      if (playable == null) {
        throw StateError(L10nHost.current.svcNoLocalCache);
      }
      if (playable.isLocal) {
        track.localPath = playable.localPath;
      }
      await _handler.loadAndPlay(
        playlist: playlist,
        startIndex: index,
        playable: playable,
      );
      unawaited(_clearRemoteMissingMirror(track));
      if (_playOpenMode == PlayOpenMode.stream) {
        _startPrefetch(playlist, index, track.accountId);
      } else {
        unawaited(_prefetch?.dispose());
        _prefetch = null;
        unawaited(_warmCacheNeighbors(playlist, index));
      }
    } catch (e) {
      _error = e.toString();
      final classified = TaskError.classify(e);
      final track = playlist[index];
      final hasLocal = track.localPath != null &&
          File(track.localPath!).existsSync() &&
          _cache.isMusicCachePath(track.localPath!);
      if (!hasLocal && classified.code == 'err.cloud.notFound') {
        unawaited(_markRemoteMissingMirror(track));
      }
      try {
        await _handler.stop();
      } catch (_) {}
    } finally {
      notifyListeners();
    }
  }

  /// Cache-mode neighbor warm: same forward/back window as stream prefetch,
  /// but enqueue into music_cache via the task queue (no prefetch_cache).
  Future<void> _warmCacheNeighbors(List<TrackInfo> playlist, int index) async {
    final indexes = prefetchNeighborIndexes(
      current: index,
      length: playlist.length,
      backward: _settings.audioStreamPrefetchBackward,
      forward: _settings.audioStreamPrefetchForward,
    );
    for (final i in indexes) {
      final t = playlist[i];
      if (t.accountId.isEmpty && t.sourceName.isEmpty) continue;
      if (_cache.hasLocalFile(
        t.effectiveAudioRemotePath,
        sourceName: t.sourceName,
      )) {
        continue;
      }
      try {
        await _taskQueue.ensureQueued(
          t.sourceName,
          t.effectiveAudioRemotePath,
          fileName: t.fileName,
        );
      } catch (_) {}
    }
  }

  void _startPrefetch(List<TrackInfo> playlist, int index, String accountId) {
    unawaited(_prefetch?.dispose());
    _prefetch = MusicPrefetchService(
      webDav: _webDav,
      tracks: () => _handler.tracks,
      currentIndex: () => _handler.index,
      backward: () => _settings.audioStreamPrefetchBackward,
      forward: () => _settings.audioStreamPrefetchForward,
      sidecarEnabled: () => _settings.audioStreamSidecarCover,
      sidecarNames: () => _settings.audioStreamSidecarNames,
      libraryCover: (t) {
        final cover = _library.find(t.sourceName, t.remotePath)?.coverPath;
        if (cover == null || cover.isEmpty || !File(cover).existsSync()) {
          return null;
        }
        return cover;
      },
      namesFor: (_) => null,
      listNames: (remotePath) async {
        final dir = remotePath.contains('/')
            ? remotePath.substring(0, remotePath.lastIndexOf('/'))
            : '/';
        final folder = dir.isEmpty ? '/' : dir;
        try {
          final items = await _webDav.listDirectory(accountId, folder);
          return [
            for (final item in items)
              if (!item.isDirectory) item.name,
          ];
        } catch (_) {
          return const [];
        }
      },
      isActive: () => !_handler.isVideoMode && current != null,
      onCover: (path) {
        final t = current;
        if (t == null || path == null) return;
        t.coverPath = path;
        final item = _handler.mediaItem.valueOrNull;
        if (item != null) {
          _handler.mediaItem.add(item.copyWith(artUri: Uri.file(path)));
        }
        notifyListeners();
      },
      onTags: (remotePath, tags) {
        if (tags == null) return;
        final t = current;
        if (t == null || t.effectiveAudioRemotePath != remotePath) return;
        _applyReadTags(t, tags);
        final item = _handler.mediaItem.valueOrNull;
        if (item != null) {
          final title = tags.title?.trim();
          final artist = tags.artist?.trim();
          final album = tags.album?.trim();
          _handler.mediaItem.add(
            item.copyWith(
              title: (title != null && title.isNotEmpty) ? title : item.title,
              artist:
                  (artist != null && artist.isNotEmpty) ? artist : item.artist,
              album: (album != null && album.isNotEmpty) ? album : item.album,
              duration: (tags.durationMs != null && tags.durationMs! > 0)
                  ? Duration(milliseconds: tags.durationMs!)
                  : item.duration,
            ),
          );
        }
        notifyListeners();
      },
      onIngestTags: (remotePath, fileName, tags) {
        unawaited(_ingest(remotePath, fileName, tags));
      },
    );
    _prefetch!.start(accountId: accountId);
  }

  Future<void> _ingest(
    String remotePath,
    String fileName,
    ReadTags tags,
  ) async {
    TrackInfo? t;
    for (final x in _handler.tracks) {
      if (x.effectiveAudioRemotePath == remotePath) {
        t = x;
        break;
      }
    }
    final sourceName = t?.sourceName ?? current?.sourceName;
    if (sourceName == null || sourceName.isEmpty) return;
    try {
      final row = await _library.ingestFromTags(
        sourceName: sourceName,
        remotePath: remotePath,
        fileName: fileName,
        tags: tags,
      );
      if (t != null) {
        _applyReadTags(t, tags);
        final cover = row.coverPath;
        if (cover != null && cover.isNotEmpty) {
          t.coverPath = cover;
          final item = _handler.mediaItem.valueOrNull;
          if (item != null) {
            _handler.mediaItem.add(item.copyWith(artUri: Uri.file(cover)));
          }
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  void _applyReadTags(TrackInfo t, ReadTags tags) {
    if (tags.title != null && tags.title!.trim().isNotEmpty) {
      t.title = tags.title;
    }
    if (tags.artist != null && tags.artist!.trim().isNotEmpty) {
      t.artist = tags.artist;
    }
    if (tags.albumArtist != null && tags.albumArtist!.trim().isNotEmpty) {
      t.albumArtist = tags.albumArtist;
    }
    if (tags.album != null && tags.album!.trim().isNotEmpty) {
      t.album = tags.album;
    }
    if (tags.durationMs != null && tags.durationMs! > 0) {
      t.duration = Duration(milliseconds: tags.durationMs!);
    }
    if (tags.trackNumber != null) t.trackNumber = tags.trackNumber;
    if (tags.trackTotal != null) t.trackTotal = tags.trackTotal;
    if (tags.discNumber != null) t.discNumber = tags.discNumber;
    if (tags.discTotal != null) t.discTotal = tags.discTotal;
    if (tags.year != null) t.year = tags.year;
    if (tags.genre != null) t.genre = tags.genre;
    if (tags.bitrate != null) t.bitrate = tags.bitrate;
    if (tags.sampleRate != null) t.sampleRate = tags.sampleRate;
  }

  void _applyMediaItemTags(MediaItem? item) {
    // no-op placeholder — tags applied via prefetch callbacks
  }

  Future<void> playPause() async {
    if (_handler.playing) {
      await _handler.pause();
    } else {
      if (current == null && _handler.tracks.isNotEmpty) {
        final idx = _handler.index < 0 ? 0 : _handler.index;
        await _ensureNotificationPermission();
        await _loadAndPlay(_handler.tracks, idx);
      } else {
        await _ensureNotificationPermission();
        await _handler.play();
      }
    }
  }

  Future<void> pause() => _handler.pause();

  /// Pause music because **video** is taking the media session.
  ///
  /// Keeps the music queue. Streaming music no longer uses video mode, so
  /// leaving a video never accidentally resumes an orphan stream session.
  Future<void> pauseForVideo() async {
    if (!_handler.playing) return;
    await _handler.pause();
    notifyListeners();
  }

  Future<void> seek(Duration position) => _handler.seek(position);

  Future<void> skipNext() async {
    await _handler.skipToNext();
    if (_playOpenMode == PlayOpenMode.stream) {
      _prefetch?.nudge();
    } else {
      unawaited(_warmCacheNeighbors(_handler.tracks, _handler.index));
    }
  }

  Future<void> skipPrevious() async {
    await _handler.skipToPrevious();
    if (_playOpenMode == PlayOpenMode.stream) {
      _prefetch?.nudge();
    } else {
      unawaited(_warmCacheNeighbors(_handler.tracks, _handler.index));
    }
  }

  Future<void> stop() async {
    await _prefetch?.dispose();
    _prefetch = null;
    await _handler.stop();
    notifyListeners();
  }

  Future<String> debugForceMediaNotification() async {
    await _ensureNotificationPermission();
    _notificationPrompted = false;
    await _ensureNotificationPermission();
    final msg = await _handler.debugForceMediaNotification();
    notifyListeners();
    return msg;
  }


  Future<void> _clearRemoteMissingMirror(TrackInfo track) async {
    await _library.clearRemoteMissing(
      sourceName: track.sourceName,
      remotePath: track.remotePath,
    );
    await _playlists?.setRemoteMissingForPath(
      sourceName: track.sourceName,
      remotePath: track.remotePath,
      cueRemotePath: track.cueRemotePath,
      cueTrackIndex: track.cueTrackIndex,
      missing: false,
    );
  }

  Future<void> _markRemoteMissingMirror(TrackInfo track) async {
    await _library.markRemoteMissing(
      sourceName: track.sourceName,
      remotePath: track.remotePath,
      hasLocalCache: false,
    );
    await _playlists?.setRemoteMissingForPath(
      sourceName: track.sourceName,
      remotePath: track.remotePath,
      cueRemotePath: track.cueRemotePath,
      cueTrackIndex: track.cueTrackIndex,
      missing: true,
    );
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    unawaited(_prefetch?.dispose());
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _mediaSub?.cancel();
    super.dispose();
  }
}
