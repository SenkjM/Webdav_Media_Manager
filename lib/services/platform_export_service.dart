import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n/generated/app_localizations.dart';

const _kAppChannel = MethodChannel('com.senkjm.media_manager/app');

/// Broadcasts Android picture-in-picture transitions reported by MainActivity.
final StreamController<bool> _pipController =
    StreamController<bool>.broadcast();

/// Last known PiP state; used to seed new listeners.
bool _pipActive = false;

bool get isInPictureInPictureSync => _pipActive;

/// Emits on every PiP enter/exit. Empty on non-Android platforms.
Stream<bool> get pictureInPictureChangesStream => _pipController.stream;

/// Wired once from `main` so native PiP callbacks reach the stream.
void handlePictureInPictureChanged(bool active) {
  _pipActive = active;
  if (!_pipController.isClosed) _pipController.add(active);
}

/// Installs the handler for the native `pictureInPictureChanged` callback.
///
/// Call once during app startup (`main`). Until this runs, native PiP events
/// reported through the same channel would be dropped.
void installPictureInPictureBridge() {
  _kAppChannel.setMethodCallHandler((call) async {
    if (call.method == 'pictureInPictureChanged') {
      handlePictureInPictureChanged(call.arguments == true);
    }
    return null;
  });
}

/// Where an exported file ended up.
class ExportResult {
  const ExportResult({
    required this.ok,
    required this.fileName,
    required this.location,
    this.uri,
    this.path,
    this.error,
    this.gallery = true,
  });

  final bool ok;
  final String fileName;

  /// Human-readable destination, e.g. `系统相册` / `下载目录/WebdavMediaManager`.
  final String location;
  final String? uri;

  /// Absolute path on API < 29; null on API 29+ (MediaStore content URI only).
  final String? path;
  final String? error;

  /// True when the file landed in the gallery (Movies / Pictures collection).
  /// Audio falls back to the Music collection and reports false.
  final bool gallery;

  static ExportResult failure(String error) =>
      ExportResult(ok: false, fileName: '', location: '', error: error);
}

/// Result of the system document picker.
class PickedFile {
  const PickedFile({
    required this.ok,
    this.path,
    this.fileName,
    this.size,
    this.relativePath,
    this.error,
  });

  final bool ok;

  /// Readable copy inside the app cache (delete it once imported).
  final String? path;
  final String? fileName;
  final int? size;

  /// Folder-upload only: the file's path below the picked root, including the
  /// root folder name (e.g. `photos/2024/cat.jpg`). Null for plain picks.
  final String? relativePath;
  final String? error;

  bool get cancelled => ok && path == null;

  static PickedFile fromMap(Map<dynamic, dynamic> raw) {
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    return PickedFile(
      ok: map['ok'] == true,
      path: map['path']?.toString(),
      fileName: map['fileName']?.toString(),
      size: (map['size'] as num?)?.toInt(),
      relativePath: map['relativePath']?.toString(),
      error: map['error']?.toString(),
    );
  }
}

/// Result of the system folder picker (SAF document tree).
class PickedFolder {
  const PickedFolder({
    required this.ok,
    this.folderName,
    this.files = const [],
    this.error,
    this.cancelled = false,
  });

  final bool ok;

  /// Display name of the picked root folder.
  final String? folderName;

  /// Every file under the root, already copied into the app cache. Each
  /// entry carries [PickedFile.relativePath] below (and including) the root.
  final List<PickedFile> files;
  final String? error;

  /// User backed out of the picker without choosing anything.
  final bool cancelled;
}

/// One file entry returned by [PlatformExportService.listFolderTree].
///
/// [uri] is an Android SAF content URI. Pass it to
/// [PlatformExportService.readUriToCache] when bytes are actually needed.
/// [relativePath] includes the root folder name (e.g. `photos/2024/cat.jpg`).
class FolderTreeEntry {
  const FolderTreeEntry({
    required this.uri,
    required this.relativePath,
    required this.fileName,
    this.size,
  });

  /// Android SAF content URI string — not a file path.
  final String uri;

  /// Path below (and including) the picked root folder name.
  final String relativePath;

  final String fileName;

  /// File size in bytes as reported by SAF; may be 0 for some providers.
  final int? size;

  static FolderTreeEntry fromMap(Map<dynamic, dynamic> raw) {
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    return FolderTreeEntry(
      uri: map['uri']?.toString() ?? '',
      relativePath: map['relativePath']?.toString() ?? '',
      fileName: map['fileName']?.toString() ?? '',
      size: (map['size'] as num?)?.toInt(),
    );
  }
}

