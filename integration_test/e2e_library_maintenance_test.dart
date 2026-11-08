import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:webdav_media_manager/models/queue_models.dart';
import 'package:webdav_media_manager/services/library_service.dart';
import 'package:webdav_media_manager/services/queue_service.dart';
import 'package:webdav_media_manager/utils/scan_candidates.dart';

import 'e2e_support.dart';

/// Maintenance module: the whole-library metadata refresh runs as **one** batch
/// task, and cover recovery repairs a thumbnail whose cached file disappeared.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('maintenance: batch retag and cover recovery each run one task',
      (tester) async {
    await bootApp(tester);
    expect(webdavConfigured, isTrue, reason: 'E2E_WEBDAV_* are not set');
    ensureE2eAccount();

    final queue = appService<QueueService>(tester);
    final library = appService<LibraryService>(tester);
    // `bootApp` returns at the first frame; the queue installs its FFI paths
    // during the app's async init, and enqueueing before that fails with
    // `err.notInitialized`.
    await pumpUntil(tester, 'queue init', () => queue.initialized,
        timeout: const Duration(seconds: 60));
    final files = _audioFiles(count: 2);
    debugPrint('[E2E] maintenance: seeding ${files.length} track(s) $files');

    for (final path in files) {
      final name = path.split('/').last;
      final scan = await queue.enqueueScan(
        sourceName: e2eAccountName,
        remotePath: path,
        fileName: name,
        unitsTotal: 1,
        paths: [ScanPathEntry(path: path, name: name, isCue: false)],
      );
      final done = await _awaitTerminal(tester, queue, scan.id, 'scan $name');
      expect(
        [QueueTaskStatus.completed, QueueTaskStatus.partial],
        contains(done.status),
        reason: 'scan of $path ended as ${done.status.wireName}: '
            '${done.errorMessage ?? '-'}',
      );
    }

    await library.refresh();
    final rows = library.tracksForSource(e2eAccountName).where(
          (t) => files.contains(t.remotePath),
        );
    expect(rows.length, files.length,
        reason: 'expected one library row per seeded file, got '
            '${rows.map((r) => r.remotePath).toList()}');

    // 1) Batch retag: one task for all rows, one unit per row.
    final revisionBefore = queue.musicLibraryRevision;
    final tasksBefore = queue.tasks.length;
    final retags = await queue.enqueueRetagAll(rows);
    expect(retags.length, 1,
        reason: 'a single-source library must queue exactly one retag task');
    final retag = retags.single;
    expect(retag.kind, QueueTaskKind.retagCloud);
    expect(queue.tasks.length, tasksBefore + 1,
        reason: 'enqueueRetagAll must queue one task, not one per track');
    final retagDone = await _awaitTerminal(tester, queue, retag.id, 'retag');
    expect(retagDone.unitsTotal, rows.length,
        reason: 'the batch should advertise one unit per track');
    expect(
      [QueueTaskStatus.completed, QueueTaskStatus.partial],
      contains(retagDone.status),
      reason: 'retag ended as ${retagDone.status.wireName}: '
          '${retagDone.errorMessage ?? '-'}',
    );
    expect(retagDone.id, retag.id, reason: 'retag must stay a single task');
    expect(queue.musicLibraryRevision, greaterThan(revisionBefore),
        reason: 'the queue did not report a library write');
    debugPrint('[E2E] maintenance: batch retag ok '
        'tracks=${rows.length} status=${retagDone.status.wireName}');

    // 2) Cover recovery. The seeded track may or may not carry embedded art:
    //    - art was written -> delete the thumbnail and expect it back (state 2)
    //    - no art -> the probe must record "none" (state 1)
    final track = rows.first;
    final thumbPath = library.covers.thumbPath(track.sourceName, track.remotePath);
    final thumbFile = thumbPath == null ? null : File(thumbPath);
    final hadThumb = thumbFile != null && thumbFile.existsSync();
    if (hadThumb) {
      thumbFile.deleteSync();
      debugPrint('[E2E] maintenance: removed thumbnail $thumbPath');
    }

    final covers = await queue.enqueueCoverRefresh(rows);
    expect(covers.length, 1,
        reason: 'a single-source library must queue exactly one cover task');
    final cover = covers.single;
    expect(cover.kind, QueueTaskKind.coverRefresh);
    final coverDone = await _awaitTerminal(tester, queue, cover.id, 'cover refresh');
    expect(
      [QueueTaskStatus.completed, QueueTaskStatus.partial],
      contains(coverDone.status),
      reason: 'cover refresh ended as ${coverDone.status.wireName}: '
          '${coverDone.errorMessage ?? '-'}',
    );

    await library.refresh();
    final after = library
        .tracksForSource(e2eAccountName)
        .firstWhere((t) => t.remotePath == track.remotePath);
    final coverTrace = 'track=${track.remotePath} hadThumb=$hadThumb '
        'thumb=${thumbPath ?? '-'} state=${after.coverState} '
        'status=${coverDone.status.wireName} '
        'error=${coverDone.errorMessage ?? '-'} '
        'units=${coverDone.unitsDone}/${coverDone.unitsTotal} '
        'result=${coverDone.resultJson ?? '-'}';
    if (hadThumb) {
      expect(after.coverState, 2,
          reason: 'a restored cover must be recorded as state 2 ($coverTrace)');
      expect(thumbFile.existsSync(), isTrue,
          reason: 'the cover refresh did not restore $thumbPath ($coverTrace)');
    } else {
      expect(after.coverState, 1,
          reason: 'a probed file without art must be recorded as state 1 '
              '($coverTrace)');
    }
    debugPrint('[E2E] maintenance ok: coverState=${after.coverState} '
        'hadThumb=$hadThumb');
  });
}

/// First [count] audio files under the lab music root (a couple of albums are
/// enough for a batch test).
List<String> _audioFiles({required int count}) {
  final files = <String>[];
  final dirs = listDir(e2eMusicRoot).where(isDir).toList();
  for (final dir in dirs.take(10)) {
    final dirPath = joinPath(e2eMusicRoot, dir);
    for (final entry in listDir(dirPath)) {
      if (isDir(entry)) continue;
      final path = joinPath(dirPath, entry);
      if (!isAudio(path)) continue;
      if (!files.contains(path)) files.add(path);
      if (files.length >= count) return files;
    }
  }
  expect(files, hasLength(count),
      reason: 'only ${files.length} audio file(s) found under $e2eMusicRoot');
  return files;
}

Future<QueueTask> _awaitTerminal(
  WidgetTester tester,
  QueueService queue,
  String id,
  String label,
) async {
  await pumpUntil(
    tester,
    label,
    () => queue.taskById(id)?.status.isTerminal ?? false,
    timeout: const Duration(minutes: 5),
  );
  final task = queue.taskById(id);
  expect(task, isNotNull, reason: '$label task $id vanished from the queue');
  return task!;
}
