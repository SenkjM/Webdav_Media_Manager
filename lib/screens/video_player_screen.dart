import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../models/video_settings.dart';
import '../models/webdav_stream.dart';
import '../services/settings_service.dart';
import '../services/video_playback_service.dart';
import '../theme/app_theme.dart';
import '../utils/video_pip.dart';

/// Full-screen WebDAV video player (streaming via media_kit).
///
/// Not surfaced as a cross-interface mini player (unlike music). Supports:
/// * configurable gestures (left/right double-tap, long-press)
/// * manual portrait/landscape toggle + rotation lock
/// * screen (UI) lock, background playback & picture-in-picture
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.source});

  final WebDavStreamSource source;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlaybackService? _service;
  Player? _player;
  VideoController? _controller;

  bool _loading = true;
  String? _error;

  final List<StreamSubscription<dynamic>> _subs = [];

  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration?> _duration = ValueNotifier(null);
  final ValueNotifier<bool> _playing = ValueNotifier(false);
  final ValueNotifier<bool> _buffering = ValueNotifier(false);
  final ValueNotifier<double> _rate = ValueNotifier(1.0);
  final ValueNotifier<bool> _controlsVisible = ValueNotifier(true);
  final ValueNotifier<bool> _locked = ValueNotifier(false);
  final ValueNotifier<bool> _rotationLocked = ValueNotifier(false);

  VideoGestureAction? _pendingDoubleTapAction;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final service = context.read<VideoPlaybackService>();
    final settings = context.read<SettingsService>();
    _service = service;
    try {
      final player = await service.prepare(
        widget.source,
        bufferSizeMb: settings.videoBufferSizeMb,
      );
      if (!mounted) return;
      // Attach the video controller BEFORE opening the media so libmpv enables
      // the video output path.
      _controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: settings.videoHardwareDecoding,
        ),
      );
      _player = player;
      _bindStreams(player);
      await player.open(service.mediaFor(widget.source));
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _bindStreams(Player player) {
    _subs.add(player.stream.position.listen((p) => _position.value = p));
    _subs.add(player.stream.duration.listen((d) => _duration.value = d));
    _subs.add(player.stream.playing.listen((v) => _playing.value = v));
    _subs.add(player.stream.buffering.listen((v) => _buffering.value = v));
    _subs.add(player.stream.rate.listen((r) => _rate.value = r));
    _subs.add(player.stream.error.listen((e) {
      if (!mounted || e.isEmpty) return;
      setState(() => _error = e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('播放错误：$e')),
      );
    }));
    _position.value = player.state.position;
    _duration.value = player.state.duration;
    _playing.value = player.state.playing;
    _rate.value = player.state.rate;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _position.dispose();
    _duration.dispose();
    _playing.dispose();
    _buffering.dispose();
    _rate.dispose();
    _controlsVisible.dispose();
    _locked.dispose();
    _rotationLocked.dispose();
    // Restore free rotation; the Video widget detaches the texture itself and
    // the Player lifetime stays owned by VideoPlaybackService.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _handleExit() async {
    final service = _service ?? context.read<VideoPlaybackService>();
    final hasError = _error != null && _error!.isNotEmpty;
    final keep =
        context.read<SettingsService>().videoBackgroundPlayback && !hasError;
    if (keep && _player?.state.playing == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('视频正在后台播放：${widget.source.name}'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: '停止',
            onPressed: () => service.stop(),
          ),
        ),
      );
    } else {
      await service.stop();
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _toggleControls() {
    _controlsVisible.value = !_controlsVisible.value;
  }

  Future<void> _runGesture(VideoGestureAction action) async {
    final player = _player;
    if (player == null) return;
    switch (action) {
      case VideoGestureAction.none:
        break;
      case VideoGestureAction.back10s:
        await _seekBy(const Duration(seconds: -10));
        break;
      case VideoGestureAction.forward10s:
        await _seekBy(const Duration(seconds: 10));
        break;
      case VideoGestureAction.back30s:
        await _seekBy(const Duration(seconds: -30));
        break;
      case VideoGestureAction.forward30s:
        await _seekBy(const Duration(seconds: 30));
        break;
      case VideoGestureAction.toggleRate2x:
        await _toggleRate();
        break;
      case VideoGestureAction.playPause:
        await player.playOrPause();
        break;
    }
  }

  Future<void> _seekBy(Duration delta) async {
    final player = _player;
    if (player == null) return;
    final dur = _duration.value ?? Duration.zero;
    var target = _position.value + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (dur > Duration.zero && target > dur) target = dur;
    await player.seek(target);
    _position.value = target;
  }

  Future<void> _toggleRate() async {
    final player = _player;
    if (player == null) return;
    final next = _rate.value == 2.0 ? 1.0 : 2.0;
    await player.setRate(next);
    _rate.value = next;
  }

  Future<void> _toggleOrientation() async {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    await _applyOrientation(!isLandscape);
  }

  Future<void> _applyOrientation(bool landscape) async {
    if (_rotationLocked.value) return;
    await SystemChrome.setPreferredOrientations(
      landscape
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
            ],
    );
  }

  Future<void> _toggleRotationLock() async {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final locked = !_rotationLocked.value;
    _rotationLocked.value = locked;
    if (locked) {
      await SystemChrome.setPreferredOrientations([
        isLandscape
            ? DeviceOrientation.landscapeLeft
            : DeviceOrientation.portraitUp,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  void _toggleLock() {
    _locked.value = !_locked.value;
    if (_locked.value) {
      _controlsVisible.value = false;
    }
  }

  Future<void> _enterPip() async {
    final ok = await enterPictureInPicture();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前设备/系统不支持画中画')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                widget.source.name,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null && _controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white70, size: 48),
                const SizedBox(height: 12),
                Text(
                  '无法播放：$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final pauseOnBackground = !settings.videoBackgroundPlayback;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleExit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: _controller!,
              fit: BoxFit.contain,
              controls: (state) => const SizedBox.shrink(),
              wakelock: true,
              pauseUponEnteringBackgroundMode: pauseOnBackground,
              resumeUponEnteringForegroundMode: false,
            ),
            _buildGestureLayer(),
          ],
        ),
      ),
    );
  }

  Widget _buildGestureLayer() {
    return ValueListenableBuilder<bool>(
      valueListenable: _locked,
      builder: (context, locked, _) {
        if (locked) {
          return Stack(
            children: [
              // Absorb gestures while locked so nothing accidental happens.
              Positioned.fill(child: Container(color: Colors.transparent)),
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _RoundIconButton(
                      icon: Icons.lock_open,
                      tooltip: '解锁',
                      onTap: _toggleLock,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          onDoubleTapDown: (details) {
            final w = MediaQuery.of(context).size.width;
            final side = details.localPosition.dx < w / 2
                ? context.read<SettingsService>().videoLeftDoubleTap
                : context.read<SettingsService>().videoRightDoubleTap;
            _pendingDoubleTapAction = side;
          },
          onDoubleTap: () {
            final action = _pendingDoubleTapAction;
            if (action != null) _runGesture(action);
          },
          onLongPressStart: (_) {
            _runGesture(context.read<SettingsService>().videoLongPress);
          },
          child: Stack(
            children: [
              Positioned.fill(child: Container(color: Colors.transparent)),
              _buildTopBar(),
              _buildBottomBar(),
              ValueListenableBuilder<bool>(
                valueListenable: _buffering,
                builder: (context, buffering, _) => buffering
                    ? const Center(child: CircularProgressIndicator())
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: ValueListenableBuilder<bool>(
          valueListenable: _controlsVisible,
          builder: (context, visible, _) {
            if (!visible) return const SizedBox.shrink();
            return Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip: '返回',
                    onPressed: _handleExit,
                  ),
                  Expanded(
                    child: Text(
                      widget.source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  _RoundIconButton(
                    icon: Icons.screen_rotation,
                    tooltip: '切换横竖屏',
                    onTap: _toggleOrientation,
                  ),
                  _RoundIconButton(
                    icon: Icons.more_vert,
                    tooltip: '更多设置',
                    onTap: _showMoreSettings,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: ValueListenableBuilder<bool>(
          valueListenable: _controlsVisible,
          builder: (context, visible, _) {
            if (!visible) return const SizedBox.shrink();
            return Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildProgressRow(),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10, color: Colors.white),
                        tooltip: '后退 10 秒',
                        onPressed: () =>
                            _seekBy(const Duration(seconds: -10)),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: _playing,
                        builder: (context, playing, _) => IconButton(
                          iconSize: 36,
                          icon: Icon(
                            playing ? Icons.pause_circle : Icons.play_circle,
                            color: Colors.white,
                          ),
                          tooltip: playing ? '暂停' : '播放',
                          onPressed: () => _player?.playOrPause(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.forward_10, color: Colors.white),
                        tooltip: '前进 10 秒',
                        onPressed: () =>
                            _seekBy(const Duration(seconds: 10)),
                      ),
                      ValueListenableBuilder<double>(
                        valueListenable: _rate,
                        builder: (context, rate, _) => TextButton(
                          onPressed: _toggleRate,
                          child: Text(
                            '${rate.toStringAsFixed(1)}x',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (context.read<SettingsService>().videoPipEnabled)
                        _RoundIconButton(
                          icon: Icons.picture_in_picture_alt,
                          tooltip: '画中画',
                          onTap: _enterPip,
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProgressRow() {
    return ValueListenableBuilder<Duration>(
      valueListenable: _position,
      builder: (context, position, _) {
        return ValueListenableBuilder<Duration?>(
          valueListenable: _duration,
          builder: (context, duration, _) {
            final total = duration ?? Duration.zero;
            final maxSec = total.inMilliseconds / 1000.0;
            final value = (position.inMilliseconds / 1000.0)
                .clamp(0.0, maxSec > 0 ? maxSec : 0.0);
            return Row(
              children: [
                Text(_fmt(position), style: const TextStyle(color: Colors.white70)),
                Expanded(
                  child: Slider(
                    value: value,
                    max: maxSec > 0 ? maxSec : 1.0,
                    onChangeStart: (_) => _controlsVisible.value = true,
                    onChanged: (v) {
                      _controlsVisible.value = true;
                    },
                    onChangeEnd: (v) {
                      final player = _player;
                      if (player != null) {
                        player.seek(
                          Duration(milliseconds: (v * 1000).round()),
                        );
                      }
                    },
                  ),
                ),
                Text(_fmt(total), style: const TextStyle(color: Colors.white70)),
              ],
            );
          },
        );
      },
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  Future<void> _showMoreSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final settings = ctx.watch<SettingsService>();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const ListTile(
                title: Text('更多设置'),
                subtitle: Text('视频播放器'),
              ),
              const Divider(height: 1, color: AppColors.divider),
              SwitchListTile(
                secondary: const Icon(Icons.lock_outline),
                title: const Text('锁定屏幕'),
                subtitle: const Text('锁定后隐藏控件并禁用手势'),
                value: _locked.value,
                onChanged: (_) {
                  _toggleLock();
                  Navigator.pop(ctx);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.screen_lock_rotation_outlined),
                title: const Text('锁定旋转方向'),
                subtitle: const Text('固定为当前横屏/竖屏'),
                value: _rotationLocked.value,
                onChanged: (_) {
                  _toggleRotationLock();
                  Navigator.pop(ctx);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.picture_in_picture_alt),
                title: const Text('允许画中画'),
                subtitle: const Text('此开关保存在设置中'),
                value: settings.videoPipEnabled,
                onChanged: (v) {
                  settings.setVideoPipEnabled(v);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.headset_outlined),
                title: const Text('后台播放'),
                subtitle: const Text('离开播放器后继续播放'),
                value: settings.videoBackgroundPlayback,
                onChanged: (v) {
                  settings.setVideoBackgroundPlayback(v);
                },
              ),
              ListTile(
                leading: const Icon(Icons.touch_app_outlined),
                title: const Text('手势设置'),
                subtitle: const Text('双击 / 长按动作'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _showGestureSettings();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showGestureSettings() async {
    final settings = context.read<SettingsService>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        VideoGestureAction left = settings.videoLeftDoubleTap;
        VideoGestureAction right = settings.videoRightDoubleTap;
        VideoGestureAction long = settings.videoLongPress;
        return StatefulBuilder(
          builder: (ctx, setLocal) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '手势设置',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  _gestureDropdown(
                    ctx,
                    label: '左侧双击',
                    value: left,
                    onChanged: (v) {
                      setLocal(() => left = v);
                      settings.setVideoLeftDoubleTap(v);
                    },
                  ),
                  _gestureDropdown(
                    ctx,
                    label: '右侧双击',
                    value: right,
                    onChanged: (v) {
                      setLocal(() => right = v);
                      settings.setVideoRightDoubleTap(v);
                    },
                  ),
                  _gestureDropdown(
                    ctx,
                    label: '长按',
                    value: long,
                    onChanged: (v) {
                      setLocal(() => long = v);
                      settings.setVideoLongPress(v);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _gestureDropdown(
    BuildContext ctx, {
    required String label,
    required VideoGestureAction value,
    required ValueChanged<VideoGestureAction> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label)),
          Expanded(
            child: DropdownButton<VideoGestureAction>(
              value: value,
              isExpanded: true,
              items: [
                for (final a in VideoGestureAction.values)
                  DropdownMenuItem(value: a, child: Text(a.labelZh)),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}
