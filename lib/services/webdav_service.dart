import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/file_type_config.dart';
import '../models/webdav_account.dart';
import '../models/webdav_item.dart';
import '../models/webdav_stream.dart';
import '../services/cloud_drive_service.dart';
import 'wdmm_vfs.dart';

/// Thin WebDAV account registry + I/O delegation layer.
///
/// After B1 step 4 (isCloudType=true for all), ALL account I/O routes through
/// [CloudDriveService] via the Rust VFS layer. This class retains the same API
/// surface for the 84 call sites that reference it, but the webdav_client
/// transport, resumable_download, and Dart driver implementations are gone.
class WebDavService extends ChangeNotifier {
  /// IDs of all configure()d accounts. Replaces the old _conns map — we no
  /// longer build webdav.Client objects; the Rust VFS layer handles all I/O.
  final Set<String> _registeredAccountIds = {};

  /// Account selected by the network library (browsing only).
  String? _activeAccountId;
  String? _lastError;

  final CloudDriveService? _cloudDrive;

  WebDavService({CloudDriveService? cloudDrive}) : _cloudDrive = cloudDrive;

  bool get isConnected => _registeredAccountIds.contains(_activeAccountId);
  String? get lastError => _lastError;

  /// Always null — webdav raw URL is no longer needed; all I/O goes through
  /// the Rust VFS layer. Kept to avoid breaking call sites that read it but
  /// don't crash on null.
  String? get baseUrl => null;
  String? get accountId => _activeAccountId;

  List<String> get registeredAccountIds => _registeredAccountIds.toList();

  bool hasAccount(String accountId) =>
      _registeredAccountIds.contains(accountId);

  int capabilitiesFor(String accountId) =>
      _cloudDrive?.capabilitiesFor(accountId) ?? 0;

  bool can(String accountId, int cap) =>
      _cloudDrive?.can(accountId, cap) ?? false;

  String typeLabelFor(WebDavAccount account) =>
      _cloudDrive?.typeLabelFor(account) ?? account.providerType;

  Future<List<AccountStatusTag>> statusTagsFor(String accountId) =>
      _cloudDrive?.statusTagsFor(accountId) ??
      Future.value(const <AccountStatusTag>[]);

  Future<void> verifyNewAccount(
    WebDavAccount account,
    Map<String, dynamic> config,
  ) async {
    if (_cloudDrive == null) {
      throw WdmmVfsException('CloudDriveService not initialized');
    }
    await _cloudDrive.verifyNewAccount(account, config);
  }

  /// Register an account. Credentials live in the Core vault (via
  /// AccountsService._upsertToCore); we only need the id for routing and to
  /// notify listeners so the UI can react.
  void configure({
    required String accountId,
    required String url,
    required String username,
    required String password,
    bool makeActive = true,
  }) {
    _registeredAccountIds.add(accountId);
    if (makeActive || _activeAccountId == null) _activeAccountId = accountId;
    _lastError = null;
    notifyListeners();
  }

  void disconnect({String? accountId}) {
    if (accountId == null) {
      _registeredAccountIds.clear();
      _activeAccountId = null;
    } else {
      _registeredAccountIds.remove(accountId);
      if (_activeAccountId == accountId) {
        _activeAccountId = _registeredAccountIds.isEmpty
            ? null
            : _registeredAccountIds.first;
      }
    }
    notifyListeners();
  }

  void setActiveAccount(String accountId) {
    if (_activeAccountId == accountId) return;
    _activeAccountId = accountId;
    notifyListeners();
  }

  /// Always returns null — all accounts now use the async Rust-VFS path.
  /// Callers must use [resolveStreamSource] instead.
  WebDavStreamSource? buildStreamSource({
    required String remotePath,
    required String name,
    required String accountId,
    StreamKind? kind,
  }) => null;

  Future<WebDavStreamSource?> resolveStreamSource({
    required String remotePath,
    required String name,
    required String accountId,
    StreamKind? kind,
  }) async {
    final cloud = _cloudOf(accountId);
    if (cloud == null) return null;
    return cloud.resolveStreamSource(
      remotePath: remotePath,
      name: name,
      accountId: accountId,
      kind: kind,
    );
  }

  Future<bool> testConnection({required String accountId}) async {
    final cloud = _cloudOf(accountId);
    if (cloud == null) {
      _lastError = 'err.webdavNotConfigured';
      notifyListeners();
      return false;
    }
    final ok = await cloud.testConnection(accountId);
    _lastError = ok ? null : 'err.driverNotReady';
    notifyListeners();
    return ok;
  }

  Future<List<WebDavItem>> listDirectory(
    String accountId,
    String path, {
    FileTypeConfig? fileTypes,
  }) => _requireCloud(accountId).listDirectory(
    accountId,
    path,
    fileTypes: fileTypes,
  );

