import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../models/queue_models.dart';
import '../utils/app_snack.dart';
import '../utils/l10n_host.dart';
import '../utils/scan_candidates.dart';
import '../utils/task_error.dart';
import '../utils/track_identity.dart';
import 'cache_service.dart';
import 'download_keepalive.dart';
import 'download_notification_service.dart';
import 'platform_export_service.dart';
import 'rust_core_service.dart';
import 'settings_service.dart';

/// True when the remote path names a virtual CUE track (`song.cue#3`).
bool _isCueVirtual(String remotePath) {
  // A CUE clip is never downloaded as a standalone file; the whole sheet is.
  return isCueVirtualRemotePath(remotePath);
}

/// Thin Dart edge over the Rust task queue (`crates/wdmm-queue`).
///
/// Every decision — ordering, retry/backoff, batch closing, session drain,
/// silent batches — is made by Rust. This class only:
///
/// * installs paths once (`wdmm_queue_set_paths`),
/// * issues commands and reads the folded `rows` / `events` / `snapshot` view,
/// * renders progress + completion through the existing Android notification and
///   foreground-service wrappers,
/// * answers `platform_request` events (SAF/MediaStore) via [PlatformExportService].
///
/// No queue state machine lives here. The only mutable Dart state is the
/// mirror used for rendering ([tasks], [rows], [session]).
class QueueService extends ChangeNotifier with WidgetsBindingObserver {
  QueueService({
    required SettingsService settings,
    required CacheService cache,
    required DownloadKeepAlive keepAlive,
    DownloadNotificationService? notifications,
    PlatformExportService platformExport = const PlatformExportService(),
    String? Function(String sourceName)? accountIdForSource,
  }) : _settings = settings,
       _cache = cache,
       _keepAlive = keepAlive,
       _notifications = notifications ?? DownloadNotificationService(),
       _platformExport = platformExport,
       _accountIdForSource = accountIdForSource ?? ((_) => null) {
    _keepAlive.onTimeout = _onKeepAliveTimeout;
  }

  static const Duration pollForeground = Duration(milliseconds: 200);
  static const Duration pollBackground = Duration(seconds: 1);
  static const Duration rowsRefreshMinGap = Duration(milliseconds: 250);

  /// FFI `since_seq` sentinel used to skip the existing ring on first poll.
  static const int _hugeSeq = 0x7FFFFFFFFFFFFFFF;

  final SettingsService _settings;
  final CacheService _cache;
  final DownloadKeepAlive _keepAlive;
  final DownloadNotificationService _notifications;
  final PlatformExportService _platformExport;
  final String? Function(String sourceName) _accountIdForSource;

  DownloadNotificationService get notificationService => _notifications;
  DownloadKeepAlive get keepAlive => _keepAlive;

  bool _initialized = false;
  bool get initialized => _initialized;

  bool _disposed = false;
  bool _background = false;
  bool _notificationsEnabled = false;
  bool _keepAliveEnabled = false;

  String? _appDocsPath;
  String? _lastError;
  String? get lastError => _lastError;

  int _rev = 0;
  int _sinceSeq = 0;

  List<QueueTask> _tasks = const [];
  List<QueueBatch> _batches = const [];
  List<QueueRow> _rows = const [];
  Map<String, QueueTask> _byId = const {};
  QueueSession _session = const QueueSession.initial();

  Timer? _pollTimer;
  Timer? _rowsTimer;
  DateTime? _lastRowsFetch;
  bool _polling = false;
  bool _rowsFetching = false;
  bool _rowsDirty = false;

  /// Non-silent task ids in the current notification session.
  final Set<String> _sessionIds = {};

  List<QueueTask> get tasks => _tasks;
  List<QueueBatch> get batches => _batches;
  List<QueueRow> get rows => _rows;
  QueueSession get session => _session;
  QueueTask? taskById(String id) => _byId[id];

  bool get notificationsEnabled => _notificationsEnabled;
  bool get keepAliveEnabled => _keepAliveEnabled;

  bool get isBusy => _tasks.any(
    (t) =>
        t.status == QueueTaskStatus.pending ||
        t.status == QueueTaskStatus.active ||
        t.status == QueueTaskStatus.awaitingPlatform,
  );

  int get activeCount => _tasks
      .where((t) => t.status == QueueTaskStatus.active)
      .length;

  // ── Init / lifecycle ──────────────────────────────────────────────────────

