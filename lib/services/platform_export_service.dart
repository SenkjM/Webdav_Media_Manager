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
    this.error,
  });

  final bool ok;

  /// Readable copy inside the app cache (delete it once imported).
  final String? path;
  final String? fileName;
  final int? size;
  final String? error;

  bool get cancelled => ok && path == null;
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
  /// Returns null on success (including a no-op on non-Android or API < 28).
  /// A non-null string is a user-visible error; MediaStore rejecting the
  /// display name `.nomedia` is reported, not swallowed.
  /// Gallery export ([saveToGallery]) never calls this.
  Future<String?> setDownloadsNomedia({required bool enabled}) async {
    if (!supported) return null;
    try {
      final raw = await _kAppChannel.invokeMethod<dynamic>('setDownloadsNomedia', {
        'enabled': enabled,
      });
      if (raw is! Map) return 'exportErr.badNativeResponse';
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      if (map['ok'] == true) return null;
      final error = map['error']?.toString();
      return (error == null || error.isEmpty) ? 'exportErr.failed' : error;
    } on MissingPluginException {
      return 'exportErr.channelUnavailable';
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return '$e';
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

  /// Open the system document picker and copy the chosen file into the app
  /// cache, returning a readable path. Returns a cancelled result when the user
  /// backs out; unsupported platforms return a failure with a message.
  Future<PickedFile> pickFile({String? mimeType}) async {
    if (!supported) {
      return const PickedFile(
        ok: false,
        error: 'pickerErr.unsupportedPlatform',
      );
    }
    try {
      final raw = await _kAppChannel.invokeMethod<dynamic>('pickFile', {
        'mimeType': mimeType,
      });
      if (raw == null) return const PickedFile(ok: true);
      if (raw is! Map) {
        return const PickedFile(ok: false, error: 'pickerErr.badResponse');
      }
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      if (map['ok'] != true) {
        return PickedFile(
          ok: false,
          error: map['error']?.toString() ?? 'pickerErr.failed',
        );
      }
      return PickedFile(
        ok: true,
        path: map['path']?.toString(),
        fileName: map['fileName']?.toString(),
        size: (map['size'] as num?)?.toInt(),
      );
    } on MissingPluginException {
      return const PickedFile(ok: false, error: 'pickerErr.channelUnavailable');
    } on PlatformException catch (e) {
      return PickedFile(ok: false, error: e.message ?? e.code);
    } catch (e) {
      return PickedFile(ok: false, error: '$e');
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
