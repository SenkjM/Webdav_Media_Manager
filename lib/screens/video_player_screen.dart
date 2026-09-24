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
import '../utils/video_pip.dart';
import '../widgets/app_bottom_sheet.dart';
import '../utils/app_snack.dart';

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
  const VideoPlayerScreen({super.key, required this.source, this.seed});

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

  /// Real video aspect ratio (width / height), or null until libmpv reports it.
  /// Used to place the control bar just below the letterboxed picture.
  double? _videoAspectRatio;

  /// Current subtitle text (only used by 视频下方 mode, which renders its own).
  final ValueNotifier<String> _subtitleText = ValueNotifier('');

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
      // 播放器实例与流式音乐页共用：把音乐页可能设上的循环清掉，
      // 否则听完一首歌再来看视频，视频也会跟着循环。
      await player.setPlaylistMode(PlaylistMode.none);
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
      deepScan: context.read<SettingsService>().videoScanSubdirs,
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
    _subs.add(
      player.stream.error.listen((e) {
        if (!mounted || e.isEmpty) return;
        setState(() => _error = e);
        AppSnack.show(context, '播放错误：$e');
      }),
    );
    // Auto-advance to the next video in the folder when one finishes.
    _completedSub = player.stream.completed.listen((completed) {
      if (completed && mounted) unawaited(_playNext(auto: true));
    });
    // Track the real video size so the control bar can sit under the picture.
    void syncAspect() {
      final w = player.state.width;
      final h = player.state.height;
      final ratio = (w != null && h != null && w > 0 && h > 0) ? w / h : null;
      if (ratio != _videoAspectRatio && mounted) {
        setState(() => _videoAspectRatio = ratio);
      }
    }

    _subs.add(player.stream.width.listen((_) => syncAspect()));
    _subs.add(player.stream.height.listen((_) => syncAspect()));
    // Keep the active subtitle text for 视频下方 mode (the built-in subtitle view
    // is disabled there, so we render the lines ourselves).
    _subs.add(
      player.stream.subtitle.listen((lines) {
        if (!mounted) return;
        _subtitleText.value = lines
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .join('\n');
      }),
    );
    _position.value = player.state.position;
    _duration.value = player.state.duration;
    _playing.value = player.state.playing;
    _rate.value = player.state.rate;
    syncAspect();
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
    _subtitleText.dispose();
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
    final source = await _streamFor(item);
    if (source == null) {
      AppSnack.show(context, 'WebDAV 未连接，无法播放');
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
      AppSnack.show(context, '切换视频失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _switching = false;
          _buffering.value = false;
        });
      }
    }
  }

  Future<WebDavStreamSource?> _streamFor(WebDavItem item) {
    final queue = _queue;
    return context.read<WebDavService>().resolveStreamSource(
      remotePath: item.path,
      name: item.name,
      accountId: queue?.accountId ?? widget.source.accountId,
    );
  }

  Future<void> _playNext({bool auto = false}) async {
    final queue = _queue;
    if (queue == null) {
      if (!auto) {
        AppSnack.show(context, '当前没有播放列表');
      }
      return;
    }
    final next = queue.next;
    if (next == null) {
      if (!auto) {
        AppSnack.show(
          context,
          queue.scanning ? '已到列表末尾（仍在扫描文件夹…）' : '已是最后一个视频',
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
      AppSnack.show(context, '当前没有播放列表');
      return;
    }
    // Standard player behavior: restart the current video first.
    if (_position.value > const Duration(seconds: 3)) {
      await _seekBy(Duration.zero, label: '从头播放', toStart: true);
      return;
    }
    final prev = queue.previous;
    if (prev == null) {
      AppSnack.show(context, queue.scanning ? '已是第一个视频（仍在扫描文件夹…）' : '已是第一个视频');
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
    _showSeekFeedback(label: label, forward: !delta.isNegative, target: target);
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
      AppSnack.show(context, '当前设备/系统不支持画中画');
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
                const Icon(
                  Icons.error_outline,
                  color: Colors.white70,
                  size: 48,
                ),
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
                // The built-in subtitle view is deliberately disabled: it lives
                // INSIDE the Video widget, so the control overlay (a later sibling
                // in this Stack) always painted on top of it and subtitles looked
                // like they rendered "under" the controls. We draw subtitles
                // ourselves in the overlay stack instead, above the controls.
                subtitleViewConfiguration: const SubtitleViewConfiguration(
                  visible: false,
                ),
              ),
            ),
            _buildGestureLayer(),
            Positioned.fill(child: _buildOverlay(settings)),
            // Subtitles last so they are never covered by the control bars.
            Positioned.fill(
              child: IgnorePointer(child: _buildSubtitles(settings)),
            ),
          ],
        ),
      ),
    );
  }

  /// Subtitles, drawn above every control.
  ///
  /// Placement is fixed by design: just above the bottom control bar, or at the
  /// bottom of the window when the controls are hidden. That is the one spot that
  /// never fights with the control bars regardless of aspect ratio / orientation
  /// (earlier "inside the picture" attempts kept ending up underneath them).
  ///
  /// Drawn last in the Stack so it can never be covered; ignored for hit testing
  /// so taps still reach the gesture layer.
  Widget _buildSubtitles(SettingsService settings) {
    if (settings.videoSubtitlePosition == VideoSubtitlePosition.hidden) {
      return const SizedBox.shrink();
    }
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // Rebuild on control visibility changes so the subtitle tracks the bar.
    return ValueListenableBuilder<bool>(
      valueListenable: _controlsVisible,
      builder: (context, visible, _) => ValueListenableBuilder<bool>(
        valueListenable: _locked,
        builder: (context, locked, _) => ValueListenableBuilder<bool>(
          valueListenable: _pip,
          builder: (context, pip, _) {
            final controlsShown = visible && !locked && !pip;
            // Controls visible → clear the control bar; hidden → sit at the
            // bottom of the window (still above the system gesture area).
            final bottom = controlsShown
                ? _approxControlsHeight + bottomInset
                : bottomInset + 12;
            return Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
                child: ValueListenableBuilder<String>(
                  valueListenable: _subtitleText,
                  builder: (context, text, _) {
                    if (text.trim().isEmpty) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: settings.videoSubtitleFontSize,
                          height: 1.3,
                          shadows: const [
                            Shadow(blurRadius: 4, color: Colors.black87),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Typical height of the bottom control card; subtitles sit clear of it.
  static const double _approxControlsHeight = 132.0;

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
    final action = left
        ? settings.videoLeftDoubleTap
        : settings.videoRightDoubleTap;
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
                    child: Tooltip(
                      message: '长按解锁',
                      child: GestureDetector(
                        // Long-press only: a single tap must not unlock, otherwise
                        // an accidental brush against the screen defeats the lock.
                        onLongPress: _toggleLock,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock_outline,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
            return ValueListenableBuilder<bool>(
              valueListenable: _controlsVisible,
              builder: (context, visible, _) {
                // Controls fade + slide in/out instead of hard-cutting. They
                // stay laid out (IgnorePointer) so the transition is smooth.
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildFeedbackLayer(),
                    _AnimatedControls(
                      visible: visible,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildTopStrip(settings),
                          _buildBottomCluster(settings),
                        ],
                      ),
                    ),
                    // Buffering must never eat the middle double-tap zone:
                    // IgnorePointer keeps the gesture layer beneath reachable,
                    // and it is drawn above centre so the picture stays clear.
                    ValueListenableBuilder<bool>(
                      valueListenable: _buffering,
                      builder: (context, buffering, _) => IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: buffering ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: const _BufferingBadge(),
                        ),
                      ),
                    ),
                    // Switching to another queue entry: the previous frame would
                    // otherwise sit there frozen with no feedback at all.
                    if (_switching) _SwitchingOverlay(title: _title.value),
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

  /// Title + non-transport actions, in a small pill hugging the **top of the
  /// video** (mirrors how the bottom bar hugs its lower edge).
  ///
  /// Full-width bar (not a pill that hugs its content).
  ///
  /// The action set adapts to available width: on a narrow portrait phone
  /// (360dp is common) five 48px buttons plus a title do not fit, so the title
  /// shrinks instead. (切换横竖屏 lives in the bottom bar.)
  Widget _buildTopStrip(SettingsService settings) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final landscape = size.width > size.height;
    // Mirror the bottom bar's contain-fit maths to find where the picture starts.
    final slot = Size(landscape ? size.width : 860.0, size.height);
    final ar = _videoAspectRatio;
    final fitted = ar == null
        ? slot
        : applyBoxFit(BoxFit.contain, Size(ar, 1), slot).destination;
    final videoTop = (size.height - fitted.height) / 2;
    final bandAbove = videoTop - media.padding.top;
    const stripHeight = 52.0;
    // Portrait: pin to the very top. Landscape: hug the picture's upper edge.
    final hugPicture = landscape && bandAbove > stripHeight;

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(
          left: 8,
          right: 8,
          top:
              media.padding.top +
              (hugPicture ? bandAbove - stripHeight + 6 : 6),
        ),
        child: SizedBox(
          // Always span the available width: the bar used to hug a short title,
          // which made it look inconsistent between videos.
          width: double.infinity,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                _RoundIconButton(
                  icon: Icons.arrow_back,
                  tooltip: '返回',
                  onTap: _handleBackPress,
                ),
                Expanded(
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
                  icon: Icons.more_vert,
                  tooltip: '更多设置',
                  onTap: _showMoreSettings,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Transport + progress, in ONE card placed just below the **video**, not at
  /// the bottom of the screen.
  ///
  /// Why not simply bottom-anchored: `BoxFit.contain` letterboxes, so on a tall
  /// phone a 16:9 video leaves a large black band underneath. Pinning the
  /// controls to the screen bottom then leaves an obvious empty gap between the
  /// picture and the controls. Instead we reproduce the `contain` fit from the
  /// real video size and sit the bar right under the picture — falling back to
  /// the screen bottom when that band is too shallow for the bar.
  Widget _buildBottomCluster(SettingsService settings) {
    final size = MediaQuery.of(context).size;
    final landscape = size.width > size.height;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // Mirror BoxFit.contain for the real aspect ratio (null until known, and we
    // then assume the full slot so the bar stays at the screen bottom).
    final slot = Size(landscape ? size.width : 860.0, size.height);
    final ar = _videoAspectRatio;
    final fitted = ar == null
        ? slot
        : applyBoxFit(BoxFit.contain, Size(ar, 1), slot).destination;
    final videoBottom = (size.height - fitted.height) / 2 + fitted.height;
    final bandBelow = size.height - bottomInset - videoBottom;
    // Height of this card (3 rows); keep in sync with its padding below.
    const cardHeight = 116.0;
    // Portrait: pin to the screen bottom. Hugging the picture left large empty
    // bands above AND below the controls, which looked broken on a tall phone.
    // Landscape keeps hugging the picture, where the bar reads as part of the
    // video frame.
    final hugPicture = landscape && bandBelow > cardHeight;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          left: 10,
          right: 10,
          bottom: hugPicture ? bandBelow - cardHeight + 6 : bottomInset + 6,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: landscape ? 860 : 560),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Opaque enough to stay legible over bright video.
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (_queue != null)
                          _TransportButton(
                            icon: Icons.skip_previous,
                            tooltip: '上一个视频',
                            onTap: _playPrevious,
                          )
                        else
                          const SizedBox(width: 44),
                        _TransportButton(
                          icon: Icons.replay_10,
                          tooltip: '后退 10 秒',
                          onTap: () => _seekBy(
                            const Duration(seconds: -10),
                            label: '后退 10 秒',
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _playing,
                              builder: (context, playing, _) =>
                                  _TransportButton(
                                    icon: playing
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    tooltip: playing ? '暂停' : '播放',
                                    size: 38,
                                    onTap: _togglePlayPause,
                                  ),
                            ),
                          ),
                        ),
                        _TransportButton(
                          icon: Icons.forward_10,
                          tooltip: '前进 10 秒',
                          onTap: () => _seekBy(
                            const Duration(seconds: 10),
                            label: '前进 10 秒',
                          ),
                        ),
                        if (_queue != null)
                          _TransportButton(
                            icon: Icons.skip_next,
                            tooltip: '下一个视频',
                            onTap: () => _playNext(),
                          )
                        else
                          const SizedBox(width: 44),
                      ],
                    ),
                    _buildProgressRow(),
                    Row(
                      children: [
                        _RoundIconButton(
                          icon: Icons.lock_outline,
                          tooltip: '锁定屏幕',
                          onTap: _toggleLock,
                        ),
                        // Orientation toggle lives with the controls, not buried
                        // in 更多设置 — it is a primary playback action here.
                        _RoundIconButton(
                          icon: Icons.screen_rotation,
                          tooltip: '切换横竖屏',
                          onTap: _toggleOrientation,
                        ),
                        const Spacer(),
                        if (_queue != null) ...[_queueLabel(), const Spacer()],
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
            ),
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
            final value = (position.inMilliseconds / 1000.0).clamp(
              0.0,
              maxSec > 0 ? maxSec : 0.0,
            );
            // No own background: the parent bottom bar already provides one, and
            // a nested card here was what made the layout look stacked.
            return Row(
              children: [
                Text(_fmt(position), style: _timeLabelStyle),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.5,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                    ),
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
                ),
                Text(_fmt(total), style: _timeLabelStyle),
              ],
            );
          },
        );
      },
    );
  }

  /// Time labels need a hard shadow: the scrim is translucent and bright frames
  /// (snow, sky, white text in the video) swallowed plain white70 text.
  static const _timeLabelStyle = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontFeatures: [FontFeature.tabularFigures()],
    shadows: [
      Shadow(blurRadius: 4, color: Colors.black87, offset: Offset(0, 1)),
    ],
  );

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
                          '扫描文件夹中…',
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
      isScrollControlled: true,
      shape: AppBottomSheet.shape,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AppBottomSheet(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
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
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
                  for (final preset in const [
                    0.5,
                    0.75,
                    1.0,
                    1.5,
                    2.0,
                    2.5,
                    3.0,
                  ])
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
    );
  }

  // --- More settings sheet ----------------------------------------------
  Future<void> _showMoreSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: AppBottomSheet.shape,
      builder: (ctx) {
        final settings = ctx.watch<SettingsService>();
        // Scrollable: this sheet has enough rows that its content exceeds a short
        // window, which produced "RenderFlex overflowed by 16 pixels".
        return AppBottomSheet(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('更多设置'), subtitle: Text('视频播放器')),
              const Divider(height: 1, color: AppColors.divider),
              SwitchListTile(
                secondary: const Icon(Icons.lock_outline),
                title: const Text('锁定屏幕'),
                subtitle: const Text('隐藏控件并禁用手势，长按解锁'),
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
                subtitle: const Text('返回时二次确认'),
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
                subtitle: const Text('主页键挂后台继续播放'),
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
                      '单击显示/隐藏控件，双击中间播放/暂停。',
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
                        '按住加速，松手恢复。',
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

/// Fades + slides the control chrome in and out.
///
/// Appearing is deliberately faster than disappearing: a tap that takes long to
/// show controls feels broken, while a slower fade-out looks intentional.
/// [IgnorePointer] while hidden keeps the gesture layer underneath usable, and
/// the child is never removed so the transition can actually run.
class _AnimatedControls extends StatelessWidget {
  const _AnimatedControls({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  static const _showDuration = Duration(milliseconds: 140);
  static const _hideDuration = Duration(milliseconds: 240);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.04),
        duration: visible ? _showDuration : _hideDuration,
        curve: visible ? Curves.easeOut : Curves.easeIn,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: visible ? _showDuration : _hideDuration,
          curve: visible ? Curves.easeOut : Curves.easeIn,
          child: child,
        ),
      ),
    );
  }
}

/// Small buffering pill, kept above the centre so it never covers the picture's
/// middle (and wrapped in IgnorePointer by the caller).
class _BufferingBadge extends StatelessWidget {
  const _BufferingBadge();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: const Alignment(0, -0.35),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 10),
              Text(
                '缓冲中…',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen dimmer shown while switching to another video in the queue, so
/// the previous video's last frame is not mistaken for a frozen player.
class _SwitchingOverlay extends StatelessWidget {
  const _SwitchingOverlay({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '正在打开',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
      tween: Tween(
        begin: 0.82,
        end: 1.06,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.06,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
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
          minimumSize: const Size(52, 40),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        // One decimal reads better on a control bar than the slider's
        // hundredths (1.0× instead of 1.00×).
        child: Text(
          '${rate.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '')}×',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }
}

/// Transport button for the bottom bar: even 44px tap target, fixed width so the
/// row stays balanced whether or not the queue buttons are present.
class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 28,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: size,
        icon: Icon(icon, color: Colors.white),
        tooltip: tooltip,
        onPressed: onTap,
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
