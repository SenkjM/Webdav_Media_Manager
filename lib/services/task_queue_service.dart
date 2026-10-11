import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/file_type_config.dart';
import '../models/queue_task.dart';
import '../models/library_track.dart';
import '../models/webdav_item.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/audio_extensions.dart';
import '../utils/app_snack.dart';
import '../utils/cue_sheet.dart';
import '../utils/l10n_host.dart';
import '../utils/task_error.dart';
import '../utils/track_identity.dart';
import 'cache_service.dart';
import 'cloud_driver.dart';
import 'download_keepalive.dart';
import 'download_notification_service.dart';
import 'task_store.dart';
import 'library_service.dart';
import 'playlist_service.dart';
import 'platform_export_service.dart';
import 'webdav_service.dart';

import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'settings_service.dart';
import 'stream_cover_reader.dart';
import 'tag_service.dart';
import '../models/webdav_stream.dart';
import '../utils/directory_walk.dart';
import '../utils/scan_candidates.dart';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/widgets.dart';

/// Background async task queue. Does not block UI/navigation.
/// Ordering: FIFO by [createdAt]. Only one active download at a time.
///
/// Two destinations (see [DownloadTarget]):
/// * music → app-internal audio cache (the only place playback reads from)
/// * video → the **system gallery** via MediaStore, so downloads show up in
///   the device's video app rather than an app-private folder
class TaskQueueService extends ChangeNotifier with WidgetsBindingObserver {
  TaskQueueService({
    required WebDavService webDav,
    required CacheService cache,
    LibraryService? library,
    PlaylistService? playlists,
    TaskStore? store,
    PlatformExportService? export,
    bool Function(String name)? isMusicFile,
    DownloadNotificationService? notifications,
    String? Function(String sourceName)? accountIdForSource,
    SettingsService? settings,
    DownloadKeepAlive? keepAlive,
  }) : _webDav = webDav,
       _cache = cache,
       _library = library,
       _playlists = playlists,
       _store = store ?? TaskStore(),
       _export = export ?? const PlatformExportService(),
       _notify = notifications ?? DownloadNotificationService(),
       _isMusicFile = isMusicFile ?? isAudioFileName,
       _accountIdForSource = accountIdForSource ?? ((_) => null),
       _settings = settings,
       _keepAlive = keepAlive ?? DownloadKeepAlive() {
    _keepAlive.onTimeout = _onKeepAliveTimeout;
  }

  final WebDavService _webDav;
  final CacheService _cache;

  /// 半截文件清理的上限来自设置（设置 → 下载队列）；测试里可以为 null。
  final SettingsService? _settings;

  /// 下载自己的 dataSync 前台服务。测试可注入；默认不碰通道直到真的要启动。
  final DownloadKeepAlive _keepAlive;

  /// 后台下载保活。默认开；关掉则不启 FGS、不改重试上限。
  bool keepAliveEnabled = true;

  bool _orderedDrainActive = false;
  final Set<String> _fgsTimeoutSuspendIds = <String>{};
  DateTime? _fgsCooldownUntil;
  LibraryService? _library;
  PlaylistService? _playlists;
  final TaskStore _store;
  final PlatformExportService _export;

  /// Resolves a task's binding point (网盘名) to a local WebDAV account.
  ///
  /// The queue persists **names**, never account ids: the account is looked up
  /// when bytes actually move, so renaming / re-adding a disk can never leave a
  /// stale pointer behind (that was the cross-disk download bug).
  String? Function(String sourceName) _accountIdForSource;

  /// Re-point the resolver (called on init / after accounts change).
  Future<void> closeDatabase() => _store.close();

  /// Opens the queue database. The 0.2.2 sentinel migration uses this before
  /// [init] loads tasks.
  Future<Database> openDatabase() => _store.database;

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

  final List<QueueTask> _tasks = [];
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, Completer<QueueTask>> _waiters = {};

  /// CUE cacheGroupId → sheet.tracks.length (for queue UI; not file count).
  final Map<String, int> _cueSongCounts = {};

  /// Sheets captured at enqueue — reuse on ingest (same decode as download).
  final Map<String, CueSheet> _cueSheetsByGroup = {};

  bool _running = false;
  bool _pumpRequested = false;
  bool _initialized = false;

  /// 自动重试上限（网络类错误）。手动点「重试」不受此限。
  static const int maxAutoRetries = 5;

  /// 应用在后台且错误属于 [isOfflineError] 时的自动重试上限。
  /// 前台，以及后台的非 offline 错误，仍用 [maxAutoRetries]。
  static const int backgroundOfflineMaxAutoRetries = 3;

  /// `_handleFailure` 用的上限。后台 offline 为 3，其余为 5。
  static int autoRetryCap({required bool inBackground, required bool offline}) {
    if (inBackground && offline) return backgroundOfflineMaxAutoRetries;
    return maxAutoRetries;
  }

  /// 这次失败还该不该自动再试。取消与不可重试的错误由调用方另判。
  static bool shouldAutoRetry({
    required int attempts,
    required Object error,
    required bool inBackground,
  }) {
    if (!isRetryable(error)) return false;
    return attempts <
        autoRetryCap(
          inBackground: inBackground,
          offline: isOfflineError(error),
        );
  }

  /// 完全没网时的等待时间。网络事件能提前唤醒。次数仍算进 [autoRetryCap]。
  ///
  /// 别调大：断网时用户等的就是这个间隔，5 分钟看起来和「卡死」没区别。
  static const Duration offlineRetryDelay = Duration(seconds: 10);

  Timer? _retryTimer;

  /// 原地重试正等在这次退避上时，网络事件用它提前叫醒。
  Completer<void>? _wake;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// 退避：2/4/8/16/32 秒，加 0~1 秒抖动（抖动避免多任务同时回头打源站）。
  static Duration retryDelay(int attempt) {
    final seconds = 1 << attempt.clamp(1, 5);
    return Duration(milliseconds: seconds * 1000 + Random().nextInt(1000));
  }

  /// 第 [attempts] 次失败后等多久再试。
  ///
  /// 没网固定 10 秒（这时等网络回来最要紧，退避拉长反而像卡死），
  /// 其余按 2/4/8/16/32 退避。**两种情况都算一次尝试**——计数只有一个来源。
  static Duration retryDelayFor(int attempts, {required bool offline}) =>
      offline ? offlineRetryDelay : retryDelay(attempts);

  /// 错误值不值得自动重试。
  ///
  /// **默认倾向可重试**：认不出来的错误也必须落到退避兜底（用户要求），
  /// 只有明确「重试也没用」的才直接判失败。
  static bool isRetryable(Object error) {
    // 内容本身坏了（解密失败）：同一份字节再拉一次还是坏的。
    // 上游错误（含 401 / 403 / 奇怪的授权失败）一律重试，不再按状态码或文案排除。
    if (error is CloudDriverDataException) return false;
    if (error is StateError) return false;
    if (error is DioException && error.type == DioExceptionType.cancel) {
      return false;
    }
    return true;
  }

  /// 这个失败是不是「当前根本没网」（DNS / unreachable）。
  ///
  /// 计数仍走 [autoRetryCap]：后台这类失败最多 3 次，前台与其它错误仍是 5 次。
  static bool isOfflineError(Object error) {
    final text = error is DioException
        ? (error.error ?? error).toString().toLowerCase()
        : error.toString().toLowerCase();
    return text.contains('network is unreachable') ||
        text.contains('network is down') ||
        text.contains('failed host lookup') ||
        text.contains('unable to resolve host') ||
        text.contains('no address associated') ||
        text.contains('nodename nor servname');
  }

  /// Last failure while persisting/starting a task.
  ///
  /// Download errors used to be swallowed (`enqueue(...).ignore()`), so a
  /// broken queue looked exactly like "the button does nothing". The UI can now
  /// surface this instead of lying.
  String? _lastError;
  String? get lastError => _lastError;

  String _describeError(Object e) => TaskError.classify(e).persisted;

  /// List / snackbar: short localized label. Full exception → [describeErrorDetail].
  static String describeError(String raw, AppLocalizations l10n) =>
      TaskError.shortLabel(raw, l10n);

