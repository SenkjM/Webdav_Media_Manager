import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/download_task.dart';
import '../models/webdav_item.dart';
import '../utils/audio_extensions.dart';
import '../utils/cue_sheet.dart';
import '../utils/track_identity.dart';
import 'cache_service.dart';
import 'download_store.dart';
import 'library_service.dart';
import 'platform_export_service.dart';
import 'webdav_service.dart';

/// Background async download queue. Does not block UI/navigation.
/// Ordering: FIFO by [createdAt]. Only one active download at a time.
///
/// Two destinations (see [DownloadTarget]):
/// * music → app-internal audio cache (the only place playback reads from)
/// * video → the **system gallery** via MediaStore, so downloads show up in
///   the device's video app rather than an app-private folder
class DownloadQueueService extends ChangeNotifier {
  DownloadQueueService({
    required WebDavService webDav,
    required CacheService cache,
    LibraryService? library,
    DownloadStore? store,
    PlatformExportService? export,
    bool Function(String name)? isMusicFile,
  })  : _webDav = webDav,
        _cache = cache,
        _library = library,
        _store = store ?? DownloadStore(),
        _export = export ?? const PlatformExportService(),
        _isMusicFile = isMusicFile ?? isAudioFileName;

  final WebDavService _webDav;
  final CacheService _cache;
  LibraryService? _library;
  final DownloadStore _store;
  final PlatformExportService _export;

  /// Whether a file name is music according to the user's configured
  /// extension sets (`SettingsService.fileTypes.musicExtensions`).
  ///
  /// Must be the single source of truth: the network library classifies entries
  /// with the configured sets, so a hard-coded list here would silently drop
  /// formats the user enabled (e.g. `.m4a`) or reject ones they added.
  bool Function(String name) _isMusicFile;

  /// Re-point the classifier at the current settings (called on init).
  void configureFileTypes(bool Function(String name) isMusicFile) {
    _isMusicFile = isMusicFile;
  }

  final _uuid = const Uuid();

  final List<DownloadTask> _tasks = [];
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, Completer<DownloadTask>> _waiters = {};
  /// CUE cacheGroupId → sheet.tracks.length (for queue UI; not file count).
  final Map<String, int> _cueSongCounts = {};
  /// Sheets captured at enqueue — reuse on ingest (same decode as download).
  final Map<String, CueSheet> _cueSheetsByGroup = {};

  bool _running = false;
  bool _initialized = false;

  void attachLibrary(LibraryService library) {
    _library = library;
  }

  UnmodifiableListView<DownloadTask> get tasks =>
      UnmodifiableListView(_tasks);

  /// After cache files are deleted, mark stale "completed" tasks so enqueue
  /// will re-download. Library clip metadata stays in the DB.
  Future<int> invalidateMissingCompleted() async {
    var n = 0;
    for (final t in List<DownloadTask>.from(_tasks)) {
      if (t.status != DownloadStatus.completed) continue;
      final path = t.localPath;
      if (path != null && File(path).existsSync()) continue;
      t.status = DownloadStatus.cancelled;
      t.localPath = null;
      t.progress = 0;
      t.errorMessage = '缓存已清除，需重新下载';
      await _store.upsert(t);
      n++;
    }
    if (n > 0) notifyListeners();
    return n;
  }

  List<DownloadTask> get pendingTasks =>
      _tasks.where((t) => t.status == DownloadStatus.pending).toList();

  List<DownloadTask> get activeTasks =>
      _tasks.where((t) => t.status == DownloadStatus.active).toList();

  bool get isBusy => activeTasks.isNotEmpty || pendingTasks.isNotEmpty;

  Future<void> init() async {
    if (_initialized) return;
    final loaded = await _store.loadAll();
    for (final t in loaded) {
      if (t.status == DownloadStatus.active) {
        t.status = DownloadStatus.pending;
        t.progress = 0;
        await _store.upsert(t);
      }
      _tasks.add(t);
    }
    _initialized = true;
    notifyListeners();
    unawaited(_pump());
  }

