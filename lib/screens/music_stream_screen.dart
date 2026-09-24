import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import '../models/file_type_config.dart';
import '../models/music_stream.dart';
import '../models/webdav_item.dart';
import '../models/webdav_stream.dart';
import '../services/settings_service.dart';
import '../services/video_playback_service.dart';
import '../services/video_queue_controller.dart';
import '../services/webdav_service.dart';
import '../theme/app_theme.dart';
import '../utils/audio_extensions.dart';
import 'video_player_screen.dart' show VideoQueueSeed;

/// 音乐流式播放界面（实验性）。

/// 为什么单独一个界面，而不是复用视频播放页：

/// * 音频没有画面，开 `VideoController` 只会白白耗电；
/// * 视频页的控件贴底、点按隐藏、左右手势、画中画、横屏旋转，对一个
///   「正在听的歌」全是负担。
///
/// 所以这一页只做三件事：显示在放什么、显示进度、给一组常驻的按钮。
/// **没有手势、控件不自动隐藏、不旋转、不画中画。**
///
/// 播放本身仍然走视频那套远端流管线（同一个 Player、同一个媒体会话），
/// 所以后台播放、锁屏控制、耳机按键照常工作。
class MusicStreamScreen extends StatefulWidget {
  const MusicStreamScreen({
    super.key,
    this.source,
    this.sourceLoader,
    this.seed,
  }) : assert(source != null || sourceLoader != null);

  /// 已解析好的远端流。调用方已经拿到网络结果时直接传。
  final WebDavStreamSource? source;

  /// 还没解析时的加载器：界面先落地，解析与缓冲都在页内异步进行，跳转
  /// 不再被网络卡住（流式体验改造，见 99 §7.2.7）。
  final Future<WebDavStreamSource?> Function()? sourceLoader;

  /// 有它就可以在同一目录里上一首 / 下一首（复用视频的播放队列）。
  final VideoQueueSeed? seed;

  @override
  State<MusicStreamScreen> createState() => _MusicStreamScreenState();
}

class _MusicStreamScreenState extends State<MusicStreamScreen> {
  VideoQueueController? _queue;
  Player? _player;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _playSub;
  StreamSubscription<Duration>? _bufSub;
  StreamSubscription<String>? _errSub;
  StreamSubscription<bool>? _completedSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  bool _playing = false;
  String? _error;
  bool _opening = true;
  bool _dragging = false;
  double _dragValue = 0;

  /// 缓存服务引用：dispose 里再查 Provider 不安全。
  VideoPlaybackService? _playback;

  /// 播放模式。存在设置里（`SettingsService.musicStreamPlayMode`），
  /// 进页面时读一次，按一下就写回去。
  MusicStreamPlayMode _mode = MusicStreamPlayMode.sequential;

  /// 播放列表面板的搜索框。控制器挂在 State 上，面板关掉也不丢已输入的字。
  final TextEditingController _playlistSearch = TextEditingController();
  String _playlistFilter = '';

  Future<WebDavStreamSource?> _sourceFor(WebDavItem item) async {
    final accountId =
        widget.source?.accountId ??
        _playback?.source?.accountId ??
        widget.seed?.accountId;
    if (accountId == null) return null;
    return context.read<WebDavService>().resolveStreamSource(
          remotePath: item.path,
          name: item.name,
          accountId: accountId,
          kind: StreamKind.music,
        );
  }

  @override
  void initState() {
    super.initState();
    _mode = context.read<SettingsService>().musicStreamPlayMode;
    final seed = widget.seed;
    if (seed != null) {
      _queue = VideoQueueController(
        webDav: context.read<WebDavService>(),
        accountId: seed.accountId,
        rootPath: seed.folderPath,
        seed: seed.siblings
            .where((e) => e.category == FileCategory.music)
            .toList(),
        initialRemotePath: seed.current.path,
        category: FileCategory.music,
        // 自动连播由本页的 completed 订阅实现（控制器的 autoAdvance 只是声明）。
        // 流式播放是「听专辑」的场景，放完一首就停住反而要用户每次回来点一下。
        autoAdvance: true,
        deepScan: context.read<SettingsService>().audioScanSubdirs,
      );
      _queue!.addListener(_onQueueChanged);
      _queue!.startScan();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInitial());
  }

