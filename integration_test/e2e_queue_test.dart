import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:webdav_media_manager/models/queue_models.dart';
import 'package:webdav_media_manager/services/cache_service.dart';
import 'package:webdav_media_manager/services/queue_service.dart';

import 'e2e_support.dart';

/// Queue module: one real cache download through the Rust queue, from enqueue
/// to a finished file registered in the media cache.
///
/// Cache downloads report their payload through the cache index rather than
/// `task.local_path` (that field is reserved for public downloads that wait on
/// the platform bridge), so the assertion goes through [CacheService].
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('queue: a cache download lands in the media cache',
      (tester) async {
    await bootApp(tester);
    expect(webdavConfigured, isTrue, reason: 'E2E_WEBDAV_* are not set');
    ensureE2eAccount();

    final queue = appService<QueueService>(tester);
    final cache = appService<CacheService>(tester);
    final path = findAudioFile();
    final task = await queue.enqueueCache(e2eAccountName, path);
    debugPrint('[E2E] queue enqueued ${task.id} for $path');

    await pumpUntil(
      tester,
      'download of $path',
      () => queue.taskById(task.id)?.status.isTerminal ?? false,
      timeout: const Duration(minutes: 5),
    );

    final done = queue.taskById(task.id);
    expect(done, isNotNull, reason: 'task ${task.id} vanished from the queue');
    expect(done!.status, QueueTaskStatus.completed,
        reason: 'download ended as ${done.status.wireName}: '
            '${done.errorMessage ?? '-'}');

    final local =
        await cache.localPathIfCached(path, sourceName: e2eAccountName);
    expect(local, isNotNull,
        reason: 'cache index has no entry for $path after the download');
    final file = File(local!);
    expect(file.existsSync(), isTrue,
        reason: 'cache reported $local but the file is missing');
    expect(file.lengthSync(), greaterThan(0));

    debugPrint('[E2E] queue ok: $local ${file.lengthSync()}B');
  });
}
