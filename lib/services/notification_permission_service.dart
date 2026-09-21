import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'media_notification_channel.dart';

/// Android notification state for media playback, owned by
/// `flutter_local_notifications`:
///
/// * **channel creation** — [ensureChannel] creates the shared「音乐播放」
///   channel ([kMediaNotificationChannel]) instead of leaving it to the first
///   playback. `audio_service`'s native `createChannel()` only creates a channel
///   when it is missing, so this is the definition the system ends up with and
///   the Settings page can report the real state before any track plays.
/// * **permission + channel state** — `POST_NOTIFICATIONS`
///   (`areNotificationsEnabled()` / [request]) *and* whether the media channel
///   was separately disabled by the user (`importance == none`). Plain
///   permission checks can't distinguish the latter and used to hide it behind
///   「已授予通知权限」.
class NotificationPermissionService extends ChangeNotifier {
  NotificationPermissionService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _pluginInitialized = false;
  bool _channelEnsured = false;
  bool _requestedOnce = false;

  bool _granted = false;
  bool _channelBlocked = false;
  bool _channelExists = false;
  Importance? _channelImportance;
  bool _loaded = false;

  /// True once a [refresh] / [request] round has completed.
  bool get loaded => _loaded;

  /// True only when POST_NOTIFICATIONS is granted AND the media channel
  /// hasn't been separately disabled by the user.
  bool get isGranted => _granted && !_channelBlocked;

  /// True when the「音乐播放」channel exists but its importance was set to
  /// none (user turned it off from system notification settings).
  bool get isChannelBlocked => _channelBlocked;

  /// True when the channel is still missing on a platform that supports
  /// channels (Android 8+) — playback would create it, but the Settings page
  /// can't report a state yet.
  bool get isChannelMissing => _loaded && supportsChannels && !_channelExists;

  /// True once a request has been made and permission is still missing — the
  /// OS won't show the permission dialog again, so send users to settings.
  bool get isPermanentlyDenied => _requestedOnce && !_granted;

  /// True when the OS requires a runtime notification permission (Android 13+).
  bool get requiresRuntimePermission {
    if (kIsWeb || !Platform.isAndroid) return false;
    return true;
  }

  /// True on platforms that use Android notification channels (API 26+).
  bool get supportsChannels {
    if (kIsWeb || !Platform.isAndroid) return false;
    return true;
  }

  /// Display-ready channel importance (`null` while the channel is missing).
  ///
  /// Kept as a label so UI code doesn't have to import
  /// `flutter_local_notifications` just to render the state.
  String? get channelImportanceLabel {
    switch (_channelImportance) {
      case Importance.none:
        return '已关闭';
      case Importance.min:
        return '最低';
      case Importance.low:
        return '低';
      case Importance.defaultImportance:
        return '默认';
      case Importance.high:
        return '高';
      case Importance.max:
        return '最高';
      default:
        return null;
    }
  }

  /// One-line channel diagnosis for the Settings page.
  String get channelStatusLabel {
    if (!_loaded) return '正在检查…';
    if (!supportsChannels) return '当前平台无通知通道';
    if (!_channelExists) return '未创建';
    if (_channelBlocked) return '已关闭（请在系统通知设置中重新开启）';
    final importance = channelImportanceLabel;
    return importance == null ? '已创建' : '已创建 · 重要性 $importance';
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

  /// Creates the shared「音乐播放」channel (idempotent).
  ///
  /// Returns whether the channel is ready. Safe to call on every startup and
  /// from the Settings page: Android ignores re-creating an existing channel and
  /// the plugin call is a no-op below Android 8 / off Android.
  Future<bool> ensureChannel() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    if (_channelEnsured) return true;
    await _ensureInitialized();
    final android = _android;
    if (android == null) return false;
    try {
      await android.createNotificationChannel(kMediaNotificationChannel);
      _channelEnsured = true;
      return true;
    } catch (_) {
      // Retried on the next call; playback still creates it natively.
      return false;
    }
  }

  Future<void> _refreshChannelState() async {
    try {
      final channels = await _android?.getNotificationChannels();
      final channel = channels?.firstWhereOrNull(
        (c) => c.id == kMediaNotificationChannelId,
      );
      _channelExists = channel != null;
      _channelImportance = channel?.importance;
      _channelBlocked =
          channel != null && channel.importance == Importance.none;
    } catch (_) {
      _channelExists = false;
      _channelImportance = null;
      _channelBlocked = false;
    }
  }

  /// Creates the channel (when possible) and re-reads permission + channel
  /// state from the system.
  Future<void> refresh() async {
    if (kIsWeb || !Platform.isAndroid) {
      _granted = true;
      _channelBlocked = false;
      _channelExists = false;
      _channelImportance = null;
      _loaded = true;
      notifyListeners();
      return;
    }
    await _ensureInitialized();
    await ensureChannel();
    try {
      _granted = await _android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      _granted = false;
    }
    await _refreshChannelState();
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
    await ensureChannel();
    _requestedOnce = true;
    try {
      _granted = await _android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      _granted = false;
    }
    await _refreshChannelState();
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
