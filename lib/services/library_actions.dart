import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../utils/app_snack.dart';
import '../widgets/tag_refresh_progress_dialog.dart';

import 'package:share_plus/share_plus.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/library_track.dart';
import '../models/queue_models.dart';
import '../models/webdav_item.dart';
import '../models/playlist.dart';
import '../providers/app_state.dart';
import '../screens/playlists_screen.dart';
import '../theme/app_theme.dart';
import '../utils/audio_extensions.dart';
import '../utils/cue_sheet.dart';
import '../utils/track_identity.dart';
import '../widgets/destroy_progress_dialog.dart';
import 'accounts_service.dart';
import 'cache_service.dart';
import 'library_service.dart';
import 'queue_service.dart';
import 'platform_export_service.dart';
import 'settings_service.dart';
import 'share_rename_service.dart';
import 'webdav_service.dart';

/// Whether the track's audio is local: derived cache file exists on disk.
String unboundSourceMessage(AppLocalizations l10n, String sourceName) =>
    l10n.unboundSource(sourceName);

bool libraryTrackIsLocal(CacheService cache, LibraryTrack track) {
  return cache.isLocalTrack(track);
}

/// Row state for one `(source, remote)` pair, derived from the Rust queue rows.
///
/// This replaces the retired Dart executor's `uiStateFor`. State precedence:
/// playing → in-flight (queued/downloading) → error → on-disk ready →
/// streamable (library rows) → remote (no chip in the network browser).
TrackUiState queueTrackUiState({
  required QueueService queue,
  required CacheService cache,
  required String sourceName,
  required String remotePath,
  String? playingRemotePath,
  String? playingSourceName,
  bool libraryRow = false,
}) {
  if (playingRemotePath == remotePath && playingSourceName == sourceName) {
    return TrackUiState.playing;
  }
  final task = queue.taskForRemote(sourceName, remotePath);
  if (task != null) {
    switch (task.status) {
      case QueueTaskStatus.pending:
        return TrackUiState.queued;
      case QueueTaskStatus.active:
        return TrackUiState.downloading;
      case QueueTaskStatus.failed:
      case QueueTaskStatus.partial:
      case QueueTaskStatus.cancelled:
        return TrackUiState.error;
      case QueueTaskStatus.completed:
        if (task.isPublic) return TrackUiState.ready;
        break;
      case QueueTaskStatus.awaitingPlatform:
        break;
    }
  }
  final cached = cache.fileForRemote(remotePath, sourceName: sourceName);
  if (cached.existsSync()) return TrackUiState.ready;
  final local = task?.localPath;
  if (task?.status == QueueTaskStatus.completed &&
      local != null &&
      File(local).existsSync()) {
    return TrackUiState.ready;
  }
  if (libraryRow) return TrackUiState.streamable;
  return TrackUiState.remote;
}

/// Re-read tags from an already-cached file. A CUE selection refreshes its
/// whole virtual album so cue-file metadata keeps precedence over audio tags.
Future<bool> refreshCachedTrackTags({
  required CacheService cache,
  required LibraryService library,
  required LibraryTrack track,
}) async {
  if (!track.isCueVirtual) {
    final localPath = await cache.localPathForTrack(track);
    if (localPath == null) return false;
    await library.refreshTrackTagsFromFile(
      track: track,
      localPath: localPath,
    );
    return true;
  }
  final cuePath = track.cueRemotePath;
  if (cuePath == null) return false;
  final cueLocal = await cache.localPathIfCached(
    cuePath,
    sourceName: track.sourceName,
  );
  if (cueLocal == null) return false;
  final sheet = CueSheet.parseOrNull(
    decodeCueText(await File(cueLocal).readAsBytes()),
  );
  if (sheet == null) return false;
  final audioPaths = sheet.audioRemotePaths(cuePath);
  for (final path in audioPaths) {
    if (!await cache.isCached(path, sourceName: track.sourceName)) {
      return false;
    }
  }
  final groupId =
      track.cacheGroupId ?? cueCacheGroupId(track.sourceName, cuePath);
  await library.ingestCueAlbum(
    sourceName: track.sourceName,
    cueRemotePath: cuePath,
    sheet: sheet,
    cacheGroupId: groupId,
    localPathFor: (remote) =>
        cache.fileForRemote(remote, sourceName: track.sourceName).path,
  );
  for (final path in audioPaths) {
    final file = cache.fileForRemote(path, sourceName: track.sourceName);
    if (file.existsSync()) {
      await cache.registerCompleted(
        track.sourceName,
        path,
        file.path,
        cacheGroupId: groupId,
      );
    }
  }
  return true;
}

