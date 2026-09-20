import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cache_policy.dart';
import '../models/library_track.dart';

/// App preferences (cache retention, library sort). WebDAV credentials live in AccountsService.
class SettingsService extends ChangeNotifier {
  SettingsService({SharedPreferences? prefs}) : _prefs = prefs;

  static const _kRetention = 'cache_retention';
  static const _kCustomRetentionHours = 'cache_custom_retention_hours';
  static const _kLibrarySort = 'library_sort_mode';

  /// Default custom retention: 30 days.
  static const int defaultCustomRetentionHours = 24 * 30;

  /// Clamp custom retention to [1 hour, 10 years].
  static const int minCustomRetentionHours = 1;
  static const int maxCustomRetentionHours = 24 * 365 * 10;

  SharedPreferences? _prefs;
  CacheRetention _retention = CacheRetention.oneWeek;
  int _customRetentionHours = defaultCustomRetentionHours;
  LibrarySortMode _librarySort = LibrarySortMode.byName;
  bool _loaded = false;

  CacheRetention get retention => _retention;
  Duration get customRetentionDuration =>
      Duration(hours: _customRetentionHours);
  int get customRetentionHours => _customRetentionHours;
  LibrarySortMode get librarySort => _librarySort;
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

  static int _clampCustomHours(int hours) {
    if (hours < minCustomRetentionHours) return minCustomRetentionHours;
    if (hours > maxCustomRetentionHours) return maxCustomRetentionHours;
    return hours;
  }
}
