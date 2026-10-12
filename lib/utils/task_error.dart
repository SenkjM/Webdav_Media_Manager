import 'dart:io';

import 'package:dio/dio.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/cloud_driver_errors.dart';

/// Stable task-queue error: short code for the list, full [detail] for the dialog.
///
/// Persisted as `code` or `code|detail` (first `|` splits). Dotted codes such as
/// `err.net.dns` are intentional — parse by the first bar, not by a short regex.
class TaskError {
  const TaskError(this.code, [this.detail = '']);

  final String code;
  final String detail;

  String get persisted => detail.isEmpty ? code : '$code|$detail';

  static const prefixes = [
    'Bad state: ',
    'WmpFormatException: ',
    'Unsupported operation: ',
    'Invalid argument(s): ',
  ];

  static final _coded = RegExp(
    r'^(err\.[A-Za-z0-9.]+)(?:\|(.*))?$',
    dotAll: true,
  );

  static String stripWrappers(String raw) {
    var text = raw;
    for (final prefix in prefixes) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length);
        break;
      }
    }
    return text;
  }

  /// Persist a fresh failure: Dio / Socket / existing `err.*` → stable code + detail.
  static TaskError classify(Object error) {
    if (error is DioException) return _fromDio(error);
    if (error is SocketException) {
      return _fromText(error.toString(), fallbackDetail: error.toString());
    }
    final text = stripWrappers(error.toString());
    if (text.startsWith('err.')) return parse(text);
    if (text.contains('has no column named')) {
      return TaskError('err.dlQueueSchemaDrift', text);
    }
    return _fromText(text, fallbackDetail: text);
  }

  /// Read a persisted row (or legacy raw Dio / Socket text).
  static TaskError parse(String raw) {
    final text = stripWrappers(raw);
    final match = _coded.firstMatch(text);
    if (match != null) {
      return TaskError(match.group(1)!, match.group(2) ?? '');
    }
    return _fromText(text, fallbackDetail: text);
  }

  static TaskError _fromDio(DioException e) {
    final detail = e.toString();
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return TaskError('err.net.timeout', detail);
      case DioExceptionType.cancel:
        return const TaskError('err.cancelled');
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        if (status == 401) return TaskError('err.cloud.unauthorized', detail);
        if (status == 403) return TaskError('err.cloud.forbidden', detail);
        if (status == 404) return TaskError('err.cloud.notFound', detail);
        if (status != null && status >= 500) {
          return TaskError('err.cloud.server', detail);
        }
        return TaskError(
          'err.cloud.http',
          status == null ? detail : 'HTTP $status|$detail',
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        final nested = (e.error ?? e).toString();
        return _fromText(nested, fallbackDetail: detail);
      case DioExceptionType.badCertificate:
        return TaskError('err.net.connection', detail);
      case DioExceptionType.transformTimeout:
        return TaskError('err.net.timeout', detail);
    }
  }

  static TaskError _fromText(String text, {required String fallbackDetail}) {
    final lower = text.toLowerCase();
    if (_isCancelledText(lower)) {
      return TaskError('err.cancelled', fallbackDetail);
    }
    if (_isDns(lower)) return TaskError('err.net.dns', fallbackDetail);
    if (_isUnreachable(lower)) {
      return TaskError('err.net.unreachable', fallbackDetail);
    }
    if (_isTimeout(lower)) return TaskError('err.net.timeout', fallbackDetail);
    if (_isForbidden(lower)) {
      return TaskError('err.cloud.forbidden', fallbackDetail);
    }
    if (_isUnauthorized(lower)) {
      return TaskError('err.cloud.unauthorized', fallbackDetail);
    }
    if (_isNotFound(lower)) {
      return TaskError('err.cloud.notFound', fallbackDetail);
    }
    if (_isServer(lower)) return TaskError('err.cloud.server', fallbackDetail);
    if (_isConnection(lower)) {
      return TaskError('err.net.connection', fallbackDetail);
    }
    return TaskError('err.unknown', fallbackDetail);
  }

  static bool _isDns(String lower) =>
      lower.contains('failed host lookup') ||
      lower.contains('unable to resolve host') ||
      lower.contains('no address associated') ||
      lower.contains('nodename nor servname') ||
      lower.contains('name or service not known');

  static bool _isUnreachable(String lower) =>
      lower.contains('network is unreachable') ||
      lower.contains('network is down') ||
      lower.contains('network unreachable');

  static bool _isTimeout(String lower) =>
      lower.contains('timeout') ||
      lower.contains('timed out') ||
      lower.contains('time out');

  static bool _isForbidden(String lower) =>
      lower.contains('403') ||
      lower.contains('forbidden') ||
      lower.contains('permission denied') ||
      lower.contains('access denied');

  static bool _isUnauthorized(String lower) =>
      lower.contains('401') || lower.contains('unauthorized');

  static bool _isNotFound(String lower) =>
      lower.contains('404') ||
      RegExp(r'\bnot found\b').hasMatch(lower) ||
      lower.contains('no such file');

  static bool _isServer(String lower) =>
      lower.contains('500') ||
      lower.contains('502') ||
      lower.contains('503') ||
      lower.contains('504') ||
      lower.contains('internal server error') ||
      lower.contains('bad gateway') ||
      lower.contains('service unavailable');

  static bool _isConnection(String lower) =>
      lower.contains('connection') ||
      lower.contains('connection reset') ||
      lower.contains('connection refused') ||
      lower.contains('broken pipe') ||
      lower.contains('software caused connection abort');

  static bool _isCancelledText(String lower) =>
      lower == 'err.cancelled' ||
      lower.contains('dioexceptiontype.cancel') ||
      lower.contains('request cancelled') ||
      lower == 'cancel' ||
      lower.startsWith('cancel:');

  /// List row: short, recognizable label (no Dio dump).
  static String shortLabel(String raw, AppLocalizations l10n) {
    final err = parse(raw);
    return _shortFor(err, l10n);
  }

  /// Dialog / secondary entry: full original detail (unwrap retry wrappers).
  static String detailText(String raw) {
    var err = parse(raw);
    while (err.code == 'err.dlRetryExhausted') {
      final bar = err.detail.indexOf('|');
      if (bar <= 0) break;
      err = parse(err.detail.substring(bar + 1));
    }
    if (err.detail.isNotEmpty) return err.detail;
    return err.persisted;
  }

  static String _shortFor(TaskError err, AppLocalizations l10n) {
    switch (err.code) {
      case 'err.net.dns':
        return l10n.taskErrNetDns;
      case 'err.net.timeout':
        return l10n.taskErrNetTimeout;
      case 'err.net.unreachable':
        return l10n.taskErrNetUnreachable;
      case 'err.net.connection':
        return l10n.taskErrNetConnection;
      case 'err.cloud.unauthorized':
        return l10n.taskErrCloudUnauthorized;
      case 'err.cloud.forbidden':
        return l10n.taskErrCloudForbidden;
      case 'err.cloud.notFound':
        return l10n.taskErrCloudNotFound;
      case 'err.cloud.server':
        return l10n.taskErrCloudServer;
      case 'err.cloud.http':
        return l10n.taskErrCloudHttp;
      case 'err.cancelled':
        return l10n.downloadCancelled;
      case 'err.unknown':
        return l10n.taskErrUnknown;
      case 'err.queueCleared':
        return l10n.dlErrQueueCleared;
      case 'err.cueMalformed':
        return l10n.dlErrCueMalformed;
      case 'err.writePublicFailed':
        return l10n.dlErrWritePublicFailed;
      case 'err.dlOffline':
        return l10n.dlErrOffline;
      case 'err.sourceUnbound':
        return l10n.taskErrSourceUnbound;
      case 'err.dlQueueSchemaDrift':
        return l10n.taskErrQueueSchemaDrift;
      case 'err.dlOfflineRetryWait':
        final wait = err.detail.split('|');
        if (wait.length >= 3) {
          return l10n.dlOfflineRetryWait(wait[0], wait[1], wait[2]);
        }
        return l10n.dlErrOffline;
      case 'err.dlNetworkInterruptedRetry':
        final parts = err.detail.split('|');
        if (parts.length >= 2) {
          return l10n.dlNetworkInterruptedRetry(parts[0], parts[1]);
        }
        return l10n.taskErrNetConnection;
      case 'err.dlRetryExhausted':
        final bar = err.detail.indexOf('|');
        final nested = bar > 0 ? err.detail.substring(bar + 1) : err.detail;
        final reason = nested.isEmpty
            ? l10n.taskErrUnknown
            : shortLabel(nested, l10n);
        return l10n.taskErrRetryExhausted(reason);
      case 'err.shardKindMismatch':
        return l10n.taskErrUnknown;
      case 'err.notWdmmFile':
        return l10n.errNotWdmmFile;
      default:
        // Other err.* (cloud drivers etc.): prefer a single short line.
        // CloudDriverErrors often embeds detail — trim to first sentence / 40 chars.
        final localized = CloudDriverErrors.describe(err.persisted, l10n);
        if (localized != err.persisted && localized.length <= 40) {
          return localized;
        }
        if (err.code.startsWith('err.')) return l10n.taskErrUnknown;
        return localized.length <= 48
            ? localized
            : '${localized.substring(0, 45)}…';
    }
  }
}