/// Queue every member of a CUE album (the `.cue` sheet plus its backing audio)
/// and bind them to one cache group. Returns the sheet's track count.
///
/// Members are offered as ordinary cache downloads; the queue owns retry and
/// progress, and the group binding is what later maps "one album" back to the
/// files on disk.
Future<int> enqueueCueGroup(
  BuildContext context, {
  required String sourceName,
  required String cueRemotePath,
  CueSheet? preParsed,
}) async {
  final queue = context.read<QueueService>();
  final cache = context.read<CacheService>();
  final webDav = context.read<WebDavService>();
  final accounts = context.read<AccountsService>();
  CueSheet sheet;
  if (preParsed != null) {
    sheet = preParsed;
  } else {
    final accountId = accounts.idForSource(sourceName);
    if (accountId == null) {
      throw StateError('err.sourceUnbound|$sourceName');
    }
    final bytes = await webDav.readAsBytes(accountId, cueRemotePath);
    final parsed = CueSheet.parseOrNull(decodeCueText(bytes));
    if (parsed == null) throw StateError('err.cueMalformed');
    sheet = parsed;
  }
  final groupId = cueCacheGroupId(sourceName, cueRemotePath);
  final paths = <String>[
    cueRemotePath,
    ...sheet.audioRemotePaths(cueRemotePath),
  ];
  final wanted = paths.toSet();
  for (final path in paths) {
    await cache.bindCacheGroup(
      sourceName: sourceName,
      remotePath: path,
      groupId: groupId,
    );
  }
  // Drop stale cancelled/failed members (or rows outside this sheet) so member
  // counts stay stable across a cache clear + re-download.
  for (final task in queue.tasks.toList()) {
    if (task.cacheGroupId != groupId) continue;
    final dead =
        task.status == QueueTaskStatus.cancelled ||
        task.status == QueueTaskStatus.failed ||
        !wanted.contains(task.remotePath);
    if (dead) await queue.remove(task.id);
  }
  for (final path in paths) {
    await queue.ensureQueued(
      sourceName,
      path,
      fileName: p.basename(path),
      cacheGroupId: groupId,
    );
  }
  return sheet.tracks.length;
}

/// List-row UI state shared by music library and playlist detail.
///
/// Overlays [LibraryTrack.remoteMissing] as a red-dot state unless the row is
/// already playing / downloading / queued. Ready and streamable stay icon-dot
/// only (no text chip).
TrackUiState libraryRowUiState({
  required QueueService queue,
  required CacheService cache,
  required LibraryTrack track,
  String? playingRemotePath,
  String? playingSourceName,
  bool entryRemoteMissing = false,
}) {
  var state = queueTrackUiState(
    queue: queue,
    cache: cache,
    sourceName: track.sourceName,
    remotePath: track.effectiveAudioRemotePath,
    playingRemotePath: playingRemotePath,
    playingSourceName: playingSourceName,
    libraryRow: true,
  );
  final missing = track.remoteMissing || entryRemoteMissing;
  if (missing &&
      state != TrackUiState.playing &&
      state != TrackUiState.downloading &&
      state != TrackUiState.queued) {
    state = TrackUiState.remoteMissing;
  }
  return state;
}

