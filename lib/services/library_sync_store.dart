import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/library_track.dart';
import '../utils/track_identity.dart';
import '../utils/wmp_container.dart';
import 'cover_service.dart';
import 'library_shard_codec.dart';
import 'settings_service.dart';
import 'webdav_service.dart';

/// One base shard as recorded in the manifest.
class BaseShard {
  const BaseShard({
    required this.file,
    required this.count,
    required this.bytes,
  });

  final String file;
  final int count;
  final int bytes;

  Map<String, dynamic> toJson() => {
    'file': file,
    'count': count,
    'bytes': bytes,
  };

  factory BaseShard.fromJson(Map<String, dynamic> json) => BaseShard(
    file: json['file'] as String? ?? '',
    count: (json['count'] as num?)?.toInt() ?? 0,
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
  );
}

/// An append-only part of the index (delta rows or tombstones).
class IndexPart {
  const IndexPart({
    required this.file,
    required this.from,
    required this.to,
    required this.count,
    required this.bytes,
  });

  final String file;
  final int from;
  final int to;
  final int count;
  final int bytes;

  Map<String, dynamic> toJson() => {
    'file': file,
    'from': from,
    'to': to,
    'count': count,
    'bytes': bytes,
  };

  factory IndexPart.fromJson(Map<String, dynamic> json) => IndexPart(
    file: json['file'] as String? ?? '',
    from: (json['from'] as num?)?.toInt() ?? 0,
    to: (json['to'] as num?)?.toInt() ?? 0,
    count: (json['count'] as num?)?.toInt() ?? 0,
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
  );
}

/// The cloud library manifest (`index.json`).
///
/// JSON on purpose: it is the entry point of every read, a few hundred bytes,
/// and the thing a human (or the 整理 function) inspects when something is
/// wrong. The rows themselves live in binary shards.
class LibraryManifest {
  LibraryManifest({
    this.baseUpTo = 0,
    List<BaseShard>? shards,
    List<IndexPart>? segments,
    List<IndexPart>? tombstones,
    this.updatedAt,
  }) : shards = shards ?? [],
       segments = segments ?? [],
       tombstones = tombstones ?? [];

  /// Highest rev materialised into [shards]; everything above it comes from
  /// [segments].
  int baseUpTo;
  final List<BaseShard> shards;
  final List<IndexPart> segments;
  final List<IndexPart> tombstones;
  DateTime? updatedAt;

  /// Append-only parts since the last rebuild — what the UI counts to suggest a
  /// rebuild.
  int get fragmentCount => segments.length + tombstones.length;

  int get fragmentBytes =>
      segments.fold(0, (a, s) => a + s.bytes) +
      tombstones.fold(0, (a, s) => a + s.bytes);

  bool get isEmpty => shards.isEmpty && segments.isEmpty && tombstones.isEmpty;

  Map<String, dynamic> toJson() => {
    'format': LibrarySyncStore.format,
    'formatVersion': LibrarySyncStore.formatVersion,
    'base': {
      'upTo': baseUpTo,
      'shards': [for (final s in shards) s.toJson()],
    },
    'segments': [for (final s in segments) s.toJson()],
    'tombstones': [for (final s in tombstones) s.toJson()],
    'updatedAt': (updatedAt ?? DateTime.now().toUtc()).toIso8601String(),
  };

  factory LibraryManifest.fromJson(Map<String, dynamic> json) {
    final base = Map<String, dynamic>.from(
      (json['base'] as Map?) ?? const <String, dynamic>{},
    );
    return LibraryManifest(
      baseUpTo: (base['upTo'] as num?)?.toInt() ?? 0,
      shards: [
        for (final s in (base['shards'] as List<dynamic>? ?? const []))
          if (s is Map) BaseShard.fromJson(Map<String, dynamic>.from(s)),
      ],
      segments: [
        for (final s in (json['segments'] as List<dynamic>? ?? const []))
          if (s is Map) IndexPart.fromJson(Map<String, dynamic>.from(s)),
      ],
      tombstones: [
        for (final s in (json['tombstones'] as List<dynamic>? ?? const []))
          if (s is Map) IndexPart.fromJson(Map<String, dynamic>.from(s)),
      ],
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }
}

/// What a rebuild would produce (for the size/片数 preview).
class RebuildEstimate {
  const RebuildEstimate({
    required this.shards,
    required this.withCoverBytes,
    required this.withoutCoverBytes,
  });

