// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models/manga.dart';
import '../models/manga_progress.dart';
import '../models/manga_series.dart';
import '../utils/manga_identity.dart';
import '../utils/track_identity.dart';
import '../utils/wmp_container.dart';
import 'library_shard_codec.dart';
import 'library_sync_store.dart';
import 'settings_service.dart';
import 'webdav_service.dart';

/// One manga row as it travels in a cloud shard: the `mangas` row, its series
/// (inline, so a pulled row can recreate it), and the frozen page order.
class MangaSyncRow {
  MangaSyncRow({required this.manga, this.series, this.pages = const []});

  final Manga manga;
  final MangaSeries? series;

  /// `manga_pages.rel_path` in page order (empty until the pages are frozen).
  final List<String> pages;

  int get rev => manga.rev;

  String get key => mangaSyncKey(manga.sourceName, manga.remotePath);
}

/// Identity of a manga row in sync: `网盘名 + normalized remotePath`.
String mangaSyncKey(String sourceName, String remotePath) =>
    trackIdentityKey(sourceName, normalizeRemotePath(remotePath));

/// One decoded manga shard.
class DecodedMangaShard {
  DecodedMangaShard({
    required this.kind,
    required this.rows,
    required this.tombstones,
    required List<WmpCoverEntry> covers,
    required Uint8List coverSection,
    required Map<int, int?> coverIndexByRow,
  }) : _covers = covers,
       _coverSection = coverSection,
       _coverIndexByRow = coverIndexByRow;

  final int kind;
  final List<MangaSyncRow> rows;
  final List<Map<String, dynamic>> tombstones;
  final List<WmpCoverEntry> _covers;
  final Uint8List _coverSection;
  final Map<int, int?> _coverIndexByRow;

  /// This row's own cover bytes (never another row's).
  Uint8List? coverFor(int rowIndex) {
    final idx = _coverIndexByRow[rowIndex];
    if (idx == null || idx < 0 || idx >= _covers.length) return null;
    return _covers[idx].bytesIn(_coverSection);
  }
}

/// Binary codec for manga shards: the same container, file kinds (`LB` / `LS`
/// / `LT`) and META as music shards, with a `MANGAS` section instead of
/// `TRACKS`. Tombstone shards are byte-identical to music tombstones.
class MangaShardCodec {
  MangaShardCodec._();

  static Map<int, Object?> rowToRecord(MangaSyncRow row, {int? coverIndex}) {
    final m = row.manga;
    final s = row.series;
    return {
      WmpManga.sourceName: m.sourceName,
      WmpManga.remotePath: normalizeRemotePath(m.remotePath),
      WmpManga.rev: m.rev,
      WmpManga.title: m.title,
      WmpManga.author: m.author,
      WmpManga.seriesId: m.seriesId,
      WmpManga.seriesTitle: s?.title,
      WmpManga.seriesAuthor: s?.author,
      WmpManga.seriesSortTitle: s?.sortTitle,
      WmpManga.volume: m.volume,
      WmpManga.chapterNumber: m.chapterNumber,
      WmpManga.pageCount: m.pageCount,
      WmpManga.coverRelpath: m.coverRelpath,
      WmpManga.format: m.format,
      WmpManga.remoteMissing: m.remoteMissing ? 1 : 0,
      WmpManga.pageTurn: m.pageTurn,
      WmpManga.updatedAt: m.updatedAt.toUtc().toIso8601String(),
      if (row.pages.isNotEmpty) WmpManga.pages: jsonEncode(row.pages),
      WmpManga.coverIndex: coverIndex,
    };
  }

