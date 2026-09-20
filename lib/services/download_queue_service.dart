import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';

import '../models/download_task.dart';
import '../models/webdav_item.dart';
import 'cache_service.dart';
import 'download_store.dart';
import 'webdav_service.dart';

/// Background async download queue. Does not block UI/navigation.
/// Ordering: FIFO by [createdAt]. Only one active download at a time.
class DownloadQueueService extends ChangeNotifier {
  DownloadQueueService({
    required WebDavService webDav,
    required CacheService cache,
    DownloadStore? store,
  })  : _webDav = webDav,
        _cache = cache,
        _store = store ?? DownloadStore();

  final WebDavService _webDav;
  final CacheService _cache;
  final DownloadStore _store;
  final _uuid = const Uuid();

  final List<DownloadTask> _tasks = [];
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, Completer<DownloadTask>> _waiters = {};

  bool _running = false;
  bool _initialized = false;

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
    // Reset interrupted active downloads to pending so they retry.
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

  DownloadTask? taskForRemote(String remotePath) {
    try {
      return _tasks.lastWhere((t) => t.remotePath == remotePath);
    } catch (_) {
      return null;
    }
  }

  TrackUiState uiStateFor(
    String remotePath, {
    String? playingRemotePath,
  }) {
    final cached = _cache.fileForRemote(remotePath);
    final task = taskForRemote(remotePath);
    if (playingRemotePath == remotePath) return TrackUiState.playing;
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
    return TrackUiState.queued; // not yet enqueued — caller may enqueue
  }

  /// Enqueue download. If already completed/cached, returns existing task.
  /// Returns a Future that completes when download finishes (or fails).
  Future<DownloadTask> enqueue(
    String remotePath, {
    String? fileName,
    bool playWhenReady = false,
  }) async {
    final existingCompleted = _tasks.cast<DownloadTask?>().firstWhere(
          (t) =>
              t!.remotePath == remotePath &&
              t.status == DownloadStatus.completed &&
              t.localPath != null &&
              File(t.localPath!).existsSync(),
          orElse: () => null,
        );
    if (existingCompleted != null) {
      return existingCompleted;
    }

    final cachedPath = await _cache.localPathIfCached(remotePath);
    if (cachedPath != null) {
      final done = DownloadTask(
        id: _uuid.v4(),
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
      notifyListeners();
      return done;
    }

    final inFlight = _tasks.cast<DownloadTask?>().firstWhere(
          (t) =>
              t!.remotePath == remotePath &&
              (t.status == DownloadStatus.pending ||
                  t.status == DownloadStatus.active),
          orElse: () => null,
        );
    if (inFlight != null) {
      return _waitFor(inFlight.id);
    }

    final task = DownloadTask(
      id: _uuid.v4(),
      remotePath: remotePath,
      fileName: fileName ?? remotePath.split('/').last,
      createdAt: DateTime.now(),
    );
    _tasks.add(task);
    await _store.upsert(task);
    notifyListeners();
    unawaited(_pump());
    return _waitFor(task.id);
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

  /// Ordered pending queue (FIFO). Exposed for unit tests via static helper.
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
    final dest = _cache.fileForRemote(task.remotePath);
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
          // Persist progress sparsely
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
      await _cache.registerCompleted(task.remotePath, dest.path);
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

  Set<String> get downloadingRemotePaths => _tasks
      .where((t) =>
          t.status == DownloadStatus.active ||
          t.status == DownloadStatus.pending)
      .map((t) => t.remotePath)
      .toSet();

  Map<String, String> get completedRemoteToLocal {
    final map = <String, String>{};
    for (final t in _tasks) {
      if (t.status == DownloadStatus.completed && t.localPath != null) {
        map[t.remotePath] = t.localPath!;
      }
    }
    return map;
  }
}
