import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/webdav_account.dart';
import 'library_database.dart';

/// Multi-WebDAV account management. Passwords in secure storage.
class AccountsService extends ChangeNotifier {
  AccountsService({
    required LibraryDatabase db,
    FlutterSecureStorage? secureStorage,
    SharedPreferences? prefs,
  })  : _db = db,
        _secure = secureStorage ?? const FlutterSecureStorage(),
        _prefs = prefs;

  static const _kActiveAccount = 'active_webdav_account_id';
  static const _kPassPrefix = 'webdav_pass_';
  // Legacy single-account keys (migrated once).
  static const _legacyUrl = 'webdav_url';
  static const _legacyUser = 'webdav_username';
  static const _legacyPass = 'webdav_password';

  final LibraryDatabase _db;
  final FlutterSecureStorage _secure;
  SharedPreferences? _prefs;
  final _uuid = const Uuid();

  final List<WebDavAccount> _accounts = [];
  String? _activeAccountId;
  bool _loaded = false;

  UnmodifiableListView<WebDavAccount> get accounts =>
      UnmodifiableListView(_accounts);
  bool get loaded => _loaded;
  String? get activeAccountId => _activeAccountId;

  WebDavAccount? get activeAccount {
    if (_activeAccountId == null) return null;
    try {
      return _accounts.firstWhere((a) => a.id == _activeAccountId);
    } catch (_) {
      return _accounts.isEmpty ? null : _accounts.first;
    }
  }

  bool get hasAccounts => _accounts.isNotEmpty;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded();
    _accounts
      ..clear()
      ..addAll(await _db.loadAccounts());
    _activeAccountId = _prefs!.getString(_kActiveAccount);
    if (_activeAccountId != null &&
        !_accounts.any((a) => a.id == _activeAccountId)) {
      _activeAccountId = null;
    }
    if (_activeAccountId == null && _accounts.isNotEmpty) {
      _activeAccountId = _accounts.first.id;
      await _prefs!.setString(_kActiveAccount, _activeAccountId!);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _migrateLegacyIfNeeded() async {
    final existing = await _db.loadAccounts();
    if (existing.isNotEmpty) return;
    final url = await _secure.read(key: _legacyUrl) ?? '';
    if (url.trim().isEmpty) return;
    final user = await _secure.read(key: _legacyUser) ?? '';
    final pass = await _secure.read(key: _legacyPass) ?? '';
    final id = _uuid.v4();
    final account = WebDavAccount(
      id: id,
      name: '默认服务器',
      url: url.trim(),
      username: user,
    );
    await _db.upsertAccount(account);
    await _secure.write(key: '$_kPassPrefix$id', value: pass);
    await _secure.delete(key: _legacyUrl);
    await _secure.delete(key: _legacyUser);
    await _secure.delete(key: _legacyPass);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kActiveAccount, id);
  }

  Future<String?> passwordFor(String accountId) async {
    return _secure.read(key: '$_kPassPrefix$accountId');
  }

  Future<WebDavAccount> addAccount({
    required String name,
    required String url,
    required String username,
    required String password,
  }) async {
    final account = WebDavAccount(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? url.trim() : name.trim(),
      url: url.trim().replaceAll(RegExp(r'/+$'), ''),
      username: username,
    );
    await _db.upsertAccount(account);
    await _secure.write(key: '$_kPassPrefix${account.id}', value: password);
    _accounts.add(account);
    _activeAccountId ??= account.id;
    _prefs ??= await SharedPreferences.getInstance();
    if (_prefs!.getString(_kActiveAccount) == null) {
      await _prefs!.setString(_kActiveAccount, account.id);
      _activeAccountId = account.id;
    }
    notifyListeners();
    return account;
  }

  Future<void> updateAccount({
    required String id,
    required String name,
    required String url,
    required String username,
    String? password,
  }) async {
    final idx = _accounts.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    final updated = _accounts[idx].copyWith(
      name: name.trim().isEmpty ? url.trim() : name.trim(),
      url: url.trim().replaceAll(RegExp(r'/+$'), ''),
      username: username,
    );
    await _db.upsertAccount(updated);
    if (password != null) {
      await _secure.write(key: '$_kPassPrefix$id', value: password);
    }
    _accounts[idx] = updated;
    notifyListeners();
  }

  Future<void> deleteAccount(String id) async {
    await _db.deleteAccount(id);
    await _secure.delete(key: '$_kPassPrefix$id');
    _accounts.removeWhere((a) => a.id == id);
    if (_activeAccountId == id) {
      _activeAccountId = _accounts.isEmpty ? null : _accounts.first.id;
      _prefs ??= await SharedPreferences.getInstance();
      if (_activeAccountId == null) {
        await _prefs!.remove(_kActiveAccount);
      } else {
        await _prefs!.setString(_kActiveAccount, _activeAccountId!);
      }
    }
    notifyListeners();
  }

  Future<void> setActiveAccount(String id) async {
    if (!_accounts.any((a) => a.id == id)) return;
    _activeAccountId = id;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kActiveAccount, id);
    notifyListeners();
  }

  /// Restore accounts + passwords from backup JSON.
  /// Expects `{ activeAccountId, accounts: [{id,name,url,username,password}, ...] }`.
  Future<void> restoreFromBackup(Map<String, dynamic> json) async {
    final list = json['accounts'] as List<dynamic>? ?? [];
    _prefs ??= await SharedPreferences.getInstance();
    // Clear existing passwords for current accounts.
    for (final a in List<WebDavAccount>.from(_accounts)) {
      await _secure.delete(key: '$_kPassPrefix${a.id}');
    }
    // Replace accounts table by upserting backup set and deleting missing.
    final existing = await _db.loadAccounts();
    final keepIds = <String>{};
    for (final raw in list) {
      final m = Map<String, dynamic>.from(raw as Map);
      final account = WebDavAccount(
        id: m['id'] as String,
        name: m['name'] as String? ?? m['url'] as String? ?? '服务器',
        url: (m['url'] as String? ?? '').trim().replaceAll(RegExp(r'/+$'), ''),
        username: m['username'] as String? ?? '',
      );
      keepIds.add(account.id);
      await _db.upsertAccount(account);
      final pass = m['password'] as String? ?? '';
      await _secure.write(key: '$_kPassPrefix${account.id}', value: pass);
    }
    for (final a in existing) {
      if (!keepIds.contains(a.id)) {
        await _db.deleteAccount(a.id);
        await _secure.delete(key: '$_kPassPrefix${a.id}');
      }
    }
    _accounts
      ..clear()
      ..addAll(await _db.loadAccounts());
    final active = json['activeAccountId'] as String?;
    if (active != null && _accounts.any((a) => a.id == active)) {
      _activeAccountId = active;
    } else {
      _activeAccountId = _accounts.isEmpty ? null : _accounts.first.id;
    }
    if (_activeAccountId == null) {
      await _prefs!.remove(_kActiveAccount);
    } else {
      await _prefs!.setString(_kActiveAccount, _activeAccountId!);
    }
    notifyListeners();
  }

}
