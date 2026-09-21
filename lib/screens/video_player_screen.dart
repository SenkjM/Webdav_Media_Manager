import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../models/video_settings.dart';
import '../models/webdav_stream.dart';
import '../services/audio_player_service.dart';
import '../services/settings_service.dart';
import '../services/video_playback_service.dart';
import '../theme/app_theme.dart';
import '../utils/android_background.dart';
import '../utils/video_pip.dart';

/// Full-screen WebDAV video player (streaming via media_kit).
///
/// Not surfaced as a cross-interface mini player (unlike music). Supports:
/// * centered floating controls (no full-width top/bottom bars)
/// * animated seek feedback for the 前进 / 后退 buttons
/// * long-press speed boost (rate from Settings, restored on release)
/// * floating 0.5×–3.0× speed slider
/// * manual portrait/landscape toggle + rotation lock + screen (UI) lock
/// * background playback (takes effect when the task is sent to the background,
///   e.g. the Home key — not when the player route is popped)
/// * picture-in-picture with the control overlay hidden
/// * a media notification / MediaSession while streaming (via the shared
///   audio handler's video mode)
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.source});

  final WebDavStreamSource source;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
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
  final ValueNotifier<bool> _pip = ValueNotifier(false);

  /// Animated seek feedback (`+10 秒`). Null when nothing is being shown.
  final ValueNotifier<_SeekFeedback?> _seekFeedback =
      ValueNotifier<_SeekFeedback?>(null);

  /// Resume position captured before the app was sent to the background.
  Duration? _resumePosition;

  VideoGestureAction? _pendingDoubleTapAction;
  StreamSubscription<bool>? _pipSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pipSub = pictureInPictureChanges.listen((active) {
      _pip.value = active;
      if (active) {
        // The small window must be free of controls.
        _controlsVisible.value = false;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final service = context.read<VideoPlaybackService>();
    final settings = context.read<SettingsService>();
    final music = context.read<AudioPlayerService>();
    _service = service;
    try {
      // Music and video must never play at the same time.
      await music.pauseForVideo();
      // Restore the user's last chosen speed (0.5×–3.0×).
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
      setState(() {
        _loading = false;
      });
      if (await isInPictureInPicture()) _pip.value = true;
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
    WidgetsBinding.instance.removeObserver(this);
    _pipSub?.cancel();
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
    // Restore free rotation; the Video widget detaches the texture itself and
    // the Player lifetime stays owned by the audio handler.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
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
          _resumePosition = player.state.position;
          unawaited(player.pause());
        }
      case AppLifecycleState.resumed:
        final resume = _resumePosition;
        _resumePosition = null;
        if (resume != null &&
            context.read<SettingsService>().videoBackgroundPlayback) {
          unawaited(player.play());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  // --- Transport --------------------------------------------------------

  /// Leaving the player stops playback. Background playback is triggered by
  /// sending the task to the background (Home key), never by navigating back.
  Future<void> _handleExit({bool stopPlayback = true}) async {
    final service = _service ?? context.read<VideoPlaybackService>();
    if (stopPlayback) {
      await service.endBoost();
      await service.stop();
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _handleBackPress() async {
    final player = _player;
    if (player != null && player.state.playing) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.elevated,
          title: const Text('退出播放？'),
          content: const Text(
            '返回将停止视频。若要让视频在后台继续播放，请按主页键。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('继续观看'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('退出并停止'),
            ),
          ],
        ),
      );
      if (leave != true) return;
    }
    if (!mounted) return;
    await _handleExit();
  }

  /// Send the task to the background exactly like the Home key, keeping
  /// playback if「后台播放」is on.
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
  Future<void> _seekBy(Duration delta, {required String label}) async {
    final player = _player;
    if (player == null) return;
    final dur = _duration.value ?? Duration.zero;
    var target = _position.value + delta;
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
    if (_locked.value) {
      _controlsVisible.value = false;
    } else {
      _controlsVisible.value = true;
    }
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
    final pauseOnBackground =
        !settings.videoBackgroundPlayback && !_pip.value;

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
            // Gesture layer sits under the controls so the buttons win the
            // hit test; it is disabled while locked or in PiP.
            _buildGestureLayer(),
            // Center-anchored controls + feedback animations.
            Positioned.fill(child: _buildCenterOverlay(settings)),
          ],
        ),
      ),
    );
  }

  Widget _buildGestureLayer() {
    return ValueListenableBuilder<bool>(
      valueListenable: _locked,
      builder: (context, locked, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: _pip,
          builder: (context, pip, _) {
            if (locked || pip) {
              return const SizedBox.shrink();
            }
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTapDown: (details) {
                final w = MediaQuery.of(context).size.width;
                final settings = context.read<SettingsService>();
                _pendingDoubleTapAction = details.localPosition.dx < w / 2
                    ? settings.videoLeftDoubleTap
                    : settings.videoRightDoubleTap;
              },
              onDoubleTap: () {
                final action = _pendingDoubleTapAction;
                if (action != null) _runGesture(action);
              },
              onLongPressStart: (_) => _beginLongPress(),
              onLongPressEnd: (_) => _endLongPress(),
              onLongPressCancel: _endLongPress,
              child: const SizedBox.expand(),
            );
          },
        );
      },
    );
  }

  // --- Long-press speed boost -------------------------------------------

  Future<void> _beginLongPress() async {
    final settings = context.read<SettingsService>();
    final action = settings.videoLongPress;
    if (action == VideoGestureAction.toggleRate2x) {
      // Temporary boost while the finger is down.
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

  // --- Overlay ----------------------------------------------------------

  Widget _buildCenterOverlay(SettingsService settings) {
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
                      _buildTopStrip(),
                      Center(child: _buildControlCluster(settings)),
                      _buildBottomProgress(),
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

  /// Animated 前进 / 后退 feedback: a scaling, fading pill in the center.
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

  /// Title + the few non-transport actions, as a small floating strip so the
  /// middle of the screen stays free for the centered controls.
  Widget _buildTopStrip() {
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
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  widget.source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
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

  /// The centered control cluster: −10s / play-pause / +10s above a small row
  /// with lock, speed and PiP.
  Widget _buildControlCluster(SettingsService settings) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              _CenterIconButton(
                icon: Icons.replay_10,
                tooltip: '后退 10 秒',
                size: 34,
                onTap: () =>
                    _seekBy(const Duration(seconds: -10), label: '后退 10 秒'),
              ),
              const SizedBox(width: 18),
              ValueListenableBuilder<bool>(
                valueListenable: _playing,
                builder: (context, playing, _) => _CenterIconButton(
                  icon: playing ? Icons.pause : Icons.play_arrow,
                  tooltip: playing ? '暂停' : '播放',
                  size: 46,
                  onTap: () => _player?.playOrPause(),
                ),
              ),
              const SizedBox(width: 18),
              _CenterIconButton(
                icon: Icons.forward_10,
                tooltip: '前进 10 秒',
                size: 34,
                onTap: () =>
                    _seekBy(const Duration(seconds: 10), label: '前进 10 秒'),
              ),
            ],
          ),
          const SizedBox(height: 6),
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
    );
  }

  /// Slim progress bar pinned to the bottom, kept out of the control cluster.
  Widget _buildBottomProgress() {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: _buildProgressRow(),
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
                  onChanged: (v) {
                    setLocal(() => draft = v);
                  },
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
                subtitle: const Text('按主页键挂后台后继续播放；返回键会停止'),
                value: settings.videoBackgroundPlayback,
                onChanged: (v) {
                  settings.setVideoBackgroundPlayback(v);
                },
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
                          const Expanded(
                            child: Text('长按临时倍速'),
                          ),
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

/// Larger tap target used for the transport buttons in the center cluster.
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
