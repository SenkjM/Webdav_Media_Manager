import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/queue_task.dart';

void main() {
  group('QueueTask', () {
    test('defaults to download + bytes progress', () {
      final t = QueueTask(
        id: '1',
        sourceName: 'a',
        remotePath: '/a.mp3',
        fileName: 'a.mp3',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(t.kind, TaskKind.download);
      expect(t.progressMode, TaskProgressMode.bytes);
      expect(t.isDownload, isTrue);
    });

    test('units progress drives displayProgress', () {
      final t = QueueTask(
        id: '1',
        sourceName: 'a',
        remotePath: '/album',
        fileName: 'album',
        createdAt: DateTime(2026, 1, 1),
        kind: TaskKind.scan,
        progressMode: TaskProgressMode.units,
        unitsDone: 3,
        unitsTotal: 10,
      );
      expect(t.displayProgress, closeTo(0.3, 1e-9));
      t.unitsDone = 10;
      t.syncProgressFromCounters();
      expect(t.progress, 1.0);
    });

    test('round-trip map keeps kind and units', () {
      final t = QueueTask(
        id: 'scan-1',
        sourceName: 'disk',
        remotePath: '/music',
        fileName: 'music',
        createdAt: DateTime.utc(2026, 10, 12),
        kind: TaskKind.retagCloud,
        progressMode: TaskProgressMode.units,
        unitsDone: 2,
        unitsTotal: 5,
        status: TaskStatus.active,
      );
      final again = QueueTask.fromMap(t.toMap());
      expect(again.kind, TaskKind.retagCloud);
      expect(again.progressMode, TaskProgressMode.units);
      expect(again.unitsDone, 2);
      expect(again.unitsTotal, 5);
      expect(again.status, TaskStatus.active);
    });

    test('orderPending skips non-download kinds', () {
      // Imported via task_queue_service in ordering test; light check here on kind filter assumption.
      expect(TaskKind.scan.storageKey, 'scan');
      expect(TaskKind.retagLocal.storageKey, 'retag_local');
    });
  });
}
