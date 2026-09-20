/// Unique binding between a network disk account and a remote path.
String trackIdentityKey(String accountId, String remotePath) {
  return '$accountId\u0000$remotePath';
}

String identityHashStem(String accountId, String remotePath) {
  return trackIdentityKey(accountId, remotePath).hashCode.toRadixString(16);
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
    'cue\u0000$accountId\u0000$cueRemotePath';
