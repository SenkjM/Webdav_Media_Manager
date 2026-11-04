import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/queue_task.dart';
import 'package:webdav_media_manager/services/task_queue_service.dart';
import 'package:webdav_media_manager/services/wdmm_vfs.dart';

/// Slice 10 moved the retry rules (caps, backoff, offline detection, verdict)
/// into Rust (`crates/wdmm-queue/src/policy.rs`, tested there). Dart is left
/// with exactly one job: classify the exception so Rust knows what it is
/// looking at.
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

DioException _dio(DioExceptionType type, {int? status, Object? error}) =>
    DioException(
      requestOptions: RequestOptions(path: '/a'),
      type: type,
      error: error,
      response: status == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: '/a'),
              statusCode: status,
            ),
    );

void main() {
  group('异常分类', () {
    test('上游 HTTP 失败（含 401/403/404）都归 dio', () {
      for (final status in [401, 403, 404, 503]) {
        expect(
          TaskQueueService.failureCategory(
            _dio(DioExceptionType.badResponse, status: status),
          ),
          'dio',
        );
      }
    });

    test('连接类 Dio 失败也归 dio', () {
      expect(
        TaskQueueService.failureCategory(
          _dio(DioExceptionType.connectionError),
        ),
        'dio',
      );
      expect(
        TaskQueueService.failureCategory(
          _dio(DioExceptionType.connectionTimeout),
        ),
        'dio',
      );
    });

    test('取消只是 flag，类别仍是 dio（Rust 用 cancelled 判 cancel）', () {
      expect(
        TaskQueueService.failureCategory(_dio(DioExceptionType.cancel)),
        'dio',
      );
    });

    test('内容损坏归 vfs_data，本地状态归 state', () {
      expect(
        TaskQueueService.failureCategory(
          const WdmmVfsDataException('decrypt failed'),
        ),
        'vfs_data',
      );
      expect(TaskQueueService.failureCategory(StateError('x')), 'state');
    });

    test('认不出来的错误归 other（Rust 仍按可重试兜底）', () {
      expect(TaskQueueService.failureCategory(Exception('莫名其妙')), 'other');
      expect(TaskQueueService.failureCategory(Object()), 'other');
      expect(
        TaskQueueService.failureCategory(const SocketException('broken pipe')),
        'other',
      );
    });
  });

  group('离线文案提取', () {
    test('Dio 失败取内层 error 文本（DNS 文案挂在那里）', () {
      final error = _dio(
        DioExceptionType.connectionError,
        error: const SocketException('Failed host lookup: example.com'),
      );
      expect(
        TaskQueueService.failureMessage(error),
        contains('Failed host lookup'),
      );
    });

    test('非 Dio 错误直接用 toString', () {
      expect(
        TaskQueueService.failureMessage(
          const SocketException('Network is unreachable'),
        ),
        contains('Network is unreachable'),
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
