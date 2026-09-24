import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/download_task.dart';
import 'package:webdav_media_manager/services/download_queue_service.dart';

DownloadTask _task(
  String id, {
  DownloadStatus status = DownloadStatus.pending,
  DateTime? nextRetryAt,
}) => DownloadTask(
  id: id,
  sourceName: 'src',
  remotePath: '/a.mp4',
  fileName: 'a.mp4',
  createdAt: DateTime(2026, 1, 1),
  status: status,
  nextRetryAt: nextRetryAt,
);

DioException _dio(DioExceptionType type, {int? status}) => DioException(
  requestOptions: RequestOptions(path: '/a'),
  type: type,
  response: status == null
      ? null
      : Response(requestOptions: RequestOptions(path: '/a'), statusCode: status),
);

void main() {
  group('错误分类', () {
    test('认不出来的错误默认按可重试兜底', () {
      expect(DownloadQueueService.isRetryable(Exception('莫名其妙')), isTrue);
      expect(DownloadQueueService.isRetryable(Object()), isTrue);
    });

    test('明确的客户端错误不重试', () {
      expect(
        DownloadQueueService.isRetryable(
          _dio(DioExceptionType.badResponse, status: 404),
        ),
        isFalse,
      );
      expect(
        DownloadQueueService.isRetryable(
          _dio(DioExceptionType.badResponse, status: 403),
        ),
        isFalse,
      );
      expect(
        DownloadQueueService.isRetryable(_dio(DioExceptionType.cancel)),
        isFalse,
      );
      expect(DownloadQueueService.isRetryable(StateError('x')), isFalse);
      expect(
        DownloadQueueService.isRetryable(Exception('HTTP 401 Unauthorized')),
        isFalse,
      );
    });

    test('网络与 5xx 可重试', () {
      expect(
        DownloadQueueService.isRetryable(_dio(DioExceptionType.connectionError)),
        isTrue,
      );
      expect(
        DownloadQueueService.isRetryable(
          _dio(DioExceptionType.connectionTimeout),
        ),
        isTrue,
      );
      expect(
        DownloadQueueService.isRetryable(
          _dio(DioExceptionType.badResponse, status: 503),
        ),
        isTrue,
      );
      expect(
        DownloadQueueService.isRetryable(const SocketException('broken pipe')),
        isTrue,
      );
    });

    test('「根本没网」单独识别，不消耗重试次数', () {
      expect(
        DownloadQueueService.isOfflineError(
          _dio(DioExceptionType.connectionError),
        ),
        isFalse,
      );
      expect(
        DownloadQueueService.isOfflineError(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionError,
            error: const SocketException('Network is unreachable'),
          ),
        ),
        isTrue,
      );
      expect(
        DownloadQueueService.isOfflineError(
          const SocketException('Failed host lookup: example.com'),
        ),
        isTrue,
      );
    });
  });

  group('退避', () {
    test('2/4/8/16/32 秒，带 0~1 秒抖动', () {
      const bases = [2000, 4000, 8000, 16000, 32000];
      for (var i = 0; i < bases.length; i++) {
        final ms = DownloadQueueService.retryDelay(i + 1).inMilliseconds;
        expect(ms, greaterThanOrEqualTo(bases[i]));
        expect(ms, lessThan(bases[i] + 1000));
      }
    });

    test('没网固定 10 秒，其它按退避表', () {
      expect(
        DownloadQueueService.retryDelayFor(3, offline: true),
        const Duration(seconds: 10),
      );
      final backoff = DownloadQueueService.retryDelayFor(
        1,
        offline: false,
      ).inMilliseconds;
      expect(backoff, greaterThanOrEqualTo(2000));
      expect(backoff, lessThan(3000));
    });

    test('无网等待是 10 秒（断网时用户等的就是它）', () {
      expect(
        DownloadQueueService.offlineRetryDelay,
        const Duration(seconds: 10),
      );
    });

    test('超过上限不再增长', () {
      expect(DownloadQueueService.retryDelay(9).inMilliseconds, lessThan(33000));
    });
  });

  group('调度', () {
    test('等退避中的任务不参与本轮调度', () {
      final now = DateTime.now();
      final tasks = [
        _task('ready'),
        _task('waiting', nextRetryAt: now.add(const Duration(seconds: 30))),
        _task('due', nextRetryAt: now.subtract(const Duration(seconds: 1))),
        _task('active', status: DownloadStatus.active),
      ];
      expect(
        DownloadQueueService.orderPending(tasks).map((t) => t.id).toList(),
        ['ready', 'due'],
      );
    });
  });
}
