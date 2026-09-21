import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../utils/app_snack.dart';

import 'package:share_plus/share_plus.dart';

import '../models/library_track.dart';
import '../models/playlist.dart';
import '../screens/playlists_screen.dart';
import '../theme/app_theme.dart';
import '../utils/audio_extensions.dart';
import '../utils/track_identity.dart';
import 'accounts_service.dart';
import 'cache_service.dart';
import 'download_queue_service.dart';
import 'library_service.dart';
import 'platform_export_service.dart';
import 'settings_service.dart';
import 'share_rename_service.dart';

/// Whether the track's audio is local: cache annex + file on disk.
/// Shown when a library row is bound to a disk name that has no local account.
String unboundSourceMessage(String sourceName) =>
    '来源网盘未绑定（$sourceName）：请先在账号页添加或改名成这个名称的网盘';

/// Stale annex rows are cleared when the file is missing.
bool libraryTrackIsLocal(CacheService cache, LibraryTrack track) {
  return cache.isLocalTrack(track);
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
      AppSnack.error(context, unboundSourceMessage(track.sourceName));
    }
    return;
  }
  final downloads = context.read<DownloadQueueService>();
  if (track.isCueVirtual && track.cueRemotePath != null) {
    unawaited(
      downloads.enqueueCueGroup(
        sourceName: track.sourceName,
        cueRemotePath: track.cueRemotePath!,
      ),
    );
  } else {
    unawaited(
      downloads.ensureQueued(
        track.sourceName,
        track.effectiveAudioRemotePath,
        fileName: track.fileName,
      ),
    );
  }
  if (showSnack && context.mounted) {
    AppSnack.show(context, '已加入下载');
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
          title: t.displayTitle,
          durationMs: t.durationMs,
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
      var n = cache.groupMemberFileNames(gid);
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
        title: Text(groupIds.length == 1 ? '删除整个 CUE 缓存组？' : '删除多个 CUE 缓存组？'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                groupIds.length == 1
                    ? '将删除整组（CUE + 关联音频）：'
                    : '将删除 ${groupIds.length} 个 CUE 缓存组（CUE + 关联音频）：',
              ),
              const SizedBox(height: 8),
              for (final n in names.take(40)) Text('• $n'),
              if (names.length > 40) Text('…共 ${names.length} 个文件'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除整组'),
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
    AppSnack.show(context, '已删除 CUE 缓存组（$n 个文件）');
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
      title: const Text('删除本地音频缓存？'),
      content: Text(
        unique.length == 1
            ? '将删除「${p.basename(unique.first.effectiveAudioRemotePath)}」。元数据与封面保留。'
            : '将删除 ${unique.length} 个本地音频缓存文件。元数据与封面保留。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('删除'),
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
  AppSnack.show(context, '已删除 $removed 个本地音频缓存');
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
  final library = context.read<LibraryService>();

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
      final members = cache.groupMemberFileNames(gid);
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
      title: const Text('销毁所选曲目？'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '将删除 ${tracks.length} 首曲目：'
              '本地音频缓存 + 音乐库记录 + 元数据与压缩封面。不可恢复。',
            ),
            if (groupIds.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('（CUE 分片会整组删除对应音频文件）'),
              ),
            const SizedBox(height: 8),
            for (final n in files.take(30)) Text('• $n'),
            if (files.length > 30) Text('…共 ${files.length} 个文件'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('销毁'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  // 1. Audio cache (whole CUE groups first, then single files).
  for (final gid in groupIds) {
    await cache.deleteCacheGroup(gid);
  }
  final seen = <String>{};
  for (final t in tracks) {
    if (t.isCueVirtual) continue;
    final key = '${t.sourceName}\u0000${t.effectiveAudioRemotePath}';
    if (!seen.add(key)) continue;
    await cache.deleteLocalFile(
      sourceName: t.sourceName,
      remotePath: t.effectiveAudioRemotePath,
    );
  }

  // 2. Library rows + metadata + cover thumbs.
  await library.destroyTracks(tracks);

  if (!context.mounted) return;
  AppSnack.show(context, '已销毁 ${tracks.length} 首曲目（含缓存、元数据与封面）');
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
      msg = 'CUE 音轨不支持分享';
    } else if (cueCount > 0) {
      msg = 'CUE 音轨不支持分享；其余曲目尚未下载到本地';
    } else {
      msg = notLocalCount == 1 ? '该曲目尚未下载到本地，无法分享' : '所选曲目均未下载到本地，无法分享';
    }
    if (!context.mounted) return;
    AppSnack.error(context, msg);
    return;
  }

  if (cueCount > 0 && context.mounted) {
    AppSnack.show(
      context,
      cueCount == 1 ? 'CUE 音轨不支持分享' : '已跳过 $cueCount 首 CUE 音轨（不支持分享）',
    );
  }
  if (notLocalCount > 0 && context.mounted) {
    AppSnack.show(context, '已跳过 $notLocalCount 首未下载曲目');
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
    AppSnack.error(context, '没有可分享的文件');
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
      AppSnack.error(context, '没有可分享的文件');
      return;
    }
    await SharePlus.instance.share(ShareParams(files: built.files));
    // Best-effort cleanup of the renamed copies.
    for (final path in built.tempPaths) {
      unawaited(File(path).delete().catchError((_) => File(path)));
    }
    if (!context.mounted) return;
    AppSnack.show(context, '已分享 ${built.files.length} 个文件');
  } catch (e) {
    if (!context.mounted) return;
    AppSnack.error(context, '分享失败：$e');
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
      backgroundColor: AppColors.elevated,
      title: const Text('分享文件名'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '按标签重命名（当前模板 ${settings.shareTagRenamePattern}）',
            style: const TextStyle(color: AppColors.mutedText, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '文件名',
              helperText: '扩展名固定为 $ext，不用自己写',
              suffixText: ext,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '原文件：${p.basename(plan.localPath)}',
            style: const TextStyle(color: AppColors.mutedText, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ''),
          child: const Text('用原文件名'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            ctx,
            // The field holds the stem only; put the extension back.
            ShareRenameService.finalizeEditedName(controller.text, plan.name),
          ),
          child: const Text('分享'),
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
