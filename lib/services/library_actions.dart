import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/library_track.dart';
import '../models/playlist.dart';
import '../screens/playlists_screen.dart';
import '../theme/app_theme.dart';
import '../utils/track_identity.dart';
import 'cache_service.dart';
import 'download_queue_service.dart';

/// Whether the track's audio file is present in the local cache.
bool libraryTrackIsLocal(CacheService cache, LibraryTrack track) {
  return cache.hasLocalFile(
    track.effectiveAudioRemotePath,
    accountId: track.accountId,
  );
}

/// Enqueue download for a non-local library track (CUE group or single file).
/// Does not start playback or tag reading.
Future<void> enqueueLibraryTrackDownload(
  BuildContext context,
  LibraryTrack track, {
  bool showSnack = true,
}) async {
  final downloads = context.read<DownloadQueueService>();
  if (track.isCueVirtual && track.cueRemotePath != null) {
    unawaited(
      downloads.enqueueCueGroup(
        accountId: track.accountId,
        cueRemotePath: track.cueRemotePath!,
      ),
    );
  } else {
    unawaited(
      downloads.ensureQueued(
        track.accountId,
        track.effectiveAudioRemotePath,
        fileName: track.fileName,
      ),
    );
  }
  if (showSnack && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已加入下载')),
    );
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
          accountId: t.accountId,
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
    final gid = t.cacheGroupId ??
        (t.cueRemotePath != null
            ? cueCacheGroupId(t.accountId, t.cueRemotePath!)
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
        for (final t in tracks.where((x) =>
            (x.cacheGroupId ??
                (x.cueRemotePath != null
                    ? cueCacheGroupId(x.accountId, x.cueRemotePath!)
                    : null)) ==
            gid)) {
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除 CUE 缓存组（$n 个文件）')),
    );
  }

  if (plain.isEmpty) return;
  // Deduplicate by audio path.
  final seen = <String>{};
  final unique = <LibraryTrack>[];
  for (final t in plain) {
    final key = '${t.accountId}\u0000${t.effectiveAudioRemotePath}';
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
      accountId: t.accountId,
      remotePath: t.effectiveAudioRemotePath,
    )) {
      removed++;
    }
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('已删除 $removed 个本地音频缓存')),
  );
}

/// Share already-cached **non-CUE** audio files via the system share sheet.
///
/// CUE-sliced rows are identified from the library DB via
/// [LibraryTrack.isCueVirtual] (`cue_remote_path` + `cue_track_index`).
/// Those tracks are never cropped/exported — sharing them only shows a
/// snackbar (`CUE 音轨不支持分享`).
Future<void> shareLibraryTracks(
  BuildContext context,
  List<LibraryTrack> tracks,
) async {
  if (tracks.isEmpty) return;
  final cache = context.read<CacheService>();
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
      msg = notLocalCount == 1
          ? '该曲目尚未下载到本地，无法分享'
          : '所选曲目均未下载到本地，无法分享';
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
    return;
  }

  if (cueCount > 0 && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cueCount == 1 ? 'CUE 音轨不支持分享' : '已跳过 $cueCount 首 CUE 音轨（不支持分享）',
        ),
      ),
    );
  }
  if (notLocalCount > 0 && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已跳过 $notLocalCount 首未下载曲目')),
    );
  }

  final files = <XFile>[];
  for (final t in localNonCue) {
    final path = await cache.localPathIfCached(
      t.effectiveAudioRemotePath,
      accountId: t.accountId,
    );
    if (path == null) continue;
    files.add(XFile(path, mimeType: _shareMimeFor(path)));
  }
  if (files.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('没有可分享的文件'),
        backgroundColor: AppColors.error,
      ),
    );
    return;
  }

  try {
    await SharePlus.instance.share(ShareParams(files: files));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已分享 ${files.length} 个文件')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('分享失败：$e'),
        backgroundColor: AppColors.error,
      ),
    );
  }
}

String _shareMimeFor(String path) {
  switch (p.extension(path).toLowerCase()) {
    case '.mp3':
      return 'audio/mpeg';
    case '.flac':
      return 'audio/flac';
    case '.m4a':
    case '.aac':
      return 'audio/mp4';
    case '.ogg':
      return 'audio/ogg';
    case '.wav':
      return 'audio/wav';
    default:
      return 'application/octet-stream';
  }
}