  void _onQueueChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// 界面先落地：已带 source 直接开流；否则先在页内异步解析源。
  /// 解析失败 / 未连接时用页内错误态表达，不再把跳转链卡住。
  Future<void> _openInitial() async {
    final pre = widget.source;
    if (pre != null) {
      await _open(pre);
      return;
    }
    WebDavStreamSource? source;
    try {
      source = await widget.sourceLoader?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      return;
    }
    if (!mounted) return;
    if (source == null) {
      setState(() => _error = 'WebDAV 未连接，无法流式播放');
      return;
    }
    await _open(source);
  }

  /// 打开一条流并接管 Player 的状态流。
  Future<void> _open(WebDavStreamSource source) async {
    final playback = _playback ?? context.read<VideoPlaybackService>();
    _playback = playback;
    await _detach();
    setState(() {
      _opening = true;
      _error = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _buffered = Duration.zero;
    });
    try {
      // 调用方（网络库）通常已经 prepare 过同一条流，进界面就不用再开一次。
      final open = playback.source;
      final sameStream =
          open != null &&
          open.remotePath == source.remotePath &&
          open.accountId == source.accountId;
      final player = sameStream
          ? (playback.player ??
                await playback.prepare(source, bufferSizeMb: 48))
          : await playback.prepare(source, bufferSizeMb: 48);
      if (!mounted) return;
      _player = player;
      _attach(player);
      await _applyPlaylistMode(player);
      await player.play();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// 把 Player 的状态流接到本页。每次 [_open] 都要重新接一遍：切歌会换
  /// Player（也可能还是同一个实例），旧订阅在 [_detach] 里已经取消。
  void _attach(Player player) {
    _posSub = player.stream.position.listen((v) {
      if (!mounted || _dragging) return;
      setState(() => _position = v);
    });
    _durSub = player.stream.duration.listen((v) {
      if (!mounted) return;
      setState(() => _duration = v);
    });
    _bufSub = player.stream.buffer.listen((v) {
      if (!mounted) return;
      setState(() => _buffered = v);
    });
    _playSub = player.stream.playing.listen((v) {
      if (!mounted) return;
      setState(() => _playing = v);
    });
    _errSub = player.stream.error.listen((e) {
      if (!mounted) return;
      setState(() => _error = e);
    });
    // 自动连播在这里：控制器不实现推进，谁开播谁负责接下一首。
    _completedSub = player.stream.completed.listen((completed) {
      if (completed && mounted) unawaited(_advance(player));
    });
  }

  /// 一首放完之后往哪走。手动点「下一首」不走这里。
  Future<void> _advance(Player player) async {
    final queue = _queue;
    if (queue == null) return;
    // 单曲循环不动队列位置，player 停在末尾，所以由本页重新起播。
    if (_mode == MusicStreamPlayMode.single) {
      await player.seek(Duration.zero);
      await _applyPlaylistMode(player);
      await player.play();
      return;
    }
    final next = queue.index + 1;
    if (next < queue.length) {
      await _switchTo(next);
      return;
    }
    // 顺序播放到队尾就停住；列表循环回到第一首。两边都保留已播完的状态。
    if (_mode == MusicStreamPlayMode.loop && queue.length > 0) {
      await _switchTo(0);
    }
  }

  /// 把当前模式报告给播放器。播放器实例与视频页共用，所以两边都要设。
  ///
  /// 这里的 `PlaylistMode` 只影响系统侧（通知栏、媒体会话）的行为，
  /// 真正的推进判定在 [_advance]：流式页在播放器眼里始终只有一条媒体，
  /// 所以 `loop` 不能替代列表循环。
  Future<void> _applyPlaylistMode(Player player) =>
      player.setPlaylistMode(switch (_mode) {
        MusicStreamPlayMode.single => PlaylistMode.single,
        MusicStreamPlayMode.sequential => PlaylistMode.none,
        MusicStreamPlayMode.loop => PlaylistMode.loop,
      });

  Future<void> _cyclePlayMode() async {
    final next = _mode.next;
    setState(() => _mode = next);
    await context.read<SettingsService>().setMusicStreamPlayMode(next);
    final player = _player;
    if (player != null) await _applyPlaylistMode(player);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next.labelZh),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _detach() async {
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _playSub?.cancel();
    await _bufSub?.cancel();
    await _errSub?.cancel();
    await _completedSub?.cancel();
    _posSub = null;
    _durSub = null;
    _playSub = null;
    _bufSub = null;
    _errSub = null;
    _completedSub = null;
  }

  @override
  void dispose() {
    _playlistSearch.dispose();
    _queue?.removeListener(_onQueueChanged);
    _queue?.cancelScan();
    _queue?.dispose();
    unawaited(_detach());
    // 离开这一页就结束远端流：退出视频模式会把媒体会话还给本地播放。
    unawaited(_playback?.stop() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final player = _player;
    if (player == null) return;
    if (player.state.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> _seekBy(Duration delta) async {
    final player = _player;
    if (player == null) return;
    var target = player.state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    final dur = player.state.duration;
    if (dur > Duration.zero && target > dur) target = dur;
    await player.seek(target);
    if (mounted) setState(() => _position = target);
  }

  /// 控制条最左边那个按钮：三个模式轮换，图标与提示跟着变。
  Widget _buildModeButton() {
    final looping = _mode != MusicStreamPlayMode.sequential;
    return IconButton(
      tooltip: '播放模式：${_mode.labelZh}',
      iconSize: 32,
      onPressed: _cyclePlayMode,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.repeat,
            color: looping ? AppColors.accent : AppColors.mutedText,
          ),
          if (_mode == MusicStreamPlayMode.single)
            const Positioned(
              right: -4,
              bottom: -2,
              child: Text('1', style: TextStyle(fontSize: 11, height: 1)),
            ),
        ],
      ),
    );
  }

  /// 播放列表：与视频页同一外形，另加搜索。
  Future<void> _showPlaylist() async {
    final queue = _queue;
    if (queue == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.7;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: StatefulBuilder(
              builder: (ctx, setSheet) {
                final query = _playlistFilter.trim().toLowerCase();
                final all = queue.tracks;
                final shown = query.isEmpty
                    ? all
                    : all
                          .where(
                            (t) =>
                                t.name.toLowerCase().contains(query) ||
                                _relativeDir(t.path)
                                    .toLowerCase()
                                    .contains(query),
                          )
                          .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          const Text(
                            '播放列表',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${all.length} 首',
                            style: const TextStyle(
                              color: AppColors.secondaryText,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        controller: _playlistSearch,
                        onChanged: (v) => setSheet(() => _playlistFilter = v),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: '搜索列表',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          border: const OutlineInputBorder(),
                          suffixIcon: _playlistFilter.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    _playlistSearch.clear();
                                    setSheet(() => _playlistFilter = '');
                                  },
                                ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: queue,
                        builder: (ctx, _) {
                          if (shown.isEmpty) {
                            return const Center(
                              child: Text(
                                '没有匹配的曲目',
                                style: TextStyle(
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            itemCount: shown.length,
                            itemBuilder: (ctx, i) {
                              final track = shown[i];
                              final selected =
                                  track.path == queue.currentRemotePath;
                              final dir = query.isEmpty
                                  ? ''
                                  : _relativeDir(track.path);
                              return ListTile(
                                dense: true,
                                selected: selected,
                                leading: Text(
                                  '${all.indexOf(track) + 1}',
                                  style: TextStyle(
                                    color: selected
                                        ? AppColors.accent
                                        : AppColors.mutedText,
                                    fontSize: 12,
                                  ),
                                ),
                                title: Text(
                                  track.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: selected
                                        ? AppColors.accent
                                        : AppColors.onDark,
                                  ),
                                ),
                                subtitle: dir.isEmpty
                                    ? null
                                    : Text(
                                        dir,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.secondaryText,
                                          fontSize: 11,
                                        ),
                                      ),
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  final index = all.indexOf(track);
                                  if (index >= 0) unawaited(_switchTo(index));
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 列表里这一条的相对目录（不含文件名）。搜索时用来区分同名曲。
  String _relativeDir(String remotePath) {
    final lastSlash = remotePath.lastIndexOf('/');
    if (lastSlash < 0) return '';
    final dir = remotePath.substring(0, lastSlash + 1);
    final root = widget.seed?.folderPath;
    if (root != null && root.isNotEmpty && dir.startsWith(root)) {
      return dir.substring(root.length);
    }
    return dir;
  }

  Future<void> _switchTo(int index) async {
    final queue = _queue;
    if (queue == null) return;
    final item = queue.selectIndex(index);
    if (item == null) return;
    final source = await _sourceFor(item);
    if (!mounted) return;
    if (source == null) {
      setState(() => _error = '无法建立流式地址，请检查账户配置');
      return;
    }
    await _open(source);
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue;
    final title = queue?.current?.name ??
        _playback?.source?.name ??
        widget.source?.name ??
        '加载中…';
    final hasPrev = (queue?.index ?? 0) > 0;
    final hasNext = queue?.hasNext ?? false;
    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(folderDisplayName(title), overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCover(),
                const SizedBox(height: 24),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.primaryText,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '流式传输 · 未缓存',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 24),
                _buildProgress(),
                const SizedBox(height: 8),
                _buildControls(hasPrev: hasPrev, hasNext: hasNext),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    '播放失败：$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 封面占位：这一版刻意不抓远端封面（要额外 Range 读文件头）。
  Widget _buildCover() {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.elevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        _opening ? Icons.graphic_eq : Icons.music_note,
        size: 72,
        color: AppColors.secondaryText,
      ),
    );
  }

  Widget _buildProgress() {
    final total = _duration.inMilliseconds;
    final value = _dragging
        ? _dragValue
        : _position.inMilliseconds.clamp(0, total == 0 ? 1 : total).toDouble();
    // 老式「先缓冲完再开播」的等待态（源解析 / 起播前）：二级轨道铺满整条
    // 并左右渐变；起播后的流式缓冲：实心二级轨道 = 已缓冲区间（buffer 流）。
    final double? secondary;
    if (_opening) {
      secondary = total == 0 ? 1.0 : total.toDouble();
    } else {
      secondary = (total == 0 || _buffered <= Duration.zero)
          ? null
          : _buffered.inMilliseconds.clamp(0, total).toDouble();
    }
    final sliderTheme = SliderTheme.of(context);
    final base =
        sliderTheme.activeTrackColor ?? Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        SliderTheme(
          data: sliderTheme.copyWith(
            trackShape: _opening
                ? _GradientSecondaryTrackShape(
                    from: base.withValues(alpha: 0.25),
                    to: base,
                  )
                : const RoundedRectSliderTrackShape(),
            secondaryActiveTrackColor: base.withValues(alpha: 0.35),
          ),
          child: Slider(
            value: total == 0 ? 0 : value,
            max: total == 0 ? 1 : total.toDouble(),
            secondaryTrackValue: secondary,
            onChanged: total == 0
                ? null
                : (v) => setState(() {
                    _dragging = true;
                    _dragValue = v;
                  }),
            onChangeEnd: total == 0
                ? null
                : (v) async {
                    setState(() => _dragging = false);
                    await _player?.seek(Duration(milliseconds: v.round()));
                  },
          ),
        ),
        // 快退 / 快进从控制条挪到进度条下面：控制条那两个位置让给了
        // 播放模式与播放列表，取色不再和它们挤在一起。
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: total == 0
                  ? null
                  : () => _seekBy(const Duration(seconds: -15)),
              icon: const Icon(Icons.replay_10, size: 20),
              label: const Text('15 秒'),
            ),
            const SizedBox(width: 24),
            TextButton.icon(
              onPressed: total == 0
                  ? null
                  : () => _seekBy(const Duration(seconds: 15)),
              icon: const Icon(Icons.forward_10, size: 20),
              label: const Text('15 秒'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(_position), style: _timeStyle),
              Text(total == 0 ? '--:--' : _fmt(_duration), style: _timeStyle),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControls({required bool hasPrev, required bool hasNext}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 快退 / 快进按钮让位给播放模式与播放列表，取色改用进度条长按拖动。
        _buildModeButton(),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '上一首',
          iconSize: 36,
          onPressed: hasPrev ? () => _switchTo(_queue!.index - 1) : null,
          icon: const Icon(Icons.skip_previous),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: _playing ? '暂停' : '播放',
          iconSize: 40,
          onPressed: _opening ? null : _togglePlay,
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '下一首',
          iconSize: 36,
          onPressed: hasNext ? () => _switchTo(_queue!.index + 1) : null,
          icon: const Icon(Icons.skip_next),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '播放列表',
          iconSize: 32,
          onPressed: _queue == null ? null : _showPlaylist,
          icon: const Icon(Icons.queue_music),
        ),
      ],
    );
  }

  static const _timeStyle = TextStyle(
    color: AppColors.secondaryText,
    fontSize: 12,
  );

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

/// 二级轨道左右渐变的轨道形状：表示「老式等待式缓冲」（源解析 / 起播前
/// 的等待阶段，正是原来会挡住界面的那段时间）。铺满整条轨道，左淡右实。
/// 只覆盖 LTR（本应用固定从左到右），thumb 由 thumbShape 在轨道之后绘制。
class _GradientSecondaryTrackShape extends RoundedRectSliderTrackShape {
  const _GradientSecondaryTrackShape({required this.from, required this.to});

  final Color from;
  final Color to;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (trackRect.height <= 0) return;
    final radius = Radius.circular(trackRect.height / 2);

    final inactive = Paint()
      ..color = ColorTween(
        begin: sliderTheme.disabledInactiveTrackColor,
        end: sliderTheme.inactiveTrackColor,
      ).evaluate(enableAnimation)!;
    context.canvas.drawRRect(
      RRect.fromLTRBR(
        trackRect.left,
        trackRect.top,
        trackRect.right,
        trackRect.bottom,
        radius,
      ),
      inactive,
    );

    final gradient = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [from, to],
      ).createShader(trackRect);
    context.canvas.drawRRect(
      RRect.fromLTRBR(
        trackRect.left,
        trackRect.top,
        trackRect.right,
        trackRect.bottom,
        radius,
      ),
      gradient,
    );

    // 播放进度段盖在渐变之上；等待态 thumb 在最左，段宽为零时直接跳过。
    if (thumbCenter.dx > trackRect.left + 1) {
      final active = Paint()
        ..color = ColorTween(
          begin: sliderTheme.disabledActiveTrackColor,
          end: sliderTheme.activeTrackColor,
        ).evaluate(enableAnimation)!;
      context.canvas.drawRRect(
        RRect.fromLTRBR(
          trackRect.left,
          trackRect.top,
          thumbCenter.dx,
          trackRect.bottom,
          radius,
        ),
        active,
      );
    }
  }
}
