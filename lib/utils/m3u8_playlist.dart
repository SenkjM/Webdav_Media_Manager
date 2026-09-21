import '../models/playlist.dart';

/// Encode / decode playlist as extended M3U8 with WebDAV Music Player extensions.
///
/// Format notes:
/// - `#EXTM3U` header
/// - `#EXT-X-WMP-ID:<uuid>` playlist id
/// - `#EXT-X-WMP-UPDATED:<iso8601>` last-write timestamp
/// - `#EXT-X-WMP-NAME:<name>` display name
/// - `#EXTINF:<seconds>,<title>` then next line path
/// - Path line: `wmp://<accountId>/<remotePath>` (absolute remote path after account)
///
/// Sync policy: last-write-wins via `#EXT-X-WMP-UPDATED`.
class M3u8PlaylistCodec {
  static const idTag = '#EXT-X-WMP-ID:';
  static const updatedTag = '#EXT-X-WMP-UPDATED:';
  static const nameTag = '#EXT-X-WMP-NAME:';
  static const pathScheme = 'wmp://';

  static String encode(Playlist playlist) {
    final buf = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('$idTag${playlist.id}')
      ..writeln('$updatedTag${playlist.updatedAt.toUtc().toIso8601String()}')
      ..writeln('$nameTag${_escape(playlist.name)}');
    for (final e in playlist.entries) {
      final secs = e.durationMs != null ? (e.durationMs! / 1000).round() : -1;
      final title = _escape(e.title ?? e.remotePath.split('/').last);
      buf.writeln('#EXTINF:$secs,$title');
      buf.writeln('$pathScheme${e.sourceName}${e.remotePath.startsWith('/') ? '' : '/'}${e.remotePath}');
    }
    return buf.toString();
  }

  static Playlist decode(String text, {String? fallbackId, String? fallbackName}) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    String id = fallbackId ?? '';
    String name = fallbackName ?? '未命名';
    DateTime updatedAt = DateTime.now().toUtc();
    final entries = <PlaylistEntry>[];
    String? pendingTitle;
    int? pendingDurationMs;

    for (final line in lines) {
      if (line.startsWith(idTag)) {
        id = line.substring(idTag.length).trim();
      } else if (line.startsWith(updatedTag)) {
        updatedAt = DateTime.tryParse(line.substring(updatedTag.length).trim())
                ?.toUtc() ??
            updatedAt;
      } else if (line.startsWith(nameTag)) {
        name = _unescape(line.substring(nameTag.length).trim());
      } else if (line.startsWith('#EXTINF:')) {
        final body = line.substring('#EXTINF:'.length);
        final comma = body.indexOf(',');
        if (comma >= 0) {
          final sec = int.tryParse(body.substring(0, comma).trim());
          pendingDurationMs = sec != null && sec >= 0 ? sec * 1000 : null;
          pendingTitle = _unescape(body.substring(comma + 1).trim());
        }
      } else if (line.startsWith('#')) {
        continue;
      } else {
        final parsed = parsePathLine(line);
        if (parsed != null) {
          entries.add(PlaylistEntry(
            sourceName: parsed.$1,
            remotePath: parsed.$2,
            title: pendingTitle,
            durationMs: pendingDurationMs,
          ));
        }
        pendingTitle = null;
        pendingDurationMs = null;
      }
    }

    if (id.isEmpty) {
      id = fallbackId ?? 'imported-${updatedAt.millisecondsSinceEpoch}';
    }

    return Playlist(
      id: id,
      name: name,
      entries: entries,
      updatedAt: updatedAt,
    );
  }

  /// Parse `wmp://accountId/remote/path` or plain `/remote/path` (account empty).
  static (String, String)? parsePathLine(String line) {
    if (line.startsWith(pathScheme)) {
      final rest = line.substring(pathScheme.length);
      final slash = rest.indexOf('/');
      if (slash <= 0) return null;
      final accountId = rest.substring(0, slash);
      var remotePath = rest.substring(slash);
      if (!remotePath.startsWith('/')) remotePath = '/$remotePath';
      return (accountId, remotePath);
    }
    if (line.startsWith('/')) {
      return ('', line);
    }
    return null;
  }

  static String safeFileName(String name, String id) {
    final base = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    final stem = base.isEmpty ? 'playlist' : base;
    final shortId = id.length > 8 ? id.substring(0, 8) : id;
    return '${stem}_$shortId.m3u8';
  }

  static String _escape(String s) => s.replaceAll('\n', ' ').replaceAll('\r', '');
  static String _unescape(String s) => s;
}