/// Result of [PlatformExportService.listFolderTree].
///
/// Unlike [PickedFolder] no bytes have been copied: [files] are SAF URIs only.
class PickedFolderTree {
  const PickedFolderTree({
    required this.ok,
    this.folderName,
    this.files = const [],
    this.error,
    this.cancelled = false,
  });

  final bool ok;
  final String? folderName;
  final List<FolderTreeEntry> files;
  final String? error;
  final bool cancelled;
}
/// Outcome of toggling `.nomedia` in `Download/WebdavMediaManager`.
class DownloadsNomediaResult {
  const DownloadsNomediaResult({this.error, this.alreadyMatched = false});

  /// User-visible failure. Null when the platform call succeeded or did nothing.
  final String? error;

  /// On-disk / MediaStore state already matched the request, so nothing was
  /// written or deleted. Not an error.
  final bool alreadyMatched;
}

/// MediaStore / Downloads exports and the SAF file picker, implemented natively
/// in `MainActivity`.
///
/// Android 10+ writes through `MediaStore` (no runtime permission). Android 9
/// and below falls back to a public-directory write plus a media scan and needs
/// `WRITE_EXTERNAL_STORAGE` (declared with `maxSdkVersion="28"`).
class PlatformExportService {
  const PlatformExportService();

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Copy [sourcePath] into the system gallery.
  Future<ExportResult> saveToGallery({
    required String sourcePath,
    required String fileName,
    String? mimeType,
    String album = 'WebdavMediaManager',
  }) => _save(
    method: 'saveToGallery',
    sourcePath: sourcePath,
    fileName: fileName,
    mimeType: mimeType,
    extraKey: 'album',
    extraValue: album,
  );

  /// Create or delete `.nomedia` in `Download/WebdavMediaManager` only.
  ///
  /// [DownloadsNomediaResult.error] is null on success, including a no-op on
  /// non-Android or API < 28. [DownloadsNomediaResult.alreadyMatched] means the
  /// folder already had (or already lacked) a real `.nomedia`, so this call
  /// did not write or delete. A renamed MediaStore display name is not a match
  /// and still surfaces as an error when the insert does not keep `.nomedia`.
  /// Gallery export ([saveToGallery]) never calls this.
  Future<DownloadsNomediaResult> setDownloadsNomedia({required bool enabled}) async {
    if (!supported) return const DownloadsNomediaResult();
    try {
      final raw = await _kAppChannel.invokeMethod<dynamic>('setDownloadsNomedia', {
        'enabled': enabled,
      });
      if (raw is! Map) {
        return const DownloadsNomediaResult(error: 'exportErr.badNativeResponse');
      }
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      if (map['ok'] == true) {
        return DownloadsNomediaResult(alreadyMatched: map['already'] == true);
      }
      final error = map['error']?.toString();
      return DownloadsNomediaResult(
        error: (error == null || error.isEmpty) ? 'exportErr.failed' : error,
      );
    } on MissingPluginException {
      return const DownloadsNomediaResult(error: 'exportErr.channelUnavailable');
    } on PlatformException catch (e) {
      return DownloadsNomediaResult(error: e.message ?? e.code);
    } catch (e) {
      return DownloadsNomediaResult(error: '$e');
    }
  }

  /// Copy [sourcePath] into the public Downloads collection.
  Future<ExportResult> saveToDownloads({
    required String sourcePath,
    required String fileName,
    String? mimeType,
    String subdir = 'WebdavMediaManager',
  }) => _save(
    method: 'saveToDownloads',
    sourcePath: sourcePath,
    fileName: fileName,
    mimeType: mimeType,
    extraKey: 'subdir',
    extraValue: subdir,
  );

  /// Map a stable error code (see [_save]/[pickFile]) to localized text.
  /// Values that are not ours (native passthrough messages) return as-is.
  static String describeError(String raw, AppLocalizations l10n) {
    final bar = raw.indexOf('|');
    if (bar > 0) {
      final code = raw.substring(0, bar);
      final detail = raw.substring(bar + 1);
      switch (code) {
        case 'exportErr.sourceMissing':
          return l10n.exportErrSourceMissing(detail);
        case 'exportErr.badNativeResponse':
          return l10n.exportErrBadNativeResponse(detail);
        case 'exportErr.failedWith':
          return l10n.exportErrFailedWith(detail);
      }
    }
    switch (raw) {
      case 'exportErr.unsupportedPlatform':
        return l10n.exportErrUnsupportedPlatform;
      case 'exportErr.failed':
        return l10n.exportErrFailed;
      case 'exportErr.channelUnavailable':
        return l10n.exportErrChannelUnavailable;
      case 'pickerErr.unsupportedPlatform':
        return l10n.pickerErrUnsupportedPlatform;
      case 'pickerErr.badResponse':
        return l10n.pickerErrBadResponse;
      case 'pickerErr.failed':
        return l10n.pickerErrFailed;
      case 'pickerErr.channelUnavailable':
        return l10n.pickerErrChannelUnavailable;
    }
    return raw;
  }

