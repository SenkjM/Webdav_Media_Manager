import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/queue_task.dart';
import 'package:webdav_media_manager/services/task_queue_service.dart';

QueueTask _task(
  String id, {
  TaskStatus status = TaskStatus.pending,
  DateTime? nextRetryAt,
}) => QueueTask(
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
      : Response(
          requestOptions: RequestOptions(path: '/a'),
          statusCode: status,
        ),
);

void main() {
  group('错误分类', () {
    test('认不出来的错误默认按可重试兜底', () {
      expect(TaskQueueService.isRetryable(Exception('莫名其妙')), isTrue);
      expect(TaskQueueService.isRetryable(Object()), isTrue);
    });

    test('上游错误都重试，包括授权和 404', () {
      expect(
        TaskQueueService.isRetryable(
          _dio(DioExceptionType.badResponse, status: 404),
        ),
        isTrue,
      );
      expect(
        TaskQueueService.isRetryable(
          _dio(DioExceptionType.badResponse, status: 403),
        ),
        isTrue,
      );
      expect(
        TaskQueueService.isRetryable(
          _dio(DioExceptionType.badResponse, status: 401),
        ),
        isTrue,
      );
      expect(
        TaskQueueService.isRetryable(Exception('HTTP 401 Unauthorized')),
        isTrue,
      );
      expect(
        TaskQueueService.isRetryable(Exception('403 forbidden')),
        isTrue,
      );
    });

    test('取消和本地状态错误不重试', () {
      expect(
        TaskQueueService.isRetryable(_dio(DioExceptionType.cancel)),
        isFalse,
      );
      expect(TaskQueueService.isRetryable(StateError('x')), isFalse);
    });

    test('网络与 5xx 可重试', () {
      expect(
        TaskQueueService.isRetryable(
          _dio(DioExceptionType.connectionError),
        ),
        isTrue,
      );
      expect(
        TaskQueueService.isRetryable(
          _dio(DioExceptionType.connectionTimeout),
        ),
        isTrue,
      );
      expect(
        TaskQueueService.isRetryable(
          _dio(DioExceptionType.badResponse, status: 503),
        ),
        isTrue,
      );
      expect(
        TaskQueueService.isRetryable(const SocketException('broken pipe')),
        isTrue,
      );
    });

    test('「根本没网」单独识别，不消耗重试次数', () {
      expect(
        TaskQueueService.isOfflineError(
          _dio(DioExceptionType.connectionError),
        ),
        isFalse,
      );
      expect(
        TaskQueueService.isOfflineError(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionError,
            error: const SocketException('Network is unreachable'),
          ),
        ),
        isTrue,
      );
      expect(
        TaskQueueService.isOfflineError(
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
        final ms = TaskQueueService.retryDelay(i + 1).inMilliseconds;
        expect(ms, greaterThanOrEqualTo(bases[i]));
        expect(ms, lessThan(bases[i] + 1000));
      }
    });

    test('没网固定 10 秒，其它按退避表', () {
      expect(
        TaskQueueService.retryDelayFor(3, offline: true),
        const Duration(seconds: 10),
      );
      final backoff = TaskQueueService.retryDelayFor(
        1,
        offline: false,
      ).inMilliseconds;
      expect(backoff, greaterThanOrEqualTo(2000));
      expect(backoff, lessThan(3000));
    });

    test('无网等待是 10 秒（断网时用户等的就是它）', () {
      expect(
        TaskQueueService.offlineRetryDelay,
        const Duration(seconds: 10),
      );
    });

    test('超过上限不再增长', () {
      expect(
        TaskQueueService.retryDelay(9).inMilliseconds,
        lessThan(33000),
      );
    });
  });

  group('后台 offline 上限', () {
    test('后台 offline 3 次到顶，前台 offline 与其它错误仍是 5', () {
      expect(TaskQueueService.backgroundOfflineMaxAutoRetries, 3);
      expect(TaskQueueService.maxAutoRetries, 5);
      expect(
        TaskQueueService.autoRetryCap(inBackground: true, offline: true),
        3,
      );
      expect(
        TaskQueueService.autoRetryCap(inBackground: false, offline: true),
        5,
      );
      expect(
        TaskQueueService.autoRetryCap(inBackground: true, offline: false),
        5,
      );

      const offline = SocketException('Failed host lookup: example.com');
      expect(
        TaskQueueService.shouldAutoRetry(
          attempts: 2,
          error: offline,
          inBackground: true,
        ),
        isTrue,
      );
      expect(
        TaskQueueService.shouldAutoRetry(
          attempts: 3,
          error: offline,
          inBackground: true,
        ),
        isFalse,
      );
      expect(
        TaskQueueService.shouldAutoRetry(
          attempts: 4,
          error: offline,
          inBackground: false,
        ),
        isTrue,
      );
      expect(
        TaskQueueService.shouldAutoRetry(
          attempts: 5,
          error: offline,
          inBackground: false,
        ),
        isFalse,
      );
      expect(
        TaskQueueService.shouldAutoRetry(
          attempts: 4,
          error: _dio(DioExceptionType.connectionTimeout),
          inBackground: true,
        ),
        isTrue,
      );
      expect(
        TaskQueueService.shouldAutoRetry(
          attempts: 0,
          error: StateError('x'),
          inBackground: true,
        ),
        isFalse,
      );
    });
  });

  group('调度', () {
    test('等退避中的任务不参与本轮调度', () {
      final now = DateTime.now();
      final tasks = [
        _task('ready'),
        _task('waiting', nextRetryAt: now.add(const Duration(seconds: 30))),
        _task('due', nextRetryAt: now.subtract(const Duration(seconds: 1))),
        _task('active', status: TaskStatus.active),
      ];
      expect(
        TaskQueueService.orderPending(tasks).map((t) => t.id).toList(),
        ['ready', 'due'],
      );
    });
  });
}
