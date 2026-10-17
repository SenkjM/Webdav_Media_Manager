import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../models/file_type_config.dart';
import '../models/library_track.dart';
import '../models/play_open_mode.dart';
import '../models/playable_media.dart';
import '../models/playback_queue_source.dart';
import '../models/queue_task.dart';
import '../models/webdav_item.dart';
import '../models/webdav_stream.dart';
import '../utils/directory_walk.dart';
import '../utils/l10n_host.dart';
import '../utils/remote_path.dart';
import '../utils/scan_candidates.dart';
import '../utils/task_error.dart';
import 'accounts_service.dart';
import 'cache_service.dart';
import 'library_actions.dart';
import 'library_backfill.dart';
import 'library_service.dart';
import 'playlist_service.dart';
import 'music_audio_handler.dart';
import 'music_prefetch_service.dart';
import 'playback_queue_store.dart';
import 'prefetch_cache.dart';
import 'stream_window.dart';
import 'notification_permission_service.dart';
import 'settings_service.dart';
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
    PlaybackQueueStore? queueStore,
  }) : _taskQueue = taskQueue,
       _notifications = notificationPermission,
       _handler = handler,
       _webDav = webDav,
       _cache = cache,
       _settings = settings,
       _library = library,
       _accounts = accounts,
       _playlists = playlists,
       _queueStore = queueStore ?? PlaybackQueueStore() {
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
      final queueIndex = s.queueIndex;
      if (queueIndex != null && queueIndex != _lastQueueIndex) {
        _lastQueueIndex = queueIndex;
        _persistQueueSoon();
        _scheduleEnrichment();
      }
      notifyListeners();
    });
    _mediaSub = _handler.mediaItem.listen((item) {
      _applyMediaItemTags(item);
      notifyListeners();
    });
    _settings.addListener(_onSettings);
    _taskQueue.addListener(_onTaskQueueChanged);
    _library.addListener(_onLibraryChanged);
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

  /// Pending play-triggered scrape → queue sync (null = none).
  _PendingPlayBackfillSync? _pendingPlayBackfillSync;

  final PlaybackQueueStore _queueStore;

  /// Source descriptor of the current queue (null = unknown).
  PlaybackQueueSource? _queueSource;
  bool _queueRestored = false;
  Timer? _persistTimer;
  int _lastQueueIndex = -1;
  bool _enrichScheduled = false;
  bool _enriching = false;
  bool _scrapePumping = false;
  final Set<String> _scrapeAttempted = {};
  final Map<String, Completer<void>> _scanWaiters = {};
  int _queueWalkToken = 0;

  /// Source descriptor of the now-playing queue (for the queue UI / debug).
  PlaybackQueueSource? get queueSource => _queueSource;

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

  void _onSettings() {
    _prefetch?.nudge();
    // Turning 自动补齐 on mid-queue should start filling missing rows without
    // requiring another play action.
    if (_autoScrapeQueue) _scheduleMissingScrapes();
  }

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
      // A complete stream-lookahead file is good enough to play: users who
      // skip around already have these bytes on disk (system-managed cache).
      final prefetched = await _prefetchedAudioPath(track, audioRemote);
      if (prefetched != null) {
        track.localPath = prefetched;
        return PlayableMedia.file(prefetched);
      }
      // Enqueue into music_cache and wait — never silent-stream.
      final path = await _taskQueue.ensureCachedAndWait(
        track.sourceName,
        audioRemote,
        fileName: track.fileName,
        priority: 10,
      );
      if (path != null) {
        track.localPath = path;
        return PlayableMedia.file(path);
      }
      return null;
    }

    // Stream mode: temporary prefetch_cache OK.
    final prefetched =
        await _prefetch?.cachedAudioPath(track) ??
        await _prefetchedAudioPath(track, audioRemote);
    if (prefetched != null) {
      track.localPath = prefetched;
      return PlayableMedia.file(prefetched);
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

  /// Complete audio lookahead file for [track], if the system-managed
  /// `prefetch_cache` still holds one (cleared on every app start).
  Future<String?> _prefetchedAudioPath(
    TrackInfo track,
    String audioRemote,
  ) async {
    final id = track.accountId.isNotEmpty
        ? track.accountId
        : (_accounts.idForSource(track.sourceName) ?? '');
    if (id.isEmpty) return null;
    try {
      final file = await PrefetchCache.file(
        bucket: 'audio',
        accountId: id,
        remotePath: audioRemote,
        name: track.fileName,
      );
      return PrefetchCache.isComplete(file) ? file.path : null;
    } catch (_) {
      return null;
    }
  }

  /// Play [track]; [playlist] becomes the unified queue (local and/or stream).
  ///
  /// [mode] overrides the default from settings. [forceStream] is a one-shot
  /// stream open that does not change the saved default. [source] describes
  /// where the queue came from (persisted for restore/reconcile/scrape scope).
  Future<void> playTrack(
    TrackInfo track, {
    List<TrackInfo>? playlist,
    PlayOpenMode? mode,
    bool forceStream = false,
    PlaybackQueueSource? source,
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

    _queueSource = source ?? PlaybackQueueSource.libraryQueue();
    _scrapeAttempted.clear();
    _queueWalkToken++; // stop any previous network-folder walk
    // Library rows are already in memory: fill title/cover/duration before the
    // first frame so a scraped/cached track never waits on the network for its
    // queue metadata.
    _applyLibraryMetadata(list);

    notifyListeners();
    await _ensureNotificationPermission();
    await _loadAndPlay(list, idx);
    _afterQueueStarted();
  }

  void _afterQueueStarted() {
    _persistQueueSoon();
    _scheduleEnrichment();
    _scheduleMissingScrapes();
  }

  // ---- persistent playback queue -----------------------------------------

  /// Restore the persisted now-playing queue (cold start). Does **not** start
  /// audio: the user taps play to resume. Call after accounts + library load.
  Future<void> restoreQueue() async {
    if (_queueRestored) return;
    _queueRestored = true;
    final snap = await _queueStore.load();
    if (snap == null || snap.entries.isEmpty) return;
    final entries = <TrackInfo>[];
    for (final entry in snap.entries) {
      final accountId = entry.accountId.isNotEmpty
          ? entry.accountId
          : (_accounts.idForSource(entry.sourceName) ?? '');
      entries.add(
        accountId.isEmpty ? entry : _withAccountId(entry, accountId),
      );
    }
    _queueSource = snap.source;
    _playOpenMode = snap.mode;
    _applyLibraryMetadata(entries);
    _handler.setQueue(tracks: entries, index: snap.index);
    _lastQueueIndex = _handler.index;
    notifyListeners();
  }

  /// Fill queue rows from the in-memory library (zero network).
  void _applyLibraryMetadata(List<TrackInfo> tracks) {
    for (final t in tracks) {
      final row = _library.find(t.sourceName, t.remotePath);
      if (row != null) _applyRowMetadata(t, row);
    }
  }

  void _applyRowMetadata(TrackInfo t, LibraryTrack row) {
    if (_present(row.title)) t.title = row.title;
    if (_present(row.artist)) t.artist = row.artist;
    if (_present(row.albumArtist)) t.albumArtist = row.albumArtist;
    if (_present(row.album)) t.album = row.album;
    if (_present(row.genre)) t.genre = row.genre;
    if (row.durationMs != null && row.durationMs! > 0) {
      t.duration = Duration(milliseconds: row.durationMs!);
    }
    if (row.trackNumber != null) t.trackNumber = row.trackNumber;
    if (row.trackTotal != null) t.trackTotal = row.trackTotal;
    if (row.discNumber != null) t.discNumber = row.discNumber;
    if (row.discTotal != null) t.discTotal = row.discTotal;
    if (row.year != null) t.year = row.year;
    if (row.bitrate != null) t.bitrate = row.bitrate;
    if (row.sampleRate != null) t.sampleRate = row.sampleRate;
    if (_present(row.coverPath)) t.coverPath = row.coverPath;
  }

  static bool _present(String? value) =>
      value != null && value.trim().isNotEmpty;

  void _onLibraryChanged() {
    _scheduleEnrichment();
  }

  void _scheduleEnrichment() {
    if (_enrichScheduled) return;
    _enrichScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      _enrichScheduled = false;
      unawaited(_enrichQueue());
    });
  }

  /// Refresh every queue row from the library, then re-publish the queue so
  /// the notification / MiniPlayer / queue panel see the new metadata.
  Future<void> _enrichQueue() async {
    if (_enriching) return;
    _enriching = true;
    try {
      final tracks = List<TrackInfo>.from(_handler.tracks);
      if (tracks.isEmpty) return;
      var changed = false;
      for (final t in tracks) {
        final row = _library.find(t.sourceName, t.remotePath);
        if (row == null) continue;
        final before = (
          t.title,
          t.artist,
          t.album,
          t.genre,
          t.duration,
          t.coverPath,
        );
        _applyRowMetadata(t, row);
        final after = (
          t.title,
          t.artist,
          t.album,
          t.genre,
          t.duration,
          t.coverPath,
        );
        if (before != after) changed = true;
      }
      if (changed) {
        _handler.replaceQueueKeepingPlayback(
          tracks: tracks,
          newIndex: _handler.index,
        );
        notifyListeners();
        _persistQueueSoon();
      }
    } finally {
      _enriching = false;
      if (_enrichScheduled) _scheduleEnrichment();
    }
  }

  // ---- queue editing -----------------------------------------------------

  /// Play [batch] immediately: insert before the current track and switch to
  /// its first item. The previous current track stays after the batch.
  Future<void> playNowBatch(List<TrackInfo> batch) async {
    if (batch.isEmpty) return;
    _normalizeAccounts(batch);
    _applyLibraryMetadata(batch);
    final old = List<TrackInfo>.from(_handler.tracks);
    final at = _handler.index < 0 ? old.length : _handler.index;
    final next = <TrackInfo>[
      ...old.sublist(0, at),
      ...batch,
      ...old.sublist(at),
    ];
    _scrapeAttempted.clear();
    await _loadAndPlay(next, at);
    _afterQueueStarted();
  }

  /// FIFO append (queue-tail, batch order preserved). Starts playback when the
  /// queue is empty.
  Future<void> appendToQueue(List<TrackInfo> batch) async {
    if (batch.isEmpty) return;
    _normalizeAccounts(batch);
    _applyLibraryMetadata(batch);
    final old = _handler.tracks;
    if (old.isEmpty) {
      await playNowBatch(batch);
      return;
    }
    _handler.replaceQueueKeepingPlayback(
      tracks: <TrackInfo>[...old, ...batch],
      newIndex: _handler.index,
    );
    notifyListeners();
    _persistQueueSoon();
    _scheduleEnrichment();
    _scheduleMissingScrapes();
  }

  bool get canEditQueue => _handler.tracks.isNotEmpty;

  Future<void> moveQueueEntry(int from, int to) async {
    final old = List<TrackInfo>.from(_handler.tracks);
    if (from < 0 || from >= old.length || to < 0 || to >= old.length) return;
    if (from == to) return;
    final current = _handler.currentTrack;
    final moved = old.removeAt(from);
    old.insert(to, moved);
    final newIndex = current == null ? -1 : old.indexOf(current);
    if (newIndex < 0) return;
    _handler.replaceQueueKeepingPlayback(tracks: old, newIndex: newIndex);
    notifyListeners();
    _persistQueueSoon();
  }

  Future<void> removeQueueEntry(int index) async {
    final old = List<TrackInfo>.from(_handler.tracks);
    if (index < 0 || index >= old.length) return;
    final wasCurrent = index == _handler.index;
    old.removeAt(index);
    if (old.isEmpty) {
      await clearQueue();
      return;
    }
    if (wasCurrent) {
      final at = index.clamp(0, old.length - 1);
      await _loadAndPlay(old, at);
      _afterQueueStarted();
      return;
    }
    final current = _handler.currentTrack;
    final newIndex = current == null ? -1 : old.indexOf(current);
    if (newIndex < 0) return;
    _handler.replaceQueueKeepingPlayback(tracks: old, newIndex: newIndex);
    notifyListeners();
    _persistQueueSoon();
  }

  /// Clear the in-memory + persisted queue. Playback stops; saved playlists and
  /// the music library are untouched. The next play regenerates a queue.
  Future<void> clearQueue() async {
    await _prefetch?.dispose();
    _prefetch = null;
    await _handler.stop();
    await _queueStore.clear();
    _queueSource = null;
    _scrapeAttempted.clear();
    notifyListeners();
  }

  void _normalizeAccounts(List<TrackInfo> tracks) {
    for (var i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      if (t.accountId.isNotEmpty) continue;
      final id = _accounts.idForSource(t.sourceName) ?? '';
      if (id.isNotEmpty) tracks[i] = _withAccountId(t, id);
    }
  }

  // ---- persistence -------------------------------------------------------

  void _persistQueueSoon() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_persistQueue());
    });
  }

  Future<void> _persistQueue() async {
    final tracks = _handler.tracks;
    if (tracks.isEmpty) {
      await _queueStore.clear();
      return;
    }
    await _queueStore.save(
      PlaybackQueueSnapshot(
        entries: tracks,
        index: _handler.index < 0 ? 0 : _handler.index,
        mode: _playOpenMode,
        source: _queueSource,
      ),
    );
  }

  // ---- auto-scrape missing queue rows ------------------------------------

  /// Queue metadata scrape: one task at a time, in playback order. Library
  /// changes then flow back through [_enrichQueue], so the queue updates
  /// dynamically after the scrape completes.
  void _scheduleMissingScrapes() {
    unawaited(_pumpMissingScrapes());
  }

  /// Missing queue rows are scraped automatically for the network-library
  /// auto-scrape feature, and for library queues only while 自动补齐 is on —
  /// manual mode keeps the library manual (explicit scans still work).
  bool get _autoScrapeQueue {
    if (_settings.musicLibraryAutoBackfill) return true;
    final kind = _queueSource?.kind;
    return kind == PlaybackQueueSourceKind.networkFolder ||
        kind == PlaybackQueueSourceKind.cueAlbum;
  }

  Future<void> _pumpMissingScrapes() async {
    if (_scrapePumping) return;
    if (!_autoScrapeQueue) return;
    _scrapePumping = true;
    try {
      while (true) {
        final entry = _nextUnscrapedEntry();
        if (entry == null) break;
        final key = _scrapeKey(entry);
        if (!_scrapeAttempted.add(key)) continue;
        final accountId = entry.accountId.isNotEmpty
            ? entry.accountId
            : (_accounts.idForSource(entry.sourceName) ?? '');
        if (accountId.isEmpty) continue;
        final path = entry.isCueVirtual
            ? (entry.cueRemotePath ?? '')
            : entry.effectiveAudioRemotePath;
        if (path.isEmpty) continue;
        final name = path.split('/').last;
        final task = await _taskQueue.enqueueScan(
          sourceName: entry.sourceName,
          remotePath: path,
          fileName: name,
          unitsTotal: 1,
          paths: [
            ScanPathEntry(path: path, name: name, isCue: entry.isCueVirtual),
          ],
          priority: 5,
        );
        await _waitForScan(task.id);
      }
    } catch (_) {
      // Best-effort background work; playback must never fail because of it.
    } finally {
      _scrapePumping = false;
    }
  }

  TrackInfo? _nextUnscrapedEntry() {
    final tracks = _handler.tracks;
    if (tracks.isEmpty) return null;
    final start = _handler.index >= 0 ? _handler.index : 0;
    for (var step = 0; step < tracks.length; step++) {
      final t = tracks[(start + step) % tracks.length];
      final key = _scrapeKey(t);
      if (_scrapeAttempted.contains(key)) continue;
      if (_library.find(t.sourceName, t.remotePath) != null) {
        // Already in the library: nothing to scrape, keep the cursor moving.
        _scrapeAttempted.add(key);
        continue;
      }
      return t;
    }
    return null;
  }

  static String _scrapeKey(TrackInfo t) =>
      '${t.sourceName}\u0000${t.isCueVirtual ? (t.cueRemotePath ?? '') : t.effectiveAudioRemotePath}';

  Future<void> _waitForScan(String taskId) async {
    final completer = Completer<void>();
    _scanWaiters[taskId] = completer;
    try {
      await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {},
      );
    } finally {
      _scanWaiters.remove(taskId);
    }
  }

  void _resolveScanWaiters() {
    if (_scanWaiters.isEmpty) return;
    final done = <String>[];
    for (final entry in _scanWaiters.entries) {
      QueueTask? task;
      for (final t in _taskQueue.tasks) {
        if (t.id == entry.key) {
          task = t;
          break;
        }
      }
      if (task == null) continue;
      if (task.status == TaskStatus.completed ||
          task.status == TaskStatus.failed ||
          task.status == TaskStatus.partial ||
          task.status == TaskStatus.cancelled) {
        done.add(entry.key);
      }
    }
    for (final id in done) {
      _scanWaiters.remove(id)?.complete();
    }
  }

  /// Extend a network-folder queue with its subdirectories, using the audio
  /// playlist walk window (Settings → 音乐播放列表 → 搜索子目录/深度).
  ///
  /// Never blocks the first frame: the caller seeds the queue with the current
  /// directory and starts playback first, then this walks in the background.
  /// Current-directory order stays the listing order; subdirectories append in
  /// walk order. [rootListing] reuses the listing the screen already has.
  Future<void> extendNetworkFolderQueue({
    required String accountId,
    required String sourceName,
    required String rootPath,
    required bool includeSubdirs,
    required int maxDepth,
    List<WebDavItem>? rootListing,
  }) async {
    if (!includeSubdirs) return;
    _queueWalkToken++;
    final token = _queueWalkToken;
    try {
      final walker = DirectoryWalker(
        rootPath: rootPath,
        options: WalkOptions(
          includeSubdirs: true,
          maxDepth: WalkOptions.clampDepth(maxDepth),
        ),
      );
      final root = walker.nextDirectory();
      if (root == null) return;
      final rootItems =
          rootListing ??
          await _webDav.listDirectory(
            accountId,
            root,
            fileTypes: _settings.fileTypes,
          );
      walker.acceptChildren(
        root,
        rootItems.where((e) => e.isDirectory).map((e) => e.path),
      );
      final known = <String>{
        for (final t in _handler.tracks) '${t.sourceName}\u0000${t.remotePath}',
      };
      while (token == _queueWalkToken) {
        final dir = walker.nextDirectory();
        if (dir == null) break;
        try {
          final items = await _webDav.listDirectory(
            accountId,
            dir,
            fileTypes: _settings.fileTypes,
          );
          if (token != _queueWalkToken) break;
          walker.acceptChildren(
            dir,
            items.where((e) => e.isDirectory).map((e) => e.path),
          );
          final batch = <TrackInfo>[];
          for (final item in items) {
            if (item.category != FileCategory.music) continue;
            final key = '$sourceName\u0000${item.path}';
            if (!known.add(key)) continue;
            batch.add(
              TrackInfo(
                sourceName: sourceName,
                accountId: accountId,
                remotePath: item.path,
                fileName: item.name,
              ),
            );
          }
          if (batch.isNotEmpty) await appendToQueue(batch);
        } catch (_) {
          // One unreadable subdirectory must not abort the rest of the walk.
        }
      }
    } catch (_) {
      // Best-effort background walk; playback already started from the seed.
    }
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
      unawaited(_maybePlayTriggeredBackfill(track));
      if (_playOpenMode == PlayOpenMode.stream) {
        _startPrefetch(playlist, index, track.accountId);
      } else {
        unawaited(_prefetch?.dispose());
        _prefetch = null;
        unawaited(_warmCacheNeighbors(playlist, index));
      }
    } catch (e) {
      final track = playlist[index];
      // CUE clips need a seekable source. If the remote stream cannot honour
      // start/end (or the server ignores Range), fall back to caching the
      // backing audio once and playing the clip from the local file.
      if (_playOpenMode == PlayOpenMode.stream && track.isCueVirtual) {
        try {
          final cached = await _cache.localPathIfCached(
            track.effectiveAudioRemotePath,
            sourceName: track.sourceName,
          );
          final path =
              cached ??
              await _taskQueue.ensureCachedAndWait(
                track.sourceName,
                track.effectiveAudioRemotePath,
                fileName: track.fileName,
                priority: 10,
              );
          if (path != null) {
            track.localPath = path;
            await _handler.loadAndPlay(
              playlist: playlist,
              startIndex: index,
              playable: PlayableMedia.file(path),
            );
            _error = null;
            unawaited(_clearRemoteMissingMirror(track));
            _startPrefetch(playlist, index, track.accountId);
            return;
          }
        } catch (_) {
          // Fall through to the normal error path.
        }
      }
      _error = e.toString();
      final classified = TaskError.classify(e);
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
    );
    _prefetch!.start(accountId: accountId);
  }

  void _applyMediaItemTags(MediaItem? item) {
    // no-op placeholder — queue metadata is applied by [_enrichQueue].
  }

  Future<void> playPause() async {
    if (_handler.playing) {
      await _handler.pause();
    } else {
      // Restored queue: the handler has the index but nothing has been opened
      // yet (currentPlayableIsLocal == null), so resolve and start for real.
      if (current != null && _handler.currentPlayableIsLocal == null) {
        await _ensureNotificationPermission();
        await _loadAndPlay(_handler.tracks, _handler.index);
        _afterQueueStarted();
      } else if (current == null && _handler.tracks.isNotEmpty) {
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


  /// Auto-backfill: shallow list parent of playing track; scrape missing only.
  ///
  /// When a scrape is enqueued, registers a pending queue-sync that runs only
  /// after that task successfully ingests (see [_onTaskQueueChanged]).
  Future<void> _maybePlayTriggeredBackfill(TrackInfo track) async {
    // Network-folder queues already enumerate the queue's own walk window;
    // their missing rows are scraped by the queue enrichment pump. Discovery
    // of *unknown* files still follows the audio playlist window.
    if (_queueSource?.kind == PlaybackQueueSourceKind.networkFolder) return;
    // CUE slices carry a virtual path; the queue enrichment pump scrapes the
    // real `.cue` path instead.
    if (track.isCueVirtual) return;
    final accountId = track.accountId.trim();
    final remotePath = track.remotePath.trim();
    final sourceName = track.sourceName.trim();
    if (accountId.isEmpty || remotePath.isEmpty || sourceName.isEmpty) return;
    try {
      final task = await enqueuePlayTriggeredShallowScrape(
        settings: _settings,
        accounts: _accounts,
        library: _library,
        webDav: _webDav,
        queue: _taskQueue,
        accountId: accountId,
        sourceName: sourceName,
        remotePath: remotePath,
      );
      if (task == null) {
        // Nothing missing / gated / already scanning — do not touch queue.
        return;
      }
      final parent = remoteParent(remotePath) ?? '/';
      _pendingPlayBackfillSync = _PendingPlayBackfillSync(
        taskId: task.id,
        sourceName: sourceName,
        parentPath: parent,
        accountId: accountId,
      );
    } catch (_) {
      // Best-effort; play must not fail because scrape failed.
    }
  }

  void _onTaskQueueChanged() {
    _resolveScanWaiters();
    final pending = _pendingPlayBackfillSync;
    if (pending == null) return;
    QueueTask? task;
    for (final t in _taskQueue.tasks) {
      if (t.id == pending.taskId) {
        task = t;
        break;
      }
    }
    if (task == null) return;
    if (task.status == TaskStatus.failed ||
        task.status == TaskStatus.cancelled) {
      _pendingPlayBackfillSync = null;
      return;
    }
    if (task.status != TaskStatus.completed) return;
    _pendingPlayBackfillSync = null;
    _syncQueueAfterPlayBackfill(pending);
  }

  /// After play-triggered scrape ingest: add new same-parent library rows to
  /// the in-memory now-playing queue without interrupting playback.
  void _syncQueueAfterPlayBackfill(_PendingPlayBackfillSync pending) {
    final current = _handler.currentTrack;
    if (current == null) return;
    final curSource = current.sourceName.trim();
    final curParent = remoteParent(current.remotePath.trim()) ?? '/';
    // User switched folder/queue before completion → abandon.
    if (curSource != pending.sourceName || curParent != pending.parentPath) {
      return;
    }

    final accountId = pending.accountId.isNotEmpty
        ? pending.accountId
        : (_accounts.idForSource(pending.sourceName) ?? '');
    final siblings = <TrackInfo>[];
    for (final row in _library.tracksForSource(pending.sourceName)) {
      final parent = remoteParent(row.remotePath) ?? '/';
      if (parent != pending.parentPath) continue;
      // Leave localPath null here; resolvePlayable fills it on next play.
      siblings.add(libraryTrackToTrackInfo(row, null, accountId));
    }
    if (siblings.isEmpty) return;
    siblings.sort((a, b) => a.remotePath.compareTo(b.remotePath));

    final queue = List<TrackInfo>.from(_handler.tracks);
    if (queue.isEmpty) return;
    final existing = <String>{
      for (final t in queue)
        if (t.sourceName == pending.sourceName) t.remotePath,
    };
    final toAdd = [
      for (final t in siblings)
        if (!existing.contains(t.remotePath)) t,
    ];
    if (toAdd.isEmpty) return;

    // Insert after the last same-parent item (or after current if none).
    var insertAt = -1;
    final curIdx = _handler.index;
    for (var i = 0; i < queue.length; i++) {
      final t = queue[i];
      if (t.sourceName != pending.sourceName) continue;
      final p = remoteParent(t.remotePath) ?? '/';
      if (p == pending.parentPath) insertAt = i + 1;
    }
    if (insertAt < 0) {
      insertAt = (curIdx + 1).clamp(0, queue.length);
    }

    // Keep remote/library order among newly added tracks.
    queue.insertAll(insertAt, toAdd);
    var newIndex = curIdx;
    if (insertAt <= curIdx) {
      newIndex = curIdx + toAdd.length;
    }
    // Never change which track is current.
    final still = queue[newIndex];
    if (still.sourceName != current.sourceName ||
        still.remotePath != current.remotePath) {
      // Safety: find current by identity.
      final found = queue.indexWhere(
        (t) =>
            t.sourceName == current.sourceName &&
            t.remotePath == current.remotePath,
      );
      if (found < 0) return;
      newIndex = found;
    }

    _handler.replaceQueueKeepingPlayback(tracks: queue, newIndex: newIndex);
    notifyListeners();
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
    _taskQueue.removeListener(_onTaskQueueChanged);
    _library.removeListener(_onLibraryChanged);
    _pendingPlayBackfillSync = null;
    _persistTimer?.cancel();
    unawaited(_persistQueue());
    for (final waiter in _scanWaiters.values) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _scanWaiters.clear();
    unawaited(_prefetch?.dispose());
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _mediaSub?.cancel();
    super.dispose();
  }
}

/// Intent to merge same-parent library rows into the now-playing queue after a
/// play-triggered scrape completes successfully.
class _PendingPlayBackfillSync {
  const _PendingPlayBackfillSync({
    required this.taskId,
    required this.sourceName,
    required this.parentPath,
    required this.accountId,
  });

  final String taskId;
  final String sourceName;
  final String parentPath;
  final String accountId;
}