  /// Map a location value (stable code, known Chinese from native, or a
  /// passthrough path) to localized text.
  static String describeLocation(String raw, AppLocalizations l10n) {
    switch (raw) {
      case 'loc.systemGallery':
      case '系统相册':
        return l10n.locationSystemGallery;
      case '下载目录':
        return l10n.locationDownloads;
    }
    if (raw.startsWith('下载目录/')) {
      return l10n.locationDownloadsSubdir(raw.substring('下载目录/'.length));
    }
    return raw;
  }

  Future<ExportResult> _save({
    required String method,
    required String sourcePath,
    required String fileName,
    required String? mimeType,
    required String extraKey,
    required String extraValue,
  }) async {
    if (!supported) {
      return ExportResult.failure('exportErr.unsupportedPlatform');
    }
    final src = File(sourcePath);
    if (!await src.exists()) {
      return ExportResult.failure('exportErr.sourceMissing|$sourcePath');
    }
    try {
      final raw = await _kAppChannel.invokeMethod<dynamic>(method, {
        'path': sourcePath,
        'fileName': fileName,
        'mimeType': mimeType,
        extraKey: extraValue,
      });
      if (raw is! Map) {
        return ExportResult.failure(
          'exportErr.badNativeResponse|${raw.runtimeType}',
        );
      }
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      if (map['ok'] != true) {
        return ExportResult.failure(
          map['error']?.toString() ?? 'exportErr.failed',
        );
      }
      return ExportResult(
        ok: true,
        fileName: map['fileName']?.toString() ?? fileName,
        location: map['location']?.toString() ?? 'loc.systemGallery',
        uri: map['uri']?.toString(),
        path: map['path']?.toString(),
        gallery: (map['collection']?.toString() ?? 'gallery') == 'gallery',
      );
    } on MissingPluginException {
      return ExportResult.failure('exportErr.channelUnavailable');
    } on PlatformException catch (e) {
      return ExportResult.failure(
        'exportErr.failedWith|${e.message ?? e.code}',
      );
    } catch (e) {
      return ExportResult.failure('exportErr.failedWith|$e');
    }
  }

  /// Whether [fileName] looks like a gallery-eligible (video/image) file.
  static bool isGalleryMedia(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    return const {
      '.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv', '.ts', //
      '.m4v', '.wmv', '.3gp', '.mpg', '.mpeg',
      '.jpg', '.jpeg', '.png', '.webp', '.gif',
    }.contains(ext);
  }

  /// Open the system document picker and copy the chosen file(s) into the app
  /// cache, returning readable paths. The native picker allows multi-select;
  /// a single pick simply yields a one-element list. Returns an empty list
  /// when the user backs out; failures throw no exception but surface through
  /// the legacy [pickFile] single-result shape below.
  Future<List<PickedFile>> pickFiles({String? mimeType}) async {
    if (!supported) {
      return const [
        PickedFile(ok: false, error: 'pickerErr.unsupportedPlatform'),
      ];
    }
    try {
      final raw = await _kAppChannel.invokeMethod<dynamic>('pickFile', {
        'mimeType': mimeType,
      });
      if (raw == null) return const [];
      if (raw is! Map) {
        return const [PickedFile(ok: false, error: 'pickerErr.badResponse')];
      }
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      if (map['ok'] != true) {
        return [
          PickedFile(
            ok: false,
            error: map['error']?.toString() ?? 'pickerErr.failed',
          ),
        ];
      }
      final files = (map['files'] as List?) ?? const [];
      return files
          .whereType<Map>()
          .map(PickedFile.fromMap)
          .toList(growable: false);
    } on MissingPluginException {
      return const [
        PickedFile(ok: false, error: 'pickerErr.channelUnavailable'),
      ];
    } on PlatformException catch (e) {
      return [PickedFile(ok: false, error: e.message ?? e.code)];
    } catch (e) {
      return [PickedFile(ok: false, error: '$e')];
    }
  }

