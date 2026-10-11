/// Prefer an external `.lrc` body when present; otherwise use embedded lyrics.
///
/// The app does not yet fetch sidecar LRC over WebDAV; callers may pass null
/// for [sidecarLrc] until that path exists. Empty / whitespace-only strings
/// are treated as missing.
String? resolveLyrics({String? sidecarLrc, String? embedded}) {
  final side = sidecarLrc?.trim();
  if (side != null && side.isNotEmpty) return side;
  final emb = embedded?.trim();
  if (emb != null && emb.isNotEmpty) return emb;
  return null;
}

/// One timed lyric line (`[mm:ss.xx]text`).
class LyricLine {
  const LyricLine({required this.at, required this.text});

  final Duration at;
  final String text;
}

final _lrcLine = RegExp(
  r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\](.*)$',
);

/// Parse LRC-style timestamps. Returns null when no timed lines are found
/// (caller should show the raw text as a static scroll).
List<LyricLine>? parseTimedLyrics(String raw) {
  final lines = <LyricLine>[];
  for (final line in raw.split('\n')) {
    final trimmed = line.trimRight();
    if (trimmed.isEmpty) continue;
    final match = _lrcLine.firstMatch(trimmed);
    if (match == null) continue;
    final min = int.tryParse(match.group(1)!) ?? 0;
    final sec = int.tryParse(match.group(2)!) ?? 0;
    final fracRaw = match.group(3);
    var ms = 0;
    if (fracRaw != null && fracRaw.isNotEmpty) {
      final padded = fracRaw.length >= 3
          ? fracRaw.substring(0, 3)
          : fracRaw.padRight(3, '0');
      ms = int.tryParse(padded) ?? 0;
    }
    final text = (match.group(4) ?? '').trim();
    lines.add(
      LyricLine(
        at: Duration(minutes: min, seconds: sec, milliseconds: ms),
        text: text,
      ),
    );
  }
  if (lines.isEmpty) return null;
  lines.sort((a, b) => a.at.compareTo(b.at));
  return lines;
}

/// Index of the last line whose timestamp is <= [position], or -1.
int lyricIndexAt(List<LyricLine> lines, Duration position) {
  if (lines.isEmpty) return -1;
  var lo = 0;
  var hi = lines.length - 1;
  var best = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].at <= position) {
      best = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return best;
}
