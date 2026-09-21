/// Single source of truth for the Android media-playback notification channel.
///
/// The channel is created by `NotificationPermissionService` through
/// `flutter_local_notifications` at startup, so the Settings page can report an
/// accurate「音乐播放」channel state (missing / enabled / turned off) *before*
/// the first playback.
///
/// `audio_service` (see `initMusicAudioService()` in `music_audio_handler.dart`)
/// then reuses this channel: its native `createChannel()` only creates the
/// channel when it is still missing, and Android never lets an app change a
/// channel's importance/sound afterwards. The values below must therefore stay
/// in sync with `AudioServiceConfig` (IMPORTANCE_DEFAULT, silent, no vibration,
/// no badge, lockscreen public) — a mismatch would silently become the
/// effective channel configuration.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Channel id.
///
/// The `.v4` suffix is deliberate: Android does not upgrade the importance of an
/// already-created channel, so a fresh id is the only way to move existing
/// installs off the old LOW-importance channel. `MainActivity`'s
/// `mediaNotificationDiagnostics` probe reads this same id.
const String kMediaNotificationChannelId =
    'com.webdav.webdav_music_player.audio.v4';

/// Channel name shown in the system notification settings.
const String kMediaNotificationChannelName = '音乐播放';

/// Channel description shown in the system notification settings.
const String kMediaNotificationChannelDescription = '正在播放的音乐控制';

/// Small icon used by the MediaStyle notification (`drawable/ic_stat_music`;
/// never an adaptive launcher icon).
const String kMediaNotificationIcon = 'drawable/ic_stat_music';

/// The「音乐播放」channel definition handed to
/// `AndroidFlutterLocalNotificationsPlugin.createNotificationChannel()`.
///
/// Mirrors `AudioService.createChannel()` in the vendored `audio_service`:
/// `IMPORTANCE_DEFAULT` + `setSound(null, null)` + `enableVibration(false)` +
/// `setShowBadge(androidShowNotificationBadge)` + `VISIBILITY_PUBLIC`.
const AndroidNotificationChannel kMediaNotificationChannel =
    AndroidNotificationChannel(
  kMediaNotificationChannelId,
  kMediaNotificationChannelName,
  description: kMediaNotificationChannelDescription,
  importance: Importance.defaultImportance,
  playSound: false,
  enableVibration: false,
  showBadge: false,
);
