import 'package:path/path.dart' as p;

import '../models/library_track.dart';
import '../models/webdav_item.dart';
import 'settings_service.dart';
import 'tag_service.dart';

/// Builds the file name used when sharing a cached audio file.
///
/// The user can pick a template in Settings (default `作者-标题`, i.e.
/// `{artist}-{title}`); the original file extension is always preserved.
class ShareRenameService {
  const ShareRenameService({TagService? tags}) : _tags = tags;

  final TagService? _tags;

  /// Placeholders accepted in a rename pattern.
  static const List<String> placeholders = [
    '{artist}',
    '{title}',
    '{album}',
    '{albumArtist}',
    '{track}',
    '{year}',
    '{genre}',
    '{fileName}',
  ];

  static const Map<String, String> placeholderLabels = {
    '{artist}': '作者',
    '{title}': '标题',
    '{album}': '专辑',
    '{albumArtist}': '专辑作者',
    '{track}': '音轨号',
    '{year}': '年份',
    '{genre}': '流派',
    '{fileName}': '原文件名',
  };

  /// Render [pattern] for [track]. Empty placeholders collapse; unknown
  /// placeholders are kept verbatim so the user sees their typo.
  static String render(String pattern, TrackInfo track, {String? albumArtist}) {
    final values = <String, String>{
      '{artist}': (track.artist ?? '').trim(),
      '{title}': (track.title ?? '').trim().isEmpty
          ? _stemOf(track.fileName)
          : track.title!.trim(),
      '{album}': (track.album ?? '').trim(),
      '{albumArtist}': (albumArtist ?? track.albumArtist ?? '').trim(),
      '{track}': track.trackNumber?.toString() ?? '',
      '{year}': track.year?.toString() ?? '',
      '{genre}': (track.genre ?? '').trim(),
      '{fileName}': _stemOf(track.fileName),
    };
    var out = pattern;
    for (final entry in values.entries) {
      out = out.replaceAll(entry.key, entry.value);
    }
    return _tidy(out, fallback: _stemOf(track.fileName));
  }

  /// Default name for a cached file that has not been indexed into the library.
  ///
  /// Reads tags straight from [localPath] so sharing from the download queue
  /// works before the library ingest finished.
  Future<String> suggestedNameForFile({
    required String localPath,
    String? fileName,
    SettingsService? settings,
  }) async {
    final source = fileName ?? p.basename(localPath);
    final pattern = settings?.shareTagRenamePattern ??
        SettingsService.defaultShareTagRenamePattern;
    final tags = _tags;
    if (tags == null) return _withExtension(_stemOf(source), source);
    try {
      final read = await tags.readFromFile(localPath);
      final track = TrackInfo(
        sourceName: '',
        remotePath: localPath,
        fileName: source,
        title: read.title,
        artist: read.artist,
        albumArtist: read.albumArtist,
        album: read.album,
        trackNumber: read.trackNumber,
        year: read.year,
        genre: read.genre,
      );
      return _withExtension(render(pattern, track), source);
    } catch (_) {
      return _withExtension(_stemOf(source), source);
    }
  }

  /// Suggested name for an already-indexed library track.
  static String suggestedNameForTrack(
    TrackInfo track,
    SettingsService settings,
  ) {
    final pattern = settings.shareTagRenamePattern;
    return _withExtension(render(pattern, track), track.fileName);
  }

  /// Adapt a library row into the [TrackInfo] shape the templates read from.
  static TrackInfo trackInfoForLibrary(
    LibraryTrack track, {
    String? localPath,
  }) {
    return TrackInfo(
      sourceName: track.sourceName,
      remotePath: track.remotePath,
      fileName: track.fileName,
      localPath: localPath,
      title: track.title,
      artist: track.artist,
      albumArtist: track.albumArtist,
      album: track.album,
      duration: track.durationMs != null
          ? Duration(milliseconds: track.durationMs!)
          : null,
      trackNumber: track.trackNumber,
      trackTotal: track.trackTotal,
      discNumber: track.discNumber,
      discTotal: track.discTotal,
      year: track.year,
      genre: track.genre,
      bitrate: track.bitrate,
      sampleRate: track.sampleRate,
      coverPath: track.coverPath,
      cueRemotePath: track.cueRemotePath,
      cueTrackIndex: track.cueTrackIndex,
      audioRemotePath: track.audioRemotePath,
      clipStart: track.clipStartMs != null
          ? Duration(milliseconds: track.clipStartMs!)
          : null,
      clipEnd: track.clipEndMs != null
          ? Duration(milliseconds: track.clipEndMs!)
          : null,
      cacheGroupId: track.cacheGroupId,
    );
  }

  /// Collapse whitespace/duplicate separators left behind by empty fields.
  static String _tidy(String raw, {required String fallback}) {
    var out = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Remove separators that ended up dangling (e.g. "-" from "a-{title}").
    out = out.replaceAll(RegExp(r'^[\s\-_.·]+'), '');
    out = out.replaceAll(RegExp(r'[\s\-_.·]+$'), '');
    out = out.replaceAll(RegExp(r'(\s*-\s*){2,}'), ' - ');
    out = out.replaceAll(RegExp(r'^[\s\-_.·]+'), '');
    out = out.replaceAll(RegExp(r'[\s\-_.·]+$'), '');
    if (out.isEmpty) return fallback;
    return out;
  }

  static String _stemOf(String fileName) {
    final base = p.basename(fileName);
    final stem = p.basenameWithoutExtension(base);
    return stem.trim().isEmpty ? base : stem.trim();
  }

  static String _withExtension(String stem, String originalFileName) {
    final ext = p.extension(originalFileName);
    return ext.isEmpty ? stem : '$stem$ext';
  }
}
