import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_music_player/models/download_task.dart';
import 'package:webdav_music_player/services/download_queue_service.dart';

void main() {
  group('DownloadQueueService.orderPending', () {
    test('orders pending tasks FIFO by createdAt', () {
      final t1 = DownloadTask(
        id: '1',
        remotePath: '/a.mp3',
        fileName: 'a.mp3',
        createdAt: DateTime(2026, 1, 1, 10),
        status: DownloadStatus.pending,
      );
      final t2 = DownloadTask(
        id: '2',
        remotePath: '/b.mp3',
        fileName: 'b.mp3',
        createdAt: DateTime(2026, 1, 1, 9),
        status: DownloadStatus.pending,
      );
      final t3 = DownloadTask(
        id: '3',
        remotePath: '/c.mp3',
        fileName: 'c.mp3',
        createdAt: DateTime(2026, 1, 1, 11),
        status: DownloadStatus.pending,
      );
      final active = DownloadTask(
        id: '4',
        remotePath: '/d.mp3',
        fileName: 'd.mp3',
        createdAt: DateTime(2026, 1, 1, 8),
        status: DownloadStatus.active,
      );
      final done = DownloadTask(
        id: '5',
        remotePath: '/e.mp3',
        fileName: 'e.mp3',
        createdAt: DateTime(2026, 1, 1, 7),
        status: DownloadStatus.completed,
      );

      final ordered = DownloadQueueService.orderPending([
        t1,
        active,
        t3,
        done,
        t2,
      ]);

      expect(ordered.map((t) => t.id).toList(), ['2', '1', '3']);
    });

    test('excludes failed and cancelled from pending order', () {
      final pending = DownloadTask(
        id: 'p',
        remotePath: '/p.mp3',
        fileName: 'p.mp3',
        createdAt: DateTime(2026, 2, 1),
        status: DownloadStatus.pending,
      );
      final failed = DownloadTask(
        id: 'f',
        remotePath: '/f.mp3',
        fileName: 'f.mp3',
        createdAt: DateTime(2026, 1, 1),
        status: DownloadStatus.failed,
      );
      final cancelled = DownloadTask(
        id: 'c',
        remotePath: '/c.mp3',
        fileName: 'c.mp3',
        createdAt: DateTime(2026, 1, 2),
        status: DownloadStatus.cancelled,
      );

      final ordered =
          DownloadQueueService.orderPending([failed, cancelled, pending]);
      expect(ordered, hasLength(1));
      expect(ordered.single.id, 'p');
    });

    test('empty input yields empty order', () {
      expect(DownloadQueueService.orderPending([]), isEmpty);
    });
  });
}