  /// Install the queue paths and load the first snapshot.
  ///
  /// [appDocs] is `getApplicationDocumentsDirectory()`; [cacheRoot] is
  /// `getApplicationSupportDirectory()` (cache lives under it, not under the
  /// system cache dir). Must run after the library DB is initialized — Rust
  /// refuses otherwise with `err.notInitialized|call wdmm_library_init first`.
  Future<void> init({
    required String appDocs,
    required String cacheRoot,
  }) async {
    if (_initialized || _disposed) return;
    final docs = Directory(appDocs);
    _appDocsPath = docs.path;
    _applySnapshot({
      'ok': true,
      ...?_decodeOrNull(
        RustCoreService.queueSetPaths(
          appDocs: docs.path,
          cacheRoot: cacheRoot,
        ),
        throwOnError: true,
      ),
    });
    WidgetsBinding.instance.addObserver(this);
    _background =
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
    await _keepAlive.restoreSuppression();
    await _fetchRows();
    _restoreSessionFromSnapshot();
    _sinceSeq = 0;
    // Prime the event cursor without replaying history into notifications.
    await _pollEvents(skipHistory: true);
    _initialized = true;
    notifyListeners();
    _schedulePoll();
    unawaited(cleanupStaleParts());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final background = state != AppLifecycleState.resumed;
    if (background == _background) return;
    _background = background;
    if (_background) {
      _ensureKeepAliveBounded();
    } else {
      unawaited(_keepAlive.restoreSuppression());
      unawaited(_pollEvents());
      _ensureKeepAliveBounded();
    }
    _schedulePoll();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    _rowsTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _keepAlive.onTimeout = null;
    unawaited(_keepAlive.release());
    unawaited(_stopNativeQueue());
    super.dispose();
  }

  Future<void> _stopNativeQueue() async {
    try {
      RustCoreService.queueCmd('{"cmd":"shutdown"}');
    } catch (_) {
      // App is going away; the process teardown is authoritative.
    }
  }

