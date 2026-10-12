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

  test('auto backfill prefs default off and persist', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fresh = SettingsService(prefs: prefs);
    await fresh.init();

    expect(fresh.musicLibraryAutoBackfill, isFalse);
    expect(fresh.musicLibraryBackfillOnOpen, isTrue);
    expect(fresh.musicLibraryBackfillRoots, isEmpty);

    await fresh.setMusicLibraryAutoBackfill(true);
    await fresh.setMusicLibraryBackfillOnOpen(false);
    await fresh.addMusicLibraryBackfillRoot(
      const MusicLibraryBackfillRoot(accountId: 'acc1', path: '/Music'),
    );
    await fresh.addMusicLibraryBackfillRoot(
      const MusicLibraryBackfillRoot(accountId: 'acc1', path: '/Music/'),
    );

    expect(fresh.musicLibraryAutoBackfill, isTrue);
    expect(fresh.musicLibraryBackfillOnOpen, isFalse);
    expect(fresh.musicLibraryBackfillRoots, hasLength(1));
    expect(fresh.musicLibraryBackfillRoots.single.path, '/Music');

    final restored = SettingsService(prefs: prefs);
    await restored.init();
    expect(restored.musicLibraryAutoBackfill, isTrue);
    expect(restored.musicLibraryBackfillOnOpen, isFalse);
    expect(restored.musicLibraryBackfillRoots.single.accountId, 'acc1');
    expect(restored.musicLibraryBackfillRoots.single.path, '/Music');
  });

  test('shouldAutoBackfillOnLibraryOpen gates on mode, on-open, roots', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsService(prefs: prefs);
    await s.init();

    expect(shouldAutoBackfillOnLibraryOpen(s), isFalse);

    await s.setMusicLibraryAutoBackfill(true);
    expect(shouldAutoBackfillOnLibraryOpen(s), isFalse);

    await s.addMusicLibraryBackfillRoot(
      const MusicLibraryBackfillRoot(accountId: 'a', path: '/'),
    );
    expect(shouldAutoBackfillOnLibraryOpen(s), isTrue);

    await s.setMusicLibraryBackfillOnOpen(false);
    expect(shouldAutoBackfillOnLibraryOpen(s), isFalse);
  });
}
