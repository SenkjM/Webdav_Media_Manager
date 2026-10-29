import 'dart:convert';

import '../models/queue_task.dart';
import 'rust_core_service.dart';

/// KV-backed persistence for the task queue (replaces the sqflite backend).
///
/// Each task is stored under `queue_task_<id>` as a JSON map; the ordered ID
/// list lives under `queue_task_ids`. The queue is a transient list — losing
/// it costs a re-enqueue, not data.
///
/// The [fileName] constant is kept so [LocalDatabaseRecoveryService] can find
/// and clean up the old `task_queue.db` SQLite file on upgraded devices.
class TaskStore {
  static const _kIndex = 'queue_task_ids';
  static const _kPrefix = 'queue_task_';

  /// Old SQLite on-disk name; kept only for [LocalDatabaseRecoveryService].
  static const fileName = 'task_queue.db';

  List<String> _readIndex() {
    final raw = RustCoreService.kvGet(_kIndex);
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<String>();
    } catch (_) {
      return [];
    }
  }

  void _writeIndex(List<String> ids) {
    RustCoreService.kvSet(_kIndex, jsonEncode(ids));
  }

  Future<List<QueueTask>> loadAll() async {
    final ids = _readIndex();
    final tasks = <QueueTask>[];
    for (final id in ids) {
      final raw = RustCoreService.kvGet('$_kPrefix$id');
      if (raw == null || raw.isEmpty || raw.startsWith('error:')) continue;
      try {
        tasks.add(QueueTask.fromMap(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // Corrupt KV entry — skip silently; the ID remains in the index until
        // the next upsert/delete cycle cleans it.
      }
    }
    return tasks;
  }

  Future<void> upsert(QueueTask task) async {
    final ids = _readIndex();
    if (!ids.contains(task.id)) {
      ids.add(task.id);
      _writeIndex(ids);
    }
    RustCoreService.kvSet('$_kPrefix${task.id}', jsonEncode(task.toMap()));
  }

  Future<void> delete(String id) async {
    final ids = _readIndex();
    if (ids.remove(id)) _writeIndex(ids);
    RustCoreService.kvDelete('$_kPrefix$id');
  }

  Future<void> deleteByStatus(TaskStatus status) async {
    final tasks = await loadAll();
    for (final t in tasks) {
      if (t.status == status) await delete(t.id);
    }
  }

  Future<QueueTask?> findByRemotePath(
    String remotePath, {
    String? accountId,
  }) async {
    final tasks = await loadAll();
    for (final t in tasks) {
      if (t.remotePath == remotePath &&
          (accountId == null || t.sourceName == accountId)) {
        return t;
      }
    }
    return null;
  }

  /// No-op: the KV store is always open.
  Future<void> close() async {}
}