  // ── Commands ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _cmd(Map<String, dynamic> body) async {
    final raw = RustCoreService.queueCmd(jsonEncode(body));
    final map = _decodeOrNull(raw, throwOnError: true)!;
    _lastError = null;
    _applySnapshot(map);
    _scheduleRowsRefresh();
    notifyListeners();
    _ensureKeepAliveBounded();
    return map;
  }

  Map<String, dynamic>? _decodeOrNull(String? raw, {bool throwOnError = false}) {
    if (raw == null) {
      const error = 'err.ffi|queue unavailable';
      _lastError = error;
      if (throwOnError) throw StateError(error);
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      _lastError = 'err.ffi|bad queue json: $e';
      if (throwOnError) throw StateError(_lastError!);
      return null;
    }
    if (decoded is! Map) {
      _lastError = 'err.ffi|bad queue reply';
      if (throwOnError) throw StateError(_lastError!);
      return null;
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['ok'] != true) {
      final error = map['error']?.toString() ?? 'err.unknown|queue';
      _lastError = error;
      if (throwOnError) throw StateError(error);
      return null;
    }
    return map;
  }

  /// Enqueue one task. Returns the (possibly deduped) task.
  Future<QueueTask> enqueue({
    required QueueTaskKind kind,
    required String sourceName,
    required String remotePath,
    required String fileName,
    QueueTarget target = QueueTarget.cache,
    int priority = 0,
    String? batchId,
    String? batchLabel,
    QueueBatchOrigin batchOrigin = QueueBatchOrigin.user,
    String? cacheGroupId,
    Object? payload,
    int? unitsTotal,
    int? remoteSize,
    DateTime? remoteModified,
    bool dedupe = true,
    String? treeUri,
    String? localPath,
    String? localUri,
    String? mangaId,
  }) async {
    final accountId = _accountIdForSource(sourceName);
    // A public download heads for a user-picked SAF tree when one is set; the
    // job (wdmm-jobs::download) reads `tree_uri` from its payload sidecar.
    final effectivePayload = (treeUri == null || treeUri.isEmpty)
        ? payload
        : <String, dynamic>{'tree_uri': treeUri};
    final body = <String, dynamic>{
      'cmd': 'enqueue',
      'kind': kind.wireName,
      'source_name': sourceName,
      'account_id': accountId,
      'remote_path': remotePath,
      'file_name': fileName,
      'target': target.wireName,
      'priority': priority,
      'batch_origin': batchOrigin.wireName,
      'dedupe': dedupe,
    };
    if (batchId != null) body['batch_id'] = batchId;
    if (batchLabel != null) body['batch_label'] = batchLabel;
    if (cacheGroupId != null) body['cache_group_id'] = cacheGroupId;
    if (effectivePayload != null) body['payload'] = effectivePayload;
    if (remoteSize != null) body['remote_size'] = remoteSize;
    if (remoteModified != null) {
      body['remote_modified'] = remoteModified.millisecondsSinceEpoch;
    }
    // Upload / manga jobs recover their source from the task row, not from a
    // payload: `local_path`/`local_uri` are the SAF materialise input, and
    // `manga:<id>` is the manga job convention (`manga_id_from_task`).
    if (localPath != null) body['local_path'] = localPath;
    if (localUri != null) body['local_uri'] = localUri;
    if (mangaId != null && mangaId.isNotEmpty) {
      body['local_path'] = 'manga:$mangaId';
    }
    final map = await _cmd(body);
    final id = map['task_id'] as String?;
    final task = id == null ? null : _byId[id];
    if (task == null) {
      throw StateError('err.unknown|enqueue returned no task');
    }
    return task;
  }

  Future<QueueTask> enqueueCache(
    String sourceName,
    String remotePath, {
    String? fileName,
    int priority = 0,
  }) => enqueue(
    kind: QueueTaskKind.downloadCache,
    sourceName: sourceName,
    remotePath: remotePath,
    fileName: fileName ?? _baseName(remotePath),
    priority: priority,
  );

  /// Enqueue a public download (gallery/Downloads chosen by Rust by extension).
  ///
  /// [treeUri] is the user's SAF tree (`SettingsService.customDownloadTreeUri`);
  /// when set the job writes through that tree instead of the public dirs.
  Future<QueueTask> enqueuePublic(
    String sourceName,
    String remotePath, {
    String? fileName,
    int priority = 0,
    String? treeUri,
  }) => enqueue(
    kind: QueueTaskKind.downloadPublic,
    sourceName: sourceName,
    remotePath: remotePath,
    fileName: fileName ?? _baseName(remotePath),
    target: QueueTarget.public,
    priority: priority,
    treeUri: _resolvedTreeUri(treeUri),
  );

  /// Atomically drop any public task for this account+remote and enqueue a
  /// fresh one (the "download again" branch of the duplicate dialog).
  Future<QueueTask> replacePublic(
    String sourceName,
    String remotePath, {
    String? fileName,
    int priority = 0,
    String? treeUri,
  }) async {
    final accountId = _accountIdForSource(sourceName);
    final resolvedTreeUri = _resolvedTreeUri(treeUri);
    final effectivePayload = (resolvedTreeUri == null || resolvedTreeUri.isEmpty)
        ? null
        : <String, dynamic>{'tree_uri': resolvedTreeUri};
    final body = <String, dynamic>{
      'cmd': 'replace_public',
      'kind': QueueTaskKind.downloadPublic.wireName,
      'source_name': sourceName,
      'account_id': accountId,
      'remote_path': remotePath,
      'file_name': fileName ?? _baseName(remotePath),
      'target': QueueTarget.public.wireName,
      'priority': priority,
    };
    if (effectivePayload != null) body['payload'] = effectivePayload;
    final map = await _cmd(body);
    final id = map['task_id'] as String?;
    final task = id == null ? null : _byId[id];
    if (task == null) {
      throw StateError('err.unknown|replace_public returned no task');
    }
    return task;
  }

  /// Enqueue a scan. [paths] become the job payload; [unitsTotal] is accepted
  /// for call-site compatibility but Rust derives the unit total from the scan
  /// job's own progress updates.
  Future<QueueTask> enqueueScan({
    required String sourceName,
    required String remotePath,
    required String fileName,
    int? unitsTotal,
    List<ScanPathEntry>? paths,
    int priority = 0,
  }) {
    final payload = paths == null || paths.isEmpty
        ? null
        : [
            for (final entry in paths)
              {
                'path': entry.path,
                'name': entry.name,
                'cue': entry.isCue,
              },
          ];
    return enqueue(
      kind: QueueTaskKind.scan,
      sourceName: sourceName,
      remotePath: remotePath,
      fileName: fileName,
      priority: priority,
      payload: payload,
    );
  }

  /// Fire-and-forget cache enqueue, mirroring the old helper's refusal cases.
  Future<bool> ensureQueued(
    String sourceName,
    String remotePath, {
    String? fileName,
    QueueTarget target = QueueTarget.cache,
    int priority = 0,
    String? treeUri,
    String? cacheGroupId,
  }) async {
    if (_isCueVirtual(remotePath)) return false;
    if (_cache.hasLocalFile(remotePath, sourceName: sourceName)) return false;
    final existing = taskForRemoteAndTarget(sourceName, remotePath, target);
    if (existing != null) {
      if (!existing.status.isTerminal) return false;
      if (existing.status == QueueTaskStatus.completed) {
        final local = existing.localPath;
        if (local != null && File(local).existsSync()) return false;
        // Completed but the file is gone: drop the stale row so the enqueue
        // below actually creates a download instead of dedupe-reviving it.
        await remove(existing.id);
      } else {
        await retry(existing.id);
        return true;
      }
    }
    await enqueue(
      kind: target == QueueTarget.public
          ? QueueTaskKind.downloadPublic
          : QueueTaskKind.downloadCache,
      sourceName: sourceName,
      remotePath: remotePath,
      fileName: fileName ?? _baseName(remotePath),
      target: target,
      priority: priority,
      treeUri: target == QueueTarget.public ? treeUri : null,
      cacheGroupId: cacheGroupId,
    );
    return true;
  }

  /// Queue into music_cache if needed, then wait for the terminal state.
  Future<String?> ensureCachedAndWait(
    String sourceName,
    String remotePath, {
    String? fileName,
    Duration timeout = const Duration(minutes: 30),
    int priority = 0,
  }) async {
    final cached = _cachedPath(sourceName, remotePath);
    if (cached != null) return cached;
    await ensureQueued(
      sourceName,
      remotePath,
      fileName: fileName,
      priority: priority,
    );
    final after = _cachedPath(sourceName, remotePath);
    if (after != null) return after;
    final task = taskForRemoteAndTarget(
      sourceName,
      remotePath,
      QueueTarget.cache,
    );
    if (task == null) return null;
    final raw = await RustCoreService.queueWait(
      task.id,
      timeoutMs: timeout.inMilliseconds,
    );
    final map = _decodeOrNull(raw);
    if (map != null && map['status'] == QueueTaskStatus.completed.wireName) {
      await _refreshRowsNow();
      return _cachedPath(sourceName, remotePath) ?? task.localPath;
    }
    await _refreshRowsNow();
    return _cachedPath(sourceName, remotePath);
  }

  Future<void> cancel(String taskId) =>
      _cmd({'cmd': 'cancel', 'task_id': taskId});

  Future<void> retry(String taskId) =>
      _cmd({'cmd': 'retry', 'task_id': taskId});

  Future<void> remove(String taskId) =>
      _cmd({'cmd': 'remove', 'task_id': taskId});

  Future<void> cancelAll() => _cmd({'cmd': 'cancel_all'});

  Future<void> clearCompleted() => _cmd({'cmd': 'clear_completed'});

  Future<void> clearAll() => _cmd({'cmd': 'clear_all'});

  /// Retry every failed/cancelled task (the tasks screen refresh action).
  Future<void> downloadAll() => _cmd({'cmd': 'retry_all'});

  Future<void> retryAll() => downloadAll();

  Future<int> invalidateMissingCompleted() async {
    final map = await _cmd({'cmd': 'invalidate_missing_completed'});
    return _asInt(map['removed']);
  }

  /// Remove stale `.part` files; limits come from settings when not overridden.
  Future<({int removed, int freedBytes})> cleanupStaleParts({
    int? maxAgeHours,
    int? maxBytes,
  }) async {
    final map = await _cmd({
      'cmd': 'cleanup_stale_parts',
      'max_age_hours': maxAgeHours ?? _settings.downloadPartMaxAgeHours,
      'max_bytes':
          maxBytes ?? _settings.downloadPartMaxMb * 1024 * 1024,
    });
    return (
      removed: _asInt(map['removed']),
      freedBytes: _asInt(map['freed_bytes']),
    );
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    _notifications.enabled = enabled;
    if (enabled) {
      await _notifications.ensureChannel();
    } else {
      await _notifications.cancelExceptProgress();
    }
    await _cmd({'cmd': 'set_notifications', 'enabled': enabled});
    notifyListeners();
  }

  Future<void> setKeepAliveEnabled(bool enabled) async {
    _keepAliveEnabled = enabled;
    await _cmd({'cmd': 'set_keep_alive', 'enabled': enabled});
    if (enabled) {
      _ensureKeepAliveBounded();
    } else {
      await _keepAlive.release();
    }
    notifyListeners();
  }

  Future<void> setConcurrency(int concurrency) =>
      _cmd({'cmd': 'set_concurrency', 'concurrency': concurrency});

  /// Report that Android refused to start/keep the foreground service.
  ///
  /// Rust moves running tasks back to `pending` and suspends itself for a
  /// cooldown; this side must not duplicate that decision.
  Future<void> notifyFgsTimeout() async {
    _keepAlive.suppressStartUntil(
      DateTime.now().add(DownloadKeepAlive.timeoutCooldown),
    );
    await _keepAlive.release();
    try {
      await _cmd({'cmd': 'fgs_timeout'});
    } catch (e) {
      debugPrint('QueueService: fgs_timeout failed: $e');
    }
  }

  // ── Reads used by the player / cache cleanup ──────────────────────────────

  QueueTask? taskForRemote(String sourceName, String remotePath) {
    QueueTask? found;
    for (final task in _tasks) {
      if (task.sourceName == sourceName && task.remotePath == remotePath) {
        found = task;
      }
    }
    return found;
  }

  QueueTask? taskForRemoteAndTarget(
    String sourceName,
    String remotePath,
    QueueTarget target,
  ) {
    QueueTask? found;
    for (final task in _tasks) {
      if (task.sourceName == sourceName &&
          task.remotePath == remotePath &&
          task.target == target) {
        found = task;
      }
    }
    return found;
  }

  Set<String> get downloadingIdentityKeys => _tasks
      .where(
        (t) =>
            t.status == QueueTaskStatus.active ||
            t.status == QueueTaskStatus.pending ||
            t.status == QueueTaskStatus.awaitingPlatform,
      )
      .map((t) => trackIdentityKey(t.sourceName, t.remotePath))
      .toSet();

  Map<String, String> get completedIdentityToLocal {
    final map = <String, String>{};
    for (final task in _tasks) {
      if (task.status == QueueTaskStatus.completed &&
          task.localPath != null) {
        map[trackIdentityKey(task.sourceName, task.remotePath)] =
            task.localPath!;
      }
    }
    return map;
  }

  /// Short localized label for a persisted `err.code|detail` string.
  static String describeError(String raw, dynamic l10n) =>
      TaskError.shortLabel(raw, l10n);

  /// Full original detail for the error dialog.
  static String describeErrorDetail(String raw) => TaskError.detailText(raw);

  // ── Snapshot / rows ───────────────────────────────────────────────────────

  void _applySnapshot(Map<String, dynamic> map) {
    final rev = map['rev'];
    if (rev is int) _rev = rev;
    final rawTasks = map['tasks'];
    if (rawTasks is List) {
      final tasks = <QueueTask>[];
      for (final raw in rawTasks) {
        if (raw is Map) {
          final task = QueueTask.fromJson(Map<String, dynamic>.from(raw));
          tasks.add(task);
        }
      }
      _installTasks(tasks);
    }
    final rawBatches = map['batches'];
    if (rawBatches is List) {
      _batches = [
        for (final raw in rawBatches)
          if (raw is Map) QueueBatch.fromJson(Map<String, dynamic>.from(raw)),
      ];
    }
    final rawSession = map['session'];
    if (rawSession is Map) {
      _session = QueueSession.fromJson(Map<String, dynamic>.from(rawSession));
    }
    final rawGroups = map['groups'];
    if (rawGroups is List) {
      _rows = [
        for (final raw in rawGroups)
          if (raw is Map) QueueRow.fromJson(Map<String, dynamic>.from(raw)),
      ];
      _lastRowsFetch = DateTime.now();
    }
  }

  void _installTasks(List<QueueTask> tasks) {
    tasks.sort((a, b) {
      final byCreated = a.createdAt.compareTo(b.createdAt);
      if (byCreated != 0) return byCreated;
      return a.updatedAt.compareTo(b.updatedAt);
    });
    _tasks = List.unmodifiable(tasks);
    _byId = {for (final task in tasks) task.id: task};
  }

  void _upsertTask(QueueTask task) {
    final next = List<QueueTask>.of(_tasks);
    final index = next.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      next[index] = task;
    } else {
      next.add(task);
    }
    _installTasks(next);
  }

  Future<void> _fetchRows() async {
    try {
      final raw = RustCoreService.queueQuery('{"query":"rows"}');
      final map = _decodeOrNull(raw);
      if (map == null) return;
      _applySnapshot(map);
    } catch (e) {
      _lastError = 'err.ffi|rows: $e';
    }
  }

  Future<void> _refreshRowsNow() async {
    if (_rowsFetching || _disposed) return;
    _rowsFetching = true;
    try {
      await _fetchRows();
      notifyListeners();
    } finally {
      _rowsFetching = false;
      _lastRowsFetch = DateTime.now();
      if (_rowsDirty) {
        _rowsDirty = false;
        _scheduleRowsRefresh();
      }
    }
  }

  void _scheduleRowsRefresh() {
    if (_disposed) return;
    final last = _lastRowsFetch;
    if (last == null ||
        DateTime.now().difference(last) >= rowsRefreshMinGap) {
      _rowsDirty = false;
      unawaited(_refreshRowsNow());
      return;
    }
    if (_rowsTimer != null) {
      _rowsDirty = true;
      return;
    }
    _rowsTimer = Timer(rowsRefreshMinGap, () {
      _rowsTimer = null;
      if (_rowsDirty) _rowsDirty = false;
      unawaited(_refreshRowsNow());
    });
  }

  // ── Event pump ────────────────────────────────────────────────────────────

  void _schedulePoll([Duration? delay]) {
    if (_disposed) return;
    _pollTimer?.cancel();
    final interval = _background ? pollBackground : pollForeground;
    _pollTimer = Timer(delay ?? interval, () {
      unawaited(_pollEvents());
    });
  }

  Future<void> _pollEvents({bool skipHistory = false}) async {
    if (_disposed || _polling) return;
    _polling = true;
    var changed = false;
    try {
      final since = skipHistory ? _hugeSeq : _sinceSeq;
      final raw = RustCoreService.queueQuery(
        jsonEncode({'query': 'events', 'since_seq': since}),
      );
      final map = _decodeOrNull(raw);
      if (map == null) return;
      final rev = map['rev'];
      if (rev is int && rev != _rev) {
        _rev = rev;
        changed = true;
      }
      final events = map['events'];
      if (events is List) {
        for (final rawEvent in events) {
          if (rawEvent is Map) {
            _handleEvent(Map<String, dynamic>.from(rawEvent));
            changed = true;
          }
        }
      }
      final nextSeq = _asInt(map['next_seq']);
      _sinceSeq = nextSeq > 0 ? nextSeq - 1 : 0;
    } catch (e) {
      _lastError = 'err.ffi|events: $e';
    } finally {
      _polling = false;
      if (changed) {
        notifyListeners();
        _scheduleRowsRefresh();
        _ensureKeepAliveBounded();
      }
      _schedulePoll();
    }
  }

  void _handleEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'task_added':
      case 'task_started':
        final raw = event['task'];
        if (raw is! Map) return;
        final task = QueueTask.fromJson(Map<String, dynamic>.from(raw));
        _upsertTask(task);
        if (!task.status.isTerminal) {
          _sessionIds.add(task.id);
        }
        _publishProgress();
      case 'task_progress':
        final id = event['task_id']?.toString();
        final task = id == null ? null : _byId[id];
        if (task == null) return;
        _upsertTask(
          task.withProgress(
            status:
                QueueTaskStatus.tryParse(event['status']) ?? task.status,
            progress: _asDouble(event['progress']),
            progressMode: QueueProgressMode.tryParse(event['progress_mode']),
            bytesDone: _asInt(event['bytes_done']),
            bytesTotal: _asIntOrNull(event['bytes_total']),
            unitsDone: _asInt(event['units_done']),
            unitsTotal: _asIntOrNull(event['units_total']),
          ),
        );
        _publishProgress();
      case 'task_terminal':
        final id = event['task_id']?.toString();
        final task = id == null ? null : _byId[id];
        if (task == null) return;
        _upsertTask(
          task.withTerminal(
            status:
                QueueTaskStatus.tryParse(event['status']) ?? task.status,
            errorMessage: event['error_message']?.toString(),
            localPath: event['local_path']?.toString(),
            localUri: event['local_uri']?.toString(),
            resultJson: event['result_json']?.toString(),
            progress: _asDouble(event['progress']),
          ),
        );
        _publishProgress();
      case 'batch_updated':
        final raw = event['batch'];
        if (raw is! Map) return;
        final batch = QueueBatch.fromJson(Map<String, dynamic>.from(raw));
        final next = List<QueueBatch>.of(_batches);
        final index = next.indexWhere((b) => b.id == batch.id);
        if (index >= 0) {
          next[index] = batch;
        } else {
          next.add(batch);
        }
        _batches = List.unmodifiable(next);
      case 'session_drained':
        _onSessionDrained();
      case 'summary':
        _onSilentSummary(
          completed: _asInt(event['completed']),
          failed: _asInt(event['failed']),
          cancelled: _asInt(event['cancelled']),
        );
      case 'keepalive_hint':
        final phase = event['phase']?.toString();
        if (phase == 'release') {
          unawaited(_keepAlive.release());
        } else if (phase == 'start') {
          _ensureKeepAliveBounded();
        }
      case 'platform_request':
        final reqId = event['req_id']?.toString();
        final action = event['action']?.toString();
        final params = event['params_json']?.toString();
        if (reqId != null && action != null) {
          unawaited(_handlePlatformRequest(reqId, action, params ?? '{}'));
        }
      case 'fgs_timeout_hint':
        // The attempt was already returned to pending by Rust; nothing to add.
        break;
    }
  }

  // ── Notifications / foreground service ────────────────────────────────────

  void _restoreSessionFromSnapshot() {
    final silentBatches = {
      for (final batch in _batches)
        if (batch.silent) batch.id,
    };
    for (final task in _tasks) {
      if (task.status.isTerminal) continue;
      if (silentBatches.contains(task.batchId)) continue;
      _sessionIds.add(task.id);
    }
  }

  ({int completed, int failed, int cancelled, int total}) _sessionCounts() {
    var completed = 0;
    var failed = 0;
    var cancelled = 0;
    var total = 0;
    for (final id in _sessionIds) {
      final task = _byId[id];
      if (task == null) continue;
      total++;
      switch (task.status) {
        case QueueTaskStatus.completed:
          completed++;
        case QueueTaskStatus.failed:
          failed++;
        case QueueTaskStatus.cancelled:
          cancelled++;
        case QueueTaskStatus.partial:
          failed++;
        case QueueTaskStatus.pending:
        case QueueTaskStatus.active:
        case QueueTaskStatus.awaitingPlatform:
          break;
      }
    }
    return (completed: completed, failed: failed, cancelled: cancelled, total: total);
  }

  QueueTask? get _currentTask {
    for (final task in _tasks) {
      if (task.status == QueueTaskStatus.active) return task;
    }
    for (final task in _tasks) {
      if (task.status == QueueTaskStatus.awaitingPlatform) return task;
    }
    return null;
  }

  void _publishProgress() {
    if (!_notificationsEnabled) return;
    final counts = _sessionCounts();
    if (counts.total == 0) return;
    final current = _currentTask;
    final done = counts.completed + counts.failed + counts.cancelled;
    final total = counts.total;
    final index = (done + (current != null ? 1 : 0)).clamp(1, total);
    unawaited(
      _notifications.showProgress(
        index: index,
        total: total,
        done: done,
        currentName: current?.fileName,
        fileProgress: current?.displayProgress ?? 0,
      ),
    );
  }

  void _onSessionDrained() {
    final counts = _sessionCounts();
    _sessionIds.clear();
    unawaited(_notifications.clearProgress());
    unawaited(_keepAlive.release());
    if (counts.total == 0) return;
    if (_notificationsEnabled && _background) {
      unawaited(
        _notifications.showSummary(
          completed: counts.completed,
          failed: counts.failed,
          cancelled: counts.cancelled,
        ),
      );
      return;
    }
    final message = _completionMessage(
      completed: counts.completed,
      failed: counts.failed,
      cancelled: counts.cancelled,
    );
    if (message != null) AppSnack.showGlobal(message);
  }

  void _onSilentSummary({
    required int completed,
    required int failed,
    required int cancelled,
  }) {
    if (completed + failed + cancelled == 0) return;
    final message = _completionMessage(
      completed: completed,
      failed: failed,
      cancelled: cancelled,
    );
    if (message == null) return;
    if (_notificationsEnabled && _background) {
      unawaited(
        _notifications.showSummary(
          completed: completed,
          failed: failed,
          cancelled: cancelled,
        ),
      );
    } else {
      AppSnack.showGlobal(message);
    }
  }

  String? _completionMessage({
    required int completed,
    required int failed,
    required int cancelled,
  }) {
    final l10n = L10nHost.current;
    final parts = <String>[
      if (completed > 0) l10n.dlDoneOkCount(completed),
      if (failed > 0) l10n.dlDoneFailedCount(failed),
      if (cancelled > 0) l10n.dlDoneCancelledCount(cancelled),
    ];
    if (parts.isEmpty) return null;
    return l10n.dlDoneTitle(parts.join(l10n.dlDoneSep));
  }

  void _ensureKeepAliveBounded() {
    if (_disposed || !_keepAliveEnabled) return;
    if (kIsWeb || !Platform.isAndroid) return;
    if (_background) return;
    if (!isBusy) return;
    unawaited(
      _keepAlive
          .ensureRunning(
            title: L10nHost.current.ntfDownloadingTitle(1, 1),
            notificationId: DownloadNotificationService.currentId,
            channelId: kDownloadChannelId,
            isForeground: () => !_background,
          )
          .timeout(const Duration(seconds: 5))
          .catchError((Object e) {
            debugPrint('QueueService: keep-alive start failed: $e');
          }),
    );
  }

  void _onKeepAliveTimeout() {
    unawaited(notifyFgsTimeout());
  }

  // ── Platform bridge ───────────────────────────────────────────────────────

  Future<void> _handlePlatformRequest(
    String reqId,
    String action,
    String paramsJson,
  ) async {
    Map<String, dynamic> params = const {};
    try {
      final decoded = jsonDecode(paramsJson);
      if (decoded is Map) params = Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Malformed params are reported to Rust through the reply below.
    }
    try {
      switch (action) {
        case 'save_to_gallery':
          final result = await _platformExport.saveToGallery(
            sourcePath: _param(params, 'temp_path'),
            fileName: _param(params, 'name'),
            mimeType: _optionalParam(params, 'mime'),
          );
          _replySave(reqId, result);
        case 'save_to_downloads':
          final result = await _platformExport.saveToDownloads(
            sourcePath: _param(params, 'temp_path'),
            fileName: _param(params, 'name'),
            mimeType: _optionalParam(params, 'mime'),
          );
          _replySave(reqId, result);
        case 'save_to_tree':
          final treeUri =
              _optionalParam(params, 'tree_uri') ??
              _optionalParam(params, 'treeUri');
          if (treeUri == null || treeUri.isEmpty) {
            _replyError(reqId, 'err.customDirInvalid|no tree uri');
            return;
          }
          final result = await _platformExport.saveToTree(
            treeUri: treeUri,
            sourcePath: _param(params, 'temp_path'),
            fileName: _param(params, 'name'),
            mimeType: _optionalParam(params, 'mime'),
          );
          _replySave(reqId, result);
        case 'materialize':
          await _materialize(reqId, _param(params, 'uri'));
        default:
          _replyError(reqId, 'err.unknownAction|$action');
      }
    } catch (e) {
      _replyError(reqId, 'err.platform|$e');
    }
  }

  void _replySave(String reqId, ExportResult result) {
    if (!result.ok) {
      final error = result.safInvalid
          ? 'err.customDirInvalid'
          : (result.error ?? 'err.writePublicFailed');
      _replyError(reqId, error);
      return;
    }
    final path = result.path ?? result.uri;
    _reply(reqId, {
      'ok': true,
      'result': {'ok': true, 'uri': ?result.uri, 'path': ?path},
    });
  }

  Future<void> _materialize(String reqId, String uri) async {
    final docs = _appDocsPath;
    if (docs == null) {
      _replyError(reqId, 'err.notInitialized|queue paths');
      return;
    }
    final cachePath = await PlatformExportService.readUriToCache(uri);
    if (cachePath == null) {
      _replyError(reqId, 'err.safUnreadable|$uri');
      return;
    }
    final dir = Directory(p.join(docs, 'queue_payloads'));
    await dir.create(recursive: true);
    final target = p.join(dir.path, '$reqId.bin');
    await File(cachePath).copy(target);
    _reply(reqId, {
      'ok': true,
      'result': {'ok': true, 'path': target},
    });
  }

  void _replyError(String reqId, String error) {
    _reply(reqId, {'ok': false, 'error': error});
  }

  void _reply(String reqId, Map<String, dynamic> payload) {
    final raw = RustCoreService.queuePlatformResult(reqId, jsonEncode(payload));
    final map = _decodeOrNull(raw);
    if (map == null) {
      debugPrint('QueueService: platform reply $reqId failed: $_lastError');
    }
  }

  // ── Small helpers ─────────────────────────────────────────────────────────

  String? _cachedPath(String sourceName, String remotePath) {
    if (!_cache.hasLocalFile(remotePath, sourceName: sourceName)) return null;
    return _cache.fileForRemote(remotePath, sourceName: sourceName).path;
  }

  static String _baseName(String remotePath) {
    final trimmed = remotePath.endsWith('/')
        ? remotePath.substring(0, remotePath.length - 1)
        : remotePath;
    final slash = trimmed.lastIndexOf('/');
    return slash < 0 ? trimmed : trimmed.substring(slash + 1);
  }

  /// Public downloads obey the user's custom SAF directory unless the caller
  /// overrides it explicitly.
  String? _resolvedTreeUri(String? explicit) {
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (!_settings.customDownloadDirActive) return null;
    final uri = _settings.customDownloadTreeUri;
    return (uri == null || uri.isEmpty) ? null : uri;
  }

  static String _param(Map<String, dynamic> params, String key) =>
      params[key]?.toString() ?? '';

  static String? _optionalParam(Map<String, dynamic> params, String key) {
    final value = params[key];
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static int? _asIntOrNull(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}
