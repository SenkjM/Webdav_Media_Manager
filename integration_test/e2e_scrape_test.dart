import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:webdav_media_manager/models/queue_models.dart';
import 'package:webdav_media_manager/services/library_service.dart';
import 'package:webdav_media_manager/services/queue_service.dart';
import 'package:webdav_media_manager/utils/scan_candidates.dart';

import 'e2e_support.dart';

/// Scrape module: enqueue a scan for one real audio file, wait for the Rust
/// job, and verify the ingested row reaches the Dart in-memory library.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scrape: scanning a file adds it to the music library',
      (tester) async {
    await bootApp(tester);
    expect(webdavConfigured, isTrue, reason: 'E2E_WEBDAV_* are not set');
    ensureE2eAccount();

    final queue = appService<QueueService>(tester);
    final library = appService<LibraryService>(tester);
    final path = findAudioFile();
    final name = path.split('/').last;

    final revisionBefore = queue.musicLibraryRevision;
    final task = await queue.enqueueScan(
      sourceName: e2eAccountName,
      remotePath: path,
      fileName: name,
      unitsTotal: 1,
      paths: [ScanPathEntry(path: path, name: name, isCue: false)],
    );
    debugPrint('[E2E] scrape enqueued ${task.id} for $path');

    await pumpUntil(
      tester,
      'scan of $path',
      () => queue.taskById(task.id)?.status.isTerminal ?? false,
      timeout: const Duration(minutes: 5),
    );

    final done = queue.taskById(task.id);
    expect(done, isNotNull, reason: 'task ${task.id} vanished from the queue');
    expect(
      [QueueTaskStatus.completed, QueueTaskStatus.partial],
      contains(done!.status),
      reason: 'scan ended as ${done.status.wireName}: '
          '${done.errorMessage ?? '-'}',
    );
    expect(queue.musicLibraryRevision, greaterThan(revisionBefore),
        reason: 'the queue did not report a library write');

    await library.refresh();
    final rows = library.tracksForSource(e2eAccountName);
    expect(rows.any((t) => t.remotePath == path), isTrue,
        reason: 'no library row for $path after the scan '
            '(${rows.length} rows in total)');

    debugPrint('[E2E] scrape ok: $path rows=${rows.length} '
        'status=${done.status.wireName}');
  });
}
