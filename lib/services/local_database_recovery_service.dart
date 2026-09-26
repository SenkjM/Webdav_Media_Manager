import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'platform_export_service.dart';

/// Emergency recovery for schema conflicts before normal services are usable.
class LocalDatabaseRecoveryService {
  const LocalDatabaseRecoveryService();

  Future<List<File>> _files() async {
    final dir = await getApplicationDocumentsDirectory();
    if (!await dir.exists()) return const <File>[];
    final files = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (name.endsWith('.db') ||
          name.endsWith('.db-wal') ||
          name.endsWith('.db-shm')) {
        files.add(entity);
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
    final exporter = const PlatformExportService();
    final results = <ExportResult>[];
    for (final file in files) {
      results.add(
        await exporter.saveToDownloads(
          sourcePath: file.path,
          fileName: 'wmp_recovery_${p.basename(file.path)}',
          mimeType: 'application/octet-stream',
          subdir: 'WebdavMediaManager/recovery',
        ),
      );
    }
    return results;
  }

  Future<int> clearAll() async {
    var removed = 0;
    for (final file in await _files()) {
      try {
        await file.delete();
        removed++;
      } on FileSystemException {
        // A locked file is reported by the caller; never claim a complete wipe.
      }
    }
    return removed;
  }
}
