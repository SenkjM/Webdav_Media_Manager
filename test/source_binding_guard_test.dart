import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture guard: a library row is bound to a disk **name**, while the
/// WebDAV layer needs a local account **id**.
///
/// Passing a name where an id is expected fails silently at runtime
/// (`UnknownWebDavAccountException: 来源网盘已移除或未配置（123）`) and cost a real
/// debugging round, so the resolution rule is asserted here instead of trusted
/// to review. The download queue itself now lives in the Rust core and resolves
/// the account id from `account_id` at enqueue time, so the Dart-side guard is
/// limited to the accounts service every caller resolves through.
void main() {
  group('source name vs account id', () {
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
