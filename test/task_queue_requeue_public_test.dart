// SPDX-FileCopyrightText: 2025 Webdav Media Manager contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_media_manager/models/queue_task.dart';
import 'package:webdav_media_manager/services/cache_service.dart';
import 'package:webdav_media_manager/services/task_queue_service.dart';
import 'package:webdav_media_manager/services/task_store.dart';
import 'package:webdav_media_manager/services/webdav_service.dart';
import 'package:webdav_media_manager/services/cloud_driver.dart';

class _MemStore extends TaskStore {
  final Map<String, QueueTask> rows = {};

  @override
  Future<List<QueueTask>> loadAll() async => rows.values.toList();

  @override
  Future<void> upsert(QueueTask task) async {
    rows[task.id] = task;
  }

  @override
  Future<void> delete(String id) async {
    rows.remove(id);
  }

  @override
  Future<void> deleteByStatus(TaskStatus status) async {
    rows.removeWhere((_, t) => t.status == status);
  }

  @override
  Future<QueueTask?> findByRemotePath(
    String remotePath, {
    String? accountId,
  }) async {
    for (final t in rows.values) {
      if (t.remotePath == remotePath &&
          (accountId == null || t.sourceName == accountId)) {
        return t;
      }
    }
    return null;
  }

  @override
  Future<void> close() async {}
}

class _HangDav extends WebDavService {
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> downloadToFile(
    String accountId,
    String remotePath,
    File localFile, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
    int resumeFrom = 0,
    bool useCryptSequentialDownload = false,
    void Function(CloudDownloadMode mode)? onMode,
    int? expectedRemoteSize,
    DateTime? expectedRemoteModified,
    void Function(int size, DateTime? modified)? onIdentity,
  }) async {
    onMode?.call(CloudDownloadMode.direct);
    onIdentity?.call(1, null);
    // Stay blocked until cancelled or test completes the gate.
    while (true) {
      if (cancelToken?.isCancelled == true) {
        throw DioException(
          requestOptions: RequestOptions(path: remotePath),
          type: DioExceptionType.cancel,
        );
      }
      if (gate.isCompleted) {
        await gate.future;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('wdmm-requeue-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'getTemporaryDirectory' ||
        'getApplicationSupportDirectory' ||
        'getApplicationDocumentsDirectory' ||
        'getApplicationSupportPath' ||
        'getTemporaryPath' ||
        'getApplicationDocumentsPath' =>
          tmp.path,
        _ => null,
      };
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('requeuePublicFresh removes old blocking row and enqueues fresh',
      () async {
    final store = _MemStore();
    final hang = _HangDav();
    final queue = TaskQueueService(
      webDav: hang,
      cache: CacheService(),
      store: store,
      accountIdForSource: (_) => 'acc',
    );

    final ok = await queue.enqueuePublic(
      'src',
      '/a.bin',
      fileName: 'a.bin',
      target: DownloadTarget.downloads,
    );
    expect(ok, isTrue);

    // Wait until active (download hung on gate).
    final sw = Stopwatch()..start();
    while (queue.tasks.every((t) => t.status != TaskStatus.active) &&
        sw.elapsed < const Duration(seconds: 3)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(queue.tasks.any((t) => t.status == TaskStatus.active), isTrue);
    final oldId = queue.tasks.first.id;

    final requeued = await queue.requeuePublicFresh(
      'src',
      '/a.bin',
      fileName: 'a.bin',
      target: DownloadTarget.downloads,
    );
    expect(requeued, isTrue);

    // Wait briefly so any in-flight cancel handler runs; it must not resurrect.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(store.rows.containsKey(oldId), isFalse);
    expect(queue.tasks.where((t) => t.id == oldId), isEmpty);
    expect(
      queue.tasks.where(
        (t) =>
            t.remotePath == '/a.bin' &&
            t.target == DownloadTarget.downloads,
      ),
      isNotEmpty,
    );

    // Clean up: let any remaining downloads complete to prevent hanging.
    if (!hang.gate.isCompleted) {
      hang.gate.complete();
    }
    // Dispose queue to cancel all active tasks.
    queue.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
}
