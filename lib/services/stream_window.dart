/// Pure window and sidecar-name rules for streaming audio.
///
/// Prefetch order is backward (tracks before the current one) first, then
/// forward. Indexes outside the queue are skipped. The ends do not wrap.
int? nextPrefetchIndex({
  required int current,
  required int length,
  required int backward,
  required int forward,
  required bool Function(int index) skip,
}) {
  if (length <= 0 || current < 0 || current >= length) return null;
  for (var delta = 1; delta <= backward; delta++) {
    final i = current - delta;
    if (i < 0) break;
    if (!skip(i)) return i;
  }
  for (var delta = 1; delta <= forward; delta++) {
    final i = current + delta;
    if (i >= length) break;
    if (!skip(i)) return i;
  }
  return null;
}

/// Where [path] should sit in [order] so the playlist stays in queue order.
int playlistInsertAt({
  required List<String> order,
  required List<String> queue,
  required String path,
}) {
  final target = queue.indexOf(path);
  if (target < 0) return order.length;
  var at = 0;
  for (final existing in order) {
    final index = queue.indexOf(existing);
    if (index >= 0 && index < target) at++;
  }
  return at;
}

String directoryOf(String remotePath) {
  final slash = remotePath.lastIndexOf('/');
  if (slash <= 0) return '/';
  final dir = remotePath.substring(0, slash);
  return dir.isEmpty ? '/' : dir;
}

String normDir(String path) {
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path.isEmpty ? '/' : path;
}

/// Split a settings string into unique base names, in the user's order.
List<String> parseSidecarNames(String raw) {
  final out = <String>[];
  final seen = <String>{};
  for (final part in raw.split(RegExp(r'[,，;\s]+'))) {
    var name = part.trim().replaceAll('\\', '').replaceAll('/', '');
    if (name.isEmpty) continue;
    final key = name.toLowerCase();
    if (!seen.add(key)) continue;
    out.add(name);
  }
  return out;
}

/// Image extensions considered for a same-directory cover, in pick order.
const List<String> sidecarImageExtensions = ['jpg', 'jpeg', 'png', 'webp'];

/// First same-directory image whose base name is in [configured] (then the
/// audio stem). When several extensions share that name, jpg wins, then
/// jpeg, png, webp. Other extensions are ignored.
String? matchSidecarCover(
  Iterable<String> fileNames,
  String audioFileName,
  String configured,
) {
  final byLower = <String, String>{};
  for (final name in fileNames) {
    byLower.putIfAbsent(name.toLowerCase(), () => name);
  }
  final bases = parseSidecarNames(configured);
  final dot = audioFileName.lastIndexOf('.');
  final stem = dot > 0 ? audioFileName.substring(0, dot) : audioFileName;
  if (stem.isNotEmpty &&
      !bases.any((base) => base.toLowerCase() == stem.toLowerCase())) {
    bases.add(stem);
  }
  for (final base in bases) {
    for (final ext in sidecarImageExtensions) {
      final hit = byLower['${base.toLowerCase()}.$ext'];
      if (hit != null) return hit;
    }
  }
  return null;
}
