import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Unique binding between a network disk account and a remote path
/// (legacy / playlist key — not the stable [musicId]).
String trackIdentityKey(String accountId, String remotePath) {
  return '$accountId\u0000$remotePath';
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

/// Stable offline music_id for a normal (non-CUE-slice) track.
/// `hash(accountId + normalized remotePath)` — NOT a content hash of audio bytes.
String musicIdForRemote(String accountId, String remotePath) {
  final key = '$accountId\u0000${normalizeRemotePath(remotePath)}';
  return sha1.convert(utf8.encode(key)).toString();
}

/// Stable offline music_id for a CUE virtual slice.
/// `hash(accountId + cuePath + trackIndex)`.
String musicIdForCueSlice(
  String accountId,
  String cueRemotePath,
  int trackIndex,
) {
  final key =
      '$accountId\u0000${normalizeRemotePath(cueRemotePath)}\u0000$trackIndex';
  return sha1.convert(utf8.encode(key)).toString();
}

/// Cue album identity: `hash("cue" + accountId + cuePath)`.
String cueIdFor(String accountId, String cueRemotePath) {
  final key = 'cue\u0000$accountId\u0000${normalizeRemotePath(cueRemotePath)}';
  return sha1.convert(utf8.encode(key)).toString();
}

/// Resolve music_id for a library row (normal or CUE slice).
String musicIdForLibraryRow({
  required String accountId,
  required String remotePath,
  String? cueRemotePath,
  int? cueTrackIndex,
}) {
  if (cueTrackIndex != null &&
      cueRemotePath != null &&
      cueRemotePath.isNotEmpty) {
    return musicIdForCueSlice(accountId, cueRemotePath, cueTrackIndex);
  }
  return musicIdForRemote(accountId, remotePath);
}

/// Stable short stem for cache / cover file names (first 16 of music_id).
String identityHashStem(String accountId, String remotePath) {
  return musicIdForRemote(accountId, remotePath).substring(0, 16);
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

String cueCacheGroupId(String accountId, String cueRemotePath) =>
    'cue\u0000$accountId\u0000${normalizeRemotePath(cueRemotePath)}';