  final int shards;
  final int withCoverBytes;
  final int withoutCoverBytes;

  String get withCoverLabel => _fmt(withCoverBytes);
  String get withoutCoverLabel => _fmt(withoutCoverBytes);

  static String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Merge decoded shard batches plus tombstone batches into the live library.
///
/// The whole sync semantics live here:
/// * rows are keyed by `网盘名 + remotePath`, so the same path on two disks stays
///   two songs;
/// * the higher `rev` wins, whatever order the parts arrive in;
/// * a tombstone hides the row it names **only when its rev is at least as new** —
///   a re-download after the deletion has a higher rev and survives;
/// * order of first appearance is preserved so the library listing is stable.
CloudLibrary mergeCloudParts({
  required List<List<LibraryTrack>> dataParts,
  required List<List<Map<String, dynamic>>> tombstoneParts,
}) {
  final byKey = <String, LibraryTrack>{};
  final order = <String>[];
  for (final rows in dataParts) {
    for (final t in rows) {
      final key = trackIdentityKey(t.sourceName, t.remotePath);
      final kept = byKey[key];
      if (kept == null) {
        byKey[key] = t;
        order.add(key);
      } else if ((t.rev ?? 0) > (kept.rev ?? 0)) {
        byKey[key] = t;
      }
    }
  }
  final tombstoned = <String>{};
  for (final rows in tombstoneParts) {
    for (final row in rows) {
      final key = trackIdentityKey(
        row['source_name'] as String? ?? '',
        row['remote_path'] as String? ?? '',
      );
      tombstoned.add(key);
      final live = byKey[key];
      if (live != null && (row['rev'] as int? ?? 0) >= (live.rev ?? 0)) {
        byKey.remove(key);
        order.remove(key);
      }
    }
  }
  return CloudLibrary(
    tracks: [for (final key in order) byKey[key]!],
    tombstonedKeys: tombstoned,
  );
}

/// Result of comparing the manifest against what is actually in the directory.
class LibraryAudit {
  const LibraryAudit({
    required this.baseShards,
    required this.segments,
    required this.tombstones,
    required this.totalBytes,
    required this.orphans,
    required this.missing,
  });

  final int baseShards;
  final int segments;
  final int tombstones;
  final int totalBytes;

  /// Files present but not named by the manifest (a crashed append, or a
  /// concurrent rebuild that lost the manifest race).
  final List<String> orphans;

  /// Files the manifest names but that are gone (the range they covered cannot
  /// be replayed — only a rebuild fixes that).
  final List<String> missing;

  bool get healthy => orphans.isEmpty && missing.isEmpty;

