import 'dart:typed_data';

import '../models/playlist.dart';
import '../models/playlist_sentinels.dart';
import '../utils/wmp_container.dart';

/// A decoded `WDMMPL01` document: the [playlist] plus each entry's own cover
/// bytes.
///
/// Covers are kept **one copy per entry** — no interning, no sharing — and are
/// addressed by *entry index*, never by identity, so two entries that happen to
/// reference the same track still get their own blobs. [coverFor] returns null
/// for an entry that had no cover, which is a normal state, not an error.
class DecodedPlaylist {
  DecodedPlaylist({
    required this.playlist,
    required this.deviceId,
    required this.createdAt,
    required List<WmpCoverEntry> covers,
    required Uint8List coverSection,
    required Map<int, int?> coverIndexByEntry,
  }) : _covers = covers,
       _coverSection = coverSection,
       _coverIndexByEntry = coverIndexByEntry;

  final Playlist playlist;
  final String deviceId;
  final String createdAt;

  final List<WmpCoverEntry> _covers;
  final Uint8List _coverSection;
  final Map<int, int?> _coverIndexByEntry;

  int get entryCount => playlist.entries.length;
  int get coverCount => _covers.length;

  /// The cover bytes of entry [entryIndex], or null when it has none.
  Uint8List? coverFor(int entryIndex) {
    final idx = _coverIndexByEntry[entryIndex];
    if (idx == null || idx < 0 || idx >= _covers.length) return null;
    return _covers[idx].bytesIn(_coverSection);
  }

  /// Image kind of that entry's cover, or [WmpImageKind.none].
  int coverKindFor(int entryIndex) {
    final idx = _coverIndexByEntry[entryIndex];
    if (idx == null || idx < 0 || idx >= _covers.length) {
      return WmpImageKind.none;
    }
    return _covers[idx].kind;
  }
}

/// Codec for a single playlist document (`WDMMPL01`, one file per playlist,
/// synced to `/Playlists/*.wdmp`).
///
/// Layout (docs/10 §4.2):
/// * `META` — [WmpMeta.kind] / [WmpMeta.count] / [WmpMeta.deviceId] /
///   [WmpMeta.createdAt] plus the playlist-only string tags
///   [WmpPlaylistMeta.playlistId] / [WmpPlaylistMeta.name] /
///   [WmpPlaylistMeta.updatedAt].
/// * `ENTRIES` — one tag/value record per entry. The rows are **references**
///   (identity + display fields), never copies of the library row: the track
///   itself lives in the music library, which is why this section is not
///   `TRACKS` and why destroying a library row must not destroy the entry.
///
/// There is no legacy read path — `.m3u`/`.m3u8` files are not parsed here.
class PlaylistCodec {
  PlaylistCodec._();

  /// File extension of a playlist document.
  static const String fileExtension = 'wdmp';

  /// Magic code of a playlist document (`WDMMPL01`).
  static const String magicKind = WmpFileKind.playlist;

  static Map<int, Object?> entryToRecord(
    PlaylistEntry entry, {
    int? coverIndex,
  }) => {
    WmpPlaylistEntry.musicId: entry.identityKey,
    WmpPlaylistEntry.sourceName: entry.sourceName,
    WmpPlaylistEntry.remotePath: entry.remotePath,
    WmpPlaylistEntry.title: entry.title,
    WmpPlaylistEntry.durationMs: entry.durationMs,
    WmpPlaylistEntry.cueTrackIndex: entry.cueTrackIndex,
    WmpPlaylistEntry.coverIndex: coverIndex,
  };

  static PlaylistEntry recordToEntry(Map<int, Object?> record) {
    String? str(int tag) {
      final v = record[tag];
      return v is String && v.isNotEmpty ? v : null;
    }

    int? num_(int tag) {
      final v = record[tag];
      return v is int ? v : null;
    }

    return PlaylistEntry(
      sourceName: str(WmpPlaylistEntry.sourceName) ?? '',
      remotePath: str(WmpPlaylistEntry.remotePath) ?? '',
      musicId: str(WmpPlaylistEntry.musicId),
      title: str(WmpPlaylistEntry.title),
      durationMs: num_(WmpPlaylistEntry.durationMs),
      cueTrackIndex: num_(WmpPlaylistEntry.cueTrackIndex),
    );
  }

  /// Encode one playlist into a self-contained `WDMMPL01` document.
  ///
  /// [coverBlobs] is parallel to the playlist's entries: element `i` is that
  /// entry's own cover bytes, or null for "no cover". Nothing is deduplicated —
  /// two entries of the same album each carry their own copy, matching the
  /// container's per-row cover rule. The blobs are written into a raw (never
  /// re-deflated) `COVERS` section, because images are already compressed.
  static Uint8List encode(
    Playlist playlist, {
    String deviceId = '',
    List<Uint8List?>? coverBlobs,
    List<int>? coverKinds,
  }) {
    final records = <Map<int, Object?>>[];
    final covers = <({Uint8List bytes, int kind})>[];
    for (var i = 0; i < playlist.entries.length; i++) {
      final blob = coverBlobs != null && i < coverBlobs.length
          ? coverBlobs[i]
          : null;
      int? coverIndex;
      if (blob != null && blob.isNotEmpty) {
        coverIndex = covers.length;
        final declared = coverKinds != null && i < coverKinds.length
            ? coverKinds[i]
            : WmpImageKind.none;
        covers.add((
          bytes: blob,
          kind: declared == WmpImageKind.none
              ? WmpImageKind.detect(blob)
              : declared,
        ));
      }
      records.add(entryToRecord(playlist.entries[i], coverIndex: coverIndex));
    }
    return _encode(
      sections: {
        WmpSections.meta: _metaBytes(
          playlist: playlist,
          deviceId: deviceId,
          entryCount: records.length,
        ),
        WmpSections.entries: encodeRecords(records),
        if (covers.isNotEmpty) WmpSections.covers: buildCoverSection(covers),
      },
      rawIds: {WmpSections.covers},
    );
  }

