import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/l10n/generated/app_localizations.dart';
import 'package:webdav_media_manager/utils/task_error.dart';

DioException _dio(
  DioExceptionType type, {
  int? status,
  Object? error,
}) => DioException(
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  group('TaskError.classify', () {
    test('DNS / host lookup → err.net.dns', () {
      final err = TaskError.classify(
        const SocketException('Failed host lookup: example.com'),
      );
      expect(err.code, 'err.net.dns');
      expect(err.detail, contains('Failed host lookup'));
      expect(err.persisted, startsWith('err.net.dns|'));
    });

    test('Dio connectionError with unreachable → err.net.unreachable', () {
      final err = TaskError.classify(
        _dio(
          DioExceptionType.connectionError,
          error: const SocketException('Network is unreachable'),
        ),
      );
      expect(err.code, 'err.net.unreachable');
    });

    test('timeouts → err.net.timeout', () {
      expect(
        TaskError.classify(_dio(DioExceptionType.connectionTimeout)).code,
        'err.net.timeout',
      );
      expect(
        TaskError.classify(_dio(DioExceptionType.receiveTimeout)).code,
        'err.net.timeout',
      );
    });

    test('HTTP status → cloud codes', () {
      expect(
        TaskError.classify(_dio(DioExceptionType.badResponse, status: 401)).code,
        'err.cloud.unauthorized',
      );
      expect(
        TaskError.classify(_dio(DioExceptionType.badResponse, status: 403)).code,
        'err.cloud.forbidden',
      );
      expect(
        TaskError.classify(_dio(DioExceptionType.badResponse, status: 404)).code,
        'err.cloud.notFound',
      );
      expect(
        TaskError.classify(_dio(DioExceptionType.badResponse, status: 503)).code,
        'err.cloud.server',
      );
    });

    test('cancel → err.cancelled', () {
      expect(
        TaskError.classify(_dio(DioExceptionType.cancel)).code,
        'err.cancelled',
      );
    });

    test('existing err.* StateError kept', () {
      final err = TaskError.classify(StateError('err.sourceUnbound|diskA'));
      expect(err.code, 'err.sourceUnbound');
      expect(err.detail, 'diskA');
    });

    test('schema drift text → err.dlQueueSchemaDrift', () {
      final err = TaskError.classify(
        Exception('table download_queue has no column named attempts'),
      );
      expect(err.code, 'err.dlQueueSchemaDrift');
    });
  });

  group('TaskError.parse legacy raw', () {
    test('raw Dio-like timeout text classifies', () {
      final err = TaskError.parse(
        'DioException [connection timeout]: timed out',
      );
      expect(err.code, 'err.net.timeout');
    });

    test('already coded row unchanged', () {
      final err = TaskError.parse(
        'err.net.dns|SocketException: Failed host lookup',
      );
      expect(err.code, 'err.net.dns');
      expect(err.detail, 'SocketException: Failed host lookup');
    });
  });

  group('short / detail labels', () {
    test('short labels are stable Chinese phrases', () {
      expect(
        TaskError.shortLabel('err.net.dns|x', zh),
        '网络错误：DNS',
      );
      expect(
        TaskError.shortLabel('err.net.timeout|x', zh),
        '网络错误：超时',
      );
      expect(
        TaskError.shortLabel('err.cloud.forbidden|x', zh),
        '云端权限不足',
      );
      expect(
        TaskError.shortLabel('err.cloud.notFound|x', zh),
        '云端文件不存在',
      );
      expect(TaskError.shortLabel('err.cancelled', zh), '已取消');
      expect(
        TaskError.shortLabel(
          'err.dlRetryExhausted|5|err.net.timeout|Dio boom',
          zh,
        ),
        '重试已尽 · 网络错误：超时',
      );
    });

    test('detail unwraps retry and keeps original', () {
      expect(
        TaskError.detailText(
          'err.dlRetryExhausted|5|err.net.timeout|DioException boom',
        ),
        'DioException boom',
      );
      expect(
        TaskError.detailText('err.cloud.notFound|HTTP 404 on /a.flac'),
        'HTTP 404 on /a.flac',
      );
    });
  });
}
