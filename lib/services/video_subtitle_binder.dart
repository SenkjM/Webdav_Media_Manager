import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/webdav_item.dart';
import '../utils/subtitle_encoding.dart';
import '../utils/subtitle_sidecar.dart';

/// A subtitle the user imported for the current episode only.
class ManualSubtitle {
  const ManualSubtitle({
    required this.fileName,
    required this.format,
    required this.bytes,
  });

  final String fileName;
  final String format;
  final List<int> bytes;

  String get id => 'manual';

  SubtitleRowLabel get label =>
      labelManualSubtitle(fileName: fileName, format: format);
}

/// Loads external text sidecars and applies [Player.setSubtitleTrack] after
/// the screen has opened the episode. Manual import and the encoding override
/// are memory only: import dies with the episode, encoding lasts until the
/// player route is disposed.
class VideoSubtitleBinder {
  VideoSubtitleBinder({
    required this.listDirectory,
    required this.readBytes,
    required this.setTrack,
    required this.onChanged,
    this.onError,
  });

  final Future<List<WebDavItem>> Function(String directory) listDirectory;
  final Future<List<int>> Function(String remotePath) readBytes;
  final Future<void> Function(SubtitleTrack track) setTrack;
  final void Function() onChanged;
  final void Function(String code)? onError;

  int epoch = 0;
  ManualSubtitle? manual;
  SubtitleEncodingChoice encoding = SubtitleEncodingChoice.auto;
  List<SidecarHit> sidecars = const [];
  List<EmbeddedSubtitleCue> embedded = const [];
  bool tracksReady = false;
  bool sidecarsReady = false;
  bool userPicked = false;
  String uiLanguageKey = '';

  final Map<String, SubtitleTrack> _embeddedTracks = {};
  final Map<String, List<int>> _bytesCache = {};
  String? _appliedKey;
  Directory? _tempDir;
  final List<File> _tempFiles = [];

  /// Drop the previous episode's manual import and start a new selection.
  /// Encoding override is kept for this player session.
  void prepareEpisode({required String uiLanguageKey}) {
    epoch++;
    manual = null;
    userPicked = false;
    _appliedKey = null;
    sidecars = const [];
    embedded = const [];
    _embeddedTracks.clear();
    tracksReady = false;
    sidecarsReady = false;
    this.uiLanguageKey = uiLanguageKey;
    onChanged();
  }

  Future<void> scan({
    required WebDavItem video,
    required List<WebDavItem>? knownSameDirectory,
    required bool sameDirEnabled,
    required bool subdirEnabled,
    required String subdirName,
    required Set<String> videoExtensions,
  }) async {
    final token = epoch;
    if (!sameDirEnabled) {
      if (token != epoch) return;
      sidecarsReady = true;
      onChanged();
      await _applyAuto(token);
      return;
    }
    try {
      final parent = videoParentDirectory(video.path);
      final listing = knownSameDirectory ?? await listDirectory(parent);
      if (token != epoch) return;
      final hits = collectSidecars(
        videoFileName: video.name,
        sameDirectory: listing,
        videoExtensions: videoExtensions,
      );
      final folder = sanitizeSubtitleSubdir(subdirName);
      if (subdirEnabled && folder != null && folder.isNotEmpty) {
        var subItems = const <WebDavItem>[];
        try {
          final subPath = parent == '/' ? '/$folder' : '$parent/$folder';
          subItems = await listDirectory(subPath);
        } catch (_) {
          subItems = const [];
        }
        if (token != epoch) return;
        hits.addAll(
          collectSidecars(
            videoFileName: video.name,
            sameDirectory: const [],
            subdirectory: subItems,
            subdirectoryName: folder,
            videoExtensions: videoExtensions,
          ),
        );
      }
      final kept = await _withoutBinarySubs(hits, token);
      if (token != epoch) return;
      sidecars = kept;
    } catch (_) {
      if (token != epoch) return;
      sidecars = const [];
    }
    sidecarsReady = true;
    onChanged();
    await _applyAuto(token);
  }

  void onTracks(List<SubtitleTrack> tracks) {
    final token = epoch;
    final cues = <EmbeddedSubtitleCue>[];
    _embeddedTracks.clear();
    for (final track in tracks) {
      final cue = embeddedCueFromTrack(
        id: track.id,
        language: track.language,
        title: track.title,
        codec: track.codec,
        isDefault: track.isDefault ?? false,
        external: track.uri || track.data,
      );
      if (cue == null) continue;
      cues.add(cue);
      _embeddedTracks[cue.id] = track;
    }
    embedded = cues;
    tracksReady = true;
    onChanged();
    if (!userPicked) {
      unawaited(_applyAuto(token));
    }
  }

