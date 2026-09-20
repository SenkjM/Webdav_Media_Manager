import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/library_track.dart';
import '../utils/share_export_clip.dart';
import 'cache_service.dart';

/// Exports library tracks for the system share sheet.
///
/// **CUE virtual tracks**: crops [LibraryTrack.clipStartMs]..[clipEndMs] with
/// FFmpeg (`ffmpeg_kit_flutter_new_audio` on device; system `ffmpeg` fallback
/// on desktop/tests) and writes title/artist/album/track tags into a
/// standalone MP3 clip — never shares the whole FILE.
///
/// **Normal tracks**: shares the cached audio file as-is when present.
class ShareExportService {
  ShareExportService({CacheService? cache, FfmpegRunner? runner})
      : _cache = cache,
        _runner = runner ?? FfmpegRunner();

  final CacheService? _cache;
  final FfmpegRunner _runner;

  /// Prepare shareable files for [tracks] and open the platform share sheet.
  Future<ShareExportResult> shareTracks(List<LibraryTrack> tracks) async {
    if (tracks.isEmpty) {
      return const ShareExportResult(ok: false, message: '未选择曲目');
    }
    final files = <XFile>[];
    final errors = <String>[];
    for (final t in tracks) {
      try {
        final path = await exportTrackFile(t);
        files.add(XFile(path, mimeType: _mimeFor(path)));
      } catch (e) {
        errors.add('${t.displayTitle}: $e');
      }
    }
    if (files.isEmpty) {
      return ShareExportResult(
        ok: false,
        message: errors.isEmpty ? '没有可分享的文件' : errors.join('\n'),
      );
    }
    await SharePlus.instance.share(ShareParams(files: files));
    final msg = errors.isEmpty
        ? '已分享 ${files.length} 个文件'
        : '已分享 ${files.length} 个；失败 ${errors.length} 个';
    return ShareExportResult(ok: true, message: msg, errors: errors);
  }

  /// Returns a local path ready to share (cropped+tagged for CUE).
  Future<String> exportTrackFile(LibraryTrack track) async {
    final cache = _cache;
    if (cache == null) {
      throw StateError('CacheService 未注入');
    }
    final audioRemote = track.effectiveAudioRemotePath;
    final local = await cache.localPathIfCached(
      audioRemote,
      accountId: track.accountId,
    );
    if (local == null || !File(local).existsSync()) {
      throw StateError('本地无缓存，请先下载');
    }

    if (!track.isCueVirtual || track.clipStartMs == null) {
      return local;
    }

    final startMs = track.clipStartMs!;
    final endMs = track.clipEndMs;
    final dir = await getTemporaryDirectory();
    final stem = sanitizeShareFileStem(track.displayTitle);
    final out = p.join(dir.path, 'wmp_share_${track.cueTrackIndex ?? 0}_$stem.mp3');
    final args = buildCueClipFfmpegArgs(
      inputPath: local,
      outputPath: out,
      startMs: startMs,
      endMs: endMs,
      title: track.title ?? track.displayTitle,
      artist: track.artist,
      album: track.album,
      albumArtist: track.albumArtist,
      trackNumber: track.trackNumber,
      trackTotal: track.trackTotal,
      discNumber: track.discNumber,
      year: track.year,
      genre: track.genre,
    );
    await _runner.run(args);
    if (!File(out).existsSync()) {
      throw StateError('裁剪导出失败');
    }
    return out;
  }

  static String _mimeFor(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.mp3':
        return 'audio/mpeg';
      case '.flac':
        return 'audio/flac';
      case '.m4a':
      case '.aac':
        return 'audio/mp4';
      case '.ogg':
        return 'audio/ogg';
      case '.wav':
        return 'audio/wav';
      default:
        return 'application/octet-stream';
    }
  }
}

class ShareExportResult {
  const ShareExportResult({
    required this.ok,
    required this.message,
    this.errors = const [],
  });
  final bool ok;
  final String message;
  final List<String> errors;
}

/// Runs ffmpeg argv (without the `ffmpeg` binary name).
class FfmpegRunner {
  /// Prefer FFmpeg Kit on mobile; fall back to system `ffmpeg` (desktop/CI).
  Future<void> run(List<String> args) async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final session = await FFmpegKit.executeWithArguments(args);
      final code = await session.getReturnCode();
      if (!ReturnCode.isSuccess(code)) {
        final fail = await session.getFailStackTrace();
        final logs = await session.getAllLogsAsString();
        throw StateError(
          'FFmpeg 失败 (code=${code?.getValue()}): ${fail ?? logs ?? 'unknown'}',
        );
      }
      return;
    }
    final bin = await _resolveSystemFfmpeg();
    final result = await Process.run(bin, args, runInShell: false);
    if (result.exitCode != 0) {
      throw StateError(
        'FFmpeg 失败 (${result.exitCode}): ${result.stderr}'.trim(),
      );
    }
  }

  Future<String> _resolveSystemFfmpeg() async {
    for (final c in ['ffmpeg', '/usr/bin/ffmpeg', '/usr/local/bin/ffmpeg']) {
      try {
        final r = await Process.run(c, ['-version']);
        if (r.exitCode == 0) return c;
      } catch (_) {}
    }
    throw StateError('未找到 ffmpeg，无法裁剪 CUE 曲目');
  }
}