  /// Decode a `WDMMPL01` document.
  ///
  /// Throws [WmpFormatException] when the magic and `META.kind` disagree, or
  /// when the document carries no playlist id.
  static DecodedPlaylist decode(Uint8List bytes) {
    final container = WmpContainer.fromBytes(bytes);
    final metaRaw = container.readSection(WmpSections.meta);
    final meta = metaRaw == null
        ? const <int, Object?>{}
        : (decodeRecords(metaRaw, intTags: kMetaIntTags).firstOrNull ??
              const <int, Object?>{});

    final kind = (meta[WmpMeta.kind] as int?) ?? -1;
    // Magic and META must both say "playlist". A deletion pack is a different
    // kind even when it reuses playlist id tags, so it must not decode as one.
    if (container.kind != WmpFileKind.playlist || kind != WmpKind.playlist) {
      throw WmpFormatException(
        'err.playlistKindMismatch|${container.kind}|$kind',
      );
    }

    final id = (meta[WmpPlaylistMeta.playlistId] as String?) ?? '';
    if (id.isEmpty) {
      throw const WmpFormatException('err.playlistMissingId');
    }

    final coversRaw = container.readSection(WmpSections.covers);
    final covers = coversRaw == null
        ? <WmpCoverEntry>[]
        : parseCoverSection(coversRaw);

    final raw = container.readSection(WmpSections.entries);
    final records = raw == null
        ? const <Map<int, Object?>>[]
        : decodeRecords(raw, intTags: kPlaylistEntryIntTags);

    final coverIndexByEntry = <int, int?>{};
    final entries = <PlaylistEntry>[];
    for (var i = 0; i < records.length; i++) {
      final idx = records[i][WmpPlaylistEntry.coverIndex];
      coverIndexByEntry[i] = idx is int ? idx : null;
      entries.add(recordToEntry(records[i]));
    }

    return DecodedPlaylist(
      playlist: Playlist(
        id: id,
        name: (meta[WmpPlaylistMeta.name] as String?) ?? kUnnamedPlaylistName,
        entries: entries,
        updatedAt:
            DateTime.tryParse(
              (meta[WmpPlaylistMeta.updatedAt] as String?) ?? '',
            )?.toUtc() ??
            DateTime.now().toUtc(),
      ),
      deviceId: (meta[WmpMeta.deviceId] as String?) ?? '',
      createdAt: (meta[WmpMeta.createdAt] as String?) ?? '',
      covers: covers,
      coverSection: coversRaw ?? Uint8List(0),
      coverIndexByEntry: coverIndexByEntry,
    );
  }

  /// Remote file name for a playlist mirror: `name_shortId.wdmp`.
  ///
  /// The name is cosmetic; identity travels inside the document. Sanitising
  /// keeps the name safe for every WebDAV server we might be talking to.
  static String safeFileName(String name, String id) {
    // 先 trim 再折叠空白：否则全是空白的名字会先变成 "_"，永远走不到下面的
    // 兜底分支。
    final sanitized = name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    final stem = sanitized.isEmpty ? 'playlist' : sanitized;
    final shortId = id.length > 8 ? id.substring(0, 8) : id;
    return '${stem}_$shortId.$fileExtension';
  }

  static Uint8List _metaBytes({
    required Playlist playlist,
    required String deviceId,
    required int entryCount,
  }) {
    return encodeRecords([
      {
        WmpMeta.kind: WmpKind.playlist,
        WmpMeta.count: entryCount,
        WmpMeta.deviceId: deviceId,
        WmpMeta.createdAt: DateTime.now().toUtc().toIso8601String(),
        WmpPlaylistMeta.playlistId: playlist.id,
        WmpPlaylistMeta.name: playlist.name,
        WmpPlaylistMeta.updatedAt: playlist.updatedAt.toUtc().toIso8601String(),
      },
    ]);
  }

  static Uint8List _encode({
    required Map<int, Uint8List> sections,
    Set<int> rawIds = const {},
  }) {
    // The META kind is the single source of truth; the magic is derived from it
    // so the two can never drift.
    final kind =
        (decodeRecords(
              sections[WmpSections.meta]!,
              intTags: kMetaIntTags,
            ).firstOrNull?[WmpMeta.kind]
            as int?) ??
        WmpKind.playlist;
    return WmpContainer.encode(
      sections,
      kind: WmpFileKind.forMetaKind(kind),
      rawIds: rawIds,
    );
  }
}