  static MangaSyncRow recordToRow(Map<int, Object?> r) {
    String? str(int tag) {
      final v = r[tag];
      return v is String && v.isNotEmpty ? v : null;
    }

    int? num_(int tag) {
      final v = r[tag];
      return v is int ? v : null;
    }

    final sourceName = str(WmpManga.sourceName) ?? '';
    final remotePath = normalizeRemotePath(str(WmpManga.remotePath) ?? '/');
    final seriesId = str(WmpManga.seriesId);
    final seriesTitle = str(WmpManga.seriesTitle);
    final updatedAt =
        DateTime.tryParse(str(WmpManga.updatedAt) ?? '')?.toLocal() ??
        DateTime.now();
    final pages = <String>[];
    final rawPages = str(WmpManga.pages);
    if (rawPages != null) {
      final decoded = jsonDecode(rawPages);
      if (decoded is List) {
        for (final e in decoded) {
          if (e is String) pages.add(e);
        }
      }
    }
    return MangaSyncRow(
      manga: Manga(
        id: mangaIdForRemote(sourceName, remotePath),
        sourceName: sourceName,
        remotePath: remotePath,
        title: str(WmpManga.title) ?? remotePath.split('/').last,
        author: str(WmpManga.author),
        seriesId: seriesId,
        volume: str(WmpManga.volume),
        chapterNumber: str(WmpManga.chapterNumber),
        pageCount: num_(WmpManga.pageCount) ?? pages.length,
        coverRelpath: str(WmpManga.coverRelpath),
        format: str(WmpManga.format) ?? MangaFormat.unknown,
        remoteMissing: (num_(WmpManga.remoteMissing) ?? 0) != 0,
        pageTurn: str(WmpManga.pageTurn),
        updatedAt: updatedAt,
        rev: num_(WmpManga.rev) ?? 0,
      ),
      series: (seriesId == null || seriesTitle == null)
          ? null
          : MangaSeries(
              id: seriesId,
              title: seriesTitle,
              author: str(WmpManga.seriesAuthor),
              sortTitle: str(WmpManga.seriesSortTitle),
              createdAt: updatedAt,
            ),
      pages: pages,
    );
  }

  /// Encode a data shard; [coverBlobs] is parallel to [rows] (null = no cover).
  static Uint8List encodeMangaShard({
    required int kind,
    required String deviceId,
    required int revFrom,
    required int revTo,
    required List<MangaSyncRow> rows,
    List<Uint8List?>? coverBlobs,
  }) {
    final records = <Map<int, Object?>>[];
    final covers = <({Uint8List bytes, int kind})>[];
    for (var i = 0; i < rows.length; i++) {
      final blob = coverBlobs == null ? null : coverBlobs[i];
      int? coverIndex;
      if (blob != null && blob.isNotEmpty) {
        coverIndex = covers.length;
        covers.add((bytes: blob, kind: WmpImageKind.detect(blob)));
      }
      records.add(rowToRecord(rows[i], coverIndex: coverIndex));
    }
    return WmpContainer.encode(
      {
        WmpSections.meta: encodeRecords([
          {
            WmpMeta.kind: kind,
            WmpMeta.seqFrom: revFrom,
            WmpMeta.seqTo: revTo,
            WmpMeta.count: rows.length,
            WmpMeta.deviceId: deviceId,
            WmpMeta.createdAt: DateTime.now().toUtc().toIso8601String(),
            WmpMeta.note: 'manga',
          },
        ]),
        WmpSections.mangas: encodeRecords(records),
        if (covers.isNotEmpty) WmpSections.covers: buildCoverSection(covers),
      },
      kind: WmpFileKind.forMetaKind(kind),
      rawIds: {WmpSections.covers},
    );
  }

  /// Decode a manga data shard or a (shared-format) tombstone shard.
  static DecodedMangaShard decode(Uint8List bytes) {
    final container = WmpContainer.fromBytes(bytes);
    final metaRaw = container.readSection(WmpSections.meta);
    final meta = metaRaw == null
        ? const <int, Object?>{}
        : (decodeRecords(metaRaw, intTags: kMetaIntTags).firstOrNull ??
              const <int, Object?>{});
    final kind = (meta[WmpMeta.kind] as int?) ?? WmpKind.seg;
    if (WmpFileKind.metaKindOf(container.kind) != kind) {
      throw WmpFormatException('err.shardKindMismatch|${container.kind}|$kind');
    }
    if (kind == WmpKind.tomb) {
      return DecodedMangaShard(
        kind: kind,
        rows: const [],
        tombstones: LibraryShardCodec.decode(bytes).tombstones,
        covers: const [],
        coverSection: Uint8List(0),
        coverIndexByRow: const {},
      );
    }
    final raw = container.readSection(WmpSections.mangas);
    final records = raw == null
        ? const <Map<int, Object?>>[]
        : decodeRecords(raw, intTags: kMangaIntTags);
    final coversRaw = container.readSection(WmpSections.covers);
    final covers = coversRaw == null
        ? <WmpCoverEntry>[]
        : parseCoverSection(coversRaw);
    final coverIndex = <int, int?>{};
    final rows = <MangaSyncRow>[];
    for (var i = 0; i < records.length; i++) {
      rows.add(recordToRow(records[i]));
      final idx = records[i][WmpManga.coverIndex];
      coverIndex[i] = idx is int ? idx : null;
    }
    return DecodedMangaShard(
      kind: kind,
      rows: rows,
      tombstones: const [],
      covers: covers,
      coverSection: coversRaw ?? Uint8List(0),
      coverIndexByRow: coverIndex,
    );
  }
}