  DownloadTask? taskForRemote(String accountId, String remotePath) {
    try {
      return _tasks.lastWhere(
        (t) => t.accountId == accountId && t.remotePath == remotePath,
      );
    } catch (_) {
      return null;
    }
  }

  /// Progress 0..1 for an in-flight (or cue-group) download of [remotePath].
  double? downloadProgressFor(String accountId, String remotePath) {
    final direct = taskForRemote(accountId, remotePath);
    if (direct != null &&
        (direct.status == DownloadStatus.active ||
            direct.status == DownloadStatus.pending)) {
      return direct.progress.clamp(0.0, 1.0);
    }
    // CUE virtual / audio member: use group average of non-terminal-cancelled tasks.
    final groupId = direct?.cacheGroupId;
    if (groupId != null && groupId.startsWith('cue')) {
      return cueGroupProgress(groupId);
    }
    // Look up by any cue-group member matching this audio path.
    for (final t in _tasks.reversed) {
      if (t.accountId != accountId || t.remotePath != remotePath) continue;
      final gid = t.cacheGroupId;
      if (gid != null && gid.startsWith('cue')) {
        return cueGroupProgress(gid);
      }
    }
    return null;
  }

  double cueGroupProgress(String groupId) {
    final members = _liveCueMembers(groupId);
    if (members.isEmpty) return 0;
    final sum = members.map((t) => t.progress).fold<double>(0, (a, b) => a + b);
    return (sum / members.length).clamp(0.0, 1.0);
  }

  /// Active generation only — ignores cancelled/failed leftovers from prior clears.
  List<DownloadTask> _liveCueMembers(String groupId) {
    final byPath = <String, DownloadTask>{};
    for (final t in _tasks) {
      if (t.cacheGroupId != groupId) continue;
      if (t.status == DownloadStatus.cancelled ||
          t.status == DownloadStatus.failed) {
        continue;
      }
      final prev = byPath[t.remotePath];
      if (prev == null || t.createdAt.isAfter(prev.createdAt)) {
        byPath[t.remotePath] = t;
      }
    }
    return byPath.values.toList();
  }

  int? cueSongCountForGroup(String groupId) => _cueSongCounts[groupId];

  void rememberCueSongCount(String groupId, int count) {
    if (count > 0) _cueSongCounts[groupId] = count;
  }

  TrackUiState uiStateFor(
    String accountId,
    String remotePath, {
    String? playingRemotePath,
    String? playingAccountId,
  }) {
    final cached = _cache.fileForRemote(remotePath, accountId: accountId);
    final task = taskForRemote(accountId, remotePath);
    if (playingRemotePath == remotePath && playingAccountId == accountId) {
      return TrackUiState.playing;
    }
    if (task != null) {
      switch (task.status) {
        case DownloadStatus.pending:
          return TrackUiState.queued;
        case DownloadStatus.active:
          return TrackUiState.downloading;
        case DownloadStatus.failed:
        case DownloadStatus.cancelled:
          return TrackUiState.error;
        case DownloadStatus.completed:
          // Gallery downloads live in the system gallery, not the audio cache,
          // so a completed gallery task alone means "downloaded".
          if (task.isGallery) return TrackUiState.ready;
          break;
      }
    }
    if (cached.existsSync()) {
      return TrackUiState.ready;
    }
    if (task?.status == DownloadStatus.completed &&
        task?.localPath != null &&
        File(task!.localPath!).existsSync()) {
      return TrackUiState.ready;
    }
    // Not downloaded and never explicitly enqueued — show no status chip.
    return TrackUiState.remote;
  }

