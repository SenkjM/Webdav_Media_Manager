import 'dart:typed_data';

import '../models/library_track.dart';
import '../utils/wmp_container.dart';

/// One decoded library shard: rows plus each row's own cover bytes.
///
/// Covers are kept **one copy per track** — no interning, no sharing — matching
/// the storage rule. [coverFor] returns the blob for a row index, or null.
class DecodedLibraryShard {
  DecodedLibraryShard({
    required this.kind,
    required this.revFrom,
    required this.revTo,
    required this.deviceId,
    required this.createdAt,
    required this.tracks,
    required this.tombstones,
    required List<WmpCoverEntry> covers,
    required Uint8List coverSection,
    required Map<int, int?> coverIndexByTrack,
  }) : _covers = covers,
       _coverSection = coverSection,
       _coverIndexByTrack = coverIndexByTrack;

  final int kind;
  final int revFrom;
  final int revTo;
  final String deviceId;
  final String createdAt;

  /// Live rows (kind != [WmpKind.tomb]).
  final List<LibraryTrack> tracks;

  /// Deletion records (kind == [WmpKind.tomb]).
  final List<Map<String, dynamic>> tombstones;

  final List<WmpCoverEntry> _covers;
  final Uint8List _coverSection;
  final Map<int, int?> _coverIndexByTrack;

  int get trackCount => tracks.length;
  int get tombstoneCount => tombstones.length;
  int get coverCount => _covers.length;

  /// This row's own cover bytes (never another row's).
  Uint8List? coverFor(int trackIndex) {
    final idx = _coverIndexByTrack[trackIndex];
    if (idx == null || idx < 0 || idx >= _covers.length) return null;
    return _covers[idx].bytesIn(_coverSection);
  }

  int get coverKindForTrackIndex0 => 0;
}

/// Encode / decode a library shard in the binary container.
///
/// Layout: `META` + `TRACKS` (or `TOMBS`) + optional raw `COVERS`. Every track
/// record is self-contained (all tags inline); the cover table gives each row
/// its **own** blob, laid out contiguously so a single cover can be read by
/// offset without inflating the record block.
class LibraryShardCodec {
  LibraryShardCodec._();

  static Map<int, Object?> trackToRecord(
    LibraryTrack track, {
    int? coverIndex,
  }) {
    return {
      WmpTrack.sourceName: track.sourceName,
      WmpTrack.remotePath: track.remotePath,
      WmpTrack.fileName: track.fileName,
      WmpTrack.rev: track.rev ?? track.lastTagReadAt.millisecondsSinceEpoch,
      WmpTrack.title: track.title,
      WmpTrack.artist: track.artist,
      WmpTrack.albumArtist: track.albumArtist,
      WmpTrack.album: track.album,
      WmpTrack.durationMs: track.durationMs,
      WmpTrack.trackNumber: track.trackNumber,
      WmpTrack.trackTotal: track.trackTotal,
      WmpTrack.discNumber: track.discNumber,
      WmpTrack.discTotal: track.discTotal,
      WmpTrack.year: track.year,
      WmpTrack.genre: track.genre,
      WmpTrack.bitrate: track.bitrate,
      WmpTrack.sampleRate: track.sampleRate,
      WmpTrack.cueId: track.cueId,
      WmpTrack.cueRemotePath: track.cueRemotePath,
      WmpTrack.cueTrackIndex: track.cueTrackIndex,
      WmpTrack.audioMusicId: track.audioMusicId,
      WmpTrack.audioRemotePath: track.audioRemotePath,
      WmpTrack.clipStartMs: track.clipStartMs,
      WmpTrack.clipEndMs: track.clipEndMs,
      WmpTrack.cacheGroupId: track.cacheGroupId,
      WmpTrack.coverIndex: coverIndex,
      WmpTrack.lastDownloadedAt: track.lastDownloadedAt.toIso8601String(),
      WmpTrack.lastTagReadAt: track.lastTagReadAt.toIso8601String(),
    };
  }

