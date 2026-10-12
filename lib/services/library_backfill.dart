import '../models/file_type_config.dart';
import '../models/music_library_backfill_root.dart';
import '../models/queue_task.dart';
import '../utils/scan_candidates.dart';
import 'accounts_service.dart';
import 'settings_service.dart';
import 'task_queue_service.dart';
import 'webdav_service.dart';

/// True when auto-backfill may enqueue background scrape (mode + on-open + roots).
bool shouldAutoBackfillOnLibraryOpen(SettingsService settings) {
  if (!settings.musicLibraryAutoBackfill) return false;
  if (!settings.musicLibraryBackfillOnOpen) return false;
  return settings.musicLibraryBackfillRoots.isNotEmpty;
}

/// Whether a scan for [sourceName]+[remotePath] is already pending/active.
bool hasActiveScanForRoot({
  required TaskQueueService queue,
  required String sourceName,
  required String remotePath,
}) {
  for (final t in queue.tasks) {
    if (t.kind != TaskKind.scan) continue;
    if (t.status != TaskStatus.pending && t.status != TaskStatus.active) {
      continue;
    }
    if (t.sourceName == sourceName && t.remotePath == remotePath) return true;
  }
  return false;
}

/// Enqueue incremental scrapes for each bound root. Returns how many tasks queued.
///
/// Explicit network-library folder scan is unrelated — call sites gate this with
/// [shouldAutoBackfillOnLibraryOpen]. Does not download/copy; scrape only.
Future<int> enqueueAutoBackfillScans({
  required SettingsService settings,
  required AccountsService accounts,
  required WebDavService webDav,
  required TaskQueueService queue,
}) async {
  if (!settings.musicLibraryAutoBackfill) return 0;
  final roots = settings.musicLibraryBackfillRoots;
  if (roots.isEmpty) return 0;

  final walk = settings.mediaScanWalkOptions;
  bool isMusic(String name) =>
      settings.fileTypes.categoryFor(name) == FileCategory.music;
  bool isCue(String name) =>
      settings.fileTypes.categoryFor(name) == FileCategory.cue;

  var queued = 0;
  for (final root in roots) {
    final account = accounts.accountById(root.accountId);
    if (account == null) continue;
    final sourceName = account.name.trim();
    if (sourceName.isEmpty) continue;
    if (hasActiveScanForRoot(
      queue: queue,
      sourceName: sourceName,
      remotePath: root.path,
    )) {
      continue;
    }

    List<ScanPathEntry> paths;
    try {
      paths = await listScanPaths(
        webDav: webDav,
        accountId: root.accountId,
        rootPath: root.path,
        rootIsFile: false,
        walk: walk,
        isMusic: isMusic,
        isCue: isCue,
      );
    } catch (_) {
      continue;
    }
    if (paths.isEmpty) continue;

    final fileName = root.path == '/'
        ? '/'
        : root.path.split('/').where((s) => s.isNotEmpty).last;
    await queue.enqueueScan(
      sourceName: sourceName,
      remotePath: root.path,
      fileName: fileName,
      unitsTotal: paths.length,
      paths: paths,
    );
    queued++;
  }
  return queued;
}

/// Display label for a bound root row (account name + path).
String backfillRootLabel({
  required MusicLibraryBackfillRoot root,
  required AccountsService accounts,
  required String Function(String name) localizeAccountName,
}) {
  final account = accounts.accountById(root.accountId);
  final name = account == null
      ? root.accountId
      : localizeAccountName(account.name);
  return '$name · ${root.path}';
}
