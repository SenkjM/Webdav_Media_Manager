// SPDX-FileCopyrightText: 2025 Webdav Media Manager contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/app_snack.dart';
import '../utils/l10n_host.dart';
import 'platform_export_service.dart';
import 'settings_service.dart';

/// 单一入口管理所有「下载目录」写入（下载任务 downloads target、本地备份导出、DB 恢复导出）。
/// 相册导出不走它。
///
/// 功能：
/// - save：决定写入 SAF 自定义目录还是 MediaStore 系统下载目录
/// - fallbackToDefault：SAF 目录失效时全局回落到系统下载目录（幂等，只提示一次）
/// - alignNomedia：按设置对当前生效目标双向对齐 .nomedia
/// - pickCustomDir / disableCustomDir：用户操作自定义目录开关
/// - verifyOnOpen：设置页打开 / app 启动时校验自定义目录可用性
class DownloadDestinationService extends ChangeNotifier {
  DownloadDestinationService({
    required SettingsService settings,
    required PlatformExportService export,
  })  : _settings = settings,
        _export = export;

  final SettingsService _settings;
  final PlatformExportService _export;

  /// 幂等回落锁：防止并发调用重复提示
  Future<bool>? _fallbackLock;

  /// 写入文件到下载目录。
  ///
  /// 若自定义目录生效：先 alignNomedia（best-effort）→ saveToTree。
  /// 结果 safInvalid → 调 fallbackToDefault，并：
  ///   - retryOnFallback=false（下载任务）→ 返回失败，不自动重试
  ///   - retryOnFallback=true（备份/恢复导出）→ 回落后再写一次到 MediaStore，
  ///     返回结果并标记 fellBack=true 以便调用方提示
  ///
  /// 否则：MediaStore saveToDownloads(subdir: mediaStoreSubdir)。
  Future<ExportResult> save({
    required String sourcePath,
    required String fileName,
    String? mimeType,
    String mediaStoreSubdir = 'WebdavMediaManager',
    bool retryOnFallback = false,
  }) async {
    if (_settings.customDownloadDirActive) {
      // Best-effort .nomedia 对齐（失败不影响本次写入）
      unawaited(alignNomedia(reportAlready: false));

      final result = await _export.saveToTree(
        treeUri: _settings.customDownloadTreeUri!,
        sourcePath: sourcePath,
        fileName: fileName,
        mimeType: mimeType,
      );

      if (result.safInvalid) {
        // SAF 目录失效 → 全局回落到系统下载目录
        await fallbackToDefault(reason: 'save_failed');

        if (!retryOnFallback) {
          // 下载任务：返回失败，不自动重试（任务保持 failed，用户可手动重试）
          return ExportResult.failure(
            'err.customDirInvalid',
            errorKind: 'safInvalid',
          );
        }

        // 备份/恢复导出：回落后再写一次到 MediaStore
        final fallbackResult = await _export.saveToDownloads(
          sourcePath: sourcePath,
          fileName: fileName,
          mimeType: mimeType,
          subdir: mediaStoreSubdir,
        );
        return fallbackResult.copyWith(fellBack: true);
      }

      return result;
    }

    // 默认：MediaStore 系统下载目录
    return _export.saveToDownloads(
      sourcePath: sourcePath,
      fileName: fileName,
      mimeType: mimeType,
      subdir: mediaStoreSubdir,
    );
  }

  /// 回落到默认目标（系统下载目录）。
  ///
  /// 幂等：若当前不 active 直接返回 false；否则 release uri、clearCustomDownloadDir、
  /// 提示用户（全局 snack，只显示一次）、随后对默认目标 alignNomedia；返回 true。
  /// 并发调用用一个 Future 锁防重复。
  Future<bool> fallbackToDefault({String? reason}) async {
    final lock = _fallbackLock;
    if (lock != null) return lock;

    final completer = Completer<bool>();
    _fallbackLock = completer.future;

    try {
      if (!_settings.customDownloadDirActive) {
        completer.complete(false);
        return false;
      }

      // Release SAF uri
      final uri = _settings.customDownloadTreeUri;
      if (uri != null && uri.isNotEmpty) {
        try {
          await _export.releaseDownloadTree(uri);
        } catch (e) {
          debugPrint('fallbackToDefault: release uri failed: $e');
        }
      }

      // Clear settings
      await _settings.clearCustomDownloadDir();

      // 提示用户（全局 snack，一次）
      final l10n = L10nHost.current;
      AppSnack.showGlobal(l10n.customDownloadDirFallback, error: true);

      // 对默认目标 alignNomedia
      unawaited(alignNomedia(reportAlready: false));

      completer.complete(true);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('fallbackToDefault failed: $e');
      completer.complete(false);
      rethrow;
    } finally {
      _fallbackLock = null;
    }
  }