  /// Enqueue download. If already completed/cached, returns existing task.
  Future<DownloadTask> enqueue(
    String accountId,
    String remotePath, {
    String? fileName,
    bool playWhenReady = false,
    String? cacheGroupId,
  }) async {
    final existingCompleted = _tasks.cast<DownloadTask?>().firstWhere(
          (t) =>
              t!.accountId == accountId &&
              t.remotePath == remotePath &&
              t.status == DownloadStatus.completed &&
              t.localPath != null &&
              File(t.localPath!).existsSync(),
          orElse: () => null,
        );
    if (existingCompleted != null) {
      if (cacheGroupId != null &&
          existingCompleted.cacheGroupId != cacheGroupId) {
        existingCompleted.cacheGroupId = cacheGroupId;
        await _store.upsert(existingCompleted);
      }
      // Refresh tags when file is already cached (re-ingest).
      unawaited(_ingest(existingCompleted));
      return existingCompleted;
    }

    final cachedPath =
        await _cache.localPathIfCached(remotePath, accountId: accountId);
    if (cachedPath != null) {
      final done = DownloadTask(
        id: _uuid.v4(),
        accountId: accountId,
        remotePath: remotePath,
        fileName: fileName ?? remotePath.split('/').last,
        createdAt: DateTime.now(),
        status: DownloadStatus.completed,
        localPath: cachedPath,
        progress: 1.0,
        completedAt: DateTime.now(),
        cacheGroupId: cacheGroupId,
      );
      _tasks.add(done);
      await _store.upsert(done);
      await _ingest(done);
      if (cacheGroupId != null && cacheGroupId.startsWith('cue')) {
        unawaited(_maybeIngestCueGroup(done));
      }
      notifyListeners();
      return done;
    }

    final inFlight = _tasks.cast<DownloadTask?>().firstWhere(
          (t) =>
              t!.accountId == accountId &&
              t.remotePath == remotePath &&
              (t.status == DownloadStatus.pending ||
                  t.status == DownloadStatus.active),
          orElse: () => null,
        );
    if (inFlight != null) {
      return _waitFor(inFlight.id);
    }

    final task = DownloadTask(
      id: _uuid.v4(),
      accountId: accountId,
      remotePath: remotePath,
      fileName: fileName ?? remotePath.split('/').last,
      createdAt: DateTime.now(),
      cacheGroupId: cacheGroupId,
    );
    _tasks.add(task);
    await _store.upsert(task);
    notifyListeners();
    unawaited(_pump());
    return _waitFor(task.id);
  }

  /// Fire-and-forget enqueue when the file is missing and not already queued.
  /// Does not wait for download completion.
  /// Call only from explicit user actions (tap / multi-select download) —
  /// never from browse/list open or cover resolve.
  Future<bool> ensureQueued(
    String accountId,
    String remotePath, {
    String? fileName,
  }) async {
    if (isCueVirtualRemotePath(remotePath)) {
      return false;
    }
    if (!_isMusicFile(fileName ?? remotePath) && !_isMusicFile(remotePath)) {
      return false;
    }
    if (_cache.hasLocalFile(remotePath, accountId: accountId)) {
      return false;
    }
    final existing = taskForRemote(accountId, remotePath);
    if (existing != null) {
      switch (existing.status) {
        case DownloadStatus.pending:
        case DownloadStatus.active:
          return false;
        case DownloadStatus.completed:
          if (existing.localPath != null &&
              File(existing.localPath!).existsSync()) {
            return false;
          }
          break;
        case DownloadStatus.failed:
        case DownloadStatus.cancelled:
          existing.status = DownloadStatus.pending;
          existing.errorMessage = null;
          existing.progress = 0;
          existing.bytesReceived = 0;
          await _store.upsert(existing);
          notifyListeners();
          unawaited(_pump());
          return true;
      }
    }

    final task = DownloadTask(
      id: _uuid.v4(),
      accountId: accountId,
      remotePath: remotePath,
      fileName: fileName ?? remotePath.split('/').last,
      createdAt: DateTime.now(),
    );
    _tasks.add(task);
    await _store.upsert(task);
    notifyListeners();
    unawaited(_pump());
    return true;
  }