/// The merged cloud manga library.
class CloudMangaLibrary {
  const CloudMangaLibrary({required this.rows, required this.tombstonedKeys});

  final List<MangaSyncRow> rows;
  final Set<String> tombstonedKeys;
}

/// Same rules as music ([mergeCloudParts]): keyed by `网盘名 + path`, higher
/// rev wins in any arrival order, a tombstone hides a row only when its rev is
/// at least as new, first-appearance order is kept.
CloudMangaLibrary mergeMangaCloudParts({
  required List<List<MangaSyncRow>> dataParts,
  required List<List<Map<String, dynamic>>> tombstoneParts,
}) {
  final byKey = <String, MangaSyncRow>{};
  final order = <String>[];
  for (final rows in dataParts) {
    for (final r in rows) {
      final kept = byKey[r.key];
      if (kept == null) {
        byKey[r.key] = r;
        order.add(r.key);
      } else if (r.rev > kept.rev) {
        byKey[r.key] = r;
      }
    }
  }
  final tombstoned = <String>{};
  for (final rows in tombstoneParts) {
    for (final row in rows) {
      final key = mangaSyncKey(
        row['source_name'] as String? ?? '',
        row['remote_path'] as String? ?? '',
      );
      tombstoned.add(key);
      final live = byKey[key];
      if (live != null && (row['rev'] as int? ?? 0) >= live.rev) {
        byKey.remove(key);
        order.remove(key);
      }
    }
  }
  return CloudMangaLibrary(
    rows: [for (final key in order) byKey[key]!],
    tombstonedKeys: tombstoned,
  );
}

/// Fixed-size rebuild slices ordered by `(网盘名, path)`.
List<List<MangaSyncRow>> chunkMangaRowsForRebuild(
  List<MangaSyncRow> rows, {
  required int perShard,
}) {
  final size = perShard < 1 ? 1 : perShard;
  final ordered = [...rows]
    ..sort((a, b) {
      final bySource = a.manga.sourceName.compareTo(b.manga.sourceName);
      if (bySource != 0) return bySource;
      return a.manga.remotePath.compareTo(b.manga.remotePath);
    });
  return [
    for (var i = 0; i < ordered.length; i += size)
      ordered.sublist(i, min(i + size, ordered.length)),
  ];
}

// --- Reading progress (progress.json, per-entry last-write-wins) ----------

/// Result of merging local and cloud reading progress.
class MangaProgressMerge {
  const MangaProgressMerge({
    required this.merged,
    required this.toApplyLocally,
    required this.cloudNeedsUpdate,
  });

  /// Union of both sides, newest `updatedAt` per manga id.
  final Map<String, MangaProgress> merged;

  /// Entries where the cloud is newer than (or missing from) this device.
  final List<MangaProgress> toApplyLocally;

  /// True when this device holds an entry the cloud lacks or has older.
  final bool cloudNeedsUpdate;
}

/// Per manga id, the newer `updatedAt` wins; an exact tie keeps the local row
/// (nothing to apply, nothing to upload).
MangaProgressMerge mergeMangaProgress({
  required List<MangaProgress> local,
  required List<MangaProgress> cloud,
}) {
  final localById = {for (final p in local) p.mangaId: p};
  final cloudById = {for (final p in cloud) p.mangaId: p};
  final merged = <String, MangaProgress>{};
  final toApply = <MangaProgress>[];
  var upload = false;
  for (final id in {...localById.keys, ...cloudById.keys}) {
    final l = localById[id];
    final c = cloudById[id];
    if (l == null) {
      merged[id] = c!;
      toApply.add(c);
    } else if (c == null) {
      merged[id] = l;
      upload = true;
    } else if (c.updatedAt.isAfter(l.updatedAt)) {
      merged[id] = c;
      toApply.add(c);
    } else {
      merged[id] = l;
      if (l.updatedAt.isAfter(c.updatedAt)) upload = true;
    }
  }
  return MangaProgressMerge(
    merged: merged,
    toApplyLocally: toApply,
    cloudNeedsUpdate: upload,
  );
}

