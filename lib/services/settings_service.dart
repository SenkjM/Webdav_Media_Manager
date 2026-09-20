import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cache_policy.dart';

/// App preferences (cache retention). WebDAV credentials live in AccountsService.
class SettingsService extends ChangeNotifier {
  SettingsService({SharedPreferences? prefs}) : _prefs = prefs;

  static const _kRetention = 'cache_retention';

  SharedPreferences? _prefs;
  CacheRetention _retention = CacheRetention.oneWeek;
  bool _loaded = false;

  CacheRetention get retention => _retention;
  bool get loaded => _loaded;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _retention = CacheRetentionX.fromStorageKey(_prefs!.getString(_kRetention));
    _loaded = true;
    notifyListeners();
  }

  Future<void> setRetention(CacheRetention retention) async {
    _retention = retention;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kRetention, retention.storageKey);
    notifyListeners();
  }
}
