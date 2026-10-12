import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:webdav_media_manager/models/music_library_backfill_root.dart';
import 'package:webdav_media_manager/services/library_backfill.dart';
import 'package:webdav_media_manager/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MusicLibraryBackfillRoot normalizes path and dedupes', () {
    final a = MusicLibraryBackfillRoot.fromJson({
      'accountId': 'acc1',
      'path': 'Music/',
    });
    expect(a.path, '/Music');
    expect(a.accountId, 'acc1');
    final b = const MusicLibraryBackfillRoot(accountId: 'acc1', path: '/Music');
    expect(a, b);
    expect(a.identityKey, b.identityKey);
  });

  test('auto backfill prefs default and persist (bind roots)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fresh = SettingsService(prefs: prefs);
    await fresh.init();

    expect(fresh.musicLibraryAutoBackfill, isFalse);
    expect(fresh.musicLibraryBackfillBindRoots, isFalse);
    expect(fresh.musicLibraryBackfillRoots, isEmpty);

    await fresh.setMusicLibraryAutoBackfill(true);
    await fresh.setMusicLibraryBackfillBindRoots(true);
    await fresh.addMusicLibraryBackfillRoot(
      const MusicLibraryBackfillRoot(accountId: 'acc1', path: '/Music'),
    );
    await fresh.addMusicLibraryBackfillRoot(
      const MusicLibraryBackfillRoot(accountId: 'acc1', path: '/Music/'),
    );

    expect(fresh.musicLibraryAutoBackfill, isTrue);
    expect(fresh.musicLibraryBackfillBindRoots, isTrue);
    expect(fresh.musicLibraryBackfillRoots, hasLength(1));
    expect(fresh.musicLibraryBackfillRoots.single.path, '/Music');

    final restored = SettingsService(prefs: prefs);
    await restored.init();
    expect(restored.musicLibraryAutoBackfill, isTrue);
    expect(restored.musicLibraryBackfillBindRoots, isTrue);
    expect(restored.musicLibraryBackfillRoots.single.accountId, 'acc1');
    expect(restored.musicLibraryBackfillRoots.single.path, '/Music');
  });

  test('legacy music_library_backfill_on_open key is ignored', () async {
    SharedPreferences.setMockInitialValues({
      'music_library_backfill_on_open': false,
      'music_library_auto_backfill': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsService(prefs: prefs);
    await s.init();
    // Auto on → play trigger always allowed; legacy on-open false is ignored.
    expect(s.musicLibraryAutoBackfill, isTrue);
    expect(shouldPlayTriggerBackfill(s), isTrue);
  });

  test('shouldPlayTriggerBackfill follows auto mode only', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsService(prefs: prefs);
    await s.init();

    expect(shouldPlayTriggerBackfill(s), isFalse);

    await s.setMusicLibraryAutoBackfill(true);
    expect(shouldPlayTriggerBackfill(s), isTrue);

    await s.setMusicLibraryAutoBackfill(false);
    expect(shouldPlayTriggerBackfill(s), isFalse);
  });

  test('shouldBackfillForPlayingTrack respects bind filter', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsService(prefs: prefs);
    await s.init();
    await s.setMusicLibraryAutoBackfill(true);

    // Bind off → always allow.
    expect(
      shouldBackfillForPlayingTrack(
        settings: s,
        accountId: 'acc1',
        remotePath: '/Other/a.mp3',
      ),
      isTrue,
    );

    await s.setMusicLibraryBackfillBindRoots(true);
    expect(
      shouldBackfillForPlayingTrack(
        settings: s,
        accountId: 'acc1',
        remotePath: '/Music/a.mp3',
      ),
      isFalse,
    );

    await s.addMusicLibraryBackfillRoot(
      const MusicLibraryBackfillRoot(accountId: 'acc1', path: '/Music'),
    );
    expect(
      shouldBackfillForPlayingTrack(
        settings: s,
        accountId: 'acc1',
        remotePath: '/Music/Album/a.mp3',
      ),
      isTrue,
    );
    expect(
      shouldBackfillForPlayingTrack(
        settings: s,
        accountId: 'acc1',
        remotePath: '/Other/a.mp3',
      ),
      isFalse,
    );
    expect(
      shouldBackfillForPlayingTrack(
        settings: s,
        accountId: 'acc2',
        remotePath: '/Music/a.mp3',
      ),
      isFalse,
    );
  });

  test('remotePathMatchesBoundRoot prefix rules', () {
    const roots = [
      MusicLibraryBackfillRoot(accountId: 'a', path: '/Music'),
      MusicLibraryBackfillRoot(accountId: 'b', path: '/'),
    ];
    expect(
      remotePathMatchesBoundRoot(
        accountId: 'a',
        remotePath: '/Music/x.mp3',
        roots: roots,
      ),
      isTrue,
    );
    expect(
      remotePathMatchesBoundRoot(
        accountId: 'a',
        remotePath: '/MusicExtra/x.mp3',
        roots: roots,
      ),
      isFalse,
    );
    expect(
      remotePathMatchesBoundRoot(
        accountId: 'b',
        remotePath: '/anything/x.mp3',
        roots: roots,
      ),
      isTrue,
    );
  });
}
