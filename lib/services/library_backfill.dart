import '../models/file_type_config.dart';
import '../models/music_library_backfill_root.dart';
import '../models/queue_task.dart';
import '../utils/directory_walk.dart';
import '../utils/remote_path.dart';
import '../utils/scan_candidates.dart';
import 'accounts_service.dart';
import 'library_service.dart';
import 'settings_service.dart';
import 'task_queue_service.dart';
import 'webdav_service.dart';

/// True when auto-backfill may run a play-triggered shallow scrape.
///
/// Play-time shallow scrape is always on while auto mode is enabled (no
/// separate on-play preference).
bool shouldPlayTriggerBackfill(SettingsService settings) {
  return settings.musicLibraryAutoBackfill;
}

/// Whether [remotePath] is under a bound root for [accountId].
///
/// Root `/` matches the whole account. Empty roots → no match when bind is on.
bool remotePathMatchesBoundRoot({
  required String accountId,
  required String remotePath,
  required List<MusicLibraryBackfillRoot> roots,
}) {
  for (final root in roots) {
    if (root.accountId != accountId) continue;
    if (_pathUnderRoot(remotePath, root.path)) return true;
  }
  return false;
}

bool _pathUnderRoot(String remotePath, String rootPath) {
  final path = _normPath(remotePath);
  final root = _normPath(rootPath);
  if (root == '/') return true;
  return path == root || path.startsWith('$root/');
}

String _normPath(String path) {
  if (path.isEmpty || path == '/') return '/';
  var p = path.startsWith('/') ? path : '/$path';
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/// Gate for play-start shallow scrape (mode + on-play + optional bind filter).
bool shouldBackfillForPlayingTrack({
  required SettingsService settings,
  required String accountId,
  required String remotePath,
}) {
  if (!shouldPlayTriggerBackfill(settings)) return false;
  if (!settings.musicLibraryBackfillBindRoots) return true;
  return remotePathMatchesBoundRoot(
    accountId: accountId,
    remotePath: remotePath,
    roots: settings.musicLibraryBackfillRoots,
  );
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

/// Play-start: list **one level** of the track's parent dir; enqueue scrape for
/// paths missing from the local library. Scrape only — no download/copy.
///
/// Enqueues a scrape when missing siblings exist.
///
/// Returns the queued [QueueTask], or null when gated / nothing missing /
/// already scanning.
Future<QueueTask?> enqueuePlayTriggeredShallowScrape({
  required SettingsService settings,
  required AccountsService accounts,
  required LibraryService library,
  required WebDavService webDav,
  required TaskQueueService queue,
  required String accountId,
  required String sourceName,
  required String remotePath,
}) async {
  if (!shouldBackfillForPlayingTrack(
    settings: settings,
    accountId: accountId,
    remotePath: remotePath,
  )) {
    return null;
  }
  final parent = remoteParent(remotePath) ?? '/';
  final src = sourceName.trim();
  if (src.isEmpty || accountId.isEmpty) return null;
  if (hasActiveScanForRoot(
    queue: queue,
    sourceName: src,
    remotePath: parent,
  )) {
    return null;
  }

  bool isMusic(String name) =>
      settings.fileTypes.categoryFor(name) == FileCategory.music;
  bool isCue(String name) =>
      settings.fileTypes.categoryFor(name) == FileCategory.cue;

  // Shallow: current directory only (no recursive children).
  const walk = WalkOptions(includeSubdirs: false, maxDepth: 0);

  List<ScanPathEntry> listed;
  try {
    listed = await listScanPaths(
      webDav: webDav,
      accountId: accountId,
      rootPath: parent,
      rootIsFile: false,
      walk: walk,
      isMusic: isMusic,
      isCue: isCue,
    );
  } catch (_) {
    return null;
  }
  if (listed.isEmpty) return null;

  final existing = <String>{
    for (final t in library.tracksForSource(src)) t.remotePath,
  };
  final missing = [
    for (final e in listed)
      if (!existing.contains(e.path)) e,
  ];
  if (missing.isEmpty) return null;

  final fileName = parent == '/'
      ? '/'
      : parent.split('/').where((s) => s.isNotEmpty).last;
  return queue.enqueueScan(
    sourceName: src,
    remotePath: parent,
    fileName: fileName,
    unitsTotal: missing.length,
    paths: missing,
  );
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