  /// Rebuild a row. [coverPath] is resolved by the caller (it writes the blob
  /// into the local cover cache and passes the resulting path).
  static LibraryTrack recordToTrack(
    Map<int, Object?> record, {
    String? coverPath,
  }) {
    String? str(int tag) {
      final v = record[tag];
      return v is String && v.isNotEmpty ? v : null;
    }

    int? num_(int tag) {
      final v = record[tag];
      return v is int ? v : null;
    }

    final sourceName = str(WmpTrack.sourceName) ?? '';
    final remotePath = str(WmpTrack.remotePath) ?? '';
    final cueRemotePath = str(WmpTrack.cueRemotePath);
    final cueTrackIndex = num_(WmpTrack.cueTrackIndex);
    return LibraryTrack(
      sourceName: sourceName,
      remotePath: remotePath,
      fileName: str(WmpTrack.fileName) ?? remotePath.split('/').last,
      title: str(WmpTrack.title),
      artist: str(WmpTrack.artist),
      albumArtist: str(WmpTrack.albumArtist),
      album: str(WmpTrack.album),
      durationMs: num_(WmpTrack.durationMs),
      trackNumber: num_(WmpTrack.trackNumber),
      trackTotal: num_(WmpTrack.trackTotal),
      discNumber: num_(WmpTrack.discNumber),
      discTotal: num_(WmpTrack.discTotal),
      year: num_(WmpTrack.year),
      genre: str(WmpTrack.genre),
      bitrate: num_(WmpTrack.bitrate),
      sampleRate: num_(WmpTrack.sampleRate),
      coverPath: coverPath,
      cueId: str(WmpTrack.cueId),
      cueRemotePath: cueRemotePath,
      cueTrackIndex: cueTrackIndex,
      audioMusicId: str(WmpTrack.audioMusicId),
      audioRemotePath: str(WmpTrack.audioRemotePath),
      clipStartMs: num_(WmpTrack.clipStartMs),
      clipEndMs: num_(WmpTrack.clipEndMs),
      cacheGroupId: str(WmpTrack.cacheGroupId),
      rev: num_(WmpTrack.rev),
      lastDownloadedAt:
          DateTime.tryParse(str(WmpTrack.lastDownloadedAt) ?? '') ??
          DateTime.now(),
      lastTagReadAt:
          DateTime.tryParse(str(WmpTrack.lastTagReadAt) ?? '') ??
          DateTime.now(),
    );
  }

  static Map<int, Object?> tombstoneToRecord({
    required String sourceName,
    required String remotePath,
    required int rev,
    required DateTime deletedAt,
  }) => {
    WmpTomb.sourceName: sourceName,
    WmpTomb.remotePath: remotePath,
    WmpTomb.rev: rev,
    WmpTomb.deletedAt: deletedAt.toUtc().toIso8601String(),
  };

  /// Encode a shard.
  ///
  /// [coverBlobs] is parallel to [tracks]: entry `i` is that track's own cover
  /// bytes (or null). Nothing is deduplicated.
  static Uint8List encodeTrackShard({
    required int kind,
    required String deviceId,
    required int revFrom,
    required int revTo,
    required List<LibraryTrack> tracks,
    List<Uint8List?>? coverBlobs,
    List<int>? coverKinds,
  }) {
    final records = <Map<int, Object?>>[];
    final covers = <({Uint8List bytes, int kind})>[];
    final withCovers = coverBlobs != null;
    for (var i = 0; i < tracks.length; i++) {
      final blob = withCovers ? coverBlobs[i] : null;
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
      records.add(trackToRecord(tracks[i], coverIndex: coverIndex));
    }
    return _encode(
      sections: {
        WmpSections.meta: _metaBytes(
          kind: kind,
          deviceId: deviceId,
          revFrom: revFrom,
          revTo: revTo,
          count: tracks.length,
        ),
        WmpSections.tracks: encodeRecords(records),
        if (covers.isNotEmpty) WmpSections.covers: buildCoverSection(covers),
      },
      rawIds: {WmpSections.covers},
    );
  }

  static Uint8List encodeTombShard({
    required String deviceId,
    required int revFrom,
    required int revTo,
    required List<
      ({String sourceName, String remotePath, int rev, DateTime deletedAt})
    >
    tombstones,
  }) {
    final records = [
      for (final t in tombstones)
        tombstoneToRecord(
          sourceName: t.sourceName,
          remotePath: t.remotePath,
          rev: t.rev,
          deletedAt: t.deletedAt,
        ),
    ];
    return _encode(
      sections: {
        WmpSections.meta: _metaBytes(
          kind: WmpKind.tomb,
          deviceId: deviceId,
          revFrom: revFrom,
          revTo: revTo,
          count: tombstones.length,
        ),
        WmpSections.tombs: encodeRecords(records),
      },
    );
  }

