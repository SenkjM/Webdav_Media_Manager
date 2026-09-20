import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cache_policy.dart';
import '../models/library_track.dart';
import '../utils/cover_image.dart';

/// App preferences (cache retention, library sort, backup/playlist paths).
/// WebDAV credentials live in AccountsService / flutter_secure_storage.
class SettingsService extends ChangeNotifier {
  SettingsService({SharedPreferences? prefs}) : _prefs = prefs;

  static const _kRetention = 'cache_retention';
  static const _kCustomRetentionHours = 'cache_custom_retention_hours';
  static const _kLibrarySort = 'library_sort_mode';
  static const _kBackupRemotePath = 'backup_remote_path';
  static const _kLibrarySyncRemotePath = 'library_sync_remote_path';
  static const _kPlaylistRemotePath = 'playlist_remote_path';
  static const _kPlaylistSyncEnabled = 'playlist_sync_enabled';
  static const _kCoverThumbSize = 'cover_thumb_size';

  /// Default custom retention: 30 days.
  static const int defaultCustomRetentionHours = 24 * 30;

  /// Clamp custom retention to [1 hour, 10 years].
  static const int minCustomRetentionHours = 1;
  static const int maxCustomRetentionHours = 24 * 365 * 10;

  static const String defaultBackupRemotePath = '/WebDAVMusicPlayer/backup/';
  static const String defaultLibrarySyncRemotePath = '/WebDAVMusicPlayer/library/';
  static const String defaultPlaylistRemotePath = '/Playlists/';

  SharedPreferences? _prefs;
  CacheRetention _retention = CacheRetention.oneWeek;
  int _customRetentionHours = defaultCustomRetentionHours;
  LibrarySortMode _librarySort = LibrarySortMode.byName;
  String _backupRemotePath = defaultBackupRemotePath;
  String _librarySyncRemotePath = defaultLibrarySyncRemotePath;
  String _playlistRemotePath = defaultPlaylistRemotePath;
  bool _playlistSyncEnabled = true;
  int _coverThumbSize = coverThumbSize;
  bool _loaded = false;

  CacheRetention get retention => _retention;
  Duration get customRetentionDuration =>
      Duration(hours: _customRetentionHours);
  int get customRetentionHours => _customRetentionHours;
  LibrarySortMode get librarySort => _librarySort;
  String get backupRemotePath => _backupRemotePath;
  String get librarySyncRemotePath => _librarySyncRemotePath;
  String get playlistRemotePath => _playlistRemotePath;
  bool get playlistSyncEnabled => _playlistSyncEnabled;
  /// Square edge (px) for newly compressed cover thumbs.
  int get coverThumbSizePx => _coverThumbSize;
  bool get loaded => _loaded;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _retention = CacheRetentionX.fromStorageKey(_prefs!.getString(_kRetention));
    final storedHours = _prefs!.getInt(_kCustomRetentionHours);
    _customRetentionHours = _clampCustomHours(
      storedHours ?? defaultCustomRetentionHours,
    );
    _librarySort =
        LibrarySortModeX.fromStorageKey(_prefs!.getString(_kLibrarySort));
    _backupRemotePath =
        _prefs!.getString(_kBackupRemotePath) ?? defaultBackupRemotePath;
    _librarySyncRemotePath =
        _prefs!.getString(_kLibrarySyncRemotePath) ?? defaultLibrarySyncRemotePath;
    _playlistRemotePath =
        _prefs!.getString(_kPlaylistRemotePath) ?? defaultPlaylistRemotePath;
    _playlistSyncEnabled = _prefs!.getBool(_kPlaylistSyncEnabled) ?? true;
    _coverThumbSize = clampCoverThumbSize(
      _prefs!.getInt(_kCoverThumbSize) ?? coverThumbSize,
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> setRetention(CacheRetention retention) async {
    _retention = retention;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kRetention, retention.storageKey);
    notifyListeners();
  }