  /// Open the system document picker and copy the chosen file into the app
  /// cache, returning a readable path. Returns a cancelled result when the user
  /// backs out; unsupported platforms return a failure with a message.
  Future<PickedFile> pickFile({String? mimeType}) async {
    final files = await pickFiles(mimeType: mimeType);
    if (files.isEmpty) return const PickedFile(ok: true);
    return files.first;
  }

  /// Open the system folder picker (SAF document tree) and copy every file
  /// under the chosen directory into the app cache. Each entry keeps its
  /// path below the root in [PickedFile.relativePath].
  Future<PickedFolder> pickFolder() async {
    if (!supported) {
      return const PickedFolder(
        ok: false,
        error: 'pickerErr.unsupportedPlatform',
      );
    }
    try {
      final raw = await _kAppChannel.invokeMethod<dynamic>('pickFolder');
      if (raw == null) return const PickedFolder(ok: true, cancelled: true);
      if (raw is! Map) {
        return const PickedFolder(ok: false, error: 'pickerErr.badResponse');
      }
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      if (map['ok'] != true) {
        return PickedFolder(
          ok: false,
          error: map['error']?.toString() ?? 'pickerErr.failed',
        );
      }
      final files = ((map['files'] as List?) ?? const [])
          .whereType<Map>()
          .map(PickedFile.fromMap)
          .toList(growable: false);
      return PickedFolder(
        ok: true,
        folderName: map['folderName']?.toString(),
        files: files,
      );
    } on MissingPluginException {
      return const PickedFolder(
        ok: false,
        error: 'pickerErr.channelUnavailable',
      );
    } on PlatformException catch (e) {
      return PickedFolder(ok: false, error: e.message ?? e.code);
    } catch (e) {
      return PickedFolder(ok: false, error: '$e');
    }
  }

  /// Open the system folder picker and return only the tree metadata — URIs,
  /// relative paths, file names, sizes — without copying any bytes.
  ///
  /// Use [readUriToCache] to materialise individual files inside a worker.
  Future<PickedFolderTree> listFolderTree() async {
    if (!supported) {
      return const PickedFolderTree(ok: false, error: 'pickerErr.unsupportedPlatform');
    }
    try {
      final raw = await _kAppChannel.invokeMethod<dynamic>('listFolderTree');
      if (raw == null) return const PickedFolderTree(ok: true, cancelled: true);
      if (raw is! Map) return const PickedFolderTree(ok: false, error: 'pickerErr.badResponse');
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      if (map['ok'] != true) {
        return PickedFolderTree(ok: false, error: map['error']?.toString() ?? 'pickerErr.failed');
      }
      final files = ((map['files'] as List?) ?? const [])
          .whereType<Map>()
          .map(FolderTreeEntry.fromMap)
          .toList(growable: false);
      return PickedFolderTree(ok: true, folderName: map['folderName']?.toString(), files: files);
    } on MissingPluginException {
      return const PickedFolderTree(ok: false, error: 'pickerErr.channelUnavailable');
    } on PlatformException catch (e) {
      return PickedFolderTree(ok: false, error: e.message ?? e.code);
    } catch (e) {
      return PickedFolderTree(ok: false, error: '$e');
    }
  }

  /// Copy one SAF content URI into the app cache and return its local path.
  ///
  /// Call from a worker thread to materialise a [FolderTreeEntry] on demand.
  /// Returns null on failure.
  static Future<String?> readUriToCache(String uri) async {
    try {
      final raw = await _kAppChannel.invokeMethod<dynamic>('readUriToCache', {'uri': uri});
      if (raw is! Map) return null;
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      if (map['ok'] != true) return null;
      return map['path']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Delete a file previously returned by [pickFile].
  static Future<void> discardPickedFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Copy bytes to a temporary file so they can be handed to the native export.
  static Future<File> writeTempExportFile(
    String fileName,
    List<int> bytes,
  ) async {
    final tmpRoot = await getTemporaryDirectory();
    final dir = Directory(p.join(tmpRoot.path, 'exports'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(p.join(dir.path, sanitizeExportFileName(fileName)));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}

/// Strip characters that are illegal in export file names.
String sanitizeExportFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  return cleaned.isEmpty ? 'file' : cleaned;
}

/// Split `song.mp3` into `('song', '.mp3')` so a user-typed name keeps its ext.
(String, String) splitFileNameExtension(String fileName) {
  final ext = p.extension(fileName);
  if (ext.isEmpty) return (fileName, '');
  return (fileName.substring(0, fileName.length - ext.length), ext);
}
