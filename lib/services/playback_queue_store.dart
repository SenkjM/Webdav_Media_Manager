import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/play_open_mode.dart';
import '../models/playback_queue_source.dart';
import '../models/webdav_item.dart';

/// Persisted now-playing queue: identities + cursor only.
///
/// Metadata is deliberately **not** stored — it is re-resolved from the music
/// library on restore (library-first), so the queue never competes with the
/// library as a metadata source. The snapshot stays local: it is not part of
/// backups or cloud sync.
class PlaybackQueueSnapshot {
  const PlaybackQueueSnapshot({
    required this.entries,
    required this.index,
    required this.mode,
    this.source,
  });

  final List<TrackInfo> entries;
  final int index;
  final PlayOpenMode mode;
  final PlaybackQueueSource? source;
}

class PlaybackQueueStore {
  PlaybackQueueStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;

  static const String _fileName = 'playback_queue.json';
  static const int _formatVersion = 1;

  Future<File> _file() async {
    final dir = await _directoryProvider();
    return File(p.join(dir.path, _fileName));
  }

  Future<PlaybackQueueSnapshot?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      final map = Map<String, Object?>.from(raw);
      if ((map['version'] as num?)?.toInt() != _formatVersion) return null;
      final rawEntries = map['entries'];
      if (rawEntries is! List || rawEntries.isEmpty) return null;
      final entries = <TrackInfo>[];
      for (final e in rawEntries) {
        final entry = _entryFromJson(e);
        if (entry != null) entries.add(entry);
      }
      if (entries.isEmpty) return null;
      final modeKey = map['mode']?.toString();
      final mode = PlayOpenMode.values.firstWhere(
        (m) => m.name == modeKey,
        orElse: () => PlayOpenMode.cache,
      );
      final index = (map['index'] as num?)?.toInt() ?? 0;
      return PlaybackQueueSnapshot(
        entries: entries,
        index: index,
        mode: mode,
        source: PlaybackQueueSource.fromJson(map['source']),
      );
    } catch (_) {
      // A corrupt snapshot only costs one lost queue; never block startup.
      return null;
    }
  }

  Future<void> save(PlaybackQueueSnapshot snapshot) async {
    if (snapshot.entries.isEmpty) {
      await clear();
      return;
    }
    final payload = <String, Object?>{
      'version': _formatVersion,
      'index': snapshot.index,
      'mode': snapshot.mode.name,
      'source': snapshot.source?.toJson(),
      'entries': [for (final t in snapshot.entries) _entryToJson(t)],
    };
    try {
      final file = await _file();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(payload), flush: true);
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    } catch (_) {
      // Persistence is best-effort; playback must never fail because of it.
    }
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Map<String, Object?> _entryToJson(TrackInfo t) => {
    'sourceName': t.sourceName,
    'remotePath': t.remotePath,
    'fileName': t.fileName,
    'cueRemotePath': t.cueRemotePath,
    'cueTrackIndex': t.cueTrackIndex,
    'audioRemotePath': t.audioRemotePath,
    'clipStartMs': t.clipStart?.inMilliseconds,
    'clipEndMs': t.clipEnd?.inMilliseconds,
    'cacheGroupId': t.cacheGroupId,
  };

  static TrackInfo? _entryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final sourceName = map['sourceName']?.toString() ?? '';
    final remotePath = map['remotePath']?.toString() ?? '';
    if (sourceName.isEmpty || remotePath.isEmpty) return null;
    int? asInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v');
    return TrackInfo(
      sourceName: sourceName,
      remotePath: remotePath,
      fileName: map['fileName']?.toString() ?? p.basename(remotePath),
      cueRemotePath: map['cueRemotePath']?.toString(),
      cueTrackIndex: asInt(map['cueTrackIndex']),
      audioRemotePath: map['audioRemotePath']?.toString(),
      clipStart: asInt(map['clipStartMs']) == null
          ? null
          : Duration(milliseconds: asInt(map['clipStartMs'])!),
      clipEnd: asInt(map['clipEndMs']) == null
          ? null
          : Duration(milliseconds: asInt(map['clipEndMs'])!),
      cacheGroupId: map['cacheGroupId']?.toString(),
    );
  }
}