  /// Enqueue a download that will be written into the system gallery
  /// (MediaStore `Movies/…`) instead of the app-private audio cache.
  ///
  /// Used for video files: the user asked for downloads to land in the system
  /// gallery, and music playback never reads video files, so no cache copy is
  /// needed. Returns false when the file is already queued/downloaded.
  Future<bool> enqueueGallery(
    String accountId,
    String remotePath, {
    String? fileName,
  }) async {
    final existing = taskForRemote(accountId, remotePath);
    if (existing != null) {
      switch (existing.status) {
        case DownloadStatus.pending:
        case DownloadStatus.active:
        case DownloadStatus.completed:
          return false;
        case DownloadStatus.failed:
        case DownloadStatus.cancelled:
          existing.status = DownloadStatus.pending;
          existing.errorMessage = null;
          existing.progress = 0;
          existing.bytesReceived = 0;
          existing.localPath = null;
          existing.completedAt = null;
          existing.target = DownloadTarget.gallery;
          await _store.upsert(existing);
          notifyListeners();
          unawaited(_pump());
          return true;
      }
    }
    final task = DownloadTask(
      id: _uuid.v4(),
      accountId: accountId,
      remotePath: remotePath,
      fileName: fileName ?? p.basename(remotePath),
      createdAt: DateTime.now(),
      target: DownloadTarget.gallery,
    );
    _tasks.add(task);
    await _store.upsert(task);
    notifyListeners();
    unawaited(_pump());
    return true;
  }

  /// Batch [enqueueGallery] for many items without awaiting each download.
  Future<int> enqueueGalleryMany(
    Iterable<({String accountId, String remotePath, String? fileName})> items,
  ) async {
    var n = 0;
    for (final item in items) {
      if (await enqueueGallery(
        item.accountId,
        item.remotePath,
        fileName: item.fileName,
      )) {
        n++;
      }
    }
    return n;
  }

  /// Latest queue task for a remote path (any status), if any.
  DownloadTask? taskFor(String accountId, String remotePath) =>
      taskForRemote(accountId, remotePath);

  /// Batch [ensureQueued] for many tracks without awaiting each download.
  Future<int> ensureQueuedMany(
    Iterable<({String accountId, String remotePath, String? fileName})> items,
  ) async {
    var n = 0;
    for (final item in items) {
      if (await ensureQueued(
        item.accountId,
        item.remotePath,
        fileName: item.fileName,
      )) {
        n++;
      }
    }
    return n;
  }

  /// Enqueue all audio files under a folder (recursive). Non-blocking.
  Future<int> enqueueFolder(String accountId, String folderPath) async {
    final items = await _webDav.collectAudioRecursive(folderPath);
    for (final item in items) {
      unawaited(enqueue(accountId, item.path, fileName: item.name));
    }
    return items.length;
  }


  Future<int> enqueueCueGroup({
    required String accountId,
    required String cueRemotePath,
    String? cueFileName,
    CueSheet? preParsed,
  }) async {
    final CueSheet sheet;
    if (preParsed != null) {
      sheet = preParsed;
    } else {
      final bytes = await _webDav.readAsBytes(cueRemotePath);
      final parsed = CueSheetParser.tryParse(decodeCueText(bytes));
      if (parsed == null) {
        throw StateError('无法解析的 CUE：需要标准 FILE + TRACK/INDEX');
      }
      sheet = parsed;
    }
    final groupId = cueCacheGroupId(accountId, cueRemotePath);
    rememberCueSongCount(groupId, sheet.tracks.length);
    _cueSheetsByGroup[groupId] = sheet;
    final paths = <String>[cueRemotePath, ...sheet.audioRemotePaths(cueRemotePath)];
    for (final path in paths) {
      await _cache.bindCacheGroup(accountId: accountId, remotePath: path, groupId: groupId);
    }
    // Drop stale cancelled/failed tasks for this group so member counts and
    // allDone checks stay stable across clear-cache + re-download.
    await _pruneDeadCueMembers(groupId, keepPaths: paths.toSet());
    // Register each path once; do not await download completion (prevents races
    // / duplicate jobs when callers also touch member files).
    for (final path in paths) {
      await _offerCueMember(
        accountId,
        path,
        fileName: p.basename(path),
        cacheGroupId: groupId,
      );
    }
    return sheet.tracks.length;
  }

  Future<void> _pruneDeadCueMembers(
    String groupId, {
    required Set<String> keepPaths,
  }) async {
    final dead = _tasks
        .where(
          (t) =>
              t.cacheGroupId == groupId &&
              (t.status == DownloadStatus.cancelled ||
                  t.status == DownloadStatus.failed ||
                  !keepPaths.contains(t.remotePath)),
        )
        .toList();
    for (final t in dead) {
      _tasks.remove(t);
      await _store.delete(t.id);
    }
    if (dead.isNotEmpty) notifyListeners();
  }

