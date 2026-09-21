import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture guard: a library row / download task is bound to a disk **name**,
/// while the WebDAV layer needs a local account **id**.
///
/// Passing a name where an id is expected fails silently at runtime
/// (`UnknownWebDavAccountException: 来源网盘已移除或未配置（123）`) and cost a real
/// debugging round, so the rule is asserted here instead of trusted to review.
void main() {
  group('source name vs account id', () {
    test(
      'the download queue never hands a source name to the WebDAV layer',
      () {
        final source = File('lib/services/download_queue_service.dart')
            .readAsStringSync();
        // e.g. `_webDav.downloadToFile(task.sourceName, …)` / `_webDav.readAsBytes(sourceName, …)`
        final offenders = RegExp(
          r'_webDav\.\w+\(\s*(?:task\.|track\.|cueTask\.)?sourceName\b',
        ).allMatches(source).map((m) => m.group(0)!).toList();
        expect(
          offenders,
          isEmpty,
          reason:
              'WebDAV 调用必须传 accountId（用 _accountIdFor(sourceName) 解析），'
              '不能直接传网盘名：$offenders',
        );
      },
    );

    test('the cloud library store only talks to WebDAV with account ids', () {
      final source = File('lib/services/library_sync_store.dart')
          .readAsStringSync();
      final offenders = RegExp(r'_webDav\.\w+\(\s*sourceName\b')
          .allMatches(source)
          .map((m) => m.group(0)!)
          .toList();
      expect(offenders, isEmpty);
    });

    test('every _webDav call in the queue resolves an account first', () {
      final source = File('lib/services/download_queue_service.dart')
          .readAsStringSync();
      // Each call site is checked by its first argument name being `accountId`.
      final calls = RegExp(r'_webDav\.\w+\(\s*\n?\s*([A-Za-z_][A-Za-z0-9_]*)')
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toSet();
      expect(
        calls,
        everyElement(anyOf(equals('accountId'), equals('destAccountId'))),
        reason: '下载队列里传给 WebDAV 的必须是账号 id，实际出现：$calls',
      );
    });

    test('the accounts service resolves names with normalization', () {
      final source = File('lib/services/accounts_service.dart')
          .readAsStringSync();
      // The lookup must compare normalized names (trim + collapse spaces), or a
      // trailing space in a disk name silently unbinds the whole library.
      expect(source, contains('normalizeSourceName(a.name) == wanted'));
      expect(
        source,
        contains('WebDavAccount? accountForSource(String sourceName)'),
      );
      expect(source, contains('String? idForSource(String sourceName)'));
    });
  });
}