  String get summary {
    final parts = <String>[
      '基础分片 $baseShards 个',
      '增量 $segments 个',
      '墓碑 $tombstones 个',
      '合计 ${RebuildEstimate._fmt(totalBytes)}',
    ];
    if (orphans.isNotEmpty) parts.add('孤儿文件 ${orphans.length} 个');
    if (missing.isNotEmpty) parts.add('缺失文件 ${missing.length} 个');
    return parts.join(' · ');
  }
}

/// Pure part/manifest comparison, so the audit rules are unit-testable.
LibraryAudit auditLibraryParts({
  required List<({String name, int size})> present,
  required LibraryManifest manifest,
}) {
  final known = <String>{
    for (final s in manifest.shards) s.file,
    for (final s in manifest.segments) s.file,
    for (final s in manifest.tombstones) s.file,
  };
  final presentNames = {for (final f in present) f.name};
  final orphans = <String>[
    for (final f in present)
      if (!known.contains(f.name) && _isLibraryPartName(f.name)) f.name,
  ]..sort();
  final missing = <String>[
    for (final name in known)
      if (!presentNames.contains(name)) name,
  ]..sort();
  return LibraryAudit(
    baseShards: manifest.shards.length,
    segments: manifest.segments.length,
    tombstones: manifest.tombstones.length,
    totalBytes: present.fold(0, (a, f) => a + f.size),
    orphans: orphans,
    missing: missing,
  );
}

bool _isLibraryPartName(String name) =>
    name.startsWith(LibrarySyncStore.shardPrefix) ||
    name.startsWith(LibrarySyncStore.segmentPrefix) ||
    name.startsWith(LibrarySyncStore.tombPrefix);

/// The merged cloud library.
class CloudLibrary {
  const CloudLibrary({required this.tracks, required this.tombstonedKeys});

  final List<LibraryTrack> tracks;

  /// `trackIdentityKey(网盘名, path)` of rows the cloud says are deleted.
  final Set<String> tombstonedKeys;
}

/// Binary, append-only storage for the cloud music library.
///
/// ```
/// <sync root>/library/
///   index.json          manifest: base shards + delta parts + tombstone parts
///   lib-<ts>-<rand>.wmp base shard (a slice of the complete live library)
///   seg-<from>-<rand>.wmp  delta: rows added/updated since the base
///   del-<from>-<rand>.wmp  tombstones: deletions, materialised only on rebuild
/// ```
///
/// There is deliberately **no automatic compaction**: appending is cheap and
/// predictable, and the user decides when to rebuild (the UI suggests it once
/// the parts pile up).
class LibrarySyncStore {
  LibrarySyncStore({
    required WebDavService webDav,
    required CoverService covers,
    required SettingsService settings,
  }) : _webDav = webDav,
       _covers = covers,
       _settings = settings;

  final WebDavService _webDav;
  final CoverService _covers;
  final SettingsService _settings;

  static const format = 'wmp_library_index';
  static const formatVersion = 1;
  static const indexName = 'index.json';
  static const shardPrefix = 'lib-';
  static const segmentPrefix = 'seg-';
  static const tombPrefix = 'del-';

  /// Suggested rebuild threshold (the UI just *suggests*).
  static const suggestRebuildAtFragments = 20;

  /// Default tracks per base shard.
  static const defaultTracksPerShard = 500;

  /// Absolute path of `<sync root>/library`.
  String dirPath() {
    final root = _settings.librarySyncRemotePath;
    final trimmed = root.endsWith('/')
        ? root.substring(0, root.length - 1)
        : root;
    return '$trimmed/library';
  }

  String indexPath() => '${dirPath()}/$indexName';

  String get deviceId => _settings.deviceId;

  // --- manifest ---------------------------------------------------------

  /// Read the manifest; an absent/legacy file reads as empty.
  Future<LibraryManifest> readManifest(String destAccountId) async {
    try {
      final bytes = await _webDav.readAsBytes(destAccountId, indexPath());
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return LibraryManifest();
      final json = Map<String, dynamic>.from(decoded);
      if (json['format'] != format) {
        // Anything else (including the pre-container per-index format) is not a
        // manifest; treat the library as empty. No compatibility branch by
        // design — a rebuild writes the current format.
        return LibraryManifest();
      }
      return LibraryManifest.fromJson(json);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (_isMissing(msg)) return LibraryManifest();
      rethrow;
    }
  }

  Future<void> writeManifest(String destAccountId, LibraryManifest m) async {
    m.updatedAt = DateTime.now().toUtc();
    await _webDav.ensureDirectory(destAccountId, dirPath());
    await _webDav.writeBytes(
      destAccountId,
      indexPath(),
      Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(m.toJson())),
      ),
    );
  }

  // --- read -------------------------------------------------------------

