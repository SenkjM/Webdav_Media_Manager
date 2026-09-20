import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cache_policy.dart';

/// Persists WebDAV credentials (secure) and app preferences.
class SettingsService extends ChangeNotifier {
  SettingsService({
    FlutterSecureStorage? secureStorage,
    SharedPreferences? prefs,
  })  : _secure = secureStorage ?? const FlutterSecureStorage(),
        _prefs = prefs;

  static const _kUrl = 'webdav_url';
  static const _kUser = 'webdav_username';
  static const _kPass = 'webdav_password';
  static const _kRetention = 'cache_retention';

  final FlutterSecureStorage _secure;
  SharedPreferences? _prefs;

  String _url = '';
  String _username = '';
  String _password = '';
  CacheRetention _retention = CacheRetention.oneWeek;
  bool _loaded = false;

  String get url => _url;
  String get username => _username;
  String get password => _password;
  CacheRetention get retention => _retention;
  bool get isConfigured => _url.trim().isNotEmpty;
  bool get loaded => _loaded;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _url = await _secure.read(key: _kUrl) ?? '';
    _username = await _secure.read(key: _kUser) ?? '';
    _password = await _secure.read(key: _kPass) ?? '';
    _retention = CacheRetentionX.fromStorageKey(_prefs!.getString(_kRetention));
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveWebDav({
    required String url,
    required String username,
    required String password,
  }) async {
    _url = url.trim();
    _username = username;
    _password = password;
    await _secure.write(key: _kUrl, value: _url);
    await _secure.write(key: _kUser, value: _username);
    await _secure.write(key: _kPass, value: _password);
    notifyListeners();
  }

  Future<void> setRetention(CacheRetention retention) async {
    _retention = retention;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kRetention, retention.storageKey);
    notifyListeners();
  }

  Future<void> clearCredentials() async {
    _url = '';
    _username = '';
    _password = '';
    await _secure.delete(key: _kUrl);
    await _secure.delete(key: _kUser);
    await _secure.delete(key: _kPass);
    notifyListeners();
  }
}