  /// Single-entry stat. Cloud accounts resolve metadata via the Rust VFS
  /// get(); returns null — callers that need metadata should use listDirectory
  /// on the parent instead.
  Future<WebDavItem?> statPath(String accountId, String path) async => null;

  Future<void> downloadToFile(
    String accountId,
    String remotePath,
    File localFile, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
    int resumeFrom = 0,
    bool useCryptSequentialDownload = false,
    void Function(CloudDownloadMode mode)? onMode,
    int? expectedRemoteSize,
    DateTime? expectedRemoteModified,
    void Function(int size, DateTime? modified)? onIdentity,
  }) => _requireCloud(accountId).downloadToFile(
    accountId,
    remotePath,
    localFile,
    onProgress: onProgress,
    cancelToken: cancelToken,
    resumeFrom: resumeFrom,
    useCryptSequentialDownload: useCryptSequentialDownload,
    onMode: onMode,
    expectedRemoteSize: expectedRemoteSize,
    expectedRemoteModified: expectedRemoteModified,
    onIdentity: onIdentity,
  );

  Future<Uint8List> readAsBytes(String accountId, String remotePath) =>
      _requireCloud(accountId).readAsBytes(accountId, remotePath);

  Future<void> writeBytes(
    String accountId,
    String remotePath,
    Uint8List data,
  ) => _requireCloud(accountId).writeBytes(accountId, remotePath, data);

  Future<void> writeFromFile(
    String accountId,
    String remotePath,
    String localPath, {
    void Function(int count, int total)? onProgress,
    CancelToken? cancelToken,
  }) => _requireCloud(accountId).writeFromFile(
    accountId,
    remotePath,
    localPath,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );

  /// Stream an in-memory byte stream to [remotePath].
  ///
  /// Upload is disabled for all drivers (PLAN §7.2.1 — AccountCaps.write not
  /// granted). This method is retained for API surface compatibility with the
  /// crypt upload path (WebDavAccountSource.writeFile); it is never reached
  /// because the UI does not expose the upload action.
  Future<void> writeStream(
    String accountId,
    String remotePath,
    Stream<List<int>> data,
    int length, {
    void Function(int count, int total)? onProgress,
    CancelToken? cancelToken,
  }) async => throw WdmmVfsException('err.cloudWriteDisabled');

  Future<void> ensureDirectory(String accountId, String path) =>
      _requireCloud(accountId).ensureDirectory(accountId, path);

  Future<void> createFolder(String accountId, String path) =>
      _requireCloud(accountId).createFolder(accountId, path);

  Future<void> deletePath(String accountId, String path) =>
      _requireCloud(accountId).deletePath(accountId, path);

  Future<void> renamePath(
    String accountId,
    String oldPath,
    String newPath, {
    bool overwrite = false,
  }) => _requireCloud(accountId).renamePath(
    accountId,
    oldPath,
    newPath,
    overwrite: overwrite,
  );

  Future<void> copyPath(
    String accountId,
    String oldPath,
    String newPath,
  ) => _requireCloud(accountId).copyPath(accountId, oldPath, newPath);

  Future<void> movePath(
    String accountId,
    String oldPath,
    String newPath,
  ) => _requireCloud(accountId).movePath(accountId, oldPath, newPath);

  Future<List<WebDavItem>> collectFilesRecursive(
    String accountId,
    String folderPath, {
    FileTypeConfig? fileTypes,
    bool onlyAudio = false,
  }) async {
    final result = <WebDavItem>[];
    final queue = <String>[folderPath];
    while (queue.isNotEmpty) {
      final dir = queue.removeAt(0);
      final items = await listDirectory(accountId, dir, fileTypes: fileTypes);
      for (final item in items) {
        if (item.isDirectory) {
          queue.add(item.path);
        } else if (!onlyAudio || item.isAudio) {
          result.add(item);
        }
      }
    }
    return result;
  }

  /// Returns [CloudDriveService] for any registered account; null when the
  /// cloud service is not initialised or the account is unknown.
  CloudDriveService? _cloudOf(String? accountId) {
    final cd = _cloudDrive;
    if (cd == null || accountId == null) return null;
    return cd.handles(accountId) ? cd : null;
  }

  CloudDriveService _requireCloud(String accountId) {
    final cloud = _cloudOf(accountId);
    if (cloud == null) throw UnknownWebDavAccountException(accountId);
    return cloud;
  }
}

/// Thrown when an operation targets an account that is no longer configured.
///
/// Distinct from a VFS 404: it means the source account was deleted, so the
/// UI can say "来源网盘已移除" instead of a confusing "file not found".
class UnknownWebDavAccountException implements Exception {
  const UnknownWebDavAccountException(this.accountId);

  final String accountId;

  @override
  String toString() => 'err.sourceUnbound|$accountId';
}

/// Cancel token for in-flight downloads (dio).
typedef DownloadCancelToken = CancelToken;
