import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:webdav_media_manager/screens/sync_screen.dart';
import 'package:webdav_media_manager/providers/app_state.dart';
import 'package:webdav_media_manager/services/accounts_service.dart';
import 'package:webdav_media_manager/services/cloud_drive_service.dart';
import 'package:webdav_media_manager/services/rust_core_service.dart';
import 'package:webdav_media_manager/services/settings_service.dart';
import 'package:webdav_media_manager/services/sync_service.dart';

import 'e2e_support.dart';

/// Sync module: the remote-root field keeps what the user typed (it used to be
/// rewritten by the normalisation), sync writes through the account the page
/// shows, and a real credential round trip lands on the configured root.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sync: the root field keeps input and sync uses the shown account',
      (tester) async {
    expect(webdavConfigured, isTrue, reason: 'E2E_WEBDAV_* are not set');
    await bootApp(tester);
    ensureE2eAccount();

    final settings = appService<SettingsService>(tester);
    final accounts = appService<AccountsService>(tester);
    final sync = appService<SyncService>(tester);

    // `ensureE2eAccount` only writes the account into the Rust core; reload the
    // Dart mirror so the list the page reads contains it, then register the
    // client routes AppState owns. Without both the vault refuses to push
    // ("err.vaultDestNotConfigured") even though the account exists natively.
    await accounts.init();
    await appService<AppState>(tester).registerAllAccounts();

    final account = accounts.accountForSource(e2eAccountName);
    expect(account, isNotNull, reason: 'the e2e account is missing');

    final originalRoot = settings.syncRemoteRoot;
    final originalAccount = settings.syncAccountId;
    // The lab root is a fixed value on purpose: it is where the account's file
    // source actually is writable, and it stays applied after the run so the
    // operator (and the backup suite) can keep using the same folder. Wiping or
    // restoring it on every run made the module untestable by hand.
    const typedRoot = '/WDMM';
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);

    try {
      // 1) The pinned account *is* the destination, and it is writable.
      await settings.setSyncAccountId(account!.id);
      expect(await sync.syncDestination(), account.id,
          reason: 'sync must write through the account the page shows');
      expect(sync.targetAccount?.id, account.id,
          reason: 'the destination account must be the displayed one');

      // 2) Drive the real page: the field must not be rewritten for the user.
      unawaited(navigator.push(
        MaterialPageRoute<void>(builder: (_) => const SyncScreen()),
      ));
      await pumpFrames(tester, frames: 24, label: 'sync screen');

      final field = find.byKey(const ValueKey('sync.remoteRoot'));
      final apply = find.byKey(const ValueKey('sync.applyRoot'));
      expect(field, findsOneWidget, reason: 'the sync root field is missing');
      expect(apply, findsOneWidget, reason: 'the apply button is missing');
      expect(_text(tester, field), originalRoot);

      await tester.enterText(field, typedRoot);
      await tester.tap(apply);
      await pumpFrames(tester, frames: 16, label: 'apply root');
      expect(settings.syncRemoteRoot, '$typedRoot/',
          reason: 'the stored root must be normalised with a trailing slash');
      expect(_text(tester, field), typedRoot,
          reason: 'the field must keep exactly what the user typed');
      expect(settings.credentialsRemotePath, startsWith('$typedRoot/'));
      expect(settings.playlistRemotePath, startsWith('$typedRoot/'));
      expect(settings.backupRemotePath, startsWith('$typedRoot/'));

      // 3) An empty root is rejected instead of silently becoming the default.
      await tester.enterText(field, '   ');
      await tester.tap(apply);
      await pumpFrames(tester, frames: 12, label: 'empty root');
      expect(settings.syncRemoteRoot, '$typedRoot/',
          reason: 'an empty root must not replace the stored one');
      expect(_text(tester, field), '   ',
          reason: 'a rejected edit must not be rewritten either');

      // Put the fixture back: the operator reads this field after the run and
      // the backup suite derives its folder from it.
      await tester.enterText(field, typedRoot);
      await tester.tap(apply);
      await pumpFrames(tester, frames: 12, label: 'restore root');
      expect(settings.syncRemoteRoot, '$typedRoot/');
      expect(_text(tester, field), typedRoot);

      // 4) A real round trip through the configured destination.
      const passphrase = 'e2e-sync-passphrase';
      final pushed = await sync.pushCredentials(passphrase: passphrase);
      expect(pushed.ok, isTrue,
          reason: 'credential push failed: ${pushed.error}');
      expect(pushed.steps, isNotEmpty);
      final pulled = await sync.pullCredentials(passphrase: passphrase);
      expect(pulled.ok, isTrue,
          reason: 'credential pull failed: ${pulled.error}');
      expect(pulled.steps, isNotEmpty);

      // 5) The real engines behind "全部同步": the library and playlist syncs
      //    both go through Core and must leave the vault + their own documents
      //    on the cloud root the page shows. Seed one library row first so the
      //    library engine actually has something to push.
      final trackPath = findAudioFile();
      final seeded = await RustCoreService.libraryIngestAsync(jsonEncode({
        'account_id': e2eAccountId,
        'remote_path': trackPath,
        'file_name': trackPath.split('/').last,
        'source_name': e2eAccountName,
      }));
      expect(seeded, isNotNull, reason: 'libraryIngest returned null');
      expect(seeded!.startsWith('error:'), isFalse,
          reason: 'libraryIngest failed: $seeded');

      final library = await sync.syncLibraryIncremental();
      expect(library.ok, isTrue,
          reason: 'library sync failed: ${library.error}');
      expect(library.steps, isNotEmpty);
      final playlists = await sync.syncPlaylistsNow();
      expect(playlists.ok, isTrue,
          reason: 'playlist sync failed: ${playlists.error}');
      expect(playlists.steps, isNotEmpty);

      // Core resolves the sync root against the account's file source, so the
      // files land under `<source><root>` (the server-absolute spelling the
      // native driver sees).
      final serverRoot = CloudDriveService.joinRemotePath(account, typedRoot);
      final remoteNames = listDir(serverRoot)
          .map((e) => e['name'] as String? ?? '')
          .toList();
      expect(remoteNames, contains('credentials.wdmcv'),
          reason: 'pushCredentials must write the vault under $serverRoot');
      expect(remoteNames, contains('library'),
          reason: 'the library engine must create its folder under $serverRoot: '
              '$remoteNames');
      debugPrint('[E2E] sync ok: root=${settings.syncRemoteRoot} '
          'server=$serverRoot '
          'push=${pushed.steps.length} pull=${pulled.steps.length} '
          'library=${library.steps.length} playlists=${playlists.steps.length} '
          'remote=$remoteNames');
    } finally {
      // Deliberately leave the root at `/WDMM` and leave the synced files in
      // place: the folder is the lab fixture for both the sync and backup
      // suites, and hand testing continues from the same state.
      await settings.setSyncAccountId(originalAccount);
      if (navigator.mounted && navigator.canPop()) navigator.pop();
      await pumpFrames(tester, frames: 8);
    }
  });
}

String _text(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!.text;
