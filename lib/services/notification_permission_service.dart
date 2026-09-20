import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android 13+ (API 33) notification permission for media playback notifications.
class NotificationPermissionService extends ChangeNotifier {
  NotificationPermissionService();

  PermissionStatus _status = PermissionStatus.denied;
  bool _loaded = false;

  PermissionStatus get status => _status;
  bool get loaded => _loaded;
  bool get isGranted => _status.isGranted;
  bool get isPermanentlyDenied => _status.isPermanentlyDenied;

  /// True when the OS requires a runtime notification permission (Android 13+).
  bool get requiresRuntimePermission {
    if (kIsWeb || !Platform.isAndroid) return false;
    // permission_handler reports denied until granted on API 33+.
    // On older Android, notification permission is granted at install.
    return true;
  }

  Future<void> refresh() async {
    if (kIsWeb || !Platform.isAndroid) {
      _status = PermissionStatus.granted;
      _loaded = true;
      notifyListeners();
      return;
    }
    try {
      _status = await Permission.notification.status;
    } catch (_) {
      // Platform channels unavailable (unit tests / unsupported host).
      _status = PermissionStatus.denied;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Request POST_NOTIFICATIONS. Returns whether notifications are allowed.
  Future<bool> request() async {
    if (kIsWeb || !Platform.isAndroid) {
      _status = PermissionStatus.granted;
      _loaded = true;
      notifyListeners();
      return true;
    }
    try {
      _status = await Permission.notification.request();
    } catch (_) {
      _status = PermissionStatus.denied;
    }
    _loaded = true;
    notifyListeners();
    return _status.isGranted;
  }

  Future<bool> openSystemSettings() => openAppSettings();
}
