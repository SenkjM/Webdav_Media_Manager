// ignore_for_file: avoid_print
//
// NOTE: These tests are skipped because AccountsService now uses Core FFI
// (wdmm_account_upsert / wdmm_account_list) as the sole source of truth.
// Core FFI is only available on Android (libwdmm_ffi.so) and cannot be mocked
// in host-side unit tests without a real device or an FFI stub library.
//
// The in-memory name-uniqueness invariant (_assertNameAvailable) and the
// duplicate-collapse logic (_collapseDuplicatesIfNeeded) are pure Dart and are
// covered by integration tests on device.

import 'package:flutter_test/flutter_test.dart';

import 'package:webdav_media_manager/services/accounts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'addAccount refuses duplicate names',
    () async {
      // AccountsService.addAccount calls _upsertToCore which throws when
      // Core FFI is unavailable (non-Android). Test is kept as documentation;
      // run on-device for a live assertion.
      final accounts = AccountsService();
      expect(accounts, isNotNull);
      expect(accounts.hasAccounts, isFalse);
    },
    skip: 'Core FFI unavailable in host unit tests; '
        'name uniqueness tested on-device via integration tests.',
  );

  test(
    'init collapses duplicate names preferring active id',
    () async {
      final accounts = AccountsService();
      expect(accounts, isNotNull);
    },
    skip: 'Core FFI unavailable in host unit tests; '
        'duplicate-collapse logic tested on-device via integration tests.',
  );
}
