import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/download_task.dart';
import '../models/webdav_item.dart';
import '../utils/cue_sheet.dart';
import '../utils/track_identity.dart';
import 'cache_service.dart';
import 'download_store.dart';
import 'library_service.dart';
import 'webdav_service.dart';

/// Background async download queue. Does not block UI/navigation.
/// Ordering: FIFO by [createdAt]. Only one active download at a time.
class DownloadQueueService extends ChangeNotifier {
  DownloadQueueService({
    required WebDavService webDav,
    required CacheService cache,
    LibraryService? library,
    DownloadStore? store,
  })  : _webDav = webDav,
        _cache = cache,
        _library = library,
        _store = store ?? DownloadStore();

  final WebDavService _webDav;
  final CacheService _cache;
  LibraryService? _library;
  final DownloadStore _store;
  final _uuid = const Uuid();

  final List<DownloadTask> _tasks = [];
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, Completer<DownloadTask>> _waiters = {};

  bool _running = false;
  bool _initialized = false;

  void attachLibrary(LibraryService library) {
    _library = library;
  }

  UnmodifiableListView<DownloadTask> get tasks =>
      UnmodifiableListView(_tasks);

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
          break;
      }
    }
    if (cached.existsSync() || task?.status == DownloadStatus.completed) {
      return TrackUiState.ready;
    }
    return TrackUiState.queued;
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
      );
      _tasks.add(done);
      await _store.upsert(done);
      await _ingest(done);
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
  /// Does not wait for download completion; safe to call from UI build/open.
  Future<bool> ensureQueued(
    String accountId,
    String remotePath, {
    String? fileName,
  }) async {
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
      final parsed = CueSheetParser.tryParse(utf8.decode(bytes, allowMalformed: true));
      if (parsed == null) {
        throw StateError('无法解析的 CUE：需要标准 FILE + TRACK/INDEX');
      }
      sheet = parsed;
    }
    final groupId = cueCacheGroupId(accountId, cueRemotePath);
    final paths = <String>[cueRemotePath, ...sheet.audioRemotePaths(cueRemotePath)];
    for (final path in paths) {
      await _cache.bindCacheGroup(accountId: accountId, remotePath: path, groupId: groupId);
    }
    for (final path in paths) {
      unawaited(() async {
        try {
          await enqueue(accountId, path, fileName: p.basename(path), cacheGroupId: groupId);
        } catch (_) {}
      }());
    }
    return paths.length;
  }

  Future<void> _maybeIngestCueGroup(DownloadTask task) async {
    final groupId = task.cacheGroupId;
    if (groupId == null || _library == null) return;
    final members = _tasks.where((t) => t.cacheGroupId == groupId).toList();
    if (members.isEmpty) return;
    final allDone = members.every((t) =>
        t.status == DownloadStatus.completed &&
        t.localPath != null &&
        File(t.localPath!).existsSync());
    if (!allDone) return;
    final cueTask = members.cast<DownloadTask?>().firstWhere(
      (t) => t!.remotePath.toLowerCase().endsWith('.cue'),
      orElse: () => null,
    );
    if (cueTask?.localPath == null) return;
    try {
      final sheet = CueSheetParser.tryParse(await File(cueTask!.localPath!).readAsString());
      if (sheet == null) return;
      await _library!.ingestCueAlbum(
        accountId: cueTask.accountId,
        cueRemotePath: cueTask.remotePath,
        sheet: sheet,
        cacheGroupId: groupId,
        localPathFor: (remote) => _cache.fileForRemote(remote, accountId: cueTask.accountId).path,
      );
    } catch (_) {}
  }

  Future<void> _ingest(DownloadTask task) async {
    final lib = _library;
    final local = task.localPath;
    if (lib == null || local == null) return;
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
    } finally {
      _cancelTokens.remove(task.id);
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