  /// 按 settings.downloadNomediaEnabled 对当前生效目标创建/删除 .nomedia。
  ///
  /// SAF: setTreeNomedia；默认：setDownloadsNomedia。
  /// SAF 结果 safInvalid → fallbackToDefault 后对默认目标再 align。
  /// 旧目录的 .nomedia 不动。
  Future<DownloadsNomediaResult> alignNomedia({
    bool reportAlready = false,
  }) async {
    final enabled = _settings.downloadNomediaEnabled;

    if (_settings.customDownloadDirActive) {
      // SAF 自定义目录
      final result = await _export.setTreeNomedia(
        treeUri: _settings.customDownloadTreeUri!,
        enabled: enabled,
      );

      if (result.safInvalid) {
        // SAF 目录失效 → 回落到默认目标
        await fallbackToDefault(reason: 'nomedia_failed');
        // 对默认目标再 align
        return _export.setDownloadsNomedia(enabled: enabled);
      }

      return result;
    }

    // 默认：MediaStore 系统下载目录
    return _export.setDownloadsNomedia(enabled: enabled);
  }

  /// 用户选择自定义目录。
  ///
  /// 调用 pickDownloadTree(oldUri: 当前 uri)；成功 → settings.setCustomDownloadDir；
  /// 然后 alignNomedia；返回结果。取消/失败 → 若之前没有 active 的 uri 则保持关闭。
  Future<PickedDownloadTree> pickCustomDir() async {
    final result = await _export.pickDownloadTree(
      oldUri: _settings.customDownloadTreeUri,
    );

    if (result.ok && result.uri != null && result.uri!.isNotEmpty) {
      await _settings.setCustomDownloadDir(
        uri: result.uri!,
        displayName: result.displayName,
      );
      unawaited(alignNomedia(reportAlready: false));
      notifyListeners();
    }

    return result;
  }

  /// 用户关闭自定义目录。
  ///
  /// Release + clear + alignNomedia（默认目标）。
  Future<void> disableCustomDir() async {
    if (!_settings.useCustomDownloadDir) return;

    final uri = _settings.customDownloadTreeUri;
    if (uri != null && uri.isNotEmpty) {
      try {
        await _export.releaseDownloadTree(uri);
      } catch (e) {
        debugPrint('disableCustomDir: release uri failed: $e');
      }
    }

    await _settings.clearCustomDownloadDir();
    unawaited(alignNomedia(reportAlready: false));
    notifyListeners();
  }

  /// 设置页打开 / app 启动时：校验自定义目录可用性。
  ///
  /// active 时 checkDownloadTree，不可用 → fallbackToDefault（会提示）。
  /// flag 开但 uri 空 → clear（提示同 fallback）。
  Future<void> verifyOnOpen() async {
    if (_settings.useCustomDownloadDir) {
      final uri = _settings.customDownloadTreeUri;
      if (uri == null || uri.isEmpty) {
        // flag 开但 uri 空 → clear
        await _settings.clearCustomDownloadDir();
        final l10n = L10nHost.current;
        AppSnack.showGlobal(l10n.customDownloadDirFallback, error: true);
        notifyListeners();
        return;
      }

      // 校验可用性
      final usable = await _export.checkDownloadTree(uri);
      if (!usable) {
        await fallbackToDefault(reason: 'verify_failed');
      }
    }
  }

  /// 当前目标显示名（用于 UI）
  String get currentTargetDisplayName {
    if (_settings.customDownloadDirActive) {
      return _settings.customDownloadDisplayName ??
          L10nHost.current.customDownloadDirCurrent('');
    }
    return L10nHost.current.customDownloadDirDefault;
  }
}
