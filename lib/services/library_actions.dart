import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/library_track.dart';
import '../models/playlist.dart';
import '../screens/playlists_screen.dart';
import '../theme/app_theme.dart';
import '../utils/track_identity.dart';
import 'cache_service.dart';
import 'share_export_service.dart';

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

Future<void> shareLibraryTracks(
  BuildContext context,
  List<LibraryTrack> tracks,
) async {
  if (tracks.isEmpty) return;
  final cache = context.read<CacheService>();
  final share = ShareExportService(cache: cache);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('正在准备分享文件…')),
        ],
      ),
    ),
  );
  ShareExportResult result;
  try {
    result = await share.shareTracks(tracks);
  } catch (e) {
    result = ShareExportResult(ok: false, message: '分享失败：$e');
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(result.message),
      backgroundColor: result.ok ? null : AppColors.error,
    ),
  );
}
