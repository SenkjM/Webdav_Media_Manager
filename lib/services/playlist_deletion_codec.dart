import 'dart:typed_data';

import '../models/playlist_deletion.dart';
import '../utils/wmp_container.dart';

/// Codec for one playlist's deletion pack (`WDMMPD01`).
///
/// A pack is its own container, not a library `LT` shard and not a section of
/// the playlist document: deleting the playlist file must leave the pack
/// behind, or another device will upload its local copy and bring it back.
///
/// Inside the file the pack is a different kind (`META.kind`) and a different
/// section ([WmpSections.playlistDeletions]) from a playlist document. The
/// `pdel_` filename is only so a directory listing can find it.
class PlaylistDeletionCodec {
  PlaylistDeletionCodec._();

  static const String fileExtension = 'wdmp';
  static const String filePrefix = 'pdel_';
  static const String magicKind = WmpFileKind.playlistDeletion;

  /// Remote file name. The playlist id inside the pack is authoritative; this
  /// name is sanitized so a listing can tell packs from playlist documents.
  static String fileNameFor(String playlistId) {
    final safe = playlistId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final stem = safe.isEmpty ? 'playlist' : safe;
    return '$filePrefix$stem.$fileExtension';
  }

  static bool looksLikePackName(String name) {
    final lower = name.toLowerCase();
    return lower.startsWith(filePrefix) && lower.endsWith('.$fileExtension');
  }

  static Uint8List encode(
    String playlistId,
    List<PlaylistDeletion> records, {
    String deviceId = '',
  }) {
    if (playlistId.isEmpty) {
      throw const WmpFormatException('err.playlistDeletionMissingId');
    }
    final sorted = [...records]
      ..sort((a, b) => a.entryIdentity.compareTo(b.entryIdentity));
    DateTime? newest;
    final encoded = <Map<int, Object?>>[];
    for (final record in sorted) {
      final at = record.deletedAt.toUtc();
      if (newest == null || at.isAfter(newest)) newest = at;
      encoded.add({
        WmpPlaylistDeletion.scope: record.deletesPlaylist
            ? WmpPlaylistDeletion.scopePlaylist
            : WmpPlaylistDeletion.scopeEntry,
        if (!record.deletesPlaylist)
          WmpPlaylistDeletion.musicId: record.entryIdentity,
        WmpPlaylistDeletion.deletedAt: at.toIso8601String(),
      });
    }
    final meta = encodeRecords([
      {
        WmpMeta.kind: WmpKind.playlistDeletion,
        WmpMeta.count: encoded.length,
        WmpMeta.deviceId: deviceId,
        WmpMeta.createdAt: DateTime.now().toUtc().toIso8601String(),
        WmpPlaylistMeta.playlistId: playlistId,
        WmpPlaylistMeta.updatedAt: (newest ?? DateTime.now().toUtc())
            .toIso8601String(),
      },
    ]);
    return WmpContainer.encode({
      WmpSections.meta: meta,
      WmpSections.playlistDeletions: encodeRecords(encoded),
    }, kind: WmpFileKind.playlistDeletion);
  }

  /// Decode a `WDMMPD01` pack. The playlist id comes from META, not the name.
  static ({String playlistId, List<PlaylistDeletion> records}) decode(
    Uint8List bytes,
  ) {
    final container = WmpContainer.fromBytes(bytes);
    final metaRaw = container.readSection(WmpSections.meta);
    final meta = metaRaw == null
        ? const <int, Object?>{}
        : (decodeRecords(metaRaw, intTags: kMetaIntTags).firstOrNull ??
              const <int, Object?>{});
    final kind = (meta[WmpMeta.kind] as int?) ?? -1;
    if (container.kind != WmpFileKind.playlistDeletion ||
        kind != WmpKind.playlistDeletion) {
      throw WmpFormatException(
        'err.playlistDeletionKindMismatch|${container.kind}|$kind',
      );
    }
    final playlistId = (meta[WmpPlaylistMeta.playlistId] as String?) ?? '';
    if (playlistId.isEmpty) {
      throw const WmpFormatException('err.playlistDeletionMissingId');
    }
    final raw = container.readSection(WmpSections.playlistDeletions);
    final rows = raw == null
        ? const <Map<int, Object?>>[]
        : decodeRecords(raw, intTags: kPlaylistDeletionIntTags);
    final records = <PlaylistDeletion>[];
    for (final row in rows) {
      final at = DateTime.tryParse(
        (row[WmpPlaylistDeletion.deletedAt] as String?) ?? '',
      )?.toUtc();
      if (at == null) continue;
      final scope = row[WmpPlaylistDeletion.scope];
      final whole = scope == WmpPlaylistDeletion.scopePlaylist;
      final musicId = (row[WmpPlaylistDeletion.musicId] as String?) ?? '';
      if (!whole && musicId.isEmpty) continue;
      records.add(
        PlaylistDeletion(
          playlistId: playlistId,
          entryIdentity: whole ? '' : musicId,
          deletedAt: at,
        ),
      );
    }
    return (playlistId: playlistId, records: records);
  }
}