const String mangaProgressFormat = 'wmp_manga_progress';

Uint8List encodeMangaProgressDoc(
  Iterable<MangaProgress> entries, {
  required String deviceId,
}) {
  final list = [...entries]..sort((a, b) => a.mangaId.compareTo(b.mangaId));
  return Uint8List.fromList(
    utf8.encode(
      const JsonEncoder.withIndent('  ').convert({
        'format': mangaProgressFormat,
        'formatVersion': 1,
        'deviceId': deviceId,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'entries': [
          for (final p in list)
            {
              'mangaId': p.mangaId,
              'page': p.pageIndex,
              'updatedAt': p.updatedAt.toUtc().toIso8601String(),
            },
        ],
      }),
    ),
  );
}

List<MangaProgress> decodeMangaProgressDoc(Uint8List bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map || decoded['format'] != mangaProgressFormat) {
    return const [];
  }
  return [
    for (final e in (decoded['entries'] as List<dynamic>? ?? const []))
      if (e is Map && e['mangaId'] is String)
        MangaProgress(
          mangaId: e['mangaId'] as String,
          pageIndex: (e['page'] as num?)?.toInt() ?? 0,
          updatedAt:
              DateTime.tryParse(e['updatedAt'] as String? ?? '')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
        ),
  ];
}

/// Cloud storage for the manga library:
///
/// ```
/// <sync root>/library/manga/
///   index.json              manifest (format wmp_manga_library_index)
///   lib-/seg-/del-*.wdmm    base / delta / tombstone shards (as music)
///   progress.json           reading progress, per-entry last-write-wins
/// ```
class MangaSyncStore {
  MangaSyncStore({
    required WebDavService webDav,
    required SettingsService settings,
    required File Function(String mangaId) coverFile,
  }) : _webDav = webDav,
       _settings = settings,
       _coverFile = coverFile;

  final WebDavService _webDav;
  final SettingsService _settings;
  final File Function(String mangaId) _coverFile;

  static const format = 'wmp_manga_library_index';
  static const progressName = 'progress.json';
  static const defaultMangasPerShard = 500;

  String dirPath() {
    final root = _settings.mangaLibraryRemotePath;
    return root.endsWith('/') ? root.substring(0, root.length - 1) : root;
  }

  String get _indexPath => '${dirPath()}/${LibrarySyncStore.indexName}';
  String get _progressPath => '${dirPath()}/$progressName';
  String get deviceId => _settings.deviceId;

  // --- manifest ---

  Future<LibraryManifest> readManifest(String dest) async {
    final empty = LibraryManifest(format: format);
    try {
      final bytes = await _webDav.readAsBytes(dest, _indexPath);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return empty;
      final json = Map<String, dynamic>.from(decoded);
      if (json['format'] != format) return empty;
      return LibraryManifest.fromJson(json, format: format);
    } catch (e) {
      if (LibrarySyncStore.isMissingError(e.toString().toLowerCase())) {
        return empty;
      }
      rethrow;
    }
  }

