import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/library_track.dart';
import '../models/webdav_item.dart';
import '../services/accounts_service.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import '../services/library_service.dart';
import '../services/tag_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_art.dart';
import '../widgets/library_cover_art.dart';
import 'now_playing_queue_screen.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }


  List<String> _metaChips(TrackInfo? track, LibraryTrack? lib) {
    final chips = <String>[];
    void add(String? v) {
      final t = v?.trim();
      if (t != null && t.isNotEmpty) chips.add(t);
    }

    final album = track?.album ?? lib?.album;
    add(album);

    if (track?.isCueVirtual == true || lib?.isCueVirtual == true) {
      add(LibraryTrack.cueMultiSliceLabel);
    }

    final albumArtist = track?.albumArtist ?? lib?.albumArtist;
    if (albumArtist != null &&
        albumArtist.trim().isNotEmpty &&
        albumArtist.trim() != (track?.displayArtist ?? '')) {
      add('专辑艺人 · $albumArtist');
    }

    final tn = track?.trackNumber ?? lib?.trackNumber;
    final tt = track?.trackTotal ?? lib?.trackTotal;
    if (tn != null) {
      add(tt != null ? '曲目 $tn/$tt' : '曲目 $tn');
    }
    final dn = track?.discNumber ?? lib?.discNumber;
    final dt = track?.discTotal ?? lib?.discTotal;
    if (dn != null) {
      add(dt != null ? '碟 $dn/$dt' : '碟 $dn');
    }
    final year = track?.year ?? lib?.year;
    if (year != null && year > 0) add('$year');
    final genre = track?.genre ?? lib?.genre;
    add(genre);

    final bitrate = track?.bitrate ?? lib?.bitrate;
    if (bitrate != null && bitrate > 0) {
      add('${(bitrate / 1000).round()} kbps');
    }
    final sr = track?.sampleRate ?? lib?.sampleRate;
    if (sr != null && sr > 0) {
      add(sr >= 1000 ? '${(sr / 1000).toStringAsFixed(sr % 1000 == 0 ? 0 : 1)} kHz' : '$sr Hz');
    }

    final durMs = track?.duration?.inMilliseconds ?? lib?.durationMs;
    if (durMs != null && durMs > 0) {
      add(_fmt(Duration(milliseconds: durMs)));
    }
    return chips;
  }

  Future<void> _showMore(BuildContext context) async {
    final player = context.read<AudioPlayerService>();
    final track = player.current;
    if (track == null) return;
    final library = context.read<LibraryService>();
    final accounts = context.read<AccountsService>();
    final cache = context.read<CacheService>();
    final lib = library.find(track.accountId, track.remotePath);
    String? accountLabel;
    String? serverUrl;
    for (final a in accounts.accounts) {
      if (a.id == track.accountId) {
        accountLabel = a.name;
        serverUrl = a.url;
        break;
      }
    }
    // Prefer live local path.
    String? localPath = track.localPath;
    if (localPath == null || !File(localPath).existsSync()) {
      localPath = await cache.localPathIfCached(
        track.effectiveAudioRemotePath,
        accountId: track.accountId,
      );
    }
    ReadTags? liveTags;
    int? fileSize;
    // Tag reads only against an existing local audio file.
    if (localPath != null && File(localPath).existsSync()) {
      liveTags = await library.tags.readFromFile(localPath);
      try {
        fileSize = await File(localPath).length();
      } catch (_) {}
    }

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final rows = <MapEntry<String, String>>[];
        void row(String k, String? v) {
          final t = v?.trim();
          if (t != null && t.isNotEmpty) rows.add(MapEntry(k, t));
        }

        row('账号', accountLabel);
        row('服务器', serverUrl);
        row('远程路径', track.remotePath);
        row('文件名', track.fileName);
        final isCue = track.isCueVirtual || (lib?.isCueVirtual ?? false);
        if (isCue) {
          row('类型', LibraryTrack.cueMultiSliceLabel);
          row(
            '说明',
            '此条目来自 CUE 分片，不是独立单曲文件；'
            '播放与缓存共用源音频。',
          );
          row(
            'CUE 文件',
            track.cueRemotePath ?? lib?.cueRemotePath,
          );
          row(
            '源音频',
            track.audioRemotePath ?? lib?.audioRemotePath,
          );
          final idx = track.cueTrackIndex ?? lib?.cueTrackIndex;
          if (idx != null) row('CUE 曲序', '$idx');
          final start = track.clipStart ??
              (lib?.clipStartMs != null
                  ? Duration(milliseconds: lib!.clipStartMs!)
                  : null);
          final end = track.clipEnd ??
              (lib?.clipEndMs != null
                  ? Duration(milliseconds: lib!.clipEndMs!)
                  : null);
          if (start != null) {
            final endLabel = end != null ? _fmt(end) : '结尾';
            row('分片区间', '${_fmt(start)} – $endLabel');
          }
        }
        row('本地缓存', localPath ?? '未下载');
        if (fileSize != null) {
          row('文件大小', _formatBytes(fileSize));
        }

        final tagMap = <String, String>{};
        if (liveTags != null) {
          tagMap.addAll(liveTags.toDisplayMap());
        } else if (lib != null) {
          tagMap.addAll(
            ReadTags(
              title: lib.title,
              artist: lib.artist,
              albumArtist: lib.albumArtist,
              album: lib.album,
              durationMs: lib.durationMs,
              trackNumber: lib.trackNumber,
              trackTotal: lib.trackTotal,
              discNumber: lib.discNumber,
              discTotal: lib.discTotal,
              year: lib.year,
              genre: lib.genre,
              bitrate: lib.bitrate,
              sampleRate: lib.sampleRate,
            ).toDisplayMap(),
          );
        } else {
          tagMap.addAll(
            ReadTags(
              title: track.title,
              artist: track.artist,
              albumArtist: track.albumArtist,
              album: track.album,
              durationMs: track.duration?.inMilliseconds,
              trackNumber: track.trackNumber,
              trackTotal: track.trackTotal,
              discNumber: track.discNumber,
              discTotal: track.discTotal,
              year: track.year,
              genre: track.genre,
              bitrate: track.bitrate,
              sampleRate: track.sampleRate,
            ).toDisplayMap(),
          );
        }
        for (final e in tagMap.entries) {
          row(e.key, e.value);
        }

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.elevatedHigh,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '文件详情',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryText,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '复制全部',
                        onPressed: () async {
                          final buf = StringBuffer();
                          for (final e in rows) {
                            buf.writeln('${e.key}: ${e.value}');
                          }
                          await Clipboard.setData(
                            ClipboardData(text: buf.toString()),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制到剪贴板')),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_outlined),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = rows[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          e.key,
                          style: const TextStyle(
                            color: AppColors.mutedText,
                            fontSize: 12,
                          ),
                        ),
                        subtitle: SelectableText(
                          e.value,
                          style: const TextStyle(
                            color: AppColors.primaryText,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                        onLongPress: () async {
                          await Clipboard.setData(ClipboardData(text: e.value));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已复制：${e.key}')),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final library = context.watch<LibraryService>();
    final track = player.current;
    final lib = track == null
        ? null
        : library.find(track.accountId, track.remotePath);
    final duration = player.duration ?? Duration.zero;
    final position = player.position;
    final maxMs = duration.inMilliseconds > 0 ? duration.inMilliseconds : 1;
    final posMs = position.inMilliseconds.clamp(0, maxMs);
    final artSize = MediaQuery.sizeOf(context).width * 0.68;
    final chips = _metaChips(track, lib);

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      body: _PlayerBackdrop(
        accountId: track?.accountId,
        audioRemotePath: track?.effectiveAudioRemotePath,
        localPath: track?.localPath,
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: const Text('正在播放'),
                actions: [
                  IconButton(
                    tooltip: '播放列表',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NowPlayingQueueScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.queue_music),
                  ),
                  if (track != null)
                    IconButton(
                      tooltip: '更多',
                      onPressed: () => _showMore(context),
                      icon: const Icon(Icons.more_vert),
                    ),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            children: [
                              const SizedBox(height: 8),
                              if (track != null)
                                PlayerCoverArt(
                                  accountId: track.accountId,
                                  remotePath: track.effectiveAudioRemotePath,
                                  localAudioPath: track.localPath,
                                  fileName: track.fileName,
                                  size: artSize.clamp(180.0, 300.0),
                                  borderRadius: 8,
                                  icon: Icons.album,
                                )
                              else
                                CoverArt(
                                  size: artSize.clamp(180.0, 300.0),
                                  borderRadius: 8,
                                  icon: Icons.album,
                                ),
                              const SizedBox(height: 28),
                              Text(
                                track?.displayTitle ?? '未选择曲目',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.onDark,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                  letterSpacing: 0.15,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                player.error ?? track?.displayArtist ?? '',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: player.error != null
                                      ? AppColors.error
                                      : AppColors.secondaryText,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (chips.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final c in chips)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.elevated,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Text(
                                          c,
                                          style: const TextStyle(
                                            color: AppColors.secondaryText,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                              const Spacer(),
                              const SizedBox(height: 16),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 6,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 9,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 18,
                                  ),
                                ),
                                child: Slider(
                                  value: posMs.toDouble(),
                                  max: maxMs.toDouble(),
                                  onChanged: duration.inMilliseconds > 0
                                      ? (v) => player.seek(
                                            Duration(milliseconds: v.round()),
                                          )
                                      : null,
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _fmt(position),
                                      style: const TextStyle(
                                        color: AppColors.mutedText,
                                        fontSize: 12,
                                        fontFeatures: [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                    ),
                                    Text(
                                      _fmt(duration),
                                      style: const TextStyle(
                                        color: AppColors.mutedText,
                                        fontSize: 12,
                                        fontFeatures: [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    iconSize: 42,
                                    color: AppColors.onDark,
                                    onPressed: () => player.skipPrevious(),
                                    icon: const Icon(
                                      Icons.skip_previous_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Material(
                                    color: AppColors.accent,
                                    shape: const CircleBorder(),
                                    elevation: 4,
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: track == null
                                          ? null
                                          : () => player.playPause(),
                                      child: SizedBox(
                                        width: 72,
                                        height: 72,
                                        child: Icon(
                                          player.playing
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          size: 42,
                                          color: AppColors.onAccent,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  IconButton(
                                    iconSize: 42,
                                    color: AppColors.onDark,
                                    onPressed: () => player.skipNext(),
                                    icon: const Icon(Icons.skip_next_rounded),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 28),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Backdrop that loads full/embedded art only — never the 100×100 thumb.
class _PlayerBackdrop extends StatefulWidget {
  const _PlayerBackdrop({
    this.accountId,
    this.audioRemotePath,
    this.localPath,
    required this.child,
  });

  final String? accountId;
  final String? audioRemotePath;
  final String? localPath;
  final Widget child;

  @override
  State<_PlayerBackdrop> createState() => _PlayerBackdropState();
}

class _PlayerBackdropState extends State<_PlayerBackdrop> {
  String? _fullPath;
  Uint8List? _bytes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _PlayerBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.audioRemotePath != widget.audioRemotePath ||
        oldWidget.localPath != widget.localPath) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final accountId = widget.accountId;
    final remote = widget.audioRemotePath;
    if (accountId == null || remote == null) {
      if (mounted) setState(() { _fullPath = null; _bytes = null; });
      return;
    }
    final library = context.read<LibraryService>();
    final covers = library.covers;
    await covers.init();
    final full = await covers.fullCoverPath(accountId, remote);
    if (full != null) {
      if (mounted) setState(() { _fullPath = full; _bytes = null; });
      return;
    }
    final local = widget.localPath;
    if (local != null && File(local).existsSync()) {
      final tags = await library.tags.readFromFile(local);
      final bytes = tags.coverBytes;
      if (bytes != null && bytes.isNotEmpty) {
        unawaited(covers.saveFull(accountId: accountId, remotePath: remote, bytes: bytes));
        if (mounted) setState(() { _fullPath = null; _bytes = bytes; });
        return;
      }
    }
    if (mounted) setState(() { _fullPath = null; _bytes = null; });
  }

  @override
  Widget build(BuildContext context) {
    return CoverBackdrop(
      path: _fullPath,
      bytes: _bytes,
      child: widget.child,
    );
  }
}