/// Build a [TrackInfo] for [AudioPlayerService.playTrack] from a library row.
TrackInfo libraryTrackToTrackInfo(
  LibraryTrack track,
  String? local,
  String accountId,
) {
  return TrackInfo(
    sourceName: track.sourceName,
    accountId: accountId,
    remotePath: track.remotePath,
    fileName: track.fileName,
    localPath: local,
    title: track.title,
    artist: track.artist,
    albumArtist: track.albumArtist,
    album: track.album,
    duration: track.durationMs != null
        ? Duration(milliseconds: track.durationMs!)
        : null,
    trackNumber: track.trackNumber,
    trackTotal: track.trackTotal,
    discNumber: track.discNumber,
    discTotal: track.discTotal,
    year: track.year,
    genre: track.genre,
    bitrate: track.bitrate,
    sampleRate: track.sampleRate,
    coverPath: null,
    cueRemotePath: track.cueRemotePath,
    cueTrackIndex: track.cueTrackIndex,
    audioRemotePath: track.audioRemotePath,
    clipStart: track.clipStartMs != null
        ? Duration(milliseconds: track.clipStartMs!)
        : null,
    clipEnd: track.clipEndMs != null
        ? Duration(milliseconds: track.clipEndMs!)
        : null,
    cacheGroupId: track.cacheGroupId,
  );
}

Future<bool> refreshOneLibraryTrackTags(
  BuildContext context,
  LibraryTrack track,
) async => refreshCachedTrackTags(
  cache: context.read<CacheService>(),
  library: context.read<LibraryService>(),
  track: track,
);

Future<({int updated, int skipped, int failed, bool cancelled})>
refreshLibraryTrackTags(
  BuildContext context,
  List<LibraryTrack> tracks, {
  bool showProgressDialog = true,
}) async {
  final unique = <String, LibraryTrack>{};
  for (final track in tracks) {
    final key = track.isCueVirtual && track.cueRemotePath != null
        ? '${track.sourceName}:${track.cueRemotePath}'
        : '${track.sourceName}:${track.effectiveAudioRemotePath}';
    unique.putIfAbsent(key, () => track);
  }
  final items = unique.values.toList();
  final cache = context.read<CacheService>();
  final library = context.read<LibraryService>();
  var updated = 0;
  var skipped = 0;
  var failed = 0;
  var cancelled = false;

  Future<void> run(
    void Function(int processed, String currentName) onProgress,
    bool Function() isCancelled,
  ) async {
    for (var i = 0; i < items.length; i++) {
      if (isCancelled()) {
        cancelled = true;
        break;
      }
      final track = items[i];
      onProgress(i, track.displayTitle);
      try {
        if (await refreshCachedTrackTags(
          cache: cache,
          library: library,
          track: track,
        )) {
          updated++;
        } else {
          skipped++;
        }
      } catch (_) {
        failed++;
      }
      onProgress(i + 1, track.displayTitle);
    }
  }

  if (showProgressDialog && context.mounted) {
    final result = await showTagRefreshProgress(
      context,
      names: items.map((t) => t.displayTitle).toList(),
      run: (onProgress, isCancelled) async {
        await run(onProgress, isCancelled);
        return (updated: updated, skipped: skipped, failed: failed);
      },
    );
    cancelled = result.cancelled;
  } else {
    await run((_, _) {}, () => false);
  }
  return (
    updated: updated,
    skipped: skipped,
    failed: failed,
    cancelled: cancelled,
  );
}