  /// Offer a cue-group member into the queue without waiting for completion.
  Future<void> _offerCueMember(
    String accountId,
    String remotePath, {
    String? fileName,
    String? cacheGroupId,
  }) async {
    final existingCompleted = _tasks.cast<DownloadTask?>().firstWhere(
          (t) =>
              t!.accountId == accountId &&
              t.remotePath == remotePath &&
              t.status == DownloadStatus.completed &&
              t.localPath != null &&
              File(t.localPath!).existsSync(),
          orElse: () => null,
        );
    if (existingCompleted != null) {
      if (cacheGroupId != null && existingCompleted.cacheGroupId != cacheGroupId) {
        existingCompleted.cacheGroupId = cacheGroupId;
        await _store.upsert(existingCompleted);
      }
      if (cacheGroupId != null && cacheGroupId.startsWith('cue')) {
        unawaited(_maybeIngestCueGroup(existingCompleted));
      }
      return;
    }

    final cachedPath =
        await _cache.localPathIfCached(remotePath, accountId: accountId);
    if (cachedPath != null) {
      // Already on disk — record completed task in the cue group (no re-download).
      final already = _tasks.cast<DownloadTask?>().firstWhere(
            (t) =>
                t!.accountId == accountId &&
                t.remotePath == remotePath &&
                t.status == DownloadStatus.completed,
            orElse: () => null,
          );
      if (already != null) {
        already.localPath = cachedPath;
        already.progress = 1.0;
        if (cacheGroupId != null) {
          already.cacheGroupId = cacheGroupId;
        }
        await _store.upsert(already);
        if (cacheGroupId != null && cacheGroupId.startsWith('cue')) {
          unawaited(_maybeIngestCueGroup(already));
        }
        notifyListeners();
        return;
      }
      // Reuse a cancelled/failed row for the same path instead of duplicating.
      final reusable = _tasks.cast<DownloadTask?>().firstWhere(
            (t) =>
                t!.accountId == accountId &&
                t.remotePath == remotePath &&
                (t.status == DownloadStatus.cancelled ||
                    t.status == DownloadStatus.failed),
            orElse: () => null,
          );
      if (reusable != null) {
        reusable.status = DownloadStatus.completed;
        reusable.localPath = cachedPath;
        reusable.progress = 1.0;
        reusable.completedAt = DateTime.now();
        reusable.errorMessage = null;
        reusable.cacheGroupId = cacheGroupId;
        await _store.upsert(reusable);
        if (cacheGroupId != null && cacheGroupId.startsWith('cue')) {
          unawaited(_maybeIngestCueGroup(reusable));
        }
        notifyListeners();
        return;
      }
      final done = DownloadTask(
        id: _uuid.v4(),
        accountId: accountId,
        remotePath: remotePath,
        fileName: fileName ?? remotePath.split('/').last,
        createdAt: DateTime.now(),
        status: DownloadStatus.completed,
        localPath: cachedPath,
        progress: 1.0,
        completedAt: DateTime.now(),
        cacheGroupId: cacheGroupId,
      );
      _tasks.add(done);
      await _store.upsert(done);
      if (cacheGroupId != null && cacheGroupId.startsWith('cue')) {
        unawaited(_maybeIngestCueGroup(done));
      }
      notifyListeners();
      return;
    }

    final inFlight = _tasks.cast<DownloadTask?>().firstWhere(
          (t) =>
              t!.accountId == accountId &&
              t.remotePath == remotePath &&
              (t.status == DownloadStatus.pending ||
                  t.status == DownloadStatus.active),
          orElse: () => null,
        );
    if (inFlight != null) {
      if (cacheGroupId != null && inFlight.cacheGroupId != cacheGroupId) {
        inFlight.cacheGroupId = cacheGroupId;
        await _store.upsert(inFlight);
        notifyListeners();
      }
      return;
    }

    // Reuse cancelled/failed task for this path (avoids +1 member each clear).
    final reusable = _tasks.cast<DownloadTask?>().firstWhere(
          (t) =>
              t!.accountId == accountId &&
              t.remotePath == remotePath &&
              (t.status == DownloadStatus.cancelled ||
                  t.status == DownloadStatus.failed),
          orElse: () => null,
        );
    if (reusable != null) {
      reusable.status = DownloadStatus.pending;
      reusable.errorMessage = null;
      reusable.progress = 0;
      reusable.bytesReceived = 0;
      reusable.localPath = null;
      reusable.completedAt = null;
      reusable.cacheGroupId = cacheGroupId;
      await _store.upsert(reusable);
      notifyListeners();
      unawaited(_pump());
      return;
    }

    final task = DownloadTask(
      id: _uuid.v4(),
      accountId: accountId,
      remotePath: remotePath,
      fileName: fileName ?? remotePath.split('/').last,
      createdAt: DateTime.now(),
      cacheGroupId: cacheGroupId,
    );
    _tasks.add(task);
    await _store.upsert(task);
    notifyListeners();
    unawaited(_pump());
  }