  /// Persist custom retention window (used when mode is [CacheRetention.custom]).
  Future<void> setCustomRetentionDuration(Duration duration) async {
    _customRetentionHours = _clampCustomHours(duration.inHours);
    // Ensure at least 1 hour even if caller passed sub-hour duration.
    if (duration > Duration.zero && _customRetentionHours < 1) {
      _customRetentionHours = 1;
    }
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_kCustomRetentionHours, _customRetentionHours);
    notifyListeners();
  }

  Future<void> setLibrarySort(LibrarySortMode mode) async {
    _librarySort = mode;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kLibrarySort, mode.storageKey);
    notifyListeners();
  }

  Future<void> setBackupRemotePath(String path) async {
    var p = path.trim();
    if (p.isEmpty) p = defaultBackupRemotePath;
    if (!p.startsWith('/')) p = '/$p';
    if (!p.endsWith('/')) p = '$p/';
    _backupRemotePath = p;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kBackupRemotePath, _backupRemotePath);
    notifyListeners();
  }

  
  Future<void> setLibrarySyncRemotePath(String path) async {
    var p = path.trim();
    if (p.isEmpty) p = defaultLibrarySyncRemotePath;
    if (!p.startsWith('/')) p = '/$p';
    if (!p.endsWith('/')) p = '$p/';
    _librarySyncRemotePath = p;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kLibrarySyncRemotePath, _librarySyncRemotePath);
    notifyListeners();
  }

  Future<void> setPlaylistRemotePath(String path) async {
    var p = path.trim();
    if (p.isEmpty) p = defaultPlaylistRemotePath;
    if (!p.startsWith('/')) p = '/$p';
    if (!p.endsWith('/')) p = '$p/';
    _playlistRemotePath = p;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kPlaylistRemotePath, _playlistRemotePath);
    notifyListeners();
  }

  Future<void> setPlaylistSyncEnabled(bool enabled) async {
    _playlistSyncEnabled = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kPlaylistSyncEnabled, enabled);
    notifyListeners();
  }


  /// Persist square cover-thumb edge. Presets: 100 / 300; custom clamped to
  /// [minCoverThumbSize]–[maxCoverThumbSize]. Applies to NEW thumbs only;
  /// existing files keep old size until re-download/re-ingest (or destroy).
  Future<void> setCoverThumbSize(int size) async {
    _coverThumbSize = clampCoverThumbSize(size);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_kCoverThumbSize, _coverThumbSize);
    notifyListeners();
  }

  Map<String, dynamic> exportForBackup() => {
        'cache_retention': _retention.storageKey,
        'cache_custom_retention_hours': _customRetentionHours,
        'library_sort_mode': _librarySort.storageKey,
        'backup_remote_path': _backupRemotePath,
        'playlist_remote_path': _playlistRemotePath,
        'playlist_sync_enabled': _playlistSyncEnabled,
        'cover_thumb_size': _coverThumbSize,
      };

  Future<Map<String, dynamic>> exportForBackupAsync() async => exportForBackup();

  Future<void> importFromBackup(Map<String, dynamic> json) async {
    _prefs ??= await SharedPreferences.getInstance();
    if (json['cache_retention'] != null) {
      await setRetention(
        CacheRetentionX.fromStorageKey(json['cache_retention'] as String?),
      );
    }
    if (json['cache_custom_retention_hours'] is int) {
      await setCustomRetentionDuration(
        Duration(hours: json['cache_custom_retention_hours'] as int),
      );
    }
    if (json['library_sort_mode'] != null) {
      await setLibrarySort(
        LibrarySortModeX.fromStorageKey(json['library_sort_mode'] as String?),
      );
    }
    if (json['backup_remote_path'] is String) {
      await setBackupRemotePath(json['backup_remote_path'] as String);
    }
    if (json['playlist_remote_path'] is String) {
      await setPlaylistRemotePath(json['playlist_remote_path'] as String);
    }
    if (json['playlist_sync_enabled'] is bool) {
      await setPlaylistSyncEnabled(json['playlist_sync_enabled'] as bool);
    }
    if (json['cover_thumb_size'] is int) {
      await setCoverThumbSize(json['cover_thumb_size'] as int);
    }
  }

  static int _clampCustomHours(int hours) {
    if (hours < minCustomRetentionHours) return minCustomRetentionHours;
    if (hours > maxCustomRetentionHours) return maxCustomRetentionHours;
    return hours;
  }
}
