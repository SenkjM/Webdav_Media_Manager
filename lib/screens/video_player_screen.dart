import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../models/video_settings.dart';
import '../models/webdav_item.dart';
import '../models/webdav_stream.dart';
import '../services/audio_player_service.dart';
import '../services/settings_service.dart';
import '../services/video_playback_service.dart';
import '../services/video_queue_controller.dart';
import '../services/webdav_service.dart';
import '../theme/app_theme.dart';
import '../utils/android_background.dart';
import '../utils/video_pip.dart';

/// Everything the player needs to build a play queue for one video.
class VideoQueueSeed {
  const VideoQueueSeed({
    required this.accountId,
    required this.folderPath,
    required this.current,
    this.siblings = const [],
  });

  final String accountId;

  /// Folder used as the root of the background scan.
  final String folderPath;

  /// The video the user actually tapped.
  final WebDavItem current;

  /// Videos already known in [folderPath] (the listing the user tapped in), so
  /// playback can start without waiting for the scan.
  final List<WebDavItem> siblings;
}

/// Full-screen WebDAV video player (streaming via media_kit).
///
/// Layout / gesture rules:
/// * controls are drawn as a **low floating cluster**, clear of the middle of
///   the frame so they never cover the picture;
/// * single tap toggles the controls, another single tap hides them again;
/// * double tap in the **middle third** = play / pause; the left and right
///   thirds run the configured seek gestures;
/// * long press = temporary speed boost (rate from Settings, restored on
///   release);
/// * a floating speed slider covers 0.5×–3.0×;
/// * picture-in-picture hides every control;
/// * background playback happens when the task is sent to the background
///   (Home key), never when the player route is popped;
/// * the queue comes from a progressive folder scan, so 上一个 / 下一个 and
///   auto-advance work while the scan is still running.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.source,
    this.seed,
  });

  final WebDavStreamSource source;

  /// When present, a queue is built by scanning [VideoQueueSeed.folderPath].
  final VideoQueueSeed? seed;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  VideoPlaybackService? _service;
  Player? _player;
  VideoController? _controller;
  VideoQueueController? _queue;

  bool _loading = true;
  String? _error;
  bool _switching = false;

  final List<StreamSubscription<dynamic>> _subs = [];

  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration?> _duration = ValueNotifier(null);
  final ValueNotifier<bool> _playing = ValueNotifier(false);
  final ValueNotifier<bool> _buffering = ValueNotifier(false);
  final ValueNotifier<double> _rate = ValueNotifier(1.0);
  final ValueNotifier<bool> _controlsVisible = ValueNotifier(true);
  final ValueNotifier<bool> _locked = ValueNotifier(false);
  final ValueNotifier<bool> _rotationLocked = ValueNotifier(false);
  final ValueNotifier<bool> _pip = ValueNotifier(false);

  final ValueNotifier<_SeekFeedback?> _seekFeedback =
      ValueNotifier<_SeekFeedback?>(null);

  /// Title shown in the bar / notification (changes as the queue advances).
  final ValueNotifier<String> _title = ValueNotifier('');

  StreamSubscription<bool>? _pipSub;
  StreamSubscription<bool>? _completedSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _title.value = widget.source.name;
    _pipSub = pictureInPictureChanges.listen((active) {
      _pip.value = active;
      if (active) _controlsVisible.value = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  // --- Open / switch ----------------------------------------------------

  Future<void> _open() async {
    final service = context.read<VideoPlaybackService>();
    final settings = context.read<SettingsService>();
    final music = context.read<AudioPlayerService>();
    _service = service;
    _buildQueue();
    try {
      // Music and video must never play at the same time.
      await music.pauseForVideo();
      final restored = SettingsService.clampVideoRate(settings.videoLastRate);
      final player = await service.prepare(
        widget.source,
        bufferSizeMb: settings.videoBufferSizeMb,
        initialRate: restored,
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
      if ((restored - 1.0).abs() > 0.001) {
        await player.setRate(restored);
        _rate.value = restored;
      }
      await player.open(service.mediaFor(widget.source));
      if (!mounted) return;
      setState(() => _loading = false);
      if (await isInPictureInPicture()) _pip.value = true;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _buildQueue() {
    final seed = widget.seed;
    if (seed == null) return;
    final queue = VideoQueueController(
      webDav: context.read<WebDavService>(),
      accountId: seed.accountId,
      rootPath: seed.folderPath,
      seed: seed.siblings,
      initialRemotePath: seed.current.path,
      fileTypes: context.read<SettingsService>().fileTypes,
      autoAdvance: true,
    );
    queue.addListener(_onQueueChanged);
    _queue = queue;
    // Progressive: never await this, playback starts from the seed.
    queue.startScan();
  }

  void _onQueueChanged() {
    if (mounted) setState(() {});
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
    // Auto-advance to the next video in the folder when one finishes.
    _completedSub = player.stream.completed.listen((completed) {
      if (completed && mounted) unawaited(_playNext(auto: true));
    });
    _position.value = player.state.position;
    _duration.value = player.state.duration;
    _playing.value = player.state.playing;
    _rate.value = player.state.rate;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pipSub?.cancel();
    _completedSub?.cancel();
    _queue?.removeListener(_onQueueChanged);
    _queue?.dispose();
    unawaited(_service?.endBoost() ?? Future<void>.value());
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
    _pip.dispose();
    _seekFeedback.dispose();
    _title.dispose();
    // Restore free rotation; the Video widget detaches the texture itself and
    // the Player lifetime stays owned by the audio handler.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  /// Switch to [item] without tearing down the VideoController: the controller
  /// stays bound to the same player, only the media changes.
  Future<void> _switchTo(WebDavItem item) async {
    final player = _player;
    final service = _service;
    if (player == null || service == null || _switching) return;
    final source = _streamFor(item);
    if (source == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebDAV 未连接，无法播放')),
      );
      return;
    }
    setState(() {
      _switching = true;
      _buffering.value = true;
      _position.value = Duration.zero;
      _duration.value = null;
    });
    try {
      await service.endBoost();
      final settings = context.read<SettingsService>();
      final rate = SettingsService.clampVideoRate(settings.videoLastRate);
      await service.prepare(
        source,
        bufferSizeMb: settings.videoBufferSizeMb,
        initialRate: rate,
      );
      _title.value = item.name;
      await player.open(service.mediaFor(source), play: true);
      if ((rate - 1.0).abs() > 0.001) await player.setRate(rate);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切换视频失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _switching = false;
          _buffering.value = false;
        });
      }
    }
  }

  WebDavStreamSource? _streamFor(WebDavItem item) {
    final queue = _queue;
    return context.read<WebDavService>().buildStreamSource(
          remotePath: item.path,
          name: item.name,
          accountId: queue?.accountId ?? widget.source.accountId,
        );
  }

  Future<void> _playNext({bool auto = false}) async {
    final queue = _queue;
    if (queue == null) {
      if (!auto) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前没有播放列表')),
        );
      }
      return;
    }
    final next = queue.next;
    if (next == null) {
      if (!auto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              queue.scanning ? '已到列表末尾（仍在扫描文件夹…）' : '已是最后一个视频',
            ),
          ),
        );
      } else {
        await _player?.pause();
      }
      return;
    }
    queue.selectRemotePath(next.path);
    await _switchTo(next);
  }

  Future<void> _playPrevious() async {
    final queue = _queue;
    if (queue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有播放列表')),
      );
      return;
    }
    // Standard player behavior: restart the current video first.
    if (_position.value > const Duration(seconds: 3)) {
      await _seekBy(Duration.zero, label: '从头播放', toStart: true);
      return;
    }
    final prev = queue.previous;
    if (prev == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queue.scanning ? '已是第一个视频（仍在扫描文件夹…）' : '已是第一个视频',
          ),
        ),
      );
      return;
    }
    queue.selectRemotePath(prev.path);
    await _switchTo(prev);
  }

  // --- App lifecycle ----------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final player = _player;
    if (player == null) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Home key / recents: background playback keeps going (the media
        // foreground service from the media notification is what allows it);
        // otherwise pause so the user does not lose their place.
        if (!context.read<SettingsService>().videoBackgroundPlayback &&
            player.state.playing) {
          unawaited(player.pause());
        }
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  // --- Exit -------------------------------------------------------------

  /// Leaving the player always stops playback: background playback is triggered
  /// by sending the task to the background, not by navigating away.
  Future<void> _handleExit({bool stopPlayback = true}) async {
    final service = _service ?? context.read<VideoPlaybackService>();
    if (stopPlayback) {
      await service.endBoost();
      await service.stop();
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _handleBackPress() async {
    final confirm = context.read<SettingsService>().videoConfirmExit;
    final player = _player;
    if (confirm && player != null && player.state.playing) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.elevated,
          content: const Text('确认关闭视频吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      if (leave != true) return;
    }
    if (!mounted) return;
    await _handleExit();
  }

  /// Send the task to the background exactly like the Home key.
  Future<void> _sendToBackground() async {
    if (!context.read<SettingsService>().videoBackgroundPlayback) {
      await _handleExit();
      return;
    }
    await moveAppToBackground();
  }

  void _toggleControls() {
    if (_locked.value || _pip.value) return;
    _controlsVisible.value = !_controlsVisible.value;
  }

  // --- Gestures ---------------------------------------------------------

  Future<void> _runGesture(VideoGestureAction action) async {
    final player = _player;
    if (player == null) return;
    switch (action) {
      case VideoGestureAction.none:
        break;
      case VideoGestureAction.back10s:
        await _seekBy(const Duration(seconds: -10), label: '后退 10 秒');
        break;
      case VideoGestureAction.forward10s:
        await _seekBy(const Duration(seconds: 10), label: '前进 10 秒');
        break;
      case VideoGestureAction.back30s:
        await _seekBy(const Duration(seconds: -30), label: '后退 30 秒');
        break;
      case VideoGestureAction.forward30s:
        await _seekBy(const Duration(seconds: 30), label: '前进 30 秒');
        break;
      case VideoGestureAction.toggleRate2x:
        await _applyRate(_rate.value == 2.0 ? 1.0 : 2.0);
        break;
      case VideoGestureAction.playPause:
        await player.playOrPause();
        break;
    }
  }

  /// Seek and flash the animated feedback overlay.
  Future<void> _seekBy(
    Duration delta, {
    required String label,
    bool toStart = false,
  }) async {
    final player = _player;
    if (player == null) return;
    final dur = _duration.value ?? Duration.zero;
    var target = toStart ? Duration.zero : _position.value + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (dur > Duration.zero && target > dur) target = dur;
    await player.seek(target);
    _position.value = target;
    _showSeekFeedback(
      label: label,
      forward: !delta.isNegative,
      target: target,
    );
  }

  void _showSeekFeedback({
    required String label,
    required bool forward,
    required Duration target,
  }) {
    final id = DateTime.now().microsecondsSinceEpoch;
    _seekFeedback.value = _SeekFeedback(
      id: id,
      label: label,
      forward: forward,
      target: target,
      total: _duration.value,
    );
    Future<void>.delayed(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      if (_seekFeedback.value?.id == id) _seekFeedback.value = null;
    });
  }

  /// Apply a playback rate chosen from the floating slider (0.5×–3.0×).
  Future<void> _applyRate(double rate) async {
    final service = _service;
    if (service == null) return;
    final clamped = SettingsService.clampVideoRate(rate);
    await service.setRate(clamped);
    _rate.value = clamped;
    if (mounted) {
      await context.read<SettingsService>().setVideoLastRate(clamped);
    }
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
    _controlsVisible.value = !_locked.value;
  }

  Future<void> _enterPip() async {
    final ok = await enterPictureInPicture();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前设备/系统不支持画中画')),
      );
      return;
    }
    _controlsVisible.value = false;
  }

  // --- Long-press speed boost -------------------------------------------

  Future<void> _beginLongPress() async {
    final settings = context.read<SettingsService>();
    final action = settings.videoLongPress;
    if (action == VideoGestureAction.toggleRate2x) {
      await _service?.beginBoost(settings.videoLongPressRate);
      return;
    }
    await _runGesture(action);
  }

  Future<void> _endLongPress() async {
    final settings = context.read<SettingsService>();
    if (settings.videoLongPress != VideoGestureAction.toggleRate2x) return;
    await _service?.endBoost();
  }

  // --- Build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
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
                  onPressed: () => _handleExit(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final settings = context.watch<SettingsService>();
    // While the PiP window is up the Activity is technically in the background;
    // do not let that pause the stream or the small window would be dead.
    final pauseOnBackground = !settings.videoBackgroundPlayback && !_pip.value;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: _pip,
              builder: (context, pip, _) => Video(
                controller: _controller!,
                fit: BoxFit.contain,
                controls: (state) => const SizedBox.shrink(),
                wakelock: true,
                pauseUponEnteringBackgroundMode: pauseOnBackground,
                resumeUponEnteringForegroundMode: false,
              ),
            ),
            _buildGestureLayer(),
            Positioned.fill(child: _buildOverlay(settings)),
          ],
        ),
      ),
    );
  }

  /// Three horizontal zones so a middle double-tap can mean play/pause while
  /// the sides keep the configurable seek gestures. Each zone handles its own
  /// single tap, so a tap anywhere still toggles the controls.
  Widget _buildGestureLayer() {
    return ValueListenableBuilder<bool>(
      valueListenable: _locked,
      builder: (context, locked, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: _pip,
          builder: (context, pip, _) {
            if (locked || pip) return const SizedBox.shrink();
            return Row(
              children: [
                Expanded(
                  flex: 30,
                  child: _GestureZone(
                    onSingleTap: _toggleControls,
                    onDoubleTap: () => _runSideDoubleTap(left: true),
                    onLongPressStart: _beginLongPress,
                    onLongPressEnd: _endLongPress,
                  ),
                ),
                Expanded(
                  flex: 40,
                  child: _GestureZone(
                    onSingleTap: _toggleControls,
                    onDoubleTap: _togglePlayPause,
                    onLongPressStart: _beginLongPress,
                    onLongPressEnd: _endLongPress,
                  ),
                ),
                Expanded(
                  flex: 30,
                  child: _GestureZone(
                    onSingleTap: _toggleControls,
                    onDoubleTap: () => _runSideDoubleTap(left: false),
                    onLongPressStart: _beginLongPress,
                    onLongPressEnd: _endLongPress,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _runSideDoubleTap({required bool left}) async {
    final settings = context.read<SettingsService>();
    final action =
        left ? settings.videoLeftDoubleTap : settings.videoRightDoubleTap;
    await _runGesture(action);
  }

  Future<void> _togglePlayPause() async {
    await _player?.playOrPause();
  }

  // --- Overlay ----------------------------------------------------------

  Widget _buildOverlay(SettingsService settings) {
    return ValueListenableBuilder<bool>(
      valueListenable: _pip,
      builder: (context, pip, _) {
        // Picture-in-picture: no controls at all in the small window.
        if (pip) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: _locked,
          builder: (context, locked, _) {
            if (locked) {
              return SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _RoundIconButton(
                      icon: Icons.lock_open,
                      tooltip: '解锁',
                      onTap: _toggleLock,
                    ),
                  ),
                ),
              );
            }
            return ValueListenableBuilder<bool>(
              valueListenable: _controlsVisible,
              builder: (context, visible, _) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildFeedbackLayer(),
                    if (visible) ...[
                      _buildTopStrip(settings),
                      _buildBottomCluster(settings),
                    ],
                    ValueListenableBuilder<bool>(
                      valueListenable: _buffering,
                      builder: (context, buffering, _) => buffering
                          ? const Center(
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: CircularProgressIndicator(strokeWidth: 3),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFeedbackLayer() {
    return ValueListenableBuilder<_SeekFeedback?>(
      valueListenable: _seekFeedback,
      builder: (context, feedback, _) {
        if (feedback == null) return const SizedBox.shrink();
        return IgnorePointer(
          child: Center(
            child: _SeekFeedbackPill(
              key: ValueKey<int>(feedback.id),
              feedback: feedback,
            ),
          ),
        );
      },
    );
  }

  /// Title + non-transport actions, in a small pill at the very top.
  Widget _buildTopStrip(SettingsService settings) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundIconButton(
                icon: Icons.arrow_back,
                tooltip: '返回',
                onTap: _handleBackPress,
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: ValueListenableBuilder<String>(
                  valueListenable: _title,
                  builder: (context, title, _) => Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
              if (_queue != null)
                _RoundIconButton(
                  icon: Icons.playlist_play,
                  tooltip: '播放列表',
                  onTap: _showQueueSheet,
                ),
              _RoundIconButton(
                icon: Icons.home_outlined,
                tooltip: '转到后台（继续播放）',
                onTap: _sendToBackground,
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
        ),
      ),
    );
  }

  /// Transport + secondary controls, anchored to the **lower** part of the
  /// frame so the middle of the picture stays unobstructed.
  Widget _buildBottomCluster(SettingsService settings) {
    return SafeArea(
      child: Align(
        alignment: const Alignment(0, 0.66),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_queue != null)
                          _CenterIconButton(
                            icon: Icons.skip_previous,
                            tooltip: '上一个视频',
                            size: 28,
                            onTap: _playPrevious,
                          ),
                        _CenterIconButton(
                          icon: Icons.replay_10,
                          tooltip: '后退 10 秒',
                          size: 28,
                          onTap: () => _seekBy(
                            const Duration(seconds: -10),
                            label: '后退 10 秒',
                          ),
                        ),
                        const SizedBox(width: 4),
                        ValueListenableBuilder<bool>(
                          valueListenable: _playing,
                          builder: (context, playing, _) => _CenterIconButton(
                            icon: playing ? Icons.pause : Icons.play_arrow,
                            tooltip: playing ? '暂停' : '播放',
                            size: 40,
                            onTap: _togglePlayPause,
                          ),
                        ),
                        const SizedBox(width: 4),
                        _CenterIconButton(
                          icon: Icons.forward_10,
                          tooltip: '前进 10 秒',
                          size: 28,
                          onTap: () => _seekBy(
                            const Duration(seconds: 10),
                            label: '前进 10 秒',
                          ),
                        ),
                        if (_queue != null)
                          _CenterIconButton(
                            icon: Icons.skip_next,
                            tooltip: '下一个视频',
                            size: 28,
                            onTap: () => _playNext(),
                          ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RoundIconButton(
                          icon: Icons.lock_outline,
                          tooltip: '锁定屏幕',
                          onTap: _toggleLock,
                        ),
                        _SpeedButton(
                          rateListenable: _rate,
                          onTap: () => _showSpeedSheet(settings),
                        ),
                        if (settings.videoPipEnabled)
                          _RoundIconButton(
                            icon: Icons.picture_in_picture_alt,
                            tooltip: '画中画',
                            onTap: _enterPip,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_queue != null) ...[
                const SizedBox(height: 4),
                _queueLabel(),
              ],
              const SizedBox(height: 4),
              _buildProgressRow(),
            ],
          ),
        ),
      ),
    );
  }

  /// `3 / 27 · 扫描中…` — shows the progressive scan making progress.
  Widget _queueLabel() {
    final queue = _queue!;
    final total = queue.length;
    final idx = queue.index;
    final parts = <String>[
      if (idx >= 0) '${idx + 1} / $total' else '— / $total',
      if (queue.scanning) '扫描中…',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        parts.join(' · '),
        style: const TextStyle(color: Colors.white70, fontSize: 11),
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
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Text(
                    _fmt(position),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
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
                  Text(
                    _fmt(total),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
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

  // --- Queue sheet ------------------------------------------------------

  Future<void> _showQueueSheet() async {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '播放列表',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: queue,
                    builder: (ctx, _) {
                      final tracks = queue.tracks;
                      return ListView.builder(
                        itemCount: tracks.length,
                        itemBuilder: (ctx, i) {
                          final t = tracks[i];
                          final selected = t.path == queue.currentRemotePath;
                          return ListTile(
                            dense: true,
                            selected: selected,
                            leading: Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: selected
                                    ? AppColors.accent
                                    : AppColors.mutedText,
                                fontSize: 12,
                              ),
                            ),
                            title: Text(
                              t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? AppColors.accent
                                    : AppColors.onDark,
                              ),
                            ),
                            subtitle: t.size != null
                                ? Text(
                                    _fmtBytes(t.size!),
                                    style: const TextStyle(fontSize: 11),
                                  )
                                : null,
                            onTap: () {
                              Navigator.pop(ctx);
                              if (selected) return;
                              queue.selectRemotePath(t.path);
                              unawaited(_switchTo(t));
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                if (queue.scanning)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text(
                          '正在扫描文件夹，列表会继续增加…',
                          style: TextStyle(
                            color: AppColors.mutedText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // --- Floating speed slider --------------------------------------------

  Future<void> _showSpeedSheet(SettingsService settings) async {
    var draft = _rate.value;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.speed, color: AppColors.accent),
                    const SizedBox(width: 8),
                    const Text(
                      '播放倍速',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${draft.toStringAsFixed(2)}×',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: draft.clamp(
                    SettingsService.minVideoRate,
                    SettingsService.maxVideoRate,
                  ),
                  min: SettingsService.minVideoRate,
                  max: SettingsService.maxVideoRate,
                  divisions: SettingsService.videoRateDivisions,
                  label: '${draft.toStringAsFixed(2)}×',
                  onChanged: (v) => setLocal(() => draft = v),
                  onChangeEnd: (v) => _applyRate(v),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${SettingsService.minVideoRate.toStringAsFixed(1)}×',
                      style: const TextStyle(
                        color: AppColors.mutedText,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${SettingsService.maxVideoRate.toStringAsFixed(1)}×',
                      style: const TextStyle(
                        color: AppColors.mutedText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final preset in const [0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0])
                      ChoiceChip(
                        label: Text('${preset.toStringAsFixed(2)}×'),
                        selected: (draft - preset).abs() < 0.001,
                        onSelected: (_) {
                          setLocal(() => draft = preset);
                          _applyRate(preset);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '长按画面可临时加速（当前 '
                  '${settings.videoLongPressRate.toStringAsFixed(2)}×，'
                  '可在「视频播放设置」中调整）。',
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- More settings sheet ----------------------------------------------

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
                secondary: const Icon(Icons.exit_to_app),
                title: const Text('退出时二次确认'),
                subtitle: const Text('返回时询问「确认关闭视频吗？」'),
                value: settings.videoConfirmExit,
                onChanged: (v) => settings.setVideoConfirmExit(v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.picture_in_picture_alt),
                title: const Text('允许画中画'),
                subtitle: const Text('此开关保存在设置中'),
                value: settings.videoPipEnabled,
                onChanged: (v) => settings.setVideoPipEnabled(v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.headset_outlined),
                title: const Text('后台播放'),
                subtitle: const Text('按主页键挂后台后继续播放；返回键会停止'),
                value: settings.videoBackgroundPlayback,
                onChanged: (v) => settings.setVideoBackgroundPlayback(v),
              ),
              ListTile(
                leading: const Icon(Icons.touch_app_outlined),
                title: const Text('手势设置'),
                subtitle: const Text('双击 / 长按动作与长按倍速'),
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
        double longRate = settings.videoLongPressRate;
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
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '单击画面显示 / 隐藏控件；双击画面中间为播放 / 暂停。',
                      style: TextStyle(
                        color: AppColors.mutedText,
                        fontSize: 12,
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
                  if (long == VideoGestureAction.toggleRate2x) ...[
                    const Divider(height: 24, color: AppColors.divider),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Expanded(child: Text('长按临时倍速')),
                          Text(
                            '${longRate.toStringAsFixed(2)}×',
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Slider(
                      value: longRate.clamp(
                        SettingsService.minVideoRate,
                        SettingsService.maxVideoRate,
                      ),
                      min: SettingsService.minVideoRate,
                      max: SettingsService.maxVideoRate,
                      divisions: SettingsService.videoRateDivisions,
                      label: '${longRate.toStringAsFixed(2)}×',
                      onChanged: (v) {
                        setLocal(() => longRate = v);
                        settings.setVideoLongPressRate(v);
                      },
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        '按住画面时加速到此倍速，松手恢复用户选择的倍速。',
                        style: TextStyle(
                          color: AppColors.mutedText,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
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

/// One horizontal gesture zone (left / middle / right).
class _GestureZone extends StatelessWidget {
  const _GestureZone({
    required this.onSingleTap,
    required this.onDoubleTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  final VoidCallback onSingleTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSingleTap,
      onDoubleTap: onDoubleTap,
      onLongPressStart: (_) => onLongPressStart(),
      onLongPressEnd: (_) => onLongPressEnd(),
      onLongPressCancel: onLongPressEnd,
      child: const SizedBox.expand(),
    );
  }
}

/// Immutable snapshot of one 前进 / 后退 feedback animation.
class _SeekFeedback {
  const _SeekFeedback({
    required this.id,
    required this.label,
    required this.forward,
    required this.target,
    required this.total,
  });

  final int id;
  final String label;
  final bool forward;
  final Duration target;
  final Duration? total;
}

/// Scaling + fading pill that visualises a seek.
class _SeekFeedbackPill extends StatefulWidget {
  const _SeekFeedbackPill({super.key, required this.feedback});

  final _SeekFeedback feedback;

  @override
  State<_SeekFeedbackPill> createState() => _SeekFeedbackPillState();
}

class _SeekFeedbackPillState extends State<_SeekFeedbackPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.82, end: 1.06)
          .chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.06, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
      weight: 20,
    ),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 45),
  ]).animate(_controller);
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
  ]).animate(_controller);

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.feedback;
    final total = f.total;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(scale: _scale.value, child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  f.forward ? Icons.fast_forward : Icons.fast_rewind,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  f.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            if (total != null && total > Duration.zero) ...[
              const SizedBox(height: 4),
              Text(
                _fmtPill(f.target),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _fmtPill(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

/// Speed chip that reflects the live playback rate.
class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.rateListenable, required this.onTap});

  final ValueListenable<double> rateListenable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: rateListenable,
      builder: (context, rate, _) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size(56, 40),
        ),
        child: Text(
          '${rate.toStringAsFixed(2)}×',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Larger tap target used for the transport buttons.
class _CenterIconButton extends StatelessWidget {
  const _CenterIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 34,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: size,
      icon: Icon(icon, color: Colors.white),
      tooltip: tooltip,
      onPressed: onTap,
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
