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
import '../utils/app_snack.dart';
import '../utils/cue_sheet.dart';
import '../utils/track_identity.dart';
import 'cache_service.dart';
import 'download_notification_service.dart';
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
    DownloadNotificationService? notifications,
    String? Function(String sourceName)? accountIdForSource,
  }) : _webDav = webDav,
       _cache = cache,
       _library = library,
       _store = store ?? DownloadStore(),
       _export = export ?? const PlatformExportService(),
       _notify = notifications ?? DownloadNotificationService(),
       _isMusicFile = isMusicFile ?? isAudioFileName,
       _accountIdForSource = accountIdForSource ?? ((_) => null);

  final WebDavService _webDav;
  final CacheService _cache;
  LibraryService? _library;
  final DownloadStore _store;
  final PlatformExportService _export;

  /// Resolves a task's binding point (网盘名) to a local WebDAV account.
  ///
  /// The queue persists **names**, never account ids: the account is looked up
  /// when bytes actually move, so renaming / re-adding a disk can never leave a
  /// stale pointer behind (that was the cross-disk download bug).
  String? Function(String sourceName) _accountIdForSource;

  /// Re-point the resolver (called on init / after accounts change).
  void configureAccountResolver(String? Function(String sourceName) resolve) {
    _accountIdForSource = resolve;
  }

  String? _accountIdFor(String sourceName) => _accountIdForSource(sourceName);

  /// System notifications mirroring the queue.
  final DownloadNotificationService _notify;
  DownloadNotificationService get notificationService => _notify;

  /// Toggles download notifications (wired from Settings).
  bool notificationsEnabled = true;

  /// Ids of the tasks that belong to the **current** transfer session.
  ///
  /// The notification must describe what is happening now, not the whole
  /// persisted history: a queue that already holds twenty completed rows would
  /// otherwise report "0 / 21 已完成" for a single new download. Ids are added
  /// when a task is actually enqueued for transfer and cleared once the queue
  /// drains.
  final Set<String> _sessionIds = <String>{};

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

  /// Last failure while persisting/starting a task.
  ///
  /// Download errors used to be swallowed (`enqueue(...).ignore()`), so a
  /// broken queue looked exactly like "the button does nothing". The UI can now
  /// surface this instead of lying.
  String? _lastError;
  String? get lastError => _lastError;

  String _describeError(Object e) {
    final raw = e.toString();
    // sqflite's "no column named X" is the classic schema-drift symptom.
    if (raw.contains('has no column named')) {
      return '下载队列数据库结构过旧（$raw）。请重启应用以升级数据库。';
    }
    return raw;
  }

  Future<void> _guardPersist(Future<void> Function() body) async {
    try {
      await body();
      _lastError = null;
    } catch (e) {
      _lastError = _describeError(e);
      debugPrint('DownloadQueueService persist failed: $e');
      notifyListeners();
      rethrow;
    }
  }

  void attachLibrary(LibraryService library) {
    _library = library;
  }

  UnmodifiableListView<DownloadTask> get tasks => UnmodifiableListView(_tasks);

  /// After the audio cache is cleared, drop the completed tasks whose file is
  /// gone so the next tap enqueues a fresh download.
  ///
  /// Rows are **deleted**, not marked cancelled: [uiStateFor] maps cancelled to
  /// [TrackUiState.error], which made every previously downloaded row show a red
  /// 「错误」chip after 设置 → 手动清空音频缓存. With the row gone,
  /// `taskForRemote` returns null and the row falls back to
  /// [TrackUiState.remote] — the same look 音乐库 → 删除缓存 already produced.
  ///
  /// Tasks whose file lives outside the audio cache are skipped: gallery /
  /// Downloads entries keep a `content://` URI (or an absolute path) in
  /// [DownloadTask.localPath], so `File(...).existsSync()` is always false for
  /// them and the cache clear never invalidates them.
  Future<int> invalidateMissingCompleted() async {
    var n = 0;
    for (final t in List<DownloadTask>.from(_tasks)) {
      if (t.status != DownloadStatus.completed) continue;
      if (t.isPublic) continue;
      final path = t.localPath;
      if (path != null && File(path).existsSync()) continue;
      _tasks.remove(t);
      await _store.delete(t.id);
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
      if (t.status != DownloadStatus.completed) _sessionIds.add(t.id);
    }
    _initialized = true;
    notifyListeners();
    unawaited(_pump());
  }

  DownloadTask? taskForRemote(String sourceName, String remotePath) {
    try {
      return _tasks.lastWhere(
        (t) => t.sourceName == sourceName && t.remotePath == remotePath,
      );
    } catch (_) {
      return null;
    }
  }

  /// Progress 0..1 for an in-flight (or cue-group) download of [remotePath].
  double? downloadProgressFor(String sourceName, String remotePath) {
    final direct = taskForRemote(sourceName, remotePath);
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
      if (t.sourceName != sourceName || t.remotePath != remotePath) continue;
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
    String sourceName,
    String remotePath, {
    String? playingRemotePath,
    String? playingSourceName,
  }) {
    final cached = _cache.fileForRemote(remotePath, sourceName: sourceName);
    final task = taskForRemote(sourceName, remotePath);
    if (playingRemotePath == remotePath && playingSourceName == sourceName) {
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
          // Public downloads land in the system gallery / Downloads folder
          // rather than the audio cache, so a completed task alone means
          // "downloaded".
          if (task.isPublic) return TrackUiState.ready;
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
    String sourceName,
    String remotePath, {
    String? fileName,
    bool playWhenReady = false,
    String? cacheGroupId,
  }) async {
    final existingCompleted = _tasks.cast<DownloadTask?>().firstWhere(
      (t) =>
          t!.sourceName == sourceName &&
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

    final cachedPath = await _cache.localPathIfCached(
      remotePath,
      sourceName: sourceName,
    );
    if (cachedPath != null) {
      final done = DownloadTask(
        id: _uuid.v4(),
        sourceName: sourceName,
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
      await _guardPersist(() => _store.upsert(done));
      await _ingest(done);
      if (cacheGroupId != null && cacheGroupId.startsWith('cue')) {
        unawaited(_maybeIngestCueGroup(done));
      }
      notifyListeners();
      return done;
    }

    final inFlight = _tasks.cast<DownloadTask?>().firstWhere(
      (t) =>
          t!.sourceName == sourceName &&
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
      sourceName: sourceName,
      remotePath: remotePath,
      fileName: fileName ?? remotePath.split('/').last,
      createdAt: DateTime.now(),
      cacheGroupId: cacheGroupId,
    );
    _tasks.add(task);
    _sessionIds.add(task.id);
    await _guardPersist(() => _store.upsert(task));
    notifyListeners();
    unawaited(_pump());
    return _waitFor(task.id);
  }

  /// Fire-and-forget enqueue when the file is missing and not already queued.
  /// Does not wait for download completion.
  /// Call only from explicit user actions (tap / multi-select download) —
  /// never from browse/list open or cover resolve.
  Future<bool> ensureQueued(
    String sourceName,
    String remotePath, {
    String? fileName,
  }) async {
    if (isCueVirtualRemotePath(remotePath)) {
      return false;
    }
    if (!_isMusicFile(fileName ?? remotePath) && !_isMusicFile(remotePath)) {
      return false;
    }
    if (_cache.hasLocalFile(remotePath, sourceName: sourceName)) {
      return false;
    }
    final existing = taskForRemote(sourceName, remotePath);
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
          await _guardPersist(() => _store.upsert(existing));
          notifyListeners();
          unawaited(_pump());
          return true;
      }
    }

    final task = DownloadTask(
      id: _uuid.v4(),
      sourceName: sourceName,
      remotePath: remotePath,
      fileName: fileName ?? remotePath.split('/').last,
      createdAt: DateTime.now(),
    );
    _tasks.add(task);
    _sessionIds.add(task.id);
    await _guardPersist(() => _store.upsert(task));
    notifyListeners();
    unawaited(_pump());
    return true;
  }

  /// Enqueue a file that should land in a **public** collection rather than the
  /// audio cache: the system gallery for videos, the Downloads folder for files
  /// whose extension is in none of the configured lists.
  ///
  /// Returns false when the file is already queued or already downloaded.
  Future<bool> enqueuePublic(
    String sourceName,
    String remotePath, {
    String? fileName,
    required DownloadTarget target,
  }) async {
    assert(target != DownloadTarget.cache);
    final existing = taskForRemote(sourceName, remotePath);
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
          existing.target = target;
          await _guardPersist(() => _store.upsert(existing));
          notifyListeners();
          unawaited(_pump());
          return true;
      }
    }
    final task = DownloadTask(
      id: _uuid.v4(),
      sourceName: sourceName,
      remotePath: remotePath,
      fileName: fileName ?? p.basename(remotePath),
      createdAt: DateTime.now(),
      target: target,
    );
    _tasks.add(task);
    _sessionIds.add(task.id);
    await _guardPersist(() => _store.upsert(task));
    notifyListeners();
    unawaited(_pump());
    return true;
  }

  /// Video → system gallery.
  Future<bool> enqueueGallery(
    String sourceName,
    String remotePath, {
    String? fileName,
  }) => enqueuePublic(
    sourceName,
    remotePath,
    fileName: fileName,
    target: DownloadTarget.gallery,
  );

  /// Unknown-extension file → public Downloads folder.
  Future<bool> enqueueToDownloads(
    String sourceName,
    String remotePath, {
    String? fileName,
  }) => enqueuePublic(
    sourceName,
    remotePath,
    fileName: fileName,
    target: DownloadTarget.downloads,
  );

  /// Batch [enqueueGallery] for many items without awaiting each download.
  Future<int> enqueueGalleryMany(
    Iterable<({String sourceName, String remotePath, String? fileName})> items,
  ) async {
    var n = 0;
    for (final item in items) {
      if (await enqueueGallery(
        item.sourceName,
        item.remotePath,
        fileName: item.fileName,
      )) {
        n++;
      }
    }
    return n;
  }

  /// Latest queue task for a remote path (any status), if any.
  DownloadTask? taskFor(String sourceName, String remotePath) =>
      taskForRemote(sourceName, remotePath);

  /// Batch [ensureQueued] for many tracks without awaiting each download.
  Future<int> ensureQueuedMany(
    Iterable<({String sourceName, String remotePath, String? fileName})> items,
  ) async {
    var n = 0;
    for (final item in items) {
      if (await ensureQueued(
        item.sourceName,
        item.remotePath,
        fileName: item.fileName,
      )) {
        n++;
      }
    }
    return n;
  }

  /// 把文件夹里的**所有内容**（递归排进系统下载目录队列，返回实际入队数量。
  ///
  /// 下载是基本功能，不挑类型：音频、视频、CUE、普通文件一律照下。跟
  /// 缓存音乐（音频进缓存、随后 ingest 进音乐库）是两条独立的线。
  Future<int> enqueueFoldersToDownloads(
    String sourceName,
    Iterable<String> folderPaths,
  ) async {
    final accountId = _accountIdFor(sourceName);
    if (accountId == null) {
      _lastError = '来源网盘未绑定（）';
      notifyListeners();
      return 0;
    }
    var n = 0;
    for (final folderPath in folderPaths) {
      final items = await _webDav.collectFilesRecursive(
        accountId,
        folderPath,
      );
      for (final item in items) {
        if (await enqueueToDownloads(
          sourceName,
          item.path,
          fileName: item.name,
        )) {
          n++;
        }
      }
    }
    return n;
  }

  /// 多个文件夹一起进缓存队列（递归取音频）。
  ///
  /// 返回实际入队数、失败（扫描出错）的文件夹数，以及第一个错误，供界面
  /// 决定是弹错误框还是只说一声。
  ///
  /// 走 [ensureQueued] 而不是裸 [enqueue]：已在队列里、或本地已有文件的项
  /// 会被跳过，于是多选几个相互嵌套的文件夹、或既选了文件夹又选了里面
  /// 那个音频文件时，不会重复入队。
  Future<({int ok, int failed, Object? firstError})> enqueueFolders(
    String sourceName,
    Iterable<String> folderPaths,
  ) async {
    final accountId = _accountIdFor(sourceName);
    if (accountId == null) {
      _lastError = '来源网盘未绑定（）';
      notifyListeners();
      return (ok: 0, failed: 1, firstError: _lastError);
    }
    var ok = 0;
    var failed = 0;
    Object? firstError;
    for (final folderPath in folderPaths) {
      try {
        final items = await _webDav.collectAudioRecursive(
          accountId,
          folderPath,
        );
        for (final item in items) {
          if (await ensureQueued(
            sourceName,
            item.path,
            fileName: item.name,
          )) {
            ok++;
          }
        }
      } catch (e) {
        // 一个文件夹扫不动不该拖垮其余的。
        failed++;
        firstError ??= e;
      }
    }
    return (ok: ok, failed: failed, firstError: firstError);
  }

  Future<int> enqueueCueGroup({
    required String sourceName,
    required String cueRemotePath,
    String? cueFileName,
    CueSheet? preParsed,
  }) async {
    final CueSheet sheet;
    if (preParsed != null) {
      sheet = preParsed;
    } else {
      final accountId = _accountIdFor(sourceName);
      if (accountId == null) {
        throw StateError('来源网盘未绑定（$sourceName）');
      }
      final bytes = await _webDav.readAsBytes(accountId, cueRemotePath);
      final parsed = CueSheetParser.tryParse(decodeCueText(bytes));
      if (parsed == null) {
        throw StateError('无法解析的 CUE：需要标准 FILE + TRACK/INDEX');
      }
      sheet = parsed;
    }
    final groupId = cueCacheGroupId(sourceName, cueRemotePath);
    rememberCueSongCount(groupId, sheet.tracks.length);
    _cueSheetsByGroup[groupId] = sheet;
    final paths = <String>[
      cueRemotePath,
      ...sheet.audioRemotePaths(cueRemotePath),
    ];
    for (final path in paths) {
      await _cache.bindCacheGroup(
        sourceName: sourceName,
        remotePath: path,
        groupId: groupId,
      );
    }
    // Drop stale cancelled/failed tasks for this group so member counts and
    // allDone checks stay stable across clear-cache + re-download.
    await _pruneDeadCueMembers(groupId, keepPaths: paths.toSet());
    // Register each path once; do not await download completion (prevents races
    // / duplicate jobs when callers also touch member files).
    for (final path in paths) {
      await _offerCueMember(
        sourceName,
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
    String sourceName,
    String remotePath, {
    String? fileName,
    String? cacheGroupId,
  }) async {
    final existingCompleted = _tasks.cast<DownloadTask?>().firstWhere(
      (t) =>
          t!.sourceName == sourceName &&
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
      if (cacheGroupId != null && cacheGroupId.startsWith('cue')) {
        unawaited(_maybeIngestCueGroup(existingCompleted));
      }
      return;
    }

    final cachedPath = await _cache.localPathIfCached(
      remotePath,
      sourceName: sourceName,
    );
    if (cachedPath != null) {
      // Already on disk — record completed task in the cue group (no re-download).
      final already = _tasks.cast<DownloadTask?>().firstWhere(
        (t) =>
            t!.sourceName == sourceName &&
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
            t!.sourceName == sourceName &&
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
        sourceName: sourceName,
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
          t!.sourceName == sourceName &&
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
          t!.sourceName == sourceName &&
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
      sourceName: sourceName,
      remotePath: remotePath,
      fileName: fileName ?? remotePath.split('/').last,
      createdAt: DateTime.now(),
      cacheGroupId: cacheGroupId,
    );
    _tasks.add(task);
    _sessionIds.add(task.id);
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
    if (cueTask?.localPath == null || !File(cueTask!.localPath!).existsSync()) {
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
      final m =
          membersByNorm[norm(path)] ??
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
        sourceName: cueTask.sourceName,
        cueRemotePath: cueTask.remotePath,
        sheet: sheet,
        cacheGroupId: groupId,
        localPathFor: (remote) =>
            _cache.fileForRemote(remote, sourceName: cueTask.sourceName).path,
      );
      // Re-bind cache annex for backing audio — ingestCueAlbum deletes
      // standalone track rows which previously also wiped annex entries.
      for (final audioRemote in sheet.audioRemotePaths(cueTask.remotePath)) {
        final f = _cache.fileForRemote(
          audioRemote,
          sourceName: cueTask.sourceName,
        );
        if (f.existsSync()) {
          await _cache.registerCompleted(
            cueTask.sourceName,
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
          t.sourceName == task.sourceName &&
          t.isCueVirtual &&
          (t.audioRemotePath == task.remotePath ||
              t.effectiveAudioRemotePath == task.remotePath),
    );
    if (ownedByCue) return;
    try {
      await lib.ingestDownloaded(
        sourceName: task.sourceName,
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
    _sessionIds.add(old.id);
    await _store.upsert(old);
    notifyListeners();
    unawaited(_pump());
  }

  Future<void> clearCompleted() async {
    final done = _tasks
        .where((t) => t.status == DownloadStatus.completed)
        .toList();
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

  /// Remove **every** queue entry, cancelling whatever is still running.
  ///
  /// Only touches the queue: files already downloaded stay in the audio cache /
  /// system gallery, and library rows are untouched. The UI asks for
  /// confirmation first because an accidentally cleared queue also loses the
  /// "failed / cancelled" entries the user may still want to retry.
  Future<void> clearAll() async {
    // Cancel in-flight transfers first so no worker keeps writing into a task we
    // are about to drop.
    for (final t in List<DownloadTask>.from(_tasks)) {
      if (t.status == DownloadStatus.active) {
        _cancelTokens[t.id]?.cancel('cleared');
      }
    }
    // Release anyone awaiting a task that will never complete.
    for (final t in List<DownloadTask>.from(_tasks)) {
      if (!t.isTerminal) {
        t.status = DownloadStatus.cancelled;
        t.errorMessage = '队列已清空';
      }
      final waiter = _waiters.remove(t.id);
      if (waiter != null && !waiter.isCompleted) {
        waiter.completeError(StateError('队列已清空'));
      }
    }
    for (final t in List<DownloadTask>.from(_tasks)) {
      await _store.delete(t.id);
    }
    _tasks.clear();
    _sessionIds.clear();
    _lastError = null;
    unawaited(_notify.cancel());
    notifyListeners();
  }

  static List<DownloadTask> orderPending(List<DownloadTask> tasks) {
    final pending =
        tasks.where((t) => t.status == DownloadStatus.pending).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return pending;
  }

  /// Push the current queue state into the system notification.
  ///
  /// Called from hot paths (progress ticks, status changes); the notification
  /// service throttles internally so this is cheap enough to call often.
  void _publishProgress() {
    if (!notificationsEnabled) return;
    DownloadTask? current;
    var running = 0;
    var pendingCount = 0;
    var completed = 0;
    var failed = 0;
    var cancelled = 0;
    for (final t in _tasks) {
      if (!_sessionIds.contains(t.id)) continue;
      switch (t.status) {
        case DownloadStatus.active:
          running++;
          current ??= t;
        case DownloadStatus.pending:
          pendingCount++;
        case DownloadStatus.completed:
          completed++;
        case DownloadStatus.failed:
          failed++;
        case DownloadStatus.cancelled:
          cancelled++;
      }
    }
    if (running == 0 && pendingCount == 0) {
      // Queue drained: the progress notifications go away, the counters reset,
      // and one fresh 「全部下载完成」 notification reports this batch.
      _sessionIds.clear();
      unawaited(_notify.clearProgress());
      if (completed + failed + cancelled > 0) {
        unawaited(
          _notify.showSummary(
            completed: completed,
            failed: failed,
            cancelled: cancelled,
          ),
        );
        // The same batch, once, in-app — the queue has no BuildContext, so this
        // goes through AppSnack's global slot.
        AppSnack.showGlobal(
          _completionMessage(
            completed: completed,
            failed: failed,
            cancelled: cancelled,
          ),
          error: failed > 0,
        );
      }
      return;
    }
    final done = completed + failed + cancelled;
    unawaited(
      _notify.showProgress(
        index: done + 1,
        // Counted from the live entries rather than `_sessionIds.length`: a task
        // the user deleted from the queue mid-batch must not inflate the total.
        total: done + running + pendingCount,
        done: done,
        currentName: current?.fileName,
        fileProgress: current?.progress ?? 0,
      ),
    );
  }

  /// One line for a finished batch, e.g. 「下载完成：成功 3 首」.
  static String _completionMessage({
    required int completed,
    required int failed,
    required int cancelled,
  }) {
    final parts = <String>[
      '成功 $completed',
      if (failed > 0) '失败 $failed',
      if (cancelled > 0) '取消 $cancelled',
    ];
    return '下载完成：${parts.join(' · ')}';
  }

  /// Best-effort creation of the download notification channel (startup).
  Future<void> initNotifications() => _notify.ensureChannel();

  /// Settings toggle. Turning it off also clears whatever is in the shade.
  Future<void> setNotifications(bool value) async {
    notificationsEnabled = value;
    _notify.enabled = value;
    if (!value) {
      await _notify.cancel();
    } else {
      await _notify.ensureChannel();
      _publishProgress();
    }
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final pending = orderPending(_tasks);
        if (pending.isEmpty) break;
        final task = pending.first;
        try {
          await _runOne(task);
        } catch (e) {
          // A task that throws before its own try/catch (e.g. a schema error
          // while persisting, or an unresolvable source disk) must not stall the
          // whole queue forever — and the failure has to be **persisted**, or the
          // row stays `active` in the database while memory says failed.
          _lastError = _describeError(e);
          task.status = DownloadStatus.failed;
          task.errorMessage = _lastError;
          debugPrint('DownloadQueueService _runOne failed: $e');
          await _guardPersist(() => _store.upsert(task));
          notifyListeners();
        }
      }
    } finally {
      _running = false;
      // Whatever finished, reflect the drained (or still busy) queue.
      _publishProgress();
    }
  }

  Future<void> _runOne(DownloadTask task) async {
    if (task.status != DownloadStatus.pending) return;
    task.status = DownloadStatus.active;
    task.progress = 0;
    await _guardPersist(() => _store.upsert(task));
    notifyListeners();

    final token = CancelToken();
    _cancelTokens[task.id] = token;
    if (task.target == DownloadTarget.cache) {
      await _runCacheDownload(task, token);
    } else {
      await _runPublicDownload(task, token);
    }
    _cancelTokens.remove(task.id);
    // Status changed (one file finished, the next is about to start): refresh the
    // aggregate notification so pending/running counts stay honest.
    _publishProgress();
  }

  /// Public collection download (system gallery for video, Downloads folder for
  /// files with unrecognised extensions). Never touches the audio cache or the
  /// music library: the file belongs to the user, not to the app.
  Future<void> _runPublicDownload(DownloadTask task, CancelToken token) async {
    final accountId = _accountIdFor(task.sourceName);
    if (accountId == null) {
      throw StateError('来源网盘未绑定（）');
    }
    final tmpRoot = await getTemporaryDirectory();
    final tmpDir = Directory(p.join(tmpRoot.path, 'public_dl'));
    if (!await tmpDir.exists()) await tmpDir.create(recursive: true);
    final tmp = File(p.join(tmpDir.path, '${task.id}.part'));
    try {
      await _webDav.downloadToFile(
        accountId,
        task.remotePath,
        tmp,
        cancelToken: token,
        onProgress: (received, total) {
          task.bytesReceived = received;
          task.bytesTotal = total > 0 ? total : null;
          task.progress = total > 0 ? received / total : 0;
          notifyListeners();
          _publishProgress();
          if (received % (512 * 1024) < 8192) {
            unawaited(_store.upsert(task));
          }
        },
      );
      if (task.status == DownloadStatus.cancelled) return;
      final result = task.target == DownloadTarget.gallery
          ? await _export.saveToGallery(
              sourcePath: tmp.path,
              fileName: task.fileName,
              mimeType: galleryMimeFor(task.fileName),
            )
          : await _export.saveToDownloads(
              sourcePath: tmp.path,
              fileName: task.fileName,
              mimeType: galleryMimeFor(task.fileName),
            );
      if (!result.ok) {
        throw StateError(result.error ?? '写入公共目录失败');
      }
      task.localPath = result.uri ?? result.path;
      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.completedAt = DateTime.now();
      task.errorMessage = null;
      await _store.upsert(task);
      _completeWaiter(task);
      notifyListeners();
      _publishProgress();
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
    final accountId = _accountIdFor(task.sourceName);
    if (accountId == null) {
      throw StateError('来源网盘未绑定（）');
    }
    final dest = _cache.fileForRemote(
      task.remotePath,
      sourceName: task.sourceName,
    );
    final tmp = File('${dest.path}.part');

    try {
      await _webDav.downloadToFile(
        accountId,
        task.remotePath,
        tmp,
        cancelToken: token,
        onProgress: (received, total) {
          task.bytesReceived = received;
          task.bytesTotal = total > 0 ? total : null;
          task.progress = total > 0 ? received / total : 0;
          notifyListeners();
          _publishProgress();
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
        task.sourceName,
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
      .where(
        (t) =>
            t.status == DownloadStatus.active ||
            t.status == DownloadStatus.pending,
      )
      .map((t) => trackIdentityKey(t.sourceName, t.remotePath))
      .toSet();

  Map<String, String> get completedIdentityToLocal {
    final map = <String, String>{};
    for (final t in _tasks) {
      if (t.status == DownloadStatus.completed && t.localPath != null) {
        map[trackIdentityKey(t.sourceName, t.remotePath)] = t.localPath!;
      }
    }
    return map;
  }
}