  Future<void> selectNone() => _applyNone(epoch, user: true);

  Future<void> selectEmbedded(String id) async {
    final cue = embedded.cast<EmbeddedSubtitleCue?>().firstWhere(
      (c) => c!.id == id,
      orElse: () => null,
    );
    if (cue == null) return;
    await _applyEmbedded(cue, epoch, user: true);
  }

  Future<void> selectSidecar(String path) async {
    final hit = _hit(path);
    if (hit == null) return;
    await _applySidecar(hit, epoch, user: true);
  }

  Future<void> selectManual() async {
    final current = manual;
    if (current == null) return;
    await _applyManual(epoch, user: true);
  }

  Future<bool> importBytes({
    required String fileName,
    required List<int> bytes,
  }) async {
    final format = _formatOf(fileName);
    if (format == null) {
      onError?.call('unsupported');
      return false;
    }
    if (format == 'sub' && looksLikeBinarySubtitle(bytes)) {
      onError?.call('binary');
      return false;
    }
    final decoded = decodeSubtitleBytes(
      bytes,
      override: encoding == SubtitleEncodingChoice.auto ? null : encoding,
    );
    if (decoded == null) {
      onError?.call(looksLikeBinarySubtitle(bytes) ? 'binary' : 'decode');
      return false;
    }
    manual = ManualSubtitle(fileName: fileName, format: format, bytes: bytes);
    onChanged();
    await _applyManual(epoch, user: true);
    return true;
  }

  Future<void> setEncoding(SubtitleEncodingChoice choice) async {
    encoding = choice;
    onChanged();
    final key = _appliedKey;
    if (key == null) return;
    if (key.startsWith('side:')) {
      final path = _pathFromSideKey(key);
      final hit = path == null ? null : _hit(path);
      if (hit != null) await _applySidecar(hit, epoch, user: true);
    } else if (key.startsWith('manual:')) {
      await _applyManual(epoch, user: true);
    }
  }

  Future<void> dispose() async {
    epoch++;
    for (final file in _tempFiles) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    _tempFiles.clear();
  }

  String _sideKey(String path) => 'side:$path:${encoding.wireName}';

  /// Path is the middle of `side:<path>:<encoding>`. Encoding names are a
  /// closed set, so a colon inside the path is kept.
  String? _pathFromSideKey(String key) {
    const prefix = 'side:';
    if (!key.startsWith(prefix)) return null;
    final body = key.substring(prefix.length);
    for (final choice in SubtitleEncodingChoice.values) {
      final suffix = ':${choice.wireName}';
      if (body.endsWith(suffix) && body.length > suffix.length) {
        return body.substring(0, body.length - suffix.length);
      }
    }
    return body.isEmpty ? null : body;
  }

  SidecarHit? _hit(String path) {
    for (final hit in sidecars) {
      if (hit.path == path) return hit;
    }
    return null;
  }

  Future<void> _applyAuto(int token) async {
    if (token != epoch || userPicked) return;
    if (manual != null) {
      await _applyManual(token, user: false);
      return;
    }
    if (!tracksReady) return;
    final emb = pickEmbedded(embedded, uiLanguageKey);
    if (emb != null) {
      await _applyEmbedded(emb, token, user: false);
      return;
    }
    if (!sidecarsReady) return;
    final side = pickSidecar(sidecars, uiLanguageKey);
    if (side != null) {
      await _applySidecar(side, token, user: false);
      return;
    }
    await _applyNone(token, user: false);
  }

  Future<void> _applyNone(int token, {required bool user}) async {
    if (token != epoch) return;
    if (user) userPicked = true;
    const key = 'none';
    if (_appliedKey == key) {
      onChanged();
      return;
    }
    _appliedKey = key;
    try {
      await setTrack(SubtitleTrack.no());
    } catch (_) {
      _appliedKey = null;
      onError?.call('load');
    }
    if (token == epoch) onChanged();
  }

  Future<void> _applyEmbedded(
    EmbeddedSubtitleCue cue,
    int token, {
    required bool user,
  }) async {
    if (token != epoch) return;
    if (user) userPicked = true;
    final key = 'emb:${cue.id}';
    if (_appliedKey == key) {
      onChanged();
      return;
    }
    final track = _embeddedTracks[cue.id];
    if (track == null) return;
    _appliedKey = key;
    try {
      await setTrack(track);
    } catch (_) {
      _appliedKey = null;
      onError?.call('load');
    }
    if (token == epoch) onChanged();
  }

