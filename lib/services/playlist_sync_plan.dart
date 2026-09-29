import '../models/playlist.dart';
import '../models/playlist_deletion.dart';

/// What a playlist pull should write back. Whole documents stay whole: entry
/// order is the winning document's order, with tombstoned identities filtered
/// out. Rows from the loser are not merged in.
class PlaylistSyncPlan {
  const PlaylistSyncPlan({
    required this.playlists,
    required this.upload,
    required this.deleteRemoteNames,
    required this.tombstones,
    required this.uploadPackIds,
  });

  /// Playlists that should exist locally after the merge.
  final List<Playlist> playlists;

  /// Documents whose bytes are not already the remote copy.
  final List<Playlist> upload;

  /// Playlist-document file names a whole-playlist tombstone retired.
  final List<String> deleteRemoteNames;

  /// Canonical deletion records (one pack per playlist id).
  final List<PlaylistDeletion> tombstones;

  /// Packs whose canonical records differ from what the server already has.
  final Set<String> uploadPackIds;
}

class _Bucket {
  DateTime? whole;
  final Map<String, DateTime> entries = {};
}

/// Merge local and remote playlist documents with per-playlist tombstones.
///
/// A whole-playlist tombstone always wins until the deletion queue is
/// compacted: a newer local copy must not resurrect a playlist that was
/// deleted on another device. An entry tombstone removes that identity from
/// the winning document when the document is not strictly newer than the
/// delete. A later edit (re-add) keeps the entry and its place in that
/// document's order.
PlaylistSyncPlan planPlaylistSync({
  required List<Playlist> local,
  required List<Playlist> remote,
  required List<PlaylistDeletion> tombstones,
  required Map<String, List<PlaylistDeletion>> remotePacks,
}) {
  final buckets = <String, _Bucket>{};
  void add(PlaylistDeletion record) {
    final bucket = buckets.putIfAbsent(record.playlistId, _Bucket.new);
    final at = record.deletedAt.toUtc();
    if (record.deletesPlaylist) {
      if (bucket.whole == null || at.isAfter(bucket.whole!)) {
        bucket.whole = at;
      }
      return;
    }
    final prev = bucket.entries[record.entryIdentity];
    if (prev == null || at.isAfter(prev)) {
      bucket.entries[record.entryIdentity] = at;
    }
  }

  for (final record in tombstones) {
    if (record.playlistId.isEmpty) continue;
    add(record);
  }

  final localById = {for (final pl in local) pl.id: pl};
  final remoteById = {for (final pl in remote) pl.id: pl};
  final ids = {...localById.keys, ...remoteById.keys};

  final kept = <Playlist>[];
  final upload = <Playlist>[];
  final deleteNames = <String>{};
  final canonical = <PlaylistDeletion>[];

  void rememberRemoteName(Playlist? playlist) {
    final name = playlist?.remoteFileName;
    if (name != null && name.isNotEmpty) deleteNames.add(name);
  }

  for (final id in ids) {
    final bucket = buckets[id];
    final localPl = localById[id];
    final remotePl = remoteById[id];
    if (bucket?.whole != null) {
      rememberRemoteName(remotePl);
      rememberRemoteName(localPl);
      canonical.add(
        PlaylistDeletion(playlistId: id, deletedAt: bucket!.whole!),
      );
      continue;
    }

    final winner = _winner(localPl, remotePl);
    if (winner == null) continue;
    final applied = _applyEntryTombstones(winner, bucket?.entries ?? const {});
    kept.add(applied);
    if (remotePl == null || !_sameDocument(applied, remotePl)) {
      upload.add(applied);
    }
    if (bucket != null) {
      for (final entry in bucket.entries.entries) {
        canonical.add(
          PlaylistDeletion(
            playlistId: id,
            entryIdentity: entry.key,
            deletedAt: entry.value,
          ),
        );
      }
    }
  }

  // Packs for playlists that no longer have a document (deleted, or a pack
  // that arrived before we ever stored the list).
  for (final entry in buckets.entries) {
    if (ids.contains(entry.key)) continue;
    if (entry.value.whole != null) {
      canonical.add(
        PlaylistDeletion(playlistId: entry.key, deletedAt: entry.value.whole!),
      );
    } else {
      for (final item in entry.value.entries.entries) {
        canonical.add(
          PlaylistDeletion(
            playlistId: entry.key,
            entryIdentity: item.key,
            deletedAt: item.value,
          ),
        );
      }
    }
  }

  final byPlaylist = <String, List<PlaylistDeletion>>{};
  for (final record in canonical) {
    byPlaylist.putIfAbsent(record.playlistId, () => []).add(record);
  }
  final uploadPackIds = <String>{};
  for (final entry in byPlaylist.entries) {
    if (!_sameDeletions(entry.value, remotePacks[entry.key] ?? const [])) {
      uploadPackIds.add(entry.key);
    }
  }

  return PlaylistSyncPlan(
    playlists: kept,
    upload: upload,
    deleteRemoteNames: deleteNames.toList()..sort(),
    tombstones: canonical,
    uploadPackIds: uploadPackIds,
  );
}

Playlist? _winner(Playlist? local, Playlist? remote) {
  if (local == null) return remote;
  if (remote == null) return local;
  final winner = mergePlaylistsLastWriteWins(local, remote);
  final name = remote.remoteFileName ?? local.remoteFileName;
  if (name == winner.remoteFileName) return winner;
  return winner.copyWith(remoteFileName: name);
}

/// Drop identities whose tombstone is at least as new as the document.
/// Remaining entries keep the document's order.
Playlist _applyEntryTombstones(Playlist doc, Map<String, DateTime> tombstones) {
  if (tombstones.isEmpty) return doc;
  final kept = <PlaylistEntry>[];
  DateTime? newest;
  var stripped = false;
  for (final entry in doc.entries) {
    final at = tombstones[entry.identityKey];
    if (at != null && !doc.updatedAt.toUtc().isAfter(at.toUtc())) {
      stripped = true;
      if (newest == null || at.isAfter(newest)) newest = at;
      continue;
    }
    kept.add(entry);
  }
  if (!stripped) return doc;
  var updatedAt = doc.updatedAt;
  if (newest != null && newest.toUtc().isAfter(updatedAt.toUtc())) {
    updatedAt = newest.toUtc();
  }
  return doc.copyWith(entries: kept, updatedAt: updatedAt);
}

bool _sameDocument(Playlist a, Playlist b) {
  if (a.name != b.name) return false;
  if (!a.updatedAt.toUtc().isAtSameMomentAs(b.updatedAt.toUtc())) return false;
  if (a.entries.length != b.entries.length) return false;
  for (var i = 0; i < a.entries.length; i++) {
    final left = a.entries[i];
    final right = b.entries[i];
    if (left.identityKey != right.identityKey) return false;
    if (left.title != right.title) return false;
    if (left.durationMs != right.durationMs) return false;
    if (left.cueTrackIndex != right.cueTrackIndex) return false;
  }
  return true;
}

bool _sameDeletions(List<PlaylistDeletion> a, List<PlaylistDeletion> b) {
  String sig(PlaylistDeletion d) =>
      '${d.entryIdentity}|${d.deletedAt.toUtc().toIso8601String()}';
  final left = a.map(sig).toSet();
  final right = b.map(sig).toSet();
  return left.length == a.length &&
      right.length == b.length &&
      left.length == right.length &&
      left.containsAll(right);
}