  Future<void> writeManifest(String dest, LibraryManifest m) async {
    m.updatedAt = DateTime.now().toUtc();
    await _webDav.ensureDirectory(dest, dirPath());
    await _webDav.writeBytes(
      dest,
      _indexPath,
      Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(m.toJson())),
      ),
    );
  }

  // --- read ---

  final Set<String> lastReadParts = <String>{};
  CloudMangaLibrary lastCloud = const CloudMangaLibrary(
    rows: [],
    tombstonedKeys: {},
  );

  Future<CloudMangaLibrary> readCloud(
    String dest,
    LibraryManifest manifest, {
    bool fetchCovers = true,
    Set<String> skipFiles = const {},
  }) async {
    lastReadParts.clear();
    final dataParts = <List<MangaSyncRow>>[];
    final tombParts = <List<Map<String, dynamic>>>[];
    for (final part in [
      ...manifest.shards.map((s) => s.file),
      ...manifest.segments.map((s) => s.file),
    ]) {
      if (skipFiles.contains(part)) continue;
      final bytes = await _readOrNull(dest, part);
      lastReadParts.add(part);
      if (bytes == null) continue;
      final decoded = MangaShardCodec.decode(bytes);
      if (fetchCovers) {
        for (var i = 0; i < decoded.rows.length; i++) {
          final blob = decoded.coverFor(i);
          if (blob != null && blob.isNotEmpty) {
            await _storeCover(decoded.rows[i].manga.id, blob);
          }
        }
      }
      dataParts.add(decoded.rows);
    }
    for (final part in manifest.tombstones) {
      if (skipFiles.contains(part.file)) continue;
      lastReadParts.add(part.file);
      final bytes = await _readOrNull(dest, part.file);
      if (bytes == null) continue;
      tombParts.add(MangaShardCodec.decode(bytes).tombstones);
    }
    lastCloud = mergeMangaCloudParts(
      dataParts: dataParts,
      tombstoneParts: tombParts,
    );
    return lastCloud;
  }

  Future<Uint8List?> _readOrNull(String dest, String file) async {
    try {
      return await _webDav.readAsBytes(dest, '${dirPath()}/$file');
    } catch (e) {
      if (LibrarySyncStore.isMissingError(e.toString().toLowerCase())) {
        return null;
      }
      rethrow;
    }
  }

  /// Keep an existing local cover; only fill a missing one.
  Future<void> _storeCover(String mangaId, Uint8List blob) async {
    try {
      final file = _coverFile(mangaId);
      if (file.existsSync()) return;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(blob, flush: true);
    } catch (_) {
      // A cover is optional; the row still syncs.
    }
  }

  Future<List<Uint8List?>> _coverBlobs(List<MangaSyncRow> rows) async {
    final out = <Uint8List?>[];
    for (final r in rows) {
      Uint8List? blob;
      try {
        final f = _coverFile(r.manga.id);
        if (f.existsSync()) blob = await f.readAsBytes();
      } catch (_) {
        blob = null;
      }
      out.add(blob);
    }
    return out;
  }

  // --- append ---

  Future<LibraryManifest> appendDelta({
    required String dest,
    required List<MangaSyncRow> changed,
    bool withCovers = true,
  }) async {
    if (changed.isEmpty) return readManifest(dest);
    final revs = [for (final r in changed) r.rev];
    final from = revs.reduce(min);
    final to = revs.reduce(max);
    final bytes = MangaShardCodec.encodeMangaShard(
      kind: WmpKind.seg,
      deviceId: deviceId,
      revFrom: from,
      revTo: to,
      rows: changed,
      coverBlobs: withCovers ? await _coverBlobs(changed) : null,
    );
    final file = _partName(LibrarySyncStore.segmentPrefix, from);
    await _webDav.ensureDirectory(dest, dirPath());
    await _webDav.writeBytes(dest, '${dirPath()}/$file', bytes);
    final latest = await readManifest(dest);
    latest.segments.add(
      IndexPart(
        file: file,
        from: from,
        to: to,
        count: changed.length,
        bytes: bytes.length,
      ),
    );
    await writeManifest(dest, latest);
    return latest;
  }

  Future<LibraryManifest> appendTombstones({
    required String dest,
    required List<Map<String, dynamic>> tombstones,
  }) async {
    if (tombstones.isEmpty) return readManifest(dest);
    final entries = [
      for (final row in tombstones)
        (
          sourceName: row['source_name'] as String? ?? '',
          remotePath: row['remote_path'] as String? ?? '',
          rev: (row['rev'] as num?)?.toInt() ?? 0,
          deletedAt:
              DateTime.tryParse(row['deleted_at'] as String? ?? '') ??
              DateTime.now(),
        ),
    ];
    final revs = [for (final e in entries) e.rev];
    final from = revs.reduce(min);
    final to = revs.reduce(max);
    final bytes = LibraryShardCodec.encodeTombShard(
      deviceId: deviceId,
      revFrom: from,
      revTo: to,
      tombstones: entries,
    );
    final file = _partName(LibrarySyncStore.tombPrefix, from);
    await _webDav.ensureDirectory(dest, dirPath());
    await _webDav.writeBytes(dest, '${dirPath()}/$file', bytes);
    final latest = await readManifest(dest);
    latest.tombstones.add(
      IndexPart(
        file: file,
        from: from,
        to: to,
        count: entries.length,
        bytes: bytes.length,
      ),
    );
    await writeManifest(dest, latest);
    return latest;
  }

  // --- rebuild ---

  Future<RebuildEstimate> estimate({
    required List<MangaSyncRow> rows,
    required int perShard,
    required bool withCovers,
  }) async {
    final size = perShard.clamp(50, 5000);
    final shards = rows.isEmpty ? 0 : ((rows.length + size - 1) ~/ size);
    final sample = rows.take(size).toList();
    final bytes = MangaShardCodec.encodeMangaShard(
      kind: WmpKind.base,
      deviceId: deviceId,
      revFrom: 0,
      revTo: 0,
      rows: sample,
      coverBlobs: withCovers ? await _coverBlobs(sample) : null,
    ).length;
    return RebuildEstimate(
      shards: shards,
      bytes: libraryTrackCountForEstimate(
        shards: shards,
        perShardSampleBytes: bytes,
        sampleCount: sample.length,
        total: rows.length,
      ),
      withCovers: withCovers,
    );
  }

  Future<LibraryManifest> rebuild({
    required String dest,
    required List<MangaSyncRow> rows,
    int perShard = defaultMangasPerShard,
    bool withCovers = true,
  }) async {
    final size = perShard.clamp(50, 5000);
    final previous = await readManifest(dest);
    await _webDav.ensureDirectory(dest, dirPath());
    final slices = chunkMangaRowsForRebuild(rows, perShard: size);
    final shards = <BaseShard>[];
    var maxRev = 0;
    for (var i = 0; i < slices.length; i++) {
      final slice = slices[i];
      for (final r in slice) {
        if (r.rev > maxRev) maxRev = r.rev;
      }
      final bytes = MangaShardCodec.encodeMangaShard(
        kind: WmpKind.base,
        deviceId: deviceId,
        revFrom: 0,
        revTo: 0,
        rows: slice,
        coverBlobs: withCovers ? await _coverBlobs(slice) : null,
      );
      final file =
          '${LibrarySyncStore.shardPrefix}'
          '${(i + 1).toString().padLeft(4, '0')}-${_rand()}.wdmm';
      await _webDav.writeBytes(dest, '${dirPath()}/$file', bytes);
      shards.add(
        BaseShard(file: file, count: slice.length, bytes: bytes.length),
      );
    }
    final manifest = LibraryManifest(
      baseUpTo: maxRev,
      shards: shards,
      format: format,
    );
    await writeManifest(dest, manifest);
    for (final old in [
      ...previous.shards.map((s) => s.file),
      ...previous.segments.map((s) => s.file),
      ...previous.tombstones.map((s) => s.file),
    ]) {
      if (shards.any((s) => s.file == old)) continue;
      try {
        await _webDav.deletePath(dest, '${dirPath()}/$old');
      } catch (_) {}
    }
    return manifest;
  }

  // --- audit ---

  Future<LibraryAudit> audit(String dest) async {
    final manifest = await readManifest(dest);
    final present = <({String name, int size})>[];
    try {
      for (final item in await _webDav.listDirectory(dest, dirPath())) {
        if (item.isDirectory) continue;
        present.add((name: item.name, size: item.size ?? 0));
      }
    } catch (_) {}
    return auditLibraryParts(present: present, manifest: manifest);
  }

  Future<int> deleteOrphans(String dest, LibraryAudit audit) async {
    var n = 0;
    for (final name in audit.orphans) {
      try {
        await _webDav.deletePath(dest, '${dirPath()}/$name');
        n++;
      } catch (_) {}
    }
    return n;
  }

  // --- progress ---

  Future<List<MangaProgress>> readProgress(String dest) async {
    try {
      return decodeMangaProgressDoc(
        await _webDav.readAsBytes(dest, _progressPath),
      );
    } catch (e) {
      if (LibrarySyncStore.isMissingError(e.toString().toLowerCase())) {
        return const [];
      }
      rethrow;
    }
  }

  Future<void> writeProgress(
    String dest,
    Iterable<MangaProgress> entries,
  ) async {
    await _webDav.ensureDirectory(dest, dirPath());
    await _webDav.writeBytes(
      dest,
      _progressPath,
      encodeMangaProgressDoc(entries, deviceId: deviceId),
    );
  }

  String _partName(String prefix, int rev) {
    final stamp = rev > 0 ? rev : DateTime.now().millisecondsSinceEpoch;
    return '$prefix$stamp-${_rand()}.wdmm';
  }

  static String _rand() =>
      Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
}
