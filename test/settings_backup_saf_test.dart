// SPDX-FileCopyrightText: 2025 Webdav Media Manager contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_media_manager/models/app_locale.dart';
import 'package:webdav_media_manager/models/app_theme_mode.dart';
import 'package:webdav_media_manager/models/cache_policy.dart';
import 'package:webdav_media_manager/models/folder_view_mode.dart';
import 'package:webdav_media_manager/models/manga_read_mode.dart';
import 'package:webdav_media_manager/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('crypt sequential download defaults to true', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsService(prefs: prefs);
    await s.init();
    expect(s.cryptSequentialDownloadEnabled, isTrue);
  });

  test('new backup keys round-trip; custom_download_* never exported/imported',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsService(prefs: prefs);
    await s.init();

    await s.setMusicCacheMaxMb(512);
    await s.setDownloadPartMaxAgeHours(48);
    await s.setDownloadPartMaxMb(256);
    await s.setCryptSequentialDownloadEnabled(false);
    await s.setMangaCacheMaxMb(128);
    await s.setMangaRetention(CacheRetention.never);
    await s.setMangaCustomRetentionDuration(const Duration(hours: 12));
    await s.setMusicDefaultStream(true);
    await s.setMangaReadMode(MangaReadMode.cache);
    await s.setMangaViewMode('series', FolderViewMode.grid2);
    await s.setMusicViewMode('albums', FolderViewMode.grid2);
    await s.setAppThemeMode(AppThemeMode.dark);
    await s.setThemeSeed(const Color(0xFF123456));
    await s.setAppLocale(AppLocalePreference.en);
    await s.setDownloadNomediaEnabled(true);

    await s.setCustomDownloadDir(
      uri: 'content://tree/primary%3ADownload%2FMyDir',
      displayName: 'MyDir',
    );
    expect(s.customDownloadDirActive, isTrue);

    final exported = s.exportForBackup();
    expect(exported.containsKey('use_custom_download_dir'), isFalse);
    expect(exported.containsKey('custom_download_tree_uri'), isFalse);
    expect(exported.containsKey('custom_download_display_name'), isFalse);
    expect(exported['music_cache_max_mb'], 512);
    expect(exported['download_part_max_age_hours'], 48);
    expect(exported['download_part_max_mb'], 256);
    expect(exported['crypt_sequential_download'], isFalse);
    expect(exported['manga_cache_max_mb'], 128);
    expect(exported['manga_cache_retention'], CacheRetention.never.storageKey);
    expect(exported['music_default_stream'], isTrue);
    expect(exported['manga_read_mode'], MangaReadMode.cache.storageKey);
    expect(exported['manga_view_modes'], containsPair('series', FolderViewMode.grid2.storageKey));
    expect(exported['music_view_modes'], containsPair('albums', FolderViewMode.grid2.storageKey));
    expect(exported['theme_mode'], AppThemeMode.dark.storageKey);
    expect(exported['theme_seed_argb'], 0xFF123456);
    expect(exported['app_locale'], AppLocalePreference.en.storageKey);
    expect(exported['download_nomedia'], isTrue);

    SharedPreferences.setMockInitialValues({});
    final prefs2 = await SharedPreferences.getInstance();
    final s2 = SettingsService(prefs: prefs2);
    await s2.init();
    expect(s2.customDownloadDirActive, isFalse);

    final poisoned = Map<String, dynamic>.from(exported)
      ..['use_custom_download_dir'] = true
      ..['custom_download_tree_uri'] = 'content://evil'
      ..['custom_download_display_name'] = 'Evil';
    await s2.importFromBackup(poisoned);

    expect(s2.customDownloadDirActive, isFalse);
    expect(s2.customDownloadTreeUri, isNull);
    expect(s2.musicCacheMaxMb, 512);
    expect(s2.downloadPartMaxAgeHours, 48);
    expect(s2.downloadPartMaxMb, 256);
    expect(s2.cryptSequentialDownloadEnabled, isFalse);
    expect(s2.mangaCacheMaxMb, 128);
    expect(s2.mangaRetention, CacheRetention.never);
    expect(s2.musicDefaultStream, isTrue);
    expect(s2.mangaReadMode, MangaReadMode.cache);
    expect(s2.mangaViewModeFor('series'), FolderViewMode.grid2);
    expect(s2.appThemeMode, AppThemeMode.dark);
    expect(s2.themeSeedArgb, 0xFF123456);
    expect(s2.appLocale, AppLocalePreference.en);
    expect(s2.downloadNomediaEnabled, isTrue);
  });
}
