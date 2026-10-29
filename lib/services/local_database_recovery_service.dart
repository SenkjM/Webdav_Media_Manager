import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cache_index_db.dart';
import 'platform_export_service.dart';
import 'playlist_store.dart';
import 'task_store.dart';
import 'download_destination_service.dart';

/// Emergency recovery for schema conflicts before normal services are usable.
///
/// The file list comes from the stores that own the files, never from a
/// directory scan: a store that renames its database is picked up here for
/// free, and [legacyFileNames] covers files older builds left behind.
class LocalDatabaseRecoveryService {
  const LocalDatabaseRecoveryService({this.destination});

  final DownloadDestinationService? destination;

  /// Names older builds used for stores that were renamed or dropped.
  ///
  /// `download_queue.db` became `task_queue.db` (56c02d3); the old file is
  /// still on upgraded devices and has to go when the user clears the data.
  static const legacyFileNames = <String>['download_queue.db'];

  /// SQLite keeps rollback journals next to the database; they are exported
  /// and deleted together with it.
  static const _suffixes = <String>['', '-wal', '-shm'];

  /// Every database file this app owns, journals included.
  static Future<List<File>> _files() async {
    final docs = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    final bases = <String>[
      p.join(docs.path, 'music_library.db'),
      p.join(docs.path, PlaylistStore.fileName),
      p.join(docs.path, TaskStore.fileName),
      // The cache index lives beside the cache it describes, not with the
      // library databases.
      p.join(support.path, CacheIndexDb.fileName),
      for (final name in legacyFileNames) p.join(docs.path, name),
    ];
    final files = <File>[];
    for (final base in bases) {
      for (final suffix in _suffixes) {
        final file = File('$base$suffix');
        if (await file.exists()) files.add(file);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<List<String>> databaseNames() async => (await _files())
      .map((file) => p.basename(file.path))
      .toList(growable: false);

  /// Export raw files, including SQLite journals needed for forensic recovery.
  Future<List<ExportResult>> exportAll() async {
    final files = await _files();
    final dest = destination;
    final exporter = const PlatformExportService();
    final results = <ExportResult>[];
    for (final file in files) {
      final ExportResult result;
      if (dest != null) {
        result = await dest.save(
          sourcePath: file.path,
          fileName: 'wmp_recovery_${p.basename(file.path)}',
          mimeType: 'application/octet-stream',
          mediaStoreSubdir: 'WebdavMediaManager/recovery',
          retryOnFallback: true,
        );
      } else {
        result = await exporter.saveToDownloads(
          sourcePath: file.path,
          fileName: 'wmp_recovery_${p.basename(file.path)}',
          mimeType: 'application/octet-stream',
          subdir: 'WebdavMediaManager/recovery',
        );
      }
      results.add(result);
    }
    return results;
  }

  /// Delete every database file.
  ///
  /// Returns the number removed plus the names that were still locked, so the
  /// caller can say so instead of reporting a complete wipe that never
  /// happened.
  Future<({int removed, List<String> failed})> clearAll() async {
    var removed = 0;
    final failed = <String>[];
    for (final file in await _files()) {
      try {
        await file.delete();
        removed++;
      } on FileSystemException {
        failed.add(p.basename(file.path));
      }
    }
    return (removed: removed, failed: failed);
  }
}