  /// Read every part the manifest names and merge them by `(网盘名, path)`.
  ///
  /// A missing part is skipped rather than fatal: after a concurrent rebuild the
  /// manifest can name a file that is already gone.
  /// Which part files a read actually fetched (so the caller can advance its
  /// cursor). Parts already covered by [skipFiles] are not downloaded at all.
  final Set<String> lastReadParts = <String>{};

  /// Result of the most recent [readCloud] call.
  CloudLibrary lastCloud = const CloudLibrary(tracks: [], tombstonedKeys: {});

  Future<CloudLibrary> readCloud(
    String destAccountId,
    LibraryManifest manifest, {
    bool fetchCovers = true,
    Set<String> skipFiles = const {},
  }) async {
    lastReadParts.clear();
    final dataParts = <List<LibraryTrack>>[];
    final tombParts = <List<Map<String, dynamic>>>[];

    for (final shard in manifest.shards) {
      if (skipFiles.contains(shard.file)) continue;
      final decoded = await _readShard(
        destAccountId,
        shard.file,
        fetchCovers: fetchCovers,
      );
      lastReadParts.add(shard.file);
      if (decoded != null) dataParts.add(decoded);
    }
    for (final seg in manifest.segments) {
      if (skipFiles.contains(seg.file)) continue;
      final decoded = await _readShard(
        destAccountId,
        seg.file,
        fetchCovers: fetchCovers,
      );
      lastReadParts.add(seg.file);
      if (decoded != null) dataParts.add(decoded);
    }
    for (final part in manifest.tombstones) {
      if (skipFiles.contains(part.file)) continue;
      lastReadParts.add(part.file);
      tombParts.add(await _readTombShard(destAccountId, part.file));
    }

    lastCloud = mergeCloudParts(
      dataParts: dataParts,
      tombstoneParts: tombParts,
    );
    return lastCloud;
  }

