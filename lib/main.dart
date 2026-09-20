import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'providers/app_state.dart';
import 'screens/home_shell.dart';
import 'services/accounts_service.dart';
import 'services/audio_player_service.dart';
import 'services/cache_service.dart';
import 'services/download_queue_service.dart';
import 'services/library_service.dart';
import 'services/notification_permission_service.dart';
import 'services/settings_service.dart';
import 'services/webdav_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must run before any AudioPlayer is created (AppState constructs one).
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await JustAudioBackground.init(
      androidNotificationChannelId:
          'com.webdav.webdav_music_player.channel.audio',
      androidNotificationChannelName: '音乐播放',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,
    );
  }
  final app = AppState();
  await app.init();
  runApp(WebDavMusicApp(appState: app));
}

class WebDavMusicApp extends StatelessWidget {
  const WebDavMusicApp({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<SettingsService>.value(value: appState.settings),
        ChangeNotifierProvider<AccountsService>.value(value: appState.accounts),
        ChangeNotifierProvider<LibraryService>.value(value: appState.library),
        ChangeNotifierProvider<WebDavService>.value(value: appState.webDav),
        ChangeNotifierProvider<CacheService>.value(value: appState.cache),
        ChangeNotifierProvider<DownloadQueueService>.value(
          value: appState.downloads,
        ),
        ChangeNotifierProvider<NotificationPermissionService>.value(
          value: appState.notificationPermission,
        ),
        ChangeNotifierProvider<AudioPlayerService>.value(value: appState.player),
      ],
      child: MaterialApp(
        title: 'WebDAV 音乐播放器',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.light,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: appState.initError != null
            ? Scaffold(
                body: Center(child: Text('初始化失败：${appState.initError}')),
              )
            : const HomeShell(),
      ),
    );
  }
}