  Future<void> _maybeIngestCueGroup(DownloadTask task) async {
    final groupId = task.cacheGroupId;
    if (groupId == null || _library == null) return;
    // Only the live generation — ignore cancelled leftovers from cache clears.
    final members = _liveCueMembers(groupId);
    if (members.isEmpty) return;
    final cueTask = members.cast<DownloadTask?>().firstWhere(
      (t) => t!.remotePath.toLowerCase().endsWith('.cue'),
      orElse: () => null,
    );
    if (cueTask?.localPath == null ||
        !File(cueTask!.localPath!).existsSync()) {
      return;
    }

    // Prefer the sheet parsed at enqueue (same bytes/decode as download).
    // Re-reading the cache file with File.readAsString() used to throw on
    // GBK/UTF-16 CUEs and silently skip library ingest.
    CueSheet? sheet = _cueSheetsByGroup[groupId];
    if (sheet == null) {
      try {
        final bytes = await File(cueTask.localPath!).readAsBytes();
        sheet = CueSheetParser.tryParse(decodeCueText(bytes));
      } catch (e, st) {
        debugPrint('CUE re-parse failed: $e\n$st');
        return;
      }
    }
    if (sheet == null) return;
    rememberCueSongCount(groupId, sheet.tracks.length);
    _cueSheetsByGroup[groupId] = sheet;

    final required = <String>{
      cueTask.remotePath,
      ...sheet.audioRemotePaths(cueTask.remotePath),
    };
    String norm(String path) => normalizeRemotePath(path);
    final membersByNorm = <String, DownloadTask>{
      for (final m in members) norm(m.remotePath): m,
    };
    // Every required path must have a live completed member with file on disk.
    for (final path in required) {
      final m = membersByNorm[norm(path)] ??
          members.cast<DownloadTask?>().firstWhere(
                (t) => t!.remotePath == path,
                orElse: () => null,
              );
      if (m == null ||
          m.status != DownloadStatus.completed ||
          m.localPath == null ||
          !File(m.localPath!).existsSync()) {
        return;
      }
    }
    try {
      await _library!.ingestCueAlbum(
        accountId: cueTask.accountId,
        cueRemotePath: cueTask.remotePath,
        sheet: sheet,
        cacheGroupId: groupId,
        localPathFor: (remote) =>
            _cache.fileForRemote(remote, accountId: cueTask.accountId).path,
      );
      // Re-bind cache annex for backing audio — ingestCueAlbum deletes
      // standalone track rows which previously also wiped annex entries.
      for (final audioRemote in sheet.audioRemotePaths(cueTask.remotePath)) {
        final f = _cache.fileForRemote(
          audioRemote,
          accountId: cueTask.accountId,
        );
        if (f.existsSync()) {
          await _cache.registerCompleted(
            cueTask.accountId,
            audioRemote,
            f.path,
            cacheGroupId: groupId,
          );
        }
      }
    } catch (e, st) {
      debugPrint('CUE library ingest failed: $e\n$st');
    }
  }

