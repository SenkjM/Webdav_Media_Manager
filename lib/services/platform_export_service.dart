import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _kAppChannel = MethodChannel('com.webdav.webdav_music_player/app');

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

  /// Human-readable destination, e.g. `系统相册` / `下载目录/WebDAVMusic`.
  final String location;
  final String? uri;

  /// Absolute path on API < 29; null on API 29+ (MediaStore content URI only).
  final String? path;
  final String? error;

  /// True when the file landed in the gallery (Movies / Pictures collection).
  /// Audio falls back to the Music collection and reports false.
  final bool gallery;

  static ExportResult failure(String error) => ExportResult(
        ok: false,
        fileName: '',
        location: '',
        error: error,
      );
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
    String album = 'WebDAVMusic',
  }) =>
      _save(
        method: 'saveToGallery',
        sourcePath: sourcePath,
        fileName: fileName,
        mimeType: mimeType,
        extraKey: 'album',
        extraValue: album,
      );

  /// Copy [sourcePath] into the public Downloads collection.
  Future<ExportResult> saveToDownloads({
    required String sourcePath,
    required String fileName,
    String? mimeType,
    String subdir = 'WebDAVMusic',
  }) =>
      _save(
        method: 'saveToDownloads',
        sourcePath: sourcePath,
        fileName: fileName,
        mimeType: mimeType,
        extraKey: 'subdir',
        extraValue: subdir,
      );

  Future<ExportResult> _save({
    required String method,
    required String sourcePath,
    required String fileName,
    required String? mimeType,
    required String extraKey,
    required String extraValue,
  }) async {
    if (!supported) {
      return ExportResult.failure('当前平台不支持写入系统相册/下载目录');
    }
    final src = File(sourcePath);
    if (!await src.exists()) {
      return ExportResult.failure('源文件不存在：$sourcePath');
    }
    try {
      final raw = await _kAppChannel.invokeMethod<dynamic>(method, {
        'path': sourcePath,
        'fileName': fileName,
        'mimeType': mimeType,
        extraKey: extraValue,
      });
      if (raw is! Map) {
        return ExportResult.failure('导出失败：原生返回 ${raw.runtimeType}');
      }
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      if (map['ok'] != true) {
        return ExportResult.failure(
          map['error']?.toString() ?? '导出失败',
        );
      }
      return ExportResult(
        ok: true,
        fileName: map['fileName']?.toString() ?? fileName,
        location: map['location']?.toString() ?? '系统相册',
        uri: map['uri']?.toString(),
        path: map['path']?.toString(),
        gallery: (map['collection']?.toString() ?? 'gallery') == 'gallery',
      );
    } on MissingPluginException {
      return ExportResult.failure('原生导出通道不可用（需完整 APK）');
    } on PlatformException catch (e) {
      return ExportResult.failure('导出失败：${e.message ?? e.code}');
    } catch (e) {
      return ExportResult.failure('导出失败：$e');
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
      return const PickedFile(ok: false, error: '当前平台不支持系统文件选择器');
    }
    try {
      final raw = await _kAppChannel.invokeMethod<dynamic>('pickFile', {
        'mimeType': mimeType,
      });
      if (raw == null) return const PickedFile(ok: true);
      if (raw is! Map) {
        return const PickedFile(ok: false, error: '文件选择返回异常');
      }
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      if (map['ok'] != true) {
        return PickedFile(
          ok: false,
          error: map['error']?.toString() ?? '文件选择失败',
        );
      }
      return PickedFile(
        ok: true,
        path: map['path']?.toString(),
        fileName: map['fileName']?.toString(),
        size: (map['size'] as num?)?.toInt(),
      );
    } on MissingPluginException {
      return const PickedFile(ok: false, error: '原生文件选择器不可用（需完整 APK）');
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
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .trim();
  return cleaned.isEmpty ? 'file' : cleaned;
}

/// Split `song.mp3` into `('song', '.mp3')` so a user-typed name keeps its ext.
(String, String) splitFileNameExtension(String fileName) {
  final ext = p.extension(fileName);
  if (ext.isEmpty) return (fileName, '');
  return (fileName.substring(0, fileName.length - ext.length), ext);
}