  /// Full original detail for the error dialog (unwraps retry wrappers).
  static String describeErrorDetail(String raw) => TaskError.detailText(raw);

  Future<void> _guardPersist(Future<void> Function() body) async {
    try {
      await body();
      _lastError = null;
    } catch (e) {
      _lastError = _describeError(e);
      debugPrint('TaskQueueService persist failed: $e');
      notifyListeners();
      rethrow;
    }
  }

  void attachLibrary(LibraryService library) {
    _library = library;
  }

  UnmodifiableListView<QueueTask> get tasks => UnmodifiableListView(_tasks);

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
  /// [QueueTask.localPath], so `File(...).existsSync()` is always false for
  /// them and the cache clear never invalidates them.
  Future<int> invalidateMissingCompleted() async {
    var n = 0;
    for (final t in List<QueueTask>.from(_tasks)) {
      if (t.status != TaskStatus.completed) continue;
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

  List<QueueTask> get pendingTasks =>
      _tasks.where((t) => t.status == TaskStatus.pending).toList();

  List<QueueTask> get activeTasks =>
      _tasks.where((t) => t.status == TaskStatus.active).toList();

  bool get isBusy => activeTasks.isNotEmpty || pendingTasks.isNotEmpty;

  Future<void> init() async {
    if (_initialized) return;
    final loaded = await _store.loadAll();
    for (final t in loaded) {
      if (t.status == TaskStatus.active) {
        t.status = TaskStatus.pending;
        t.progress = 0;
        await _store.upsert(t);
      }
      _tasks.add(t);
      if (t.status != TaskStatus.completed) _sessionIds.add(t.id);
    }
    _initialized = true;
    // Timer 在后台会被挂起；回到前台补一次唤醒，别等下一次退避到期。
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
    unawaited(_pump());
    // 启动顺手收拾半截文件，不阻塞队列（.part 是续传的现场，不能无脑删）。
    unawaited(cleanupStaleParts());
    notifyListeners();
    unawaited(_pump());
  }

  QueueTask? taskForRemote(String sourceName, String remotePath) {
    try {
      return _tasks.lastWhere(
        (t) => t.sourceName == sourceName && t.remotePath == remotePath,
      );
    } catch (_) {
      return null;
    }
  }

  /// 同一个远端路径可能同时挂在两条线上（缓存 + 系统下载目录），所以去重按
  /// **(来源, 路径, 目标)** 三段比：只比路径的话，先点缓存再点下载时第二条会
  /// 被静默吞掉，看起来就像按钮没反应。
  QueueTask? taskForRemoteAndTarget(
    String sourceName,
    String remotePath,
    DownloadTarget target,
  ) {
    try {
      return _tasks.lastWhere(
        (t) =>
            t.sourceName == sourceName &&
            t.remotePath == remotePath &&
            t.target == target,
      );
    } catch (_) {
      return null;
    }
  }

  /// Progress 0..1 for an in-flight (or cue-group) download of [remotePath].
  double? downloadProgressFor(String sourceName, String remotePath) {
    final direct = taskForRemote(sourceName, remotePath);
    if (direct != null &&
        (direct.status == TaskStatus.active ||
            direct.status == TaskStatus.pending)) {
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
  List<QueueTask> _liveCueMembers(String groupId) {
    final byPath = <String, QueueTask>{};
    for (final t in _tasks) {
      if (t.cacheGroupId != groupId) continue;
      if (t.status == TaskStatus.cancelled ||
          t.status == TaskStatus.failed) {
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
    bool libraryRow = false,
  }) {
    final cached = _cache.fileForRemote(remotePath, sourceName: sourceName);
    final task = taskForRemote(sourceName, remotePath);
    if (playingRemotePath == remotePath && playingSourceName == sourceName) {
      return TrackUiState.playing;
    }
    if (task != null) {
      switch (task.status) {
        case TaskStatus.pending:
          return TrackUiState.queued;
        case TaskStatus.active:
          return TrackUiState.downloading;
        case TaskStatus.failed:
        case TaskStatus.cancelled:
          return TrackUiState.error;
        case TaskStatus.completed:
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
    if (task?.status == TaskStatus.completed &&
        task?.localPath != null &&
        File(task!.localPath!).existsSync()) {
      return TrackUiState.ready;
    }
    // Library rows without a cache file are still playable via stream.
    if (libraryRow) return TrackUiState.streamable;
    // Network browser: not downloaded and never enqueued — no status chip.
    return TrackUiState.remote;
  }


  /// Enqueue a media-library scrape for one root (file or folder).
  ///
  /// When [paths] is provided (from the UI lightweight walk), it is stored as a
  /// sidecar JSON and used by [_runScan] so execution does not re-list.
  Future<QueueTask> enqueueScan({
    required String sourceName,
    required String remotePath,
    required String fileName,
    int? unitsTotal,
    List<ScanPathEntry>? paths,
  }) async {
    final task = QueueTask(
      id: _uuid.v4(),
      sourceName: sourceName,
      remotePath: remotePath,
      fileName: fileName,
      createdAt: DateTime.now(),
      kind: TaskKind.scan,
      progressMode: TaskProgressMode.units,
      unitsTotal: unitsTotal ?? paths?.length,
      unitsDone: 0,
    );
    if (paths != null && paths.isNotEmpty) {
      final payload = await _scanPayloadFile(task.id);
      await payload.writeAsString(
        jsonEncode([for (final e in paths) e.toJson()]),
        flush: true,
      );
      task.localPath = payload.path;
    }
    _tasks.add(task);
    _sessionIds.add(task.id);
    await _guardPersist(() => _store.upsert(task));
    notifyListeners();
    unawaited(_pump());
    return task;
  }

  Future<File> _scanPayloadFile(String taskId) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'scan_payloads'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, '$taskId.json'));
  }

  Future<List<ScanPathEntry>?> _readScanPayload(QueueTask task) async {
    final path = task.localPath;
    if (path == null || path.isEmpty || !path.endsWith('.json')) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return null;
      return [
        for (final e in raw)
          if (e is Map)
            ScanPathEntry.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      return null;
    }
  }

  /// Cloud retag (+ cover) for one library row.
  Future<QueueTask> enqueueRetagCloud({
    required String sourceName,
    required String remotePath,
    required String fileName,
  }) async {
    final task = QueueTask(
      id: _uuid.v4(),
      sourceName: sourceName,
      remotePath: remotePath,
      fileName: fileName,
      createdAt: DateTime.now(),
      kind: TaskKind.retagCloud,
      progressMode: TaskProgressMode.units,
      unitsTotal: 1,
      unitsDone: 0,
    );
    _tasks.add(task);
    _sessionIds.add(task.id);
    await _guardPersist(() => _store.upsert(task));
    notifyListeners();
    unawaited(_pump());
    return task;
  }

  /// Probe every library row for this source (or all sources) and write red dots.
  Future<QueueTask> enqueueMatchRemote({
    required String sourceName,
    int? unitsTotal,
  }) async {
    final task = QueueTask(
      id: _uuid.v4(),
      sourceName: sourceName,
      remotePath: '/',
      fileName: 'match_remote',
      createdAt: DateTime.now(),
      kind: TaskKind.matchRemote,
      progressMode: TaskProgressMode.units,
      unitsTotal: unitsTotal,
      unitsDone: 0,
    );
    _tasks.add(task);
    _sessionIds.add(task.id);
    await _guardPersist(() => _store.upsert(task));
    notifyListeners();
    unawaited(_pump());
    return task;
  }

  /// Enqueue download. If already completed/cached, returns existing task.
  Future<QueueTask> enqueue(
    String sourceName,
    String remotePath, {
    String? fileName,
    bool playWhenReady = false,
    String? cacheGroupId,
  }) async {
    final existingCompleted = _tasks.cast<QueueTask?>().firstWhere(
      (t) =>
          t!.sourceName == sourceName &&
          t.remotePath == remotePath &&
          t.status == TaskStatus.completed &&
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
      final done = QueueTask(
        id: _uuid.v4(),
        sourceName: sourceName,
        remotePath: remotePath,
        fileName: fileName ?? remotePath.split('/').last,
        createdAt: DateTime.now(),
        status: TaskStatus.completed,
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

    final inFlight = _tasks.cast<QueueTask?>().firstWhere(
      (t) =>
          t!.sourceName == sourceName &&
          t.remotePath == remotePath &&
          (t.status == TaskStatus.pending ||
              t.status == TaskStatus.active),
      orElse: () => null,
    );
    if (inFlight != null) {
      return _waitFor(inFlight.id);
    }

    final task = QueueTask(
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
  /// 批量版：**同一次选中的内容统一走这里**——文件夹该扫的扫、文件直接用，
  /// 扫出来的路径先与已选文件去重，最后按 (来源, 路径, 目标) 入队。
  ///
  /// 界面不该再自己分「文件夹那条路 / 文件那条路」：那样一旦同时选中文件夹
  /// 和里面的文件，同一个路径就会从两个入口各排一次。
  Future<bool> ensureQueued(
    String sourceName,
    String remotePath, {
    String? fileName,
    // 默认缓存：这是「缓存音乐」那条线的入口。
    DownloadTarget target = DownloadTarget.cache,
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
    final existing = taskForRemoteAndTarget(sourceName, remotePath, target);
    if (existing != null) {
      switch (existing.status) {
        case TaskStatus.pending:
        case TaskStatus.active:
          return false;
        case TaskStatus.completed:
          if (existing.localPath != null &&
              File(existing.localPath!).existsSync()) {
            return false;
          }
          break;
        case TaskStatus.failed:
        case TaskStatus.cancelled:
          existing.status = TaskStatus.pending;
          existing.errorMessage = null;
          existing.progress = 0;
          existing.bytesReceived = 0;
          await _guardPersist(() => _store.upsert(existing));
          notifyListeners();
          unawaited(_pump());
          return true;
      }
    }

    final task = QueueTask(
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
    // 去重按**目标**分：同一个文件既可以缓存、也可以下载到系统目录，两条线
    // 互不顶掉（只按路径去重就会让第二条静默失效）。
    final existing = taskForRemoteAndTarget(sourceName, remotePath, target);
    if (existing != null) {
      switch (existing.status) {
        case TaskStatus.pending:
        case TaskStatus.active:
        case TaskStatus.completed:
          return false;
        case TaskStatus.failed:
        case TaskStatus.cancelled:
          existing.status = TaskStatus.pending;
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
    final task = QueueTask(
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
  QueueTask? taskFor(String sourceName, String remotePath) =>
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

  /// 把**一次选中的内容**统一排队：文件夹由后端递归扫描，文件直接用。
  ///
  /// 界面只管「缓存音乐」和「下载」两条线，不自己分文件夹那条路和文件那条
  /// 路——那样一旦同时选中文件夹和里面的文件，同一个路径就会从两个入口各
  /// 排一次。这里先把扫出来的路径与已选文件去重，再按 (来源, 路径, 目标)
  /// 入队。
  ///
  /// [target] 决定去处：[DownloadTarget.cache] 是缓存音乐（只有音频会被
  /// 收下，随后 ingest 进音乐库），其余是系统侧目标（音频、视频、CUE、普通
  /// 文件一律照下，不跳过任何类型）。
  ///
  /// 返回实际入队数、扫描失败的文件夹数、扫到的文件总数（`scanned == 0` 且
  /// 没选文件，说明文件夹本来就是空的）与第一个错误。
  Future<({int ok, int failed, int scanned, Object? firstError})>
  enqueueSelection(
    String sourceName, {
    Iterable<String> folderPaths = const [],
    Iterable<WebDavItem> files = const [],
    required DownloadTarget target,
  }) async {
    final accountId = _accountIdFor(sourceName);
    if (accountId == null) {
      _lastError = 'err.sourceUnbound|$sourceName';
      notifyListeners();
      return (ok: 0, failed: 1, scanned: 0, firstError: _lastError);
    }
    // 选中的文件先占位，扫出来的同路径不再重复入队。
    final pending = <String, String>{};
    for (final f in files) {
      pending.putIfAbsent(f.path, () => f.name);
    }
    var failed = 0;
    Object? firstError;
    for (final folderPath in folderPaths) {
      try {
        final items = await _webDav.collectFilesRecursive(
          accountId,
          folderPath,
        );
        for (final item in items) {
          pending.putIfAbsent(item.path, () => item.name);
        }
      } catch (e) {
        // 一个文件夹扫不动不该拖垮其余的。
        failed++;
        firstError ??= e;
      }
    }
    var ok = 0;
    for (final entry in pending.entries) {
      final queued = target == DownloadTarget.cache
          ? await ensureQueued(
              sourceName,
              entry.key,
              fileName: entry.value,
              target: DownloadTarget.cache,
            )
          : await enqueuePublic(
              sourceName,
              entry.key,
              fileName: entry.value,
              target: target,
            );
      if (queued) ok++;
    }
    return (
      ok: ok,
      failed: failed,
      scanned: pending.length,
      firstError: firstError,
    );
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
        throw StateError('err.sourceUnbound|$sourceName');
      }
      final bytes = await _webDav.readAsBytes(accountId, cueRemotePath);
      final parsed = CueSheetParser.tryParse(decodeCueText(bytes));
      if (parsed == null) {
        throw StateError('err.cueMalformed');
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
              (t.status == TaskStatus.cancelled ||
                  t.status == TaskStatus.failed ||
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
    final existingCompleted = _tasks.cast<QueueTask?>().firstWhere(
      (t) =>
          t!.sourceName == sourceName &&
          t.remotePath == remotePath &&
          t.status == TaskStatus.completed &&
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
      final already = _tasks.cast<QueueTask?>().firstWhere(
        (t) =>
            t!.sourceName == sourceName &&
            t.remotePath == remotePath &&
            t.status == TaskStatus.completed,
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
      final reusable = _tasks.cast<QueueTask?>().firstWhere(
        (t) =>
            t!.sourceName == sourceName &&
            t.remotePath == remotePath &&
            (t.status == TaskStatus.cancelled ||
                t.status == TaskStatus.failed),
        orElse: () => null,
      );
      if (reusable != null) {
        reusable.status = TaskStatus.completed;
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
      final done = QueueTask(
        id: _uuid.v4(),
        sourceName: sourceName,
        remotePath: remotePath,
        fileName: fileName ?? remotePath.split('/').last,
        createdAt: DateTime.now(),
        status: TaskStatus.completed,
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

    final inFlight = _tasks.cast<QueueTask?>().firstWhere(
      (t) =>
          t!.sourceName == sourceName &&
          t.remotePath == remotePath &&
          (t.status == TaskStatus.pending ||
              t.status == TaskStatus.active),
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
    final reusable = _tasks.cast<QueueTask?>().firstWhere(
      (t) =>
          t!.sourceName == sourceName &&
          t.remotePath == remotePath &&
          (t.status == TaskStatus.cancelled ||
              t.status == TaskStatus.failed),
      orElse: () => null,
    );
    if (reusable != null) {
      reusable.status = TaskStatus.pending;
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

    final task = QueueTask(
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

  Future<void> _maybeIngestCueGroup(QueueTask task) async {
    final groupId = task.cacheGroupId;
    if (groupId == null || _library == null) return;
    // Only the live generation — ignore cancelled leftovers from cache clears.
    final members = _liveCueMembers(groupId);
    if (members.isEmpty) return;
    final cueTask = members.cast<QueueTask?>().firstWhere(
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
    final membersByNorm = <String, QueueTask>{
      for (final m in members) norm(m.remotePath): m,
    };
    // Every required path must have a live completed member with file on disk.
    for (final path in required) {
      final m =
          membersByNorm[norm(path)] ??
          members.cast<QueueTask?>().firstWhere(
            (t) => t!.remotePath == path,
            orElse: () => null,
          );
      if (m == null ||
          m.status != TaskStatus.completed ||
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
      // Re-register the backing audio files — ingestCueAlbum deletes
      // standalone track rows that previously also wiped cache group members.
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

  /// Re-read tags from an existing cache file. A CUE selection refreshes its
  /// complete virtual album so cue-file metadata keeps precedence over audio tags.
  Future<bool> refreshTrackTagsFromCache(LibraryTrack track) async {
    final library = _library;
    if (library == null) return false;
    if (!track.isCueVirtual) {
      final localPath = await _cache.localPathForTrack(track);
      if (localPath == null) return false;
      await library.refreshTrackTagsFromFile(
        track: track,
        localPath: localPath,
      );
      return true;
    }

    final cuePath = track.cueRemotePath;
    if (cuePath == null) return false;
    final cueLocal = await _cache.localPathIfCached(
      cuePath,
      sourceName: track.sourceName,
    );
    if (cueLocal == null) return false;
    final sheet = CueSheetParser.tryParse(
      decodeCueText(await File(cueLocal).readAsBytes()),
    );
    if (sheet == null) return false;
    final audioPaths = sheet.audioRemotePaths(cuePath);
    for (final path in audioPaths) {
      if (!await _cache.isCached(path, sourceName: track.sourceName)) {
        return false;
      }
    }
    final groupId =
        track.cacheGroupId ?? cueCacheGroupId(track.sourceName, cuePath);
    await library.ingestCueAlbum(
      sourceName: track.sourceName,
      cueRemotePath: cuePath,
      sheet: sheet,
      cacheGroupId: groupId,
      localPathFor: (remote) =>
          _cache.fileForRemote(remote, sourceName: track.sourceName).path,
    );
    for (final path in audioPaths) {
      final file = _cache.fileForRemote(path, sourceName: track.sourceName);
      if (file.existsSync()) {
        await _cache.registerCompleted(
          track.sourceName,
          path,
          file.path,
          cacheGroupId: groupId,
        );
      }
    }
    return true;
  }

  Future<void> _ingest(QueueTask task) async {
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
      // Every completed cache download ingests current file tags, including a
      // re-download after a library row was restored from cloud backup.
      await lib.ingestDownloaded(
        sourceName: task.sourceName,
        remotePath: task.remotePath,
        fileName: task.fileName,
        localPath: local,
      );
    } catch (_) {}
  }

  Future<QueueTask> _waitFor(String id) {
    final existing = _waiters[id];
    if (existing != null) return existing.future;
    final c = Completer<QueueTask>();
    _waiters[id] = c;
    final task = _tasks.firstWhere((t) => t.id == id);
    if (task.isTerminal) {
      _waiters.remove(id);
      if (task.status == TaskStatus.completed) {
        c.complete(task);
      } else {
        c.completeError(StateError(task.errorMessage ?? task.status.name));
      }
    }
    return c.future;
  }

  void _completeWaiter(QueueTask task) {
    final c = _waiters.remove(task.id);
    if (c == null || c.isCompleted) return;
    if (task.status == TaskStatus.completed) {
      c.complete(task);
    } else {
      c.completeError(StateError(task.errorMessage ?? task.status.name));
    }
  }

  Future<void> cancel(String id) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final task = _tasks[idx];
    if (task.status == TaskStatus.active) {
      _cancelTokens[id]?.cancel('cancelled');
    }
    if (task.status == TaskStatus.pending ||
        task.status == TaskStatus.active) {
      task.status = TaskStatus.cancelled;
      task.errorMessage = 'err.cancelled';
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
    if (old.status != TaskStatus.failed &&
        old.status != TaskStatus.cancelled) {
      return;
    }
    old.status = TaskStatus.pending;
    old.errorMessage = null;
    old.progress = 0;
    old.bytesReceived = 0;
    // 手动重试是明确的用户意图：重置自动重试计数（半截文件仍然复用）。
    old.attempts = 0;
    old.nextRetryAt = null;
    _sessionIds.add(old.id);
    await _store.upsert(old);
    notifyListeners();
    unawaited(_pump());
  }

  /// Wake pending tasks immediately, including those waiting for retry backoff.
  Future<void> downloadWaiting() async {
    for (final task in _tasks) {
      if (task.status == TaskStatus.pending) {
        task.nextRetryAt = null;
        await _store.upsert(task);
      }
    }
    _wake?.complete();
    _wake = null;
    notifyListeners();
    unawaited(_pump());
  }

  /// Resume every non-completed task, resetting failed/cancelled rows.
  Future<void> downloadAll() async {
    for (final task in _tasks) {
      if (task.status == TaskStatus.failed ||
          task.status == TaskStatus.cancelled) {
        task.status = TaskStatus.pending;
        task.errorMessage = null;
        task.progress = 0;
        task.bytesReceived = 0;
        task.nextRetryAt = null;
        task.attempts = 0;
        _sessionIds.add(task.id);
      } else if (task.status == TaskStatus.pending) {
        task.nextRetryAt = null;
      }
      if (task.status != TaskStatus.completed) await _store.upsert(task);
    }
    _wake?.complete();
    _wake = null;
    notifyListeners();
    unawaited(_pump());
  }

  Future<void> cancelAll() async {
    for (final task in List<QueueTask>.from(_tasks)) {
      if (task.status == TaskStatus.pending ||
          task.status == TaskStatus.active) {
        await cancel(task.id);
      }
    }
  }

  Future<void> clearCompleted() async {
    final done = _tasks
        .where((t) => t.status == TaskStatus.completed)
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
    for (final t in List<QueueTask>.from(_tasks)) {
      if (t.status == TaskStatus.active) {
        _cancelTokens[t.id]?.cancel('cleared');
      }
    }
    // Release anyone awaiting a task that will never complete.
    for (final t in List<QueueTask>.from(_tasks)) {
      if (!t.isTerminal) {
        t.status = TaskStatus.cancelled;
        t.errorMessage = 'err.queueCleared';
      }
      final waiter = _waiters.remove(t.id);
      if (waiter != null && !waiter.isCompleted) {
        waiter.completeError(StateError('err.queueCleared'));
      }
    }
    for (final t in List<QueueTask>.from(_tasks)) {
      await _store.delete(t.id);
    }
    _tasks.clear();
    _sessionIds.clear();
    _orderedDrainActive = false;
    _lastError = null;
    unawaited(_stopKeepAliveThenCancelNotifications());
    notifyListeners();
  }

  Future<void> _stopKeepAliveThenCancelNotifications() async {
    _notify.pauseProgressUpdates();
    try {
      await _releaseKeepAliveIfAndroid();
    } finally {
      _notify.resumeProgressUpdates();
    }
    await _notify.cancel();
  }

  static List<QueueTask> orderPending(List<QueueTask> tasks) {
    final now = DateTime.now();
    // 正在等退避 / 等网络的任务不算「可以跑」——否则 _pump 的 while(true)
    // 会空转，而且一个等待中的任务会把整条队列堵在后面。
    final pending =
        tasks
            .where(
              (t) =>
                  t.status == TaskStatus.pending &&
                  (t.kind == TaskKind.download ||
                      t.kind == TaskKind.scan ||
                      t.kind == TaskKind.retagCloud ||
                      t.kind == TaskKind.matchRemote) &&
                  (t.nextRetryAt == null || !t.nextRetryAt!.isAfter(now)),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return pending;
  }

  /// Update count progress for scan / retag (and sync [QueueTask.progress]).
  Future<void> reportUnitsProgress(
    String id, {
    required int done,
    int? total,
  }) async {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final task = _tasks[i];
    task.progressMode = TaskProgressMode.units;
    task.unitsDone = done;
    if (total != null) task.unitsTotal = total;
    task.syncProgressFromCounters();
    await _guardPersist(() => _store.upsert(task));
    notifyListeners();
    _publishProgress();
  }

  /// Push the current queue state into the system notification.
  ///
  /// Called from hot paths (progress ticks, status changes); the notification
  /// service throttles internally so this is cheap enough to call often.
  void _publishProgress() {
    if (!notificationsEnabled && !_keepAlive.holdsOrStarting) return;
    QueueTask? current;
    var running = 0;
    var pendingCount = 0;
    var completed = 0;
    var failed = 0;
    var cancelled = 0;
    for (final t in _tasks) {
      if (!_sessionIds.contains(t.id)) continue;
      switch (t.status) {
        case TaskStatus.active:
          running++;
          current ??= t;
        case TaskStatus.pending:
          pendingCount++;
        case TaskStatus.completed:
          completed++;
        case TaskStatus.failed:
          failed++;
        case TaskStatus.cancelled:
          cancelled++;
      }
    }
    if (running == 0 && pendingCount == 0) {
      // Queue drained. With the keep-alive FGS up, the order is fixed:
      // stop Dart updates of 2001, stopForeground(REMOVE), stopSelf, then 2003.
      // Toggle off keeps today's clear-then-summary path.
      if (_orderedDrainActive) return;
      if (_sessionIds.isEmpty && !_keepAlive.holdsOrStarting) return;
      final postSummary =
          notificationsEnabled && (completed + failed + cancelled > 0);
      _sessionIds.clear();
      if (_keepAlive.holdsOrStarting) {
        _orderedDrainActive = true;
        unawaited(
          _orderedDrain(
            completed: completed,
            failed: failed,
            cancelled: cancelled,
            postSummary: postSummary,
          ),
        );
      } else {
        unawaited(_notify.clearProgress());
        if (postSummary) {
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
      }
      return;
    }
    if (!notificationsEnabled || _notify.progressUpdatesPaused) return;
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
    final l10n = L10nHost.current;
    final parts = <String>[
      l10n.dlDoneOkCount(completed),
      if (failed > 0) l10n.dlDoneFailedCount(failed),
      if (cancelled > 0) l10n.dlDoneCancelledCount(cancelled),
    ];
    return l10n.dlDoneTitle(parts.join(l10n.dlDoneSep));
  }

  /// 排空：先停 Dart 对 2001 的更新，再让原生移除前台通知并 stopSelf，最后才发 2003。
  Future<void> _orderedDrain({
    required int completed,
    required int failed,
    required int cancelled,
    required bool postSummary,
  }) async {
    _notify.pauseProgressUpdates();
    try {
      await _releaseKeepAliveIfAndroid();
    } finally {
      _notify.resumeProgressUpdates();
    }
    try {
      if (!postSummary) return;
      await _notify.showSummary(
        completed: completed,
        failed: failed,
        cancelled: cancelled,
      );
      AppSnack.showGlobal(
        _completionMessage(
          completed: completed,
          failed: failed,
          cancelled: cancelled,
        ),
        error: failed > 0,
      );
    } finally {
      _orderedDrainActive = false;
    }
  }

  /// Best-effort creation of the download notification channel (startup).
  Future<void> initNotifications() => _notify.ensureChannel();

  /// Settings toggle. Turning it off also clears whatever is in the shade.
  Future<void> setNotifications(bool value) async {
    notificationsEnabled = value;
    _notify.enabled = value;
    if (!value) {
      // 保活开着时 2001 是 FGS 通知，不能被「关掉下载通知」清掉。
      if (_keepAlive.holdsOrStarting) {
        await _notify.cancelExceptProgress();
      } else {
        await _notify.cancel();
      }
    } else {
      await _notify.ensureChannel();
      _publishProgress();
    }
  }

  /// 设置里的「后台下载保活」。关 = 立刻拆掉 FGS，2001 回到今天的行为。
  Future<void> setKeepAliveEnabled(bool value) async {
    if (keepAliveEnabled == value) return;
    keepAliveEnabled = value;
    if (!value) {
      _notify.pauseProgressUpdates();
      try {
        await _releaseKeepAliveIfAndroid();
      } finally {
        _notify.resumeProgressUpdates();
      }
      if (notificationsEnabled) {
        _publishProgress();
      } else {
        await _notify.cancel();
      }
      return;
    }
    await _ensureKeepAliveBounded();
  }

  /// 一次下载失败后的统一处理：立刻失败 / 退避重试 / 等网络。
  ///
  /// 文案码不变（`err.dlNetworkInterruptedRetry` / `err.dlOfflineRetryWait` /
  /// `err.dlRetryExhausted`）。次数上限见 [autoRetryCap]：前台 5，后台 offline 3。
  Future<void> _handleFailure(
    QueueTask task,
    Object error, {
    bool cancelled = false,
  }) async {
    if (_takeFgsTimeoutSuspend(task)) {
      task.status = TaskStatus.pending;
      task.nextRetryAt =
          _fgsCooldownUntil ??
          DateTime.now().add(DownloadKeepAlive.timeoutCooldown);
      await _guardPersist(() => _store.upsert(task));
      notifyListeners();
      _publishProgress();
      _scheduleRetryWake();
      return;
    }
    final userCancelled = cancelled || task.status == TaskStatus.cancelled;
    if (!userCancelled) {
      unawaited(_recordFailureDiagnostics(error));
    }
    final offline = isOfflineError(error);
    final inBackground = _isBackground;
    final cap = autoRetryCap(inBackground: inBackground, offline: offline);
    if (userCancelled) {
      task.status = TaskStatus.cancelled;
      task.errorMessage = 'err.cancelled';
      task.nextRetryAt = null;
    } else if (shouldAutoRetry(
      attempts: task.attempts,
      error: error,
      inBackground: inBackground,
    )) {
      // 计数**只有一个来源**：task.attempts。没网也照样 +1 —— 否则
      // 「重试中 (n/5)」会停在原地不动，看起来就是卡死（真机反馈）。
      // 后台 offline 的上限是 3，其余仍是 5；文案码本身不改。
      task.attempts += 1;
      task.nextRetryAt = DateTime.now().add(
        retryDelayFor(task.attempts, offline: offline),
      );
      task.status = TaskStatus.pending;
      task.errorMessage = offline
          ? 'err.dlOfflineRetryWait|${task.attempts}|$cap|'
                '${offlineRetryDelay.inSeconds}'
          : 'err.dlNetworkInterruptedRetry|${task.attempts}|$cap';
    } else {
      task.status = TaskStatus.failed;
      task.nextRetryAt = null;
      // Persist a stable short code + full detail (DNS/timeout/403…), not a Dio dump alone.
      final why = _describeError(error);
      task.errorMessage = task.attempts >= cap
          ? 'err.dlRetryExhausted|$cap|$why'
          : why;
    }
    await _guardPersist(() => _store.upsert(task));
    if (task.status != TaskStatus.pending) _completeWaiter(task);
    notifyListeners();
    _publishProgress();
    if (task.status == TaskStatus.pending) _scheduleRetryWake();
  }

  bool get _isBackground => DownloadKeepAlive.lifecycleIsBackground();

  bool get _queueHasWork => _tasks.any(
    (t) =>
        t.status == TaskStatus.pending || t.status == TaskStatus.active,
  );

  bool _takeFgsTimeoutSuspend(QueueTask task) =>
      _fgsTimeoutSuspendIds.remove(task.id);

  void _onKeepAliveTimeout() {
    unawaited(_suspendQueueForFgsTimeout());
  }

  /// dataSync 配额用尽：停掉的是原生服务。这里把还没完的任务挂起为等待，
  /// 不增加 attempts，也不写新的失败文案。回前台不会自动把已失败的任务捞起来。
  Future<void> _suspendQueueForFgsTimeout() async {
    final until = DateTime.now().add(DownloadKeepAlive.timeoutCooldown);
    _fgsCooldownUntil = until;
    _keepAlive.suppressStartUntil(until);
    for (final task in _tasks) {
      if (task.status == TaskStatus.active) {
        _fgsTimeoutSuspendIds.add(task.id);
        _cancelTokens[task.id]?.cancel('fgs-timeout');
      } else if (task.status == TaskStatus.pending) {
        final when = task.nextRetryAt;
        if (when == null || when.isBefore(until)) {
          task.nextRetryAt = until;
          try {
            await _store.upsert(task);
          } catch (e) {
            debugPrint('DownloadKeepAlive suspend persist failed: $e');
          }
        }
      }
    }
    debugPrint('DownloadKeepAlive onTimeout: queue waiting until $until');
    notifyListeners();
    _scheduleRetryWake();
  }

  Future<void> _recordFailureDiagnostics(Object error) async {
    try {
      String connectivity;
      try {
        final results = await Connectivity().checkConnectivity();
        connectivity = results.map((r) => r.name).join(',');
      } catch (e) {
        connectivity = 'unavailable:$e';
      }
      Map<String, Object?> native = const {};
      if (!kIsWeb && Platform.isAndroid) {
        native = await _keepAlive.diagnostics();
      }
      final dioType = error is DioException ? error.type.name : null;
      debugPrint(
        'DownloadQueue KeepAlive failure '
        'background=$_isBackground '
        'connectivity=$connectivity '
        'offline=${isOfflineError(error)} '
        'dioType=$dioType '
        'fgsRunning=${_keepAlive.isRunning} '
        'phase=${_keepAlive.phase.name} '
        'startError=${_keepAlive.lastStartError} '
        'native=$native '
        'error=$error',
      );
    } catch (e) {
      debugPrint('DownloadQueue KeepAlive diagnostics failed: $e');
    }
  }

  Future<void> _ensureKeepAliveBounded() async {
    if (!keepAliveEnabled) return;
    if (kIsWeb || !Platform.isAndroid) return;
    if (_isBackground) return;
    if (!_queueHasWork) return;
    try {
      await _keepAlive
          .ensureRunning(
            title: L10nHost.current.ntfDownloadingTitle(1, 1),
            notificationId: DownloadNotificationService.currentId,
            channelId: kDownloadChannelId,
            isForeground: () => !_isBackground,
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('DownloadKeepAlive ensure skipped: $e');
    }
  }

  Future<void> _releaseKeepAliveIfAndroid() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _keepAlive.release();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _retryTimer?.cancel();
      unawaited(_pump());
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    unawaited(_connectivitySub?.cancel());
    unawaited(_releaseKeepAliveIfAndroid());
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    super.dispose();
  }

  /// 清理半截文件（.part）。
  ///
  /// 保留 .part 是断点续传的前提，但失败任务堆着不放会吃满磁盘，所以按设置
  /// 里的「保留时长」和「总体积上限」收拾：
  /// * 仍属于未完成任务（pending / active）的**一律保留**——那是续传的现场；
  /// * 其余超过保留时长的删；
  /// * 总量仍超上限时，从最旧的开始删到上限内。
  /// 返回删除的文件数。
  Future<int> cleanupStaleParts() async {
    final maxAge = Duration(
      hours:
          _settings?.downloadPartMaxAgeHours ??
          SettingsService.defaultDownloadPartMaxAgeHours,
    );
    final maxBytes =
        (_settings?.downloadPartMaxMb ??
            SettingsService.defaultDownloadPartMaxMb) *
        1024 *
        1024;
    final now = DateTime.now();
    final alive = <String>{
      for (final t in _tasks)
        if (t.status == TaskStatus.pending ||
            t.status == TaskStatus.active)
          t.id,
    };
    final files = <File>[];
    Future<void> collect(Directory dir) async {
      if (!await dir.exists()) return;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.part')) continue;
        final name = p.basename(entity.path);
        if (alive.any(name.contains)) continue;
        files.add(entity);
      }
    }

    try {
      await collect(_cache.cacheDir);
      await collect(
        Directory(p.join((await getTemporaryDirectory()).path, 'public_dl')),
      );
    } catch (e) {
      debugPrint('TaskQueueService 扫描半截文件失败: $e');
    }
    if (files.isEmpty) return 0;
    final stat = <File, FileStat>{};
    for (final file in files) {
      try {
        stat[file] = await file.stat();
      } catch (_) {}
    }
    final ordered = stat.keys.toList()
      ..sort((a, b) => stat[a]!.modified.compareTo(stat[b]!.modified));
    var removed = 0;
    var total = stat.values.fold<int>(0, (sum, s) => sum + s.size);
    for (final file in ordered) {
      final info = stat[file]!;
      if (total <= maxBytes && now.difference(info.modified) <= maxAge) break;
      try {
        await file.delete();
        total -= info.size;
        removed++;
      } catch (_) {}
    }
    if (removed > 0) {
      debugPrint('TaskQueueService 清理半截文件：$removed 个');
    }
    return removed;
  }

  /// 退避到期自己回来——网络事件是加速器，不是唯一唤醒源。
  void _scheduleRetryWake() {
    final waiting = _tasks
        .where(
          (t) => t.status == TaskStatus.pending && t.nextRetryAt != null,
        )
        .toList();
    if (waiting.isEmpty) return;
    waiting.sort((a, b) => a.nextRetryAt!.compareTo(b.nextRetryAt!));
    final delay = waiting.first.nextRetryAt!.difference(DateTime.now());
    _retryTimer?.cancel();
    _retryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(_pump()),
    );
  }

  /// 网络恢复就叫醒正在等的退避；**不碰任何计数**。
  ///
  /// 早期版本在这里还维护了一套「事件唤醒连败」计数（`_eventStrikes` /
  /// `_ignoreEventUntil`），语义上和 `task.attempts` 撞车，真机表现为
  /// 「一直卡在第二次重试」。兜底的计数只能有一个来源。
  void _listenConnectivity() {
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (!online) return;
      // 原地重试正等在这次退避上：直接叫醒，不用等满。
      if (_wake != null) {
        _wake!.complete();
        _wake = null;
        return;
      }
      if (!_running) unawaited(_pump());
    });
  }

  /// 跑一次任务；连 `_runOne` 自己都没接住的异常也交给统一失败处理。
  ///
  /// 顺带记录这一跑是不是网络事件唤醒的（事件连赔要冷却，见 `_handleFailure`）。
  Future<void> _attempt(QueueTask task) async {
    try {
      await _ensureKeepAliveBounded();
      await _runOne(task);
    } catch (e) {
      // A task that throws before its own try/catch (e.g. a schema error
      // while persisting, or an unresolvable source disk) must not stall the
      // whole queue forever — and the failure has to be **persisted**, or the
      // row stays `active` in the database while memory says failed.
      _lastError = _describeError(e);
      debugPrint('TaskQueueService _runOne failed: $e');
      // 这里也走统一失败处理：认不出来的错误默认按可重试兜底，
      // 而不是把任务直接判死（99 §7.5 之后的下载可靠性要求）。
      await _handleFailure(task, e);
    }
  }

  /// 等这次退避到期；网络事件（`_wake`）会提前叫醒。
  Future<void> _waitForRetry(QueueTask task) async {
    final when = task.nextRetryAt;
    if (when == null) return;
    final delay = when.difference(DateTime.now());
    if (delay <= Duration.zero) return;
    final wake = _wake = Completer<void>();
    try {
      await Future.any(<Future<void>>[
        Future<void>.delayed(delay),
        wake.future,
      ]);
    } finally {
      if (identical(_wake, wake)) _wake = null;
    }
  }

  Future<void> _pump() async {
    if (_running) {
      _pumpRequested = true;
      return;
    }
    _running = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _listenConnectivity();
    try {
      while (true) {
        final pending = orderPending(_tasks);
        if (pending.isEmpty) break;
        final task = pending.first;
        await _attempt(task);
        // 原地重试：任务自己约了下一次尝试，就别把它放回队尾去「等待」——
        // 它继续占着当前这个位置（进度不重置、后面的任务不插队），
        // 列表里也一直显示成这一条在重试。
        while (task.status == TaskStatus.pending &&
            task.nextRetryAt != null) {
          await _waitForRetry(task);
          task.nextRetryAt = null;
          await _attempt(task);
        }
      }
    } finally {
      _running = false;
      // Whatever finished, reflect the drained (or still busy) queue.
      // 保活要留到队列排空，包括还在退避 / 等网络的 pending。
      _publishProgress();
      if (!_queueHasWork &&
          !_orderedDrainActive &&
          _keepAlive.holdsOrStarting) {
        unawaited(_releaseKeepAliveIfAndroid());
      }
      // 还有在等退避 / 等网络的任务：安排下一次唤醒，否则队列就停在这了。
      _scheduleRetryWake();
      if (_pumpRequested) {
        _pumpRequested = false;
        unawaited(_pump());
      }
    }
  }

  Future<void> _runOne(QueueTask task) async {
    if (task.status != TaskStatus.pending) return;
    task.status = TaskStatus.active;
    task.progress = 0;
    task.progressMode = task.kind == TaskKind.download
        ? TaskProgressMode.bytes
        : TaskProgressMode.units;
    await _guardPersist(() => _store.upsert(task));
    notifyListeners();

    final token = CancelToken();
    _cancelTokens[task.id] = token;
    try {
      switch (task.kind) {
        case TaskKind.download:
          if (task.target == DownloadTarget.cache) {
            await _runCacheDownload(task, token);
          } else {
            await _runPublicDownload(task, token);
          }
        case TaskKind.scan:
          await _runScan(task, token);
        case TaskKind.retagCloud:
          await _runRetagCloud(task, token);
        case TaskKind.matchRemote:
          await _runMatchRemote(task, token);
        case TaskKind.retagLocal:
          // Local retag stays interactive (settings); not scheduled here.
          task.status = TaskStatus.cancelled;
          await _guardPersist(() => _store.upsert(task));
      }
    } finally {
      _cancelTokens.remove(task.id);
    }
    // Status changed (one file finished, the next is about to start): refresh the
    // aggregate notification so pending/running counts stay honest.
    _publishProgress();
  }

  /// Public collection download (system gallery for video, Downloads folder for
  /// files with unrecognised extensions). Never touches the audio cache or the
  /// music library: the file belongs to the user, not to the app.
  Future<void> _runPublicDownload(QueueTask task, CancelToken token) async {
    final accountId = _accountIdFor(task.sourceName);
    if (accountId == null) {
      throw StateError('err.sourceUnbound|${task.sourceName}');
    }
    final tmpRoot = await getTemporaryDirectory();
    final tmpDir = Directory(p.join(tmpRoot.path, 'public_dl'));
    if (!await tmpDir.exists()) await tmpDir.create(recursive: true);
    final tmp = File(p.join(tmpDir.path, '${task.id}.part'));
    // 续传：上次失败留下的 .part 还在，就从它的长度继续（源不支持 Range 时
    // downloadResumable 会自己截断重下，不会拼出坏文件）。
    final have = await tmp.exists() ? await tmp.length() : 0;
    try {
      await _webDav.downloadToFile(
        accountId,
        task.remotePath,
        tmp,
        resumeFrom: have,
        cancelToken: token,
        onMode: (mode) => task.downloadMode = mode,
        expectedRemoteSize: task.remoteSize,
        expectedRemoteModified: task.remoteModified,
        onIdentity: (size, modified) {
          task.remoteSize = size;
          task.remoteModified = modified;
        },
        useCryptSequentialDownload:
            _settings?.cryptSequentialDownloadEnabled ?? false,
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
      if (task.status == TaskStatus.cancelled) return;
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
        throw StateError(result.error ?? 'err.writePublicFailed');
      }
      task.localPath = result.uri ?? result.path;
      _fgsTimeoutSuspendIds.remove(task.id);
      task.status = TaskStatus.completed;
      task.progress = 1.0;
      task.completedAt = DateTime.now();
      task.errorMessage = null;
      task.attempts = 0;
      await _store.upsert(task);
      _completeWaiter(task);
      notifyListeners();
      _publishProgress();
    } catch (e) {
      await _handleFailure(
        task,
        e,
        cancelled: task.status == TaskStatus.cancelled || token.isCancelled,
      );
    } finally {
      // 失败时**保留** .part 供下次续传；清理交给 cleanupStaleParts 与设置在管。
      if (task.status == TaskStatus.completed ||
          task.status == TaskStatus.cancelled) {
        if (await tmp.exists()) {
          try {
            await tmp.delete();
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _runCacheDownload(QueueTask task, CancelToken token) async {
    final accountId = _accountIdFor(task.sourceName);
    if (accountId == null) {
      throw StateError('err.sourceUnbound|${task.sourceName}');
    }
    final dest = _cache.fileForRemote(
      task.remotePath,
      sourceName: task.sourceName,
    );
    final tmp = File('${dest.path}.part');
    final have = await tmp.exists() ? await tmp.length() : 0;

    try {
      await _webDav.downloadToFile(
        accountId,
        task.remotePath,
        tmp,
        resumeFrom: have,
        cancelToken: token,
        onMode: (mode) => task.downloadMode = mode,
        expectedRemoteSize: task.remoteSize,
        expectedRemoteModified: task.remoteModified,
        onIdentity: (size, modified) {
          task.remoteSize = size;
          task.remoteModified = modified;
        },
        useCryptSequentialDownload:
            _settings?.cryptSequentialDownloadEnabled ?? false,
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
      if (task.status == TaskStatus.cancelled) return;
      if (await dest.exists()) await dest.delete();
      await tmp.rename(dest.path);
      task.localPath = dest.path;
      _fgsTimeoutSuspendIds.remove(task.id);
      task.status = TaskStatus.completed;
      task.progress = 1.0;
      task.completedAt = DateTime.now();
      task.errorMessage = null;
      task.attempts = 0;
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
      final cancelled =
          task.status == TaskStatus.cancelled || token.isCancelled;
      if (cancelled && await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
      await _handleFailure(task, e, cancelled: cancelled);
    }
  }

  Set<String> get downloadingIdentityKeys => _tasks
      .where(
        (t) =>
            t.status == TaskStatus.active ||
            t.status == TaskStatus.pending,
      )
      .map((t) => trackIdentityKey(t.sourceName, t.remotePath))
      .toSet();

  Map<String, String> get completedIdentityToLocal {
    final map = <String, String>{};
    for (final t in _tasks) {
      if (t.status == TaskStatus.completed && t.localPath != null) {
        map[trackIdentityKey(t.sourceName, t.remotePath)] = t.localPath!;
      }
    }
    return map;
  }

  Future<void> _runScan(QueueTask task, CancelToken token) async {
    final accountId = _accountIdFor(task.sourceName);
    if (accountId == null) {
      throw StateError('err.sourceUnbound|${task.sourceName}');
    }
    final library = _library;
    if (library == null) {
      throw StateError('err.unknown|library unavailable');
    }
    final walk = _settings?.mediaScanWalkOptions ?? const WalkOptions();
    final lower = task.fileName.toLowerCase();
    final rootIsFile = !task.remotePath.endsWith('/') &&
        (_isMusicFile(task.fileName) ||
            _isMusicFile(task.remotePath) ||
            lower.endsWith('.cue') ||
            isCueFileName(task.fileName));
    List<WebDavItem> candidates;
    final prelisted = await _readScanPayload(task);
    if (prelisted != null && prelisted.isNotEmpty) {
      candidates = [for (final e in prelisted) e.toItem()];
    } else {
      candidates = await collectScanCandidates(
        webDav: _webDav,
        accountId: accountId,
        sourceName: task.sourceName,
        rootPath: task.remotePath,
        rootIsFile: rootIsFile,
        walk: walk,
        isMusic: _isMusicFile,
        isCue: isCueFileName,
        alreadyInLibrary: (path) => library.find(task.sourceName, path) != null,
        cueAlbumInLibrary: (cuePath) => library.tracks.any(
          (tr) =>
              tr.sourceName == task.sourceName && tr.cueRemotePath == cuePath,
        ),
        audioCoveredByCue: (audioPath) => library.tracks.any(
          (tr) =>
              tr.sourceName == task.sourceName &&
              tr.audioRemotePath == audioPath,
        ),
        cancel: token,
      );
    }
    task.unitsTotal = candidates.length;
    task.unitsDone = 0;
    task.syncProgressFromCounters();
    await _guardPersist(() => _store.upsert(task));
    notifyListeners();

    final covers = StreamCoverReader();
    // Two-pass: all CUE first (parse + ingest, mark covered audio), then music.
    final cueItems = <WebDavItem>[];
    final musicItems = <WebDavItem>[];
    for (final item in candidates) {
      if (isCueFileName(item.name) || item.category == FileCategory.cue) {
        cueItems.add(item);
      } else {
        musicItems.add(item);
      }
    }
    final coveredByCue = <String>{};
    var done = 0;
    final total = candidates.length;

    Future<bool> bumpOrCancel() async {
      if (token.isCancelled) {
        task.status = TaskStatus.cancelled;
        await _guardPersist(() => _store.upsert(task));
        notifyListeners();
        return true;
      }
      return false;
    }

    for (final item in cueItems) {
      if (await bumpOrCancel()) return;
      try {
        final already = library.tracks.any(
          (tr) =>
              tr.sourceName == task.sourceName &&
              tr.cueRemotePath == item.path,
        );
        if (!already) {
          final bytes = await _webDav.readAsBytes(accountId, item.path);
          final sheet = CueSheetParser.tryParse(decodeCueText(bytes));
          if (sheet == null) {
            throw StateError('err.cueMalformed|${item.path}');
          }
          await library.ingestCueRemote(
            sourceName: task.sourceName,
            cueRemotePath: item.path,
            sheet: sheet,
          );
          coveredByCue.addAll(sheet.audioRemotePaths(item.path));
        }
      } catch (e) {
        if (token.isCancelled ||
            (e is DioException && CancelToken.isCancel(e))) {
          task.status = TaskStatus.cancelled;
          await _guardPersist(() => _store.upsert(task));
          notifyListeners();
          return;
        }
        task.errorMessage = TaskError.classify(e).persisted;
        debugPrint('scan cue failed ${item.path}: $e');
      }
      done++;
      await reportUnitsProgress(task.id, done: done, total: total);
    }

    for (final item in musicItems) {
      if (await bumpOrCancel()) return;
      try {
        if (library.find(task.sourceName, item.path) != null ||
            coveredByCue.contains(item.path)) {
          done++;
          await reportUnitsProgress(task.id, done: done, total: total);
          continue;
        }
        final source = await _webDav.resolveStreamSource(
          remotePath: item.path,
          name: item.name,
          accountId: accountId,
          kind: StreamKind.music,
        );
        if (source == null || source.uri.isEmpty) {
          throw StateError('err.cloud.notFound|${item.path}');
        }
        final tags = await covers.extractTags(source, cancel: token);
        await library.ingestFromTags(
          sourceName: task.sourceName,
          remotePath: item.path,
          fileName: item.name,
          tags: tags ?? const ReadTags(),
        );
      } catch (e) {
        if (token.isCancelled ||
            (e is DioException && CancelToken.isCancel(e))) {
          task.status = TaskStatus.cancelled;
          await _guardPersist(() => _store.upsert(task));
          notifyListeners();
          return;
        }
        task.errorMessage = TaskError.classify(e).persisted;
        debugPrint('scan music failed ${item.path}: $e');
      }
      done++;
      await reportUnitsProgress(task.id, done: done, total: total);
    }

    task.status = TaskStatus.completed;
    task.completedAt = DateTime.now();
    task.progress = 1;
    await _guardPersist(() => _store.upsert(task));
    notifyListeners();
  }

  Future<void> _runRetagCloud(QueueTask task, CancelToken token) async {
    final accountId = _accountIdFor(task.sourceName);
    if (accountId == null) {
      throw StateError('err.sourceUnbound|${task.sourceName}');
    }
    final library = _library;
    if (library == null) {
      throw StateError('err.unknown|library unavailable');
    }
    task.unitsTotal = 1;
    task.unitsDone = 0;
    await reportUnitsProgress(task.id, done: 0, total: 1);
    final source = await _webDav.resolveStreamSource(
      remotePath: task.remotePath,
      name: task.fileName,
      accountId: accountId,
      kind: StreamKind.music,
    );
    if (source == null || source.uri.isEmpty) {
      throw StateError('err.cloud.notFound|${task.remotePath}');
    }
    final tags = await StreamCoverReader().extractTags(source, cancel: token);
    if (tags == null) {
      throw StateError('err.unknown|no tags');
    }
    await library.ingestFromTags(
      sourceName: task.sourceName,
      remotePath: task.remotePath,
      fileName: task.fileName,
      tags: tags,
    );
    await library.clearRemoteMissing(
      sourceName: task.sourceName,
      remotePath: task.remotePath,
    );
    await _playlists?.setRemoteMissingForPath(
      sourceName: task.sourceName,
      remotePath: task.remotePath,
      missing: false,
    );
    task.unitsDone = 1;
    task.status = TaskStatus.completed;
    task.completedAt = DateTime.now();
    task.progress = 1;
    await reportUnitsProgress(task.id, done: 1, total: 1);
    await _guardPersist(() => _store.upsert(task));
    notifyListeners();
  }


  Future<void> _runMatchRemote(QueueTask task, CancelToken token) async {
    final library = _library;
    if (library == null) {
      throw StateError('err.unknown|library unavailable');
    }
    final cache = _cache;
    final targets = <LibraryTrack>[];
    for (final tr in library.tracks) {
      if (task.sourceName.isNotEmpty &&
          task.sourceName != '*' &&
          tr.sourceName != task.sourceName) {
        continue;
      }
      final probePath = tr.isCueVirtual
          ? (tr.audioRemotePath ?? tr.remotePath)
          : tr.remotePath;
      if (cache.hasLocalFile(probePath, sourceName: tr.sourceName)) {
        continue;
      }
      targets.add(tr);
    }
    task.unitsTotal = targets.length;
    task.unitsDone = 0;
    task.syncProgressFromCounters();
    await _guardPersist(() => _store.upsert(task));
    notifyListeners();

    var done = 0;
    for (final tr in targets) {
      if (token.isCancelled) {
        task.status = TaskStatus.cancelled;
        await _guardPersist(() => _store.upsert(task));
        notifyListeners();
        return;
      }
      final accountId = _accountIdFor(tr.sourceName);
      if (accountId == null) {
        done++;
        await reportUnitsProgress(task.id, done: done, total: targets.length);
        continue;
      }
      final probePath = tr.isCueVirtual
          ? (tr.audioRemotePath ?? tr.remotePath)
          : tr.remotePath;
      final probeName = probePath.split('/').where((s) => s.isNotEmpty).last;
      try {
        final exists = await _remoteExists(
          accountId: accountId,
          remotePath: probePath,
          name: probeName.isEmpty ? tr.fileName : probeName,
        );
        if (exists) {
          await library.clearRemoteMissing(
            sourceName: tr.sourceName,
            remotePath: tr.remotePath,
          );
          await _playlists?.setRemoteMissingForIdentities(
            identityKeys: [tr.musicId],
            missing: false,
          );
        } else {
          await library.markRemoteMissing(
            sourceName: tr.sourceName,
            remotePath: tr.remotePath,
          );
          await _playlists?.setRemoteMissingForIdentities(
            identityKeys: [tr.musicId],
            missing: true,
          );
        }
      } catch (e) {
        if (token.isCancelled ||
            (e is DioException && CancelToken.isCancel(e))) {
          task.status = TaskStatus.cancelled;
          await _guardPersist(() => _store.upsert(task));
          notifyListeners();
          return;
        }
        debugPrint('matchRemote unit failed ${tr.remotePath}: $e');
        task.errorMessage = TaskError.classify(e).persisted;
      }
      done++;
      await reportUnitsProgress(task.id, done: done, total: targets.length);
    }
    task.status = TaskStatus.completed;
    task.completedAt = DateTime.now();
    task.progress = 1;
    await _guardPersist(() => _store.upsert(task));
    notifyListeners();
  }

  Future<bool> _remoteExists({
    required String accountId,
    required String remotePath,
    required String name,
  }) async {
    try {
      final item = await _webDav.statPath(accountId, remotePath);
      if (item != null) return true;
    } catch (_) {
      // Fall through to stream resolve (cloud / crypt).
    }
    try {
      final source = await _webDav.resolveStreamSource(
        remotePath: remotePath,
        name: name,
        accountId: accountId,
        kind: StreamKind.music,
      );
      return source != null && source.uri.isNotEmpty;
    } catch (e) {
      final code = TaskError.classify(e).code;
      if (code == 'err.cloud.notFound') {
        return false;
      }
      rethrow;
    }
  }

}