  Future<void> _applySidecar(
    SidecarHit hit,
    int token, {
    required bool user,
  }) async {
    if (token != epoch) return;
    if (user) userPicked = true;
    final key = _sideKey(hit.path);
    _appliedKey = key;
    try {
      final bytes = _bytesCache[hit.path] ?? await readBytes(hit.path);
      if (token != epoch) return;
      if (hit.format == 'sub' && looksLikeBinarySubtitle(bytes)) {
        sidecars = [
          for (final item in sidecars)
            if (item.path != hit.path) item,
        ];
        _appliedKey = null;
        onError?.call('binary');
        onChanged();
        if (!user) await _applyAuto(token);
        return;
      }
      _bytesCache[hit.path] = bytes;
      final file = await _materialize(bytes, hit.format, hit.path);
      if (token != epoch || file == null) {
        if (file == null && token == epoch) {
          _appliedKey = null;
          onError?.call('decode');
          onChanged();
        }
        return;
      }
      await setTrack(
        SubtitleTrack.uri(
          file.uri.toString(),
          title: hit.name,
          language: hit.languageKey.isEmpty ? null : hit.languageKey,
        ),
      );
    } catch (_) {
      if (token == epoch && _appliedKey == key) {
        _appliedKey = null;
        onError?.call('load');
      }
    }
    if (token == epoch) onChanged();
  }

  Future<void> _applyManual(int token, {required bool user}) async {
    final current = manual;
    if (current == null || token != epoch) return;
    if (user) userPicked = true;
    final key = 'manual:${encoding.wireName}';
    _appliedKey = key;
    try {
      final file = await _materialize(
        current.bytes,
        current.format,
        current.fileName,
      );
      if (token != epoch || file == null) {
        if (file == null && token == epoch) {
          _appliedKey = null;
          onError?.call('decode');
          onChanged();
        }
        return;
      }
      await setTrack(
        SubtitleTrack.uri(
          file.uri.toString(),
          title: current.fileName,
          language: null,
        ),
      );
    } catch (_) {
      if (token == epoch && _appliedKey == key) {
        _appliedKey = null;
        onError?.call('load');
      }
    }
    if (token == epoch) onChanged();
  }

  Future<List<SidecarHit>> _withoutBinarySubs(
    List<SidecarHit> hits,
    int token,
  ) async {
    final kept = <SidecarHit>[];
    for (final hit in hits) {
      if (token != epoch) return kept;
      if (hit.format != 'sub') {
        kept.add(hit);
        continue;
      }
      if (hit.size != null && hit.size! > 8 * 1024 * 1024) continue;
      try {
        final bytes = await readBytes(hit.path);
        if (token != epoch) return kept;
        if (!subtitlePayloadIsText(bytes, 'sub')) continue;
        _bytesCache[hit.path] = bytes;
        kept.add(hit);
      } catch (_) {
        // Unreadable sidecar stays out of the list.
      }
    }
    return kept;
  }

  Future<File?> _materialize(
    List<int> bytes,
    String extension,
    String identity,
  ) async {
    final decoded = decodeSubtitleBytes(
      bytes,
      override: encoding == SubtitleEncodingChoice.auto ? null : encoding,
    );
    if (decoded == null) return null;
    final dir = await _ensureTemp();
    final safeExt = extension.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    final file = File(
      p.join(dir.path, '${epoch}_${identity.hashCode}.$safeExt'),
    );
    await file.writeAsBytes(utf8SubtitleBytes(decoded.text), flush: true);
    _tempFiles.add(file);
    return file;
  }

  Future<Directory> _ensureTemp() async {
    final existing = _tempDir;
    if (existing != null) return existing;
    final root = await getTemporaryDirectory();
    final dir = Directory(p.join(root.path, 'video_subtitles'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _tempDir = dir;
    return dir;
  }

  String? _formatOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return null;
    final ext = fileName.substring(dot + 1).toLowerCase();
    if (!subtitleSidecarExtensions.contains(ext)) return null;
    return ext;
  }

  String? get selectedKey {
    final key = _appliedKey;
    if (key == null) return null;
    if (key == 'none') return 'none';
    if (key.startsWith('emb:')) return key.substring(4);
    if (key.startsWith('side:')) return _pathFromSideKey(key);
    if (key.startsWith('manual:')) return 'manual';
    return null;
  }
}
