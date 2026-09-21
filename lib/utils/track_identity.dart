import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Identity of a library row is **`网盘名 + remote_path`**.
///
/// The URL, username and password deliberately do **not** participate: they live
/// only in the local WebDAV account table, so the cloud library and backups can
/// be moved to a different backing disk without rewriting anything. The disk
/// *name* is the single binding point, which is why renaming an account is
/// treated as "a different disk".

/// Legacy-ish composite key (playlists / UI maps).
String trackIdentityKey(String sourceName, String remotePath) {
  return '$sourceName\u0000$remotePath';
}

/// Normalize remote paths so music_id stays stable across slash variants.
String normalizeRemotePath(String path) {
  var out = path.trim().replaceAll('\\', '/');
  if (out.isEmpty) return '/';
  if (!out.startsWith('/')) out = '/$out';
  while (out.contains('//')) {
    out = out.replaceAll('//', '/');
  }
  return out;
}

/// Normalize a disk name so trailing spaces / inner runs don't split identity.
String normalizeSourceName(String name) {
  return name.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Stable offline music_id for a normal (non-CUE-slice) track.
/// `hash(网盘名 + normalized remotePath)` — NOT a content hash of audio bytes.
String musicIdForRemote(String sourceName, String remotePath) {
  final key =
      '${normalizeSourceName(sourceName)}\u0000${normalizeRemotePath(remotePath)}';
  return sha1.convert(utf8.encode(key)).toString();
}

/// Stable offline music_id for a CUE virtual slice.
/// `hash(网盘名 + cuePath + trackIndex)`.
String musicIdForCueSlice(
  String sourceName,
  String cueRemotePath,
  int trackIndex,
) {
  final key =
      '${normalizeSourceName(sourceName)}\u0000'
      '${normalizeRemotePath(cueRemotePath)}\u0000$trackIndex';
  return sha1.convert(utf8.encode(key)).toString();
}

/// Cue album identity: `hash("cue" + 网盘名 + cuePath)`.
String cueIdFor(String sourceName, String cueRemotePath) {
  final key =
      'cue\u0000${normalizeSourceName(sourceName)}\u0000'
      '${normalizeRemotePath(cueRemotePath)}';
  return sha1.convert(utf8.encode(key)).toString();
}

/// Resolve music_id for a library row (normal or CUE slice).
String musicIdForLibraryRow({
  required String sourceName,
  required String remotePath,
  String? cueRemotePath,
  int? cueTrackIndex,
}) {
  if (cueTrackIndex != null &&
      cueRemotePath != null &&
      cueRemotePath.isNotEmpty) {
    return musicIdForCueSlice(sourceName, cueRemotePath, cueTrackIndex);
  }
  return musicIdForRemote(sourceName, remotePath);
}

/// Stable short stem for cache / cover file names (first 16 of music_id).
String identityHashStem(String sourceName, String remotePath) {
  return musicIdForRemote(sourceName, remotePath).substring(0, 16);
}

const String cueVirtualMarker = '#cue:';

String cueVirtualRemotePath(String audioRemotePath, int cueTrackIndex) =>
    '$audioRemotePath$cueVirtualMarker$cueTrackIndex';

bool isCueVirtualRemotePath(String remotePath) =>
    remotePath.contains(cueVirtualMarker);

({String audioRemotePath, int cueTrackIndex})? parseCueVirtualRemotePath(
  String remotePath,
) {
  final i = remotePath.lastIndexOf(cueVirtualMarker);
  if (i < 0) return null;
  final audio = remotePath.substring(0, i);
  final idx = int.tryParse(remotePath.substring(i + cueVirtualMarker.length));
  if (audio.isEmpty || idx == null || idx < 1) return null;
  return (audioRemotePath: audio, cueTrackIndex: idx);
}

String cueCacheGroupId(String sourceName, String cueRemotePath) =>
    'cue\u0000${normalizeSourceName(sourceName)}\u0000'
    '${normalizeRemotePath(cueRemotePath)}';