Future<int> downloadUncachedLibraryTracks(
  BuildContext context,
  List<LibraryTrack> tracks,
) async {
  final cache = context.read<CacheService>();
  final accounts = context.read<AccountsService>();
  final queue = context.read<QueueService>();
  final seen = <String>{};
  var queued = 0;
  var unavailable = 0;
  for (final track in tracks) {
    final key = track.isCueVirtual && track.cueRemotePath != null
        ? '${track.sourceName}:${track.cueRemotePath}'
        : '${track.sourceName}:${track.effectiveAudioRemotePath}';
    if (!seen.add(key) || libraryTrackIsLocal(cache, track)) continue;
    if (!accounts.isSourceBound(track.sourceName)) {
      unavailable++;
      continue;
    }
    try {
      if (track.isCueVirtual && track.cueRemotePath != null) {
        await enqueueCueGroup(
          context,
          sourceName: track.sourceName,
          cueRemotePath: track.cueRemotePath!,
        );
        queued++;
      } else if (await queue.ensureQueued(
        track.sourceName,
        track.effectiveAudioRemotePath,
        fileName: track.fileName,
      )) {
        queued++;
      }
    } catch (_) {
      unavailable++;
    }
  }
  if (context.mounted) {
    AppSnack.show(
      context,
      '${AppLocalizations.of(context)!.libQueuedCount(queued)}${unavailable > 0 ? ', ${AppLocalizations.of(context)!.libQueuedUnavailable(unavailable)}' : ''}',
      error: unavailable > 0 && queued == 0,
    );
  }
  return queued;
}

/// Enqueue download for a non-local library track (CUE group or single file).
/// Does not start playback or tag reading.
Future<void> enqueueLibraryTrackDownload(
  BuildContext context,
  LibraryTrack track, {
  bool showSnack = true,
}) async {
  // The row is bound to a disk **name**; without a local account for that name
  // there is nothing to download from. Say so instead of silently doing nothing.
  final accounts = context.read<AccountsService>();
  if (!accounts.isSourceBound(track.sourceName)) {
    if (context.mounted) {
      AppSnack.error(
        context,
        unboundSourceMessage(AppLocalizations.of(context)!, track.sourceName),
      );
    }
    return;
  }
  final queue = context.read<QueueService>();
  if (track.isCueVirtual && track.cueRemotePath != null) {
    unawaited(
      enqueueCueGroup(
        context,
        sourceName: track.sourceName,
        cueRemotePath: track.cueRemotePath!,
      ),
    );
  } else {
    unawaited(
      queue.ensureQueued(
        track.sourceName,
        track.effectiveAudioRemotePath,
        fileName: track.fileName,
      ),
    );
  }
  if (showSnack && context.mounted) {
    AppSnack.show(context, AppLocalizations.of(context)!.libQueuedAdded);
  }
}

/// Add one or more library tracks to a playlist (Chinese UI).
Future<void> addTracksToPlaylist(
  BuildContext context,
  List<LibraryTrack> tracks,
) async {
  if (tracks.isEmpty) return;
  final entries = tracks
      .map(
        (t) => PlaylistEntry(
          sourceName: t.sourceName,
          remotePath: t.remotePath,
          musicId: t.musicId,
          title: t.displayTitle,
          durationMs: t.durationMs,
          cueTrackIndex: t.cueTrackIndex,
        ),
      )
      .toList();
  if (entries.length == 1) {
    await showAddToPlaylistDialog(context, entries.first);
    return;
  }
  await showAddManyToPlaylistDialog(context, entries);
}

