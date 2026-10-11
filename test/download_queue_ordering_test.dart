import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/queue_task.dart';
import 'package:webdav_media_manager/services/task_queue_service.dart';

void main() {
  group('TaskQueueService.orderPending', () {
    test('orders pending tasks FIFO by createdAt', () {
      final t1 = QueueTask(
        id: '1',
        sourceName: 'a',
        remotePath: '/a.mp3',
        fileName: 'a.mp3',
        createdAt: DateTime(2026, 1, 1, 10),
        status: TaskStatus.pending,
      );
      final t2 = QueueTask(
        id: '2',
        sourceName: 'a',
        remotePath: '/b.mp3',
        fileName: 'b.mp3',
        createdAt: DateTime(2026, 1, 1, 9),
        status: TaskStatus.pending,
      );
      final t3 = QueueTask(
        id: '3',
        sourceName: 'a',
        remotePath: '/c.mp3',
        fileName: 'c.mp3',
        createdAt: DateTime(2026, 1, 1, 11),
        status: TaskStatus.pending,
      );
      final active = QueueTask(
        id: '4',
        sourceName: 'a',
        remotePath: '/d.mp3',
        fileName: 'd.mp3',
        createdAt: DateTime(2026, 1, 1, 8),
        status: TaskStatus.active,
      );
      final done = QueueTask(
        id: '5',
        sourceName: 'a',
        remotePath: '/e.mp3',
        fileName: 'e.mp3',
        createdAt: DateTime(2026, 1, 1, 7),
        status: TaskStatus.completed,
      );

      final ordered = TaskQueueService.orderPending([
        t1,
        active,
        t3,
        done,
        t2,
      ]);

      expect(ordered.map((t) => t.id).toList(), ['2', '1', '3']);
    });

    test('excludes failed and cancelled from pending order', () {
      final pending = QueueTask(
        id: 'p',
        sourceName: 'a',
        remotePath: '/p.mp3',
        fileName: 'p.mp3',
        createdAt: DateTime(2026, 2, 1),
        status: TaskStatus.pending,
      );
      final failed = QueueTask(
        id: 'f',
        sourceName: 'a',
        remotePath: '/f.mp3',
        fileName: 'f.mp3',
        createdAt: DateTime(2026, 1, 1),
        status: TaskStatus.failed,
      );
      final cancelled = QueueTask(
        id: 'c',
        sourceName: 'a',
        remotePath: '/c.mp3',
        fileName: 'c.mp3',
        createdAt: DateTime(2026, 1, 2),
        status: TaskStatus.cancelled,
      );

      final ordered = TaskQueueService.orderPending([
        failed,
        cancelled,
        pending,
      ]);
      expect(ordered, hasLength(1));
      expect(ordered.single.id, 'p');
    });

    test('empty input yields empty order', () {
      expect(TaskQueueService.orderPending([]), isEmpty);
    });

    test('skips non-download kinds (shell has no executor yet)', () {
      final download = QueueTask(
        id: 'd',
        sourceName: 'a',
        remotePath: '/d.mp3',
        fileName: 'd.mp3',
        createdAt: DateTime(2026, 1, 1),
        status: TaskStatus.pending,
        kind: TaskKind.download,
      );
      final scan = QueueTask(
        id: 's',
        sourceName: 'a',
        remotePath: '/album',
        fileName: 'album',
        createdAt: DateTime(2026, 1, 1),
        status: TaskStatus.pending,
        kind: TaskKind.scan,
        progressMode: TaskProgressMode.units,
        unitsTotal: 10,
      );
      final ordered = TaskQueueService.orderPending([scan, download]);
      expect(ordered.map((t) => t.id).toList(), ['d']);
    });
  });
}
