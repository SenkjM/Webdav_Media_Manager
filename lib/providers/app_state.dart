import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/cache_policy.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import '../services/download_queue_service.dart';
import '../services/settings_service.dart';
import '../services/webdav_service.dart';

/// Root composition / lifecycle for the app.
class AppState extends ChangeNotifier {
  AppState() {
    settings = SettingsService();
    webDav = WebDavService();
    cache = CacheService();
    downloads = DownloadQueueService(webDav: webDav, cache: cache);
    player = AudioPlayerService(downloads: downloads);
  }

  late final SettingsService settings;
  late final WebDavService webDav;
  late final CacheService cache;
  late final DownloadQueueService downloads;
  late final AudioPlayerService player;

  bool ready = false;
  String? initError;

  Future<void> init() async {
    try {
      await settings.init();
      await cache.init();
      await downloads.init();
      if (settings.isConfigured) {
        webDav.configure(
          url: settings.url,
          username: settings.username,
          password: settings.password,
        );
      }
      // Fire-and-forget cleanup on start.
      unawaited(runCacheCleanup());
      ready = true;
    } catch (e) {
      initError = e.toString();
      ready = true;
    }
    notifyListeners();
  }

  Future<void> applyWebDavSettings({
    required String url,
    required String username,
    required String password,
  }) async {
    await settings.saveWebDav(
      url: url,
      username: username,
      password: password,
    );
    webDav.configure(url: url, username: username, password: password);
  }

  Future<int> runCacheCleanup() {
    return cache.cleanupKnown(
      retention: settings.retention,
      remoteToLocal: downloads.completedRemoteToLocal,
      playingRemotePath: player.currentRemotePath,
      downloadingRemotePaths: downloads.downloadingRemotePaths,
    );
  }

  Future<int> manualClearCache() {
    return cache.clearAll(
      playingRemotePath: player.currentRemotePath,
      playingLocalPath: player.current?.localPath,
      downloadingRemotePaths: downloads.downloadingRemotePaths,
    );
  }

  Future<void> setRetention(CacheRetention r) async {
    await settings.setRetention(r);
    unawaited(runCacheCleanup());
  }

  @override
  void dispose() {
    player.dispose();
    downloads.dispose();
    cache.dispose();
    webDav.dispose();
    settings.dispose();
    super.dispose();
  }
}