  Future<void> _ingest(DownloadTask task) async {
    final lib = _library;
    final local = task.localPath;
    if (lib == null || local == null) return;
    // Non-music (including .cue) must never become library rows. Uses the
    // configured extension sets so custom formats still land in the library.
    if (!_isMusicFile(task.fileName) && !_isMusicFile(task.remotePath)) {
      return;
    }
    // Cue-group audio is expanded into virtual tracks via _maybeIngestCueGroup.
    if (task.cacheGroupId != null && task.cacheGroupId!.startsWith('cue')) {
      return;
    }
    // If this audio is already the backing file of a CUE album, never create a
    // standalone library row (that was the clear+redownload +1 drift).
    final ownedByCue = lib.tracks.any(
      (t) =>
          t.accountId == task.accountId &&
          t.isCueVirtual &&
          (t.audioRemotePath == task.remotePath ||
              t.effectiveAudioRemotePath == task.remotePath),
    );
    if (ownedByCue) return;
    try {
      await lib.ingestDownloaded(
        accountId: task.accountId,
        remotePath: task.remotePath,
        fileName: task.fileName,
        localPath: local,
      );
    } catch (_) {}
  }

  Future<DownloadTask> _waitFor(String id) {
    final existing = _waiters[id];
    if (existing != null) return existing.future;
    final c = Completer<DownloadTask>();
    _waiters[id] = c;
    final task = _tasks.firstWhere((t) => t.id == id);
    if (task.isTerminal) {
      _waiters.remove(id);
      if (task.status == DownloadStatus.completed) {
        c.complete(task);
      } else {
        c.completeError(StateError(task.errorMessage ?? task.status.name));
      }
    }
    return c.future;
  }

  void _completeWaiter(DownloadTask task) {
    final c = _waiters.remove(task.id);
    if (c == null || c.isCompleted) return;
    if (task.status == DownloadStatus.completed) {
      c.complete(task);
    } else {
      c.completeError(StateError(task.errorMessage ?? task.status.name));
    }
  }

