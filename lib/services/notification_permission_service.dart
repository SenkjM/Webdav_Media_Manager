import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'music_audio_handler.dart' show kMediaNotificationChannelId;

/// Android 13+ (API 33) notification permission *and* "音乐播放" channel
/// status for media playback notifications, backed by
/// flutter_local_notifications instead of permission_handler.
///
/// Using flutter_local_notifications lets us also see whether the media
/// channel itself was disabled by the user (importance == none) even while
/// POST_NOTIFICATIONS is still granted — a case permission_handler can't
/// distinguish and that plain "已授予通知权限" text used to hide.
class NotificationPermissionService extends ChangeNotifier {
  NotificationPermissionService();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _pluginInitialized = false;
  bool _requestedOnce = false;

  bool _granted = false;
  bool _channelBlocked = false;
  bool _loaded = false;

  bool get loaded => _loaded;

  /// True only when POST_NOTIFICATIONS is granted AND the media channel
  /// hasn't been separately disabled by the user.
  bool get isGranted => _granted && !_channelBlocked;

  /// True when the "音乐播放" channel exists but its importance was set to
  /// none (user turned it off from system notification settings).
  bool get isChannelBlocked => _channelBlocked;

  /// True once a request has been made and permission is still missing — the
  /// OS won't show the permission dialog again, so send users to settings.
  bool get isPermanentlyDenied => _requestedOnce && !_granted;

  /// True when the OS requires a runtime notification permission (Android 13+).
  bool get requiresRuntimePermission {
    if (kIsWeb || !Platform.isAndroid) return false;
    return true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android {
    return _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
  }

  Future<void> _ensureInitialized() async {
    if (_pluginInitialized) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
    } catch (_) {
      // Platform channels unavailable (unit tests / unsupported host).
    }
    _pluginInitialized = true;
  }

  Future<bool> _channelIsBlocked() async {
    try {
      final channels = await _android?.getNotificationChannels();
      final channel = channels?.firstWhereOrNull(
        (c) => c.id == kMediaNotificationChannelId,
      );
      return channel != null && channel.importance == Importance.none;
    } catch (_) {
      return false;
    }
  }

  Future<void> refresh() async {
    if (kIsWeb || !Platform.isAndroid) {
      _granted = true;
      _channelBlocked = false;
      _loaded = true;
      notifyListeners();
      return;
    }
    await _ensureInitialized();
    try {
      _granted = await _android?.areNotificationsEnabled() ?? false;
      _channelBlocked = await _channelIsBlocked();
    } catch (_) {
      _granted = false;
      _channelBlocked = false;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Request POST_NOTIFICATIONS. Returns whether notifications are allowed.
  Future<bool> request() async {
    if (kIsWeb || !Platform.isAndroid) {
      _granted = true;
      _loaded = true;
      notifyListeners();
      return true;
    }
    await _ensureInitialized();
    _requestedOnce = true;
    try {
      _granted = await _android?.requestNotificationsPermission() ?? false;
      _channelBlocked = await _channelIsBlocked();
    } catch (_) {
      _granted = false;
    }
    _loaded = true;
    notifyListeners();
    return _granted;
  }

  /// Opens the system notification settings screen for this app.
  Future<bool> openSystemSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    await _ensureInitialized();
    try {
      return await _android?.openAppNotificationSettings() ?? false;
    } catch (_) {
      return false;
    }
  }
}
