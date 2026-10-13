// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../models/manga.dart';
import 'track_identity.dart';

/// Stable offline manga id: path-index, not a content hash.
///
/// `sha1('manga' + sourceName + normalized remotePath)`.
String mangaIdForRemote(String sourceName, String remotePath) {
  final key =
      'manga\u0000${normalizeSourceName(sourceName)}\u0000'
      '${normalizeRemotePath(remotePath)}';
  return sha1.convert(utf8.encode(key)).toString();
}

/// Stable series id: `sha1('mangaSeries' + trimmed title)`.
///
/// Deterministic so two devices that create the same series title converge on
/// one id (cloud sync and `mangaSeries` folder refs depend on that).
String mangaSeriesIdForTitle(String title) {
  final key = 'mangaSeries\u0000${title.trim()}';
  return sha1.convert(utf8.encode(key)).toString();
}

/// Fresh surrogate id for a **loose-image** book.
///
/// Loose-image books are not path-bound: the folder they were built from is a
/// one-off input, so the id is minted once and never recomputed. Container
/// books keep [mangaIdForRemote] — the music-track rule, a materialised file
/// *is* its path.
String newMangaId() => const Uuid().v4();

/// The key a manga row (or its tombstone) travels under in cloud sync.
///
/// Containers keep the music-style `网盘名 + path` key, so shards written
/// before the surrogate-id model keep merging with the new ones. A loose-image
/// book has no meaningful path key, so its own id is the key.
String mangaSyncKeyForManga({
  required String id,
  required String format,
  required String sourceName,
  required String remotePath,
}) => format == MangaFormat.images
    ? id
    : trackIdentityKey(sourceName, normalizeRemotePath(remotePath));

/// True for a loose-image row written **before** the surrogate-id model
/// (schema v18): its id was derived from (source, path) and its page paths were
/// relative to the book folder. Shards and backups may still carry such rows;
/// sync and restore drop them instead of importing a book whose pages no
/// longer resolve.
bool isLegacyLooseManga({
  required String id,
  required String sourceName,
  required String remotePath,
  required String format,
}) =>
    format == MangaFormat.images &&
    id == mangaIdForRemote(sourceName, remotePath);