  Future<void> cancel(String id) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final task = _tasks[idx];
    if (task.status == DownloadStatus.active) {
      _cancelTokens[id]?.cancel('cancelled');
    }
    if (task.status == DownloadStatus.pending ||
        task.status == DownloadStatus.active) {
      task.status = DownloadStatus.cancelled;
      task.errorMessage = '已取消';
      await _store.upsert(task);
      _completeWaiter(task);
      notifyListeners();
      unawaited(_pump());
    }
  }

  Future<void> retry(String id) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final old = _tasks[idx];
    if (old.status != DownloadStatus.failed &&
        old.status != DownloadStatus.cancelled) {
      return;
    }
    old.status = DownloadStatus.pending;
    old.errorMessage = null;
    old.progress = 0;
    old.bytesReceived = 0;
    await _store.upsert(old);
    notifyListeners();
    unawaited(_pump());
  }

  Future<void> clearCompleted() async {
    final done =
        _tasks.where((t) => t.status == DownloadStatus.completed).toList();
    for (final t in done) {
      _tasks.remove(t);
      await _store.delete(t.id);
    }
    notifyListeners();
  }

  Future<void> remove(String id) async {
    await cancel(id);
    _tasks.removeWhere((t) => t.id == id);
    await _store.delete(id);
    notifyListeners();
  }

  static List<DownloadTask> orderPending(List<DownloadTask> tasks) {
    final pending = tasks
        .where((t) => t.status == DownloadStatus.pending)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return pending;
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final pending = orderPending(_tasks);
        if (pending.isEmpty) break;
        await _runOne(pending.first);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _runOne(DownloadTask task) async {
    if (task.status != DownloadStatus.pending) return;
    task.status = DownloadStatus.active;
    task.progress = 0;
    await _store.upsert(task);
    notifyListeners();

    final token = CancelToken();
    _cancelTokens[task.id] = token;
    if (task.isGallery) {
      await _runGalleryDownload(task, token);
    } else {
      await _runCacheDownload(task, token);
    }
    _cancelTokens.remove(task.id);
  }

  /// Video → system gallery (MediaStore). Never touches the audio cache or the
  /// music library: the file belongs to the user's media library, not the app.
  Future<void> _runGalleryDownload(DownloadTask task, CancelToken token) async {
    final tmpRoot = await getTemporaryDirectory();
    final tmpDir = Directory(p.join(tmpRoot.path, 'gallery_dl'));
    if (!await tmpDir.exists()) await tmpDir.create(recursive: true);
    final tmp = File(p.join(tmpDir.path, '${task.id}.part'));
    try {
      await _webDav.downloadToFile(
        task.remotePath,
        tmp,
        cancelToken: token,
        onProgress: (received, total) {
          task.bytesReceived = received;
          task.bytesTotal = total > 0 ? total : null;
          task.progress = total > 0 ? received / total : 0;
          notifyListeners();
          if (received % (512 * 1024) < 8192) {
            unawaited(_store.upsert(task));
          }
        },
      );
      if (task.status == DownloadStatus.cancelled) return;
      final result = await _export.saveToGallery(
        sourcePath: tmp.path,
        fileName: task.fileName,
        mimeType: galleryMimeFor(task.fileName),
      );
      if (!result.ok) {
        throw StateError(result.error ?? '写入系统相册失败');
      }
      task.localPath = result.uri ?? result.path;
      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.completedAt = DateTime.now();
      task.errorMessage = null;
      await _store.upsert(task);
      _completeWaiter(task);
      notifyListeners();
    } catch (e) {
      if (task.status == DownloadStatus.cancelled || token.isCancelled) {
        task.status = DownloadStatus.cancelled;
        task.errorMessage = '已取消';
      } else {
        task.status = DownloadStatus.failed;
        task.errorMessage = e.toString();
      }
      await _store.upsert(task);
      _completeWaiter(task);
      notifyListeners();
    } finally {
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _runCacheDownload(DownloadTask task, CancelToken token) async {
    final dest =
        _cache.fileForRemote(task.remotePath, accountId: task.accountId);
    final tmp = File('${dest.path}.part');

    try {
      await _webDav.downloadToFile(
        task.remotePath,
        tmp,
        cancelToken: token,
        onProgress: (received, total) {
          task.bytesReceived = received;
          task.bytesTotal = total > 0 ? total : null;
          task.progress = total > 0 ? received / total : 0;
          notifyListeners();
          if (received % (512 * 1024) < 8192) {
            unawaited(_store.upsert(task));
          }
        },
      );
      if (task.status == DownloadStatus.cancelled) return;
      if (await dest.exists()) await dest.delete();
      await tmp.rename(dest.path);
      task.localPath = dest.path;
      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.completedAt = DateTime.now();
      task.errorMessage = null;
      await _cache.registerCompleted(
        task.accountId,
        task.remotePath,
        dest.path,
        cacheGroupId: task.cacheGroupId,
      );
      if (task.cacheGroupId != null && task.cacheGroupId!.startsWith('cue')) {
        unawaited(_maybeIngestCueGroup(task));
      }
      await _store.upsert(task);
      await _ingest(task);
      _completeWaiter(task);
      notifyListeners();
    } catch (e) {
      if (task.status == DownloadStatus.cancelled || token.isCancelled) {
        task.status = DownloadStatus.cancelled;
        task.errorMessage = '已取消';
      } else {
        task.status = DownloadStatus.failed;
        task.errorMessage = e.toString();
      }
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
      await _store.upsert(task);
      _completeWaiter(task);
      notifyListeners();
    }
  }

  Set<String> get downloadingIdentityKeys => _tasks
      .where((t) =>
          t.status == DownloadStatus.active ||
          t.status == DownloadStatus.pending)
      .map((t) => trackIdentityKey(t.accountId, t.remotePath))
      .toSet();

  Map<String, String> get completedIdentityToLocal {
    final map = <String, String>{};
    for (final t in _tasks) {
      if (t.status == DownloadStatus.completed && t.localPath != null) {
        map[trackIdentityKey(t.accountId, t.remotePath)] = t.localPath!;
      }
    }
    return map;
  }
}