  Future<List<LibraryTrack>?> _readShard(
    String destAccountId,
    String file, {
    required bool fetchCovers,
  }) async {
    final bytes = await _readBytesOrNull(destAccountId, '${dirPath()}/$file');
    if (bytes == null) return null;
    final decoded = LibraryShardCodec.decode(bytes);
    final out = <LibraryTrack>[];
    for (var i = 0; i < decoded.tracks.length; i++) {
      final track = decoded.tracks[i];
      String? coverPath = decoded.tracks[i].coverPath;
      final blob = fetchCovers ? decoded.coverFor(i) : null;
      if (blob != null && blob.isNotEmpty) {
        coverPath = await _storeCover(track, blob);
      } else if (coverPath == null) {
        // The manifest carries no cover for this row: reuse whatever this device
        // already cached rather than clearing it.
        final local = await _covers.coverFile(
          track.sourceName,
          track.remotePath,
        );
        if (local.existsSync()) coverPath = local.path;
      }
      out.add(
        LibraryTrack.fromMap({...track.toMap(), 'cover_path': coverPath}),
      );
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _readTombShard(
    String destAccountId,
    String file,
  ) async {
    final bytes = await _readBytesOrNull(destAccountId, '${dirPath()}/$file');
    if (bytes == null) return const [];
    return LibraryShardCodec.decode(bytes).tombstones;
  }

  /// Shards above this size are streamed to a temp file instead of being held in
  /// memory (the shard size is the user's knob, so this is the memory ceiling).
  static const streamToFileAboveBytes = 1 << 20;

  Future<Uint8List?> _readBytesOrNull(String accountId, String path) async {
    try {
      final declared = await _declaredSize(accountId, path);
      if (declared != null && declared > streamToFileAboveBytes) {
        final dir = await getTemporaryDirectory();
        final tmp = File(p.join(dir.path, 'wmp_shard.part'));
        await _webDav.downloadToFile(accountId, path, tmp);
        try {
          return await tmp.readAsBytes();
        } finally {
          if (await tmp.exists()) {
            try {
              await tmp.delete();
            } catch (_) {}
          }
        }
      }
      return await _webDav.readAsBytes(accountId, path);
    } catch (e) {
      if (_isMissing(e.toString().toLowerCase())) return null;
      rethrow;
    }
  }

  /// Content length from a shallow directory listing, when the server gives it.
  Future<int?> _declaredSize(String accountId, String path) async {
    try {
      final parent = path.substring(0, path.lastIndexOf('/'));
      final name = path.substring(path.lastIndexOf('/') + 1);
      final items = await _webDav.listDirectory(accountId, parent);
      for (final item in items) {
        if (item.name == name) return item.size;
      }
    } catch (_) {
      // Not fatal: fall back to a plain read.
    }
    return null;
  }

  /// Write a cover blob into this device's cover cache (deterministic file name,
  /// so nothing about the path needs to travel).
  Future<String?> _storeCover(LibraryTrack track, Uint8List blob) async {
    try {
      final file = await _covers.coverFile(track.sourceName, track.remotePath);
      if (!file.existsSync()) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(blob, flush: true);
      }
      return file.path;
    } catch (_) {
      return null;
    }
  }

  // --- append -----------------------------------------------------------

  /// Append one delta part with only [changed] rows (and their covers).
  ///
  /// Returns the manifest that was written. The part is uploaded **before** the
  /// manifest, so a crash in between leaves an unreferenced file (harmless)
  /// rather than a manifest pointing at nothing.
  Future<LibraryManifest> appendDelta({
    required String destAccountId,
    required List<LibraryTrack> changed,
    bool withCovers = true,
  }) async {
    if (changed.isEmpty) return readManifest(destAccountId);
    final revs = [for (final t in changed) t.rev ?? 0];
    final from = revs.reduce(min);
    final to = revs.reduce(max);
    final bytes = LibraryShardCodec.encodeTrackShard(
      kind: WmpKind.seg,
      deviceId: deviceId,
      revFrom: from,
      revTo: to,
      tracks: changed,
      coverBlobs: withCovers ? await _coverBlobs(changed) : null,
    );
    final file = _partName(segmentPrefix, from);
    await _webDav.ensureDirectory(destAccountId, dirPath());
    await _webDav.writeBytes(destAccountId, '${dirPath()}/$file', bytes);

    // Re-read first: another device (or another pass) may have appended while we
    // were uploading.
    final latest = await readManifest(destAccountId);
    latest.segments.add(
      IndexPart(
        file: file,
        from: from,
        to: to,
        count: changed.length,
        bytes: bytes.length,
      ),
    );
    await writeManifest(destAccountId, latest);
    return latest;
  }

  /// Append one tombstone part with the given local tombstones.
  Future<LibraryManifest> appendTombstones({
    required String destAccountId,
    required List<Map<String, dynamic>> tombstones,
  }) async {
    if (tombstones.isEmpty) return readManifest(destAccountId);
    final entries =
        <
          ({String sourceName, String remotePath, int rev, DateTime deletedAt})
        >[];
    for (final row in tombstones) {
      entries.add((
        sourceName: row['source_name'] as String? ?? '',
        remotePath: row['remote_path'] as String? ?? '',
        rev: (row['rev'] as num?)?.toInt() ?? 0,
        deletedAt:
            DateTime.tryParse(row['deleted_at'] as String? ?? '') ??
            DateTime.now(),
      ));
    }
    final revs = [for (final e in entries) e.rev];
    final from = revs.reduce(min);
    final to = revs.reduce(max);
    final bytes = LibraryShardCodec.encodeTombShard(
      deviceId: deviceId,
      revFrom: from,
      revTo: to,
      tombstones: entries,
    );
    final file = _partName(tombPrefix, from);
    await _webDav.ensureDirectory(destAccountId, dirPath());
    await _webDav.writeBytes(destAccountId, '${dirPath()}/$file', bytes);

    final latest = await readManifest(destAccountId);
    latest.tombstones.add(
      IndexPart(
        file: file,
        from: from,
        to: to,
        count: entries.length,
        bytes: bytes.length,
      ),
    );
    await writeManifest(destAccountId, latest);
    return latest;
  }

  // --- rebuild ----------------------------------------------------------

  /// Estimated shard count and size for a rebuild, so the user can pick a
  /// tracks-per-shard value before committing.
  Future<RebuildEstimate> estimate({
    required List<LibraryTrack> tracks,
    required int tracksPerShard,
    required bool withCovers,
  }) async {
    final perShard = tracksPerShard.clamp(50, 5000);
    final shards = tracks.isEmpty
        ? 0
        : ((tracks.length + perShard - 1) ~/ perShard);
    // Encode one representative slice to measure real bytes (covers included).
    final sample = tracks.take(perShard).toList();
    final blobs = withCovers ? await _coverBlobs(sample) : null;
    final bytes = LibraryShardCodec.encodeTrackShard(
      kind: WmpKind.base,
      deviceId: deviceId,
      revFrom: 0,
      revTo: 0,
      tracks: sample,
      coverBlobs: blobs,
    ).length;
    final full = libraryTrackCountForEstimate(
      shards: shards,
      perShardSampleBytes: bytes,
      sampleCount: sample.length,
      total: tracks.length,
    );
    final withoutCovers = LibraryShardCodec.encodeTrackShard(
      kind: WmpKind.base,
      deviceId: deviceId,
      revFrom: 0,
      revTo: 0,
      tracks: sample,
      coverBlobs: null,
    ).length;
    final fullNoCover = libraryTrackCountForEstimate(
      shards: shards,
      perShardSampleBytes: withoutCovers,
      sampleCount: sample.length,
      total: tracks.length,
    );
    return RebuildEstimate(
      shards: shards,
      withCoverBytes: full,
      withoutCoverBytes: fullNoCover,
    );
  }

  /// Rebuild the cloud library from [tracks] into fixed-size base shards.
  ///
  /// This is the **only** place deletions are materialised: tombstoned rows are
  /// simply absent from [tracks], and every delta/tombstone part is dropped from
  /// the manifest afterwards.
  Future<LibraryManifest> rebuild({
    required String destAccountId,
    required List<LibraryTrack> tracks,
    int tracksPerShard = defaultTracksPerShard,
    bool withCovers = true,
  }) async {
    final perShard = tracksPerShard.clamp(50, 5000);
    final previous = await readManifest(destAccountId);
    await _webDav.ensureDirectory(destAccountId, dirPath());

    // Slice on album boundaries where possible: an album's tracks then share one
    // shard, which keeps a future read local and avoids splitting a CUE group.
    final ordered = [...tracks]
      ..sort((a, b) {
        final albumA = '${a.sourceName}\u0000${a.displayAlbum}';
        final albumB = '${b.sourceName}\u0000${b.displayAlbum}';
        final byAlbum = albumA.compareTo(albumB);
        if (byAlbum != 0) return byAlbum;
        return a.remotePath.compareTo(b.remotePath);
      });
    final slices = <List<LibraryTrack>>[];
    var current = <LibraryTrack>[];
    var currentAlbum = ordered.isEmpty
        ? ''
        : '${ordered.first.sourceName}\u0000${ordered.first.displayAlbum}';
    for (final t in ordered) {
      final album = '${t.sourceName}\u0000${t.displayAlbum}';
      if (current.isNotEmpty &&
          (current.length >= perShard || album != currentAlbum)) {
        slices.add(current);
        current = <LibraryTrack>[];
      }
      currentAlbum = album;
      current.add(t);
    }
    if (current.isNotEmpty) slices.add(current);

    final shards = <BaseShard>[];
    var maxRev = 0;
    for (var i = 0; i < slices.length; i++) {
      final slice = slices[i];
      for (final t in slice) {
        final rev = t.rev ?? 0;
        if (rev > maxRev) maxRev = rev;
      }
      final bytes = LibraryShardCodec.encodeTrackShard(
        kind: WmpKind.base,
        deviceId: deviceId,
        revFrom: 0,
        revTo: 0,
        tracks: slice,
        coverBlobs: withCovers ? await _coverBlobs(slice) : null,
      );
      final file =
          '$shardPrefix${(i + 1).toString().padLeft(4, '0')}-${_rand()}.wmp';
      await _webDav.writeBytes(destAccountId, '${dirPath()}/$file', bytes);
      shards.add(
        BaseShard(file: file, count: slice.length, bytes: bytes.length),
      );
    }

    final manifest = LibraryManifest(baseUpTo: maxRev, shards: shards);
    await writeManifest(destAccountId, manifest);

    // Only now drop the parts the new base replaced.
    for (final old in [
      ...previous.shards.map((s) => s.file),
      ...previous.segments.map((s) => s.file),
      ...previous.tombstones.map((s) => s.file),
    ]) {
      if (shards.any((s) => s.file == old)) continue;
      try {
        await _webDav.deletePath(destAccountId, '${dirPath()}/$old');
      } catch (_) {
        // Leftovers are ignored: the manifest no longer names them.
      }
    }
    return manifest;
  }

  // --- audit / tidy -----------------------------------------------------

  /// Compare the manifest with the directory's real contents.
  Future<LibraryAudit> audit(String destAccountId) async {
    final manifest = await readManifest(destAccountId);
    final present = <({String name, int size})>[];
    try {
      final items = await _webDav.listDirectory(destAccountId, dirPath());
      for (final item in items) {
        if (item.isDirectory) continue;
        present.add((name: item.name, size: item.size ?? 0));
      }
    } catch (_) {
      // A missing directory means an empty cloud library.
    }
    return auditLibraryParts(present: present, manifest: manifest);
  }

  /// Delete files the manifest no longer references.
  Future<int> deleteOrphans(String destAccountId, LibraryAudit audit) async {
    var n = 0;
    for (final name in audit.orphans) {
      try {
        await _webDav.deletePath(destAccountId, '${dirPath()}/$name');
        n++;
      } catch (_) {
        // Best effort: leaving an orphan costs space, not correctness.
      }
    }
    return n;
  }

  // --- helpers ----------------------------------------------------------

  Future<List<Uint8List?>> _coverBlobs(List<LibraryTrack> tracks) async {
    final out = <Uint8List?>[];
    for (final t in tracks) {
      Uint8List? blob;
      final path = t.coverPath;
      if (path != null && path.isNotEmpty) {
        try {
          final file = File(path);
          if (file.existsSync()) blob = await file.readAsBytes();
        } catch (_) {
          blob = null;
        }
      }
      out.add(blob);
    }
    return out;
  }

  String _partName(String prefix, int rev) {
    final stamp = rev > 0 ? rev : DateTime.now().millisecondsSinceEpoch;
    return '$prefix$stamp-${_rand()}.wmp';
  }

  static String _rand() =>
      Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');

  static bool _isMissing(String lowercasedMessage) =>
      lowercasedMessage.contains('404') ||
      lowercasedMessage.contains('not found') ||
      lowercasedMessage.contains('does not exist') ||
      lowercasedMessage.contains('no such file');
}

/// Scale a measured sample up to the whole library (kept separate so it can be
/// unit-tested without touching the network).
int libraryTrackCountForEstimate({
  required int shards,
  required int perShardSampleBytes,
  required int sampleCount,
  required int total,
}) {
  if (shards == 0 || sampleCount == 0 || total == 0) return 0;
  final perTrack = perShardSampleBytes / sampleCount;
  return (perTrack * total).round();
}

/// Path helper kept out of the service for reuse in tests.
String libraryDirFor(String syncRoot) {
  final trimmed = syncRoot.endsWith('/')
      ? syncRoot.substring(0, syncRoot.length - 1)
      : syncRoot;
  return p.url.normalize('$trimmed/library');
}