/// Delete local audio cache for [tracks], with CUE group warnings.
Future<void> deleteTracksLocalCache(
  BuildContext context,
  List<LibraryTrack> tracks,
) async {
  if (tracks.isEmpty) return;
  final cache = context.read<CacheService>();

  // Collapse CUE virtual members into unique cache groups.
  final groupIds = <String>{};
  final plain = <LibraryTrack>[];
  for (final t in tracks) {
    final gid =
        t.cacheGroupId ??
        (t.cueRemotePath != null
            ? cueCacheGroupId(t.sourceName, t.cueRemotePath!)
            : null);
    if (t.isCueVirtual && gid != null) {
      groupIds.add(gid);
    } else {
      plain.add(t);
    }
  }

  if (groupIds.isNotEmpty) {
    final names = <String>{};
    for (final gid in groupIds) {
      var n = await cache.groupMemberFileNames(gid);
      if (n.isEmpty) {
        for (final t in tracks.where(
          (x) =>
              (x.cacheGroupId ??
                  (x.cueRemotePath != null
                      ? cueCacheGroupId(x.sourceName, x.cueRemotePath!)
                      : null)) ==
              gid,
        )) {
          if (t.cueRemotePath != null) names.add(p.basename(t.cueRemotePath!));
          if (t.audioRemotePath != null) {
            names.add(p.basename(t.audioRemotePath!));
          }
        }
      } else {
        names.addAll(n);
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          groupIds.length == 1
              ? AppLocalizations.of(ctx)!.cueGroupDeleteTitle
              : AppLocalizations.of(ctx)!.cueGroupDeleteTitleMulti,
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                groupIds.length == 1
                    ? AppLocalizations.of(ctx)!.cueGroupDeleteBodyIntro
                    : AppLocalizations.of(ctx)!
                          .cueGroupDeleteBodyIntroCount(groupIds.length),
              ),
              const SizedBox(height: 8),
              for (final n in names.take(40)) Text('• $n'),
              if (names.length > 40)
                Text(AppLocalizations.of(ctx)!.moreFilesCount(names.length)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(ctx)!.cueGroupDeleteWhole),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    var n = 0;
    for (final gid in groupIds) {
      n += await cache.deleteCacheGroup(gid);
    }
    if (!context.mounted) return;
    AppSnack.show(context, AppLocalizations.of(context)!.cueGroupDeleted(n));
  }

  if (plain.isEmpty) return;
  // Deduplicate by audio path.
  final seen = <String>{};
  final unique = <LibraryTrack>[];
  for (final t in plain) {
    final key = '${t.sourceName}\u0000${t.effectiveAudioRemotePath}';
    if (seen.add(key)) unique.add(t);
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(AppLocalizations.of(ctx)!.cacheDeleteTitle),
      content: Text(
        unique.length == 1
            ? AppLocalizations.of(ctx)!.cacheDeleteBodyOne(
                p.basename(unique.first.effectiveAudioRemotePath),
              )
            : AppLocalizations.of(ctx)!.cacheDeleteBodyMany(unique.length),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(AppLocalizations.of(ctx)!.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(AppLocalizations.of(ctx)!.delete),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  var removed = 0;
  for (final t in unique) {
    if (await cache.deleteLocalFile(
      sourceName: t.sourceName,
      remotePath: t.effectiveAudioRemotePath,
    )) {
      removed++;
    }
  }
  if (!context.mounted) return;
  AppSnack.show(
    context,
    AppLocalizations.of(context)!.cacheDeletedCount(removed),
  );
}

/// Destroy tracks: delete their audio cache, remove them from the music
/// library and drop their metadata + cached cover art.
///
/// This is the destructive counterpart of [deleteTracksLocalCache] (which only
/// removes cached audio and keeps tags/covers).
Future<void> destroyLibraryTracks(
  BuildContext context,
  List<LibraryTrack> tracks,
) async {
  if (tracks.isEmpty) return;
  final cache = context.read<CacheService>();
  final app = context.read<AppState>();
  // 展开成「实际会被销毁的全集」：CUE 分片点一片等于整张专辑，普通曲目就是自己。
  // 确认框与进度条的数字都按这个集合算，否则会出现「将删除 1 首」而实际删掉一整张。
  final all = app.destroyTargets(tracks);

  // CUE-sliced rows share one backing audio file; collapse the groups so the
  // confirmation lists files rather than virtual tracks.
  final groupIds = <String>{};
  final files = <String>{};
  for (final t in tracks) {
    final gid =
        t.cacheGroupId ??
        (t.cueRemotePath != null
            ? cueCacheGroupId(t.sourceName, t.cueRemotePath!)
            : null);
    if (t.isCueVirtual && gid != null) {
      groupIds.add(gid);
      final members = await cache.groupMemberFileNames(gid);
      if (members.isEmpty) {
        files.add(p.basename(t.effectiveAudioRemotePath));
      } else {
        files.addAll(members);
      }
    } else {
      files.add(p.basename(t.effectiveAudioRemotePath));
    }
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(AppLocalizations.of(ctx)!.destroyTracksTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLocalizations.of(ctx)!.destroyTracksBody(all.length)),
            if (groupIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(AppLocalizations.of(ctx)!.destroyTracksCueNote),
              ),
            const SizedBox(height: 8),
            for (final n in files.take(30)) Text('• $n'),
            if (files.length > 30)
              Text(AppLocalizations.of(ctx)!.moreFilesCount(files.length)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(AppLocalizations.of(ctx)!.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(AppLocalizations.of(ctx)!.destroyAction),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  // 一首一首销毁：进度框走完（或用户终止）之后才回到这里。
  final destroyed = await showDestroyProgress(
    context,
    total: all.length,
    run: (onProgress, isCancelled) => app.destroyLibraryTracks(
      all,
      onProgress: onProgress,
      isCancelled: isCancelled,
    ),
  );

  if (!context.mounted) return;
  AppSnack.show(
    context,
    AppLocalizations.of(context)!.destroyedTracksCount(destroyed),
  );
}

/// Share already-cached **non-CUE** audio files via the system share sheet.
///
/// CUE-sliced rows are identified from the library DB via
/// [LibraryTrack.isCueVirtual] (`cue_remote_path` + `cue_track_index`).
/// Those tracks are never cropped/exported — sharing them only shows a
/// snackbar (`CUE 音轨不支持分享`).
///
/// When「基于标签重命名」is enabled (default `作者-标题`), the shared copy can be
/// renamed; a single file opens an editable rename dialog first.
Future<void> shareLibraryTracks(
  BuildContext context,
  List<LibraryTrack> tracks,
) async {
  if (tracks.isEmpty) return;
  final cache = context.read<CacheService>();
  final settings = context.read<SettingsService>();
  final localNonCue = <LibraryTrack>[];
  var cueCount = 0;
  var notLocalCount = 0;
  for (final t in tracks) {
    if (t.isCueVirtual) {
      cueCount++;
      continue;
    }
    if (libraryTrackIsLocal(cache, t)) {
      localNonCue.add(t);
    } else {
      notLocalCount++;
    }
  }

  if (localNonCue.isEmpty) {
    final String msg;
    if (cueCount > 0 && notLocalCount == 0) {
      msg = AppLocalizations.of(context)!.shareCueUnsupported;
    } else if (cueCount > 0) {
      msg = AppLocalizations.of(context)!.shareCueUnsupportedAndNotLocal;
    } else {
      msg = notLocalCount == 1
          ? AppLocalizations.of(context)!.shareNotLocalOne
          : AppLocalizations.of(context)!.shareNotLocalAll;
    }
    if (!context.mounted) return;
    AppSnack.error(context, msg);
    return;
  }

  if (cueCount > 0 && context.mounted) {
    AppSnack.show(
      context,
      cueCount == 1
          ? AppLocalizations.of(context)!.shareCueUnsupported
          : AppLocalizations.of(context)!.shareCueSkipped(cueCount),
    );
  }
  if (notLocalCount > 0 && context.mounted) {
    AppSnack.show(
      context,
      AppLocalizations.of(context)!.shareNotLocalSkipped(notLocalCount),
    );
  }

  final plan = <_SharePlan>[];
  for (final t in localNonCue) {
    final path = await cache.localPathIfCached(
      t.effectiveAudioRemotePath,
      sourceName: t.sourceName,
    );
    if (path == null) continue;
    final info = ShareRenameService.trackInfoForLibrary(t, localPath: path);
    final suggested = settings.shareTagRenameEnabled
        ? ShareRenameService.suggestedNameForTrack(info, settings)
        : p.basename(path);
    plan.add(_SharePlan(track: t, localPath: path, name: suggested));
  }
  if (plan.isEmpty) {
    if (!context.mounted) return;
    AppSnack.error(context, AppLocalizations.of(context)!.shareNothingToShare);
    return;
  }

  // Single file: let the user confirm / edit the (tag-derived) name.
  var applyRename = settings.shareTagRenameEnabled;
  if (plan.length == 1 && settings.shareTagRenameEnabled && context.mounted) {
    final edited = await _askShareName(context, plan.first, settings);
    if (edited == null) return; // cancelled
    if (edited.isEmpty) {
      applyRename = false; // user chose the original name
    } else {
      plan.first = plan.first.copyWith(name: edited);
    }
  } else if (plan.length == 1) {
    applyRename = false;
  }

  try {
    final built = await _materializeShareFiles(plan, rename: applyRename);
    if (built.files.isEmpty) {
      if (!context.mounted) return;
      AppSnack.error(
        context,
        AppLocalizations.of(context)!.shareNothingToShare,
      );
      return;
    }
    await SharePlus.instance.share(ShareParams(files: built.files));
    // Best-effort cleanup of the renamed copies.
    for (final path in built.tempPaths) {
      unawaited(File(path).delete().catchError((_) => File(path)));
    }
    if (!context.mounted) return;
    AppSnack.show(
      context,
      AppLocalizations.of(context)!.shareDoneCount(built.files.length),
    );
  } catch (e) {
    if (!context.mounted) return;
    AppSnack.error(
      context,
      AppLocalizations.of(context)!.shareFailed(e.toString()),
    );
  }
}

/// One file to share, with the name the user wants it to carry.
class _SharePlan {
  _SharePlan({
    required this.track,
    required this.localPath,
    required this.name,
  });

  final LibraryTrack track;
  final String localPath;
  final String name;

  _SharePlan copyWith({String? name}) =>
      _SharePlan(track: track, localPath: localPath, name: name ?? this.name);
}

/// Asks for the share file name, pre-filled with the tag-derived suggestion.
///
/// Returns the chosen name, `''` for "keep the original name", or null when
/// the user cancelled.
Future<String?> _askShareName(
  BuildContext context,
  _SharePlan plan,
  SettingsService settings,
) async {
  final controller = TextEditingController(
    text: p.basenameWithoutExtension(plan.name),
  );
  final ext = p.extension(plan.name);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      title: Text(AppLocalizations.of(ctx)!.shareNameTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(ctx)!.shareRenameTemplateHint,
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(ctx)!.fileNameLabel,
              helperText: AppLocalizations.of(ctx)!.shareExtFixed(ext),
              suffixText: ext,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            AppLocalizations.of(ctx)!
                .shareOriginalFile(p.basename(plan.localPath)),
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(AppLocalizations.of(ctx)!.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ''),
          child: Text(AppLocalizations.of(ctx)!.shareUseOriginalName),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            ctx,
            // The field holds the stem only; put the extension back.
            ShareRenameService.finalizeEditedName(controller.text, plan.name),
          ),
          child: Text(AppLocalizations.of(ctx)!.shareAction),
        ),
      ],
    ),
  );
}

/// Result of preparing the share payload.
class _ShareBundle {
  _ShareBundle(this.files, this.tempPaths);

  final List<XFile> files;

  /// Copies created only for renaming — deleted after the share sheet closes.
  final List<String> tempPaths;
}

/// Build [XFile]s for the share sheet, copying renamed files into a temp dir so
/// the cache file itself is never modified.
Future<_ShareBundle> _materializeShareFiles(
  List<_SharePlan> plan, {
  required bool rename,
}) async {
  final files = <XFile>[];
  final tempPaths = <String>[];
  Directory? tmpDir;
  for (final entry in plan) {
    final original = p.basename(entry.localPath);
    final wanted = rename ? sanitizeExportFileName(entry.name) : original;
    final mime = audioShareMimeFor(entry.localPath);
    if (!rename || wanted == original || wanted.isEmpty) {
      files.add(XFile(entry.localPath, mimeType: mime));
      continue;
    }
    tmpDir ??= await Directory(
      p.join((await getTemporaryDirectory()).path, 'share_rename'),
    ).create(recursive: true);
    final target = File(p.join(tmpDir.path, wanted));
    await File(entry.localPath).copy(target.path);
    tempPaths.add(target.path);
    files.add(XFile(target.path, mimeType: mime));
  }
  return _ShareBundle(files, tempPaths);
}
