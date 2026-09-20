import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cache_policy.dart';
import '../models/library_track.dart';

/// App preferences (cache retention, library sort). WebDAV credentials live in AccountsService.
class SettingsService extends ChangeNotifier {
  SettingsService({SharedPreferences? prefs}) : _prefs = prefs;

  static const _kRetention = 'cache_retention';
  static const _kLibrarySort = 'library_sort_mode';

  SharedPreferences? _prefs;
  CacheRetention _retention = CacheRetention.oneWeek;
  LibrarySortMode _librarySort = LibrarySortMode.byName;
  bool _loaded = false;

  CacheRetention get retention => _retention;
  LibrarySortMode get librarySort => _librarySort;
  bool get loaded => _loaded;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _retention = CacheRetentionX.fromStorageKey(_prefs!.getString(_kRetention));
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

  Future<void> setLibrarySort(LibrarySortMode mode) async {
    _librarySort = mode;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kLibrarySort, mode.storageKey);
    notifyListeners();
  }
}