  /// Decode a shard. Covers come back as blobs; the caller decides where to
  /// write them.
  static DecodedLibraryShard decode(Uint8List bytes) {
    final container = WmpContainer.fromBytes(bytes);
    final metaRaw = container.readSection(WmpSections.meta);
    final meta = metaRaw == null
        ? const <int, Object?>{}
        : (decodeRecords(metaRaw, intTags: kMetaIntTags).firstOrNull ??
              const <int, Object?>{});

    final kind = (meta[WmpMeta.kind] as int?) ?? WmpKind.seg;
    // The magic says what the file is; META repeats it. They must agree, or this
    // is not a shard we should be feeding into the library.
    if (WmpFileKind.metaKindOf(container.kind) != kind) {
      throw WmpFormatException(
        '分片类型不一致：文件头 ${container.kind}，META kind=$kind',
      );
    }
    final revFrom = (meta[WmpMeta.seqFrom] as int?) ?? 0;
    final revTo = (meta[WmpMeta.seqTo] as int?) ?? 0;
    final deviceId = (meta[WmpMeta.deviceId] as String?) ?? '';
    final createdAt = (meta[WmpMeta.createdAt] as String?) ?? '';

    final coversRaw = container.readSection(WmpSections.covers);
    final covers = coversRaw == null
        ? <WmpCoverEntry>[]
        : parseCoverSection(coversRaw);

    if (kind == WmpKind.tomb) {
      final raw = container.readSection(WmpSections.tombs);
      final records = raw == null
          ? const <Map<int, Object?>>[]
          : decodeRecords(raw, intTags: kTombIntTags);
      return DecodedLibraryShard(
        kind: kind,
        revFrom: revFrom,
        revTo: revTo,
        deviceId: deviceId,
        createdAt: createdAt,
        tracks: const [],
        tombstones: [
          for (final r in records)
            {
              'source_name': r[WmpTomb.sourceName] as String? ?? '',
              'remote_path': r[WmpTomb.remotePath] as String? ?? '',
              'rev': r[WmpTomb.rev] as int? ?? 0,
              'deleted_at': r[WmpTomb.deletedAt] as String? ?? '',
            },
        ],
        covers: covers,
        coverSection: coversRaw ?? Uint8List(0),
        coverIndexByTrack: const {},
      );
    }

    final raw = container.readSection(WmpSections.tracks);
    final records = raw == null
        ? const <Map<int, Object?>>[]
        : decodeRecords(raw, intTags: kTrackIntTags);
    final coverIndexByTrack = <int, int?>{};
    final tracks = <LibraryTrack>[];
    for (var i = 0; i < records.length; i++) {
      final idx = records[i][WmpTrack.coverIndex];
      coverIndexByTrack[i] = idx is int ? idx : null;
      // The local cover path is filled in by the caller after it stores the blob.
      tracks.add(recordToTrack(records[i]));
    }
    return DecodedLibraryShard(
      kind: kind,
      revFrom: revFrom,
      revTo: revTo,
      deviceId: deviceId,
      createdAt: createdAt,
      tracks: tracks,
      tombstones: const [],
      covers: covers,
      coverSection: coversRaw ?? Uint8List(0),
      coverIndexByTrack: coverIndexByTrack,
    );
  }

  static Uint8List _metaBytes({
    required int kind,
    required String deviceId,
    required int revFrom,
    required int revTo,
    required int count,
  }) {
    return encodeRecords([
      {
        WmpMeta.kind: kind,
        WmpMeta.seqFrom: revFrom,
        WmpMeta.seqTo: revTo,
        WmpMeta.count: count,
        WmpMeta.deviceId: deviceId,
        WmpMeta.createdAt: DateTime.now().toUtc().toIso8601String(),
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
        (decodeRecords(sections[WmpSections.meta]!, intTags: kMetaIntTags)
                    .firstOrNull?[WmpMeta.kind]
                as int?) ??
        WmpKind.seg;
    return WmpContainer.encode(
      sections,
      kind: WmpFileKind.forMetaKind(kind),
      rawIds: rawIds,
    );
  }
}
