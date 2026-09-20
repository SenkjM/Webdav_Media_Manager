import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../models/webdav_item.dart';

/// Set true (or --dart-define=AUDIO_NOTIF_DEBUG=true) to log playbackState.
const bool kAudioNotifDebug = bool.fromEnvironment(
  'AUDIO_NOTIF_DEBUG',
  defaultValue: false,
);

void _notifLog(String message) {
  if (kAudioNotifDebug || kDebugMode) {
    developer.log(message, name: 'MusicAudioHandler');
  }
}

const _kAppChannel = MethodChannel('com.webdav.webdav_music_player/app');

/// Fresh channel so IMPORTANCE_DEFAULT applies (Android does not upgrade
/// importance of an already-created channel in-place).
const String kMediaNotificationChannelId =
    'com.webdav.webdav_music_player.audio.v3';

/// Actions Android 13+ / lock screen / control center read from PlaybackState.
const Set<MediaAction> _kSystemActions = {
  MediaAction.play,
  MediaAction.pause,
  MediaAction.playPause,
  MediaAction.stop,
  MediaAction.seek,
  MediaAction.seekForward,
  MediaAction.seekBackward,
  MediaAction.skipToNext,
  MediaAction.skipToPrevious,
};

/// audio_service handler owning one [AudioPlayer]. Continuously pipes
/// just_audio events into [playbackState] / [mediaItem] / [queue] so Android
/// keeps an active MediaSession + MediaStyle notification (system media center).
class MusicAudioHandler extends BaseAudioHandler with SeekHandler {
  MusicAudioHandler({AudioPlayer? player})
      : _player = player ??
            AudioPlayer(
              // Keep interruption handling; AudioSession is configured once
              // below — do not re-configure on every play (causes focus clicks).
              handleInterruptions: true,
              androidApplyAudioAttributes: true,
              handleAudioSessionActivation: true,
            ) {
    _eventSub = _player.playbackEventStream.map(_transformEvent).listen(
      (state) {
        if (_gatePlayerEvents) {
          // Keep MediaSession non-idle while swapping sources / preparing,
          // but do not let stale playing=false undo an explicit play().
          playbackState.add(state.copyWith(
            playing: playbackState.value.playing || state.playing,
            processingState:
                state.processingState == AudioProcessingState.idle &&
                        !_allowIdleBroadcast &&
                        _index >= 0
                    ? AudioProcessingState.loading
                    : state.processingState,
            controls: _controls(
              playing: playbackState.value.playing || state.playing,
            ),
            systemActions: _kSystemActions,
            androidCompactActionIndices: const [0, 1, 3],
            queueIndex: _index >= 0 ? _index : state.queueIndex,
          ));
          return;
        }
        playbackState.add(state);
        _notifLog(
          'playbackState playing=${state.playing} '
          'proc=${state.processingState} idx=${state.queueIndex} '
          'actions=${state.systemActions.length} controls=${state.controls.length}',
        );
      },
      onError: (Object e, StackTrace st) {
        _notifLog('playbackEventStream error: $e');
      },
    );
    _completeSub = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !_gatePlayerEvents) {
        unawaited(skipToNext());
      }
    });
    unawaited(_ensureAudioSessionConfigured());
  }

  final AudioPlayer _player;
  StreamSubscription<PlaybackState>? _eventSub;
  StreamSubscription<ProcessingState>? _completeSub;

  /// When true, idle may be broadcast (tears down Android AudioService).
  bool _allowIdleBroadcast = false;

  /// Suppresses event-driven playing=false while load/play is in progress.
  bool _gatePlayerEvents = false;

  bool _audioSessionConfigured = false;
  bool _mutedForPrep = false;

  /// Optional resolver when skipping to a queue item that needs a local path.
  Future<String?> Function(TrackInfo track)? resolveLocalPath;

  final List<TrackInfo> _tracks = [];
  int _index = -1;

  List<TrackInfo> get tracks => List.unmodifiable(_tracks);
  int get index => _index;
  TrackInfo? get currentTrack =>
      (_index >= 0 && _index < _tracks.length) ? _tracks[_index] : null;
  AudioPlayer get player => _player;

  Future<void> _ensureAudioSessionConfigured() async {
    if (_audioSessionConfigured) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _audioSessionConfigured = true;
      _notifLog('AudioSession configured (music) once');
    } catch (e) {
      _notifLog('AudioSession configure failed: $e');
    }
  }

  Future<void> _muteForPrep() async {
    _mutedForPrep = true;
    try {
      await _player.setVolume(0);
    } catch (_) {}
  }

  Future<void> _unmuteWhenReady() async {
    if (!_mutedForPrep) return;
    try {
      // Wait until ExoPlayer reports ready so seek/clip/activate settles
      // while still silent — avoids the audible seek / focus click pair.
      final readyNow = _player.processingState == ProcessingState.ready ||
          _player.processingState == ProcessingState.completed;
      if (!readyNow) {
        await _player.processingStateStream
            .firstWhere(
              (s) =>
                  s == ProcessingState.ready || s == ProcessingState.completed,
            )
            .timeout(const Duration(seconds: 8), onTimeout: () {
          return _player.processingState;
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await _player.setVolume(1);
    } catch (_) {
      try {
        await _player.setVolume(1);
      } catch (_) {}
    } finally {
      _mutedForPrep = false;
    }
  }

  AudioSource _sourceFor(TrackInfo track, String localPath) {
    final start = track.clipStart;
    final end = track.clipEnd;
    final fileSrc = AudioSource.file(localPath);
    if (start != null || end != null) {
      // ClippingMediaSource starts at [start] — no play-then-seek blip.
      return ClippingAudioSource(
        child: fileSrc,
        start: start ?? Duration.zero,
        end: end,
        duration: track.duration,
      );
    }
    return fileSrc;
  }

  MediaItem mediaItemFor(TrackInfo track) {
    // Title is required for system media center; never leave empty.
    final title = track.displayTitle.trim().isEmpty
        ? track.fileName
        : track.displayTitle;
    return MediaItem(
      id: '${track.accountId}|${track.remotePath}',
      title: title,
      album: track.album,
      artist: track.displayArtist,
      duration: track.duration,
      artUri: _artUri(track),
      extras: {
        'accountId': track.accountId,
        'remotePath': track.remotePath,
        'fileName': track.fileName,
        'localPath': track.localPath,
      },
    );
  }

  Uri? _artUri(TrackInfo track) {
    final cover = track.coverPath;
    if (cover == null || cover.isEmpty) return null;
    if (!File(cover).existsSync()) return null;
    return Uri.file(cover);
  }

  /// Replace queue and start playback at [startIndex] with a resolved local path.
  Future<void> loadAndPlay({
    required List<TrackInfo> playlist,
    required int startIndex,
    required String localPath,
  }) async {
    if (playlist.isEmpty) return;
    final idx = startIndex.clamp(0, playlist.length - 1);
    _allowIdleBroadcast = false;
    _gatePlayerEvents = true;
    _tracks
      ..clear()
      ..addAll(playlist);
    _index = idx;
    _tracks[_index].localPath = localPath;

    await _ensureAudioSessionConfigured();
    await _muteForPrep();

    final items = _tracks.map(mediaItemFor).toList();
    // Real queue enables skipToNext/Previous for MediaSession callbacks.
    queue.add(items);
    final item = items[_index];
    mediaItem.add(item);
    _notifLog('mediaItem set title=${item.title} artist=${item.artist}');

    // Publish non-idle BEFORE setAudioSource. just_audio may briefly stay
    // idle / emit idle while swapping sources; mapping that through would
    // call AudioService.stop() on Android and kill the MediaStyle notification.
    playbackState.add(playbackState.value.copyWith(
      controls: _controls(playing: false),
      systemActions: _kSystemActions,
      androidCompactActionIndices: const [0, 1, 3],
      processingState: AudioProcessingState.loading,
      playing: false,
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      queueIndex: _index,
    ));

    try {
      await _player.setAudioSource(_sourceFor(_tracks[_index], localPath));
      mediaItem.add(item.copyWith(duration: _player.duration ?? item.duration));
      await play();
      // Unmute after play has started and engine is ready (still gated).
      await _unmuteWhenReady();
    } finally {
      _gatePlayerEvents = false;
      // Push authoritative state once gate lifts.
      playbackState.add(_transformEvent(_player.playbackEvent));
    }
  }

  /// Always expose skip + play/pause + stop so PlaybackState actions stay rich
  /// for Android 13+ system media buttons (not only notification addAction).
  List<MediaControl> _controls({required bool playing}) {
    return [
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.stop,
      MediaControl.skipToNext,
    ];
  }

  AudioProcessingState _mapProcessing(ProcessingState state) {
    final mapped = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[state]!;
    // Root cause #2: audio_service Android stops the MediaBrowserService when
    // processingState transitions to idle. just_audio emits idle while
    // activating/replacing sources; if we forward that after a load started,
    // startForeground never sticks and the system media center stays empty
    // even though in-process audio still plays.
    if (mapped == AudioProcessingState.idle &&
        !_allowIdleBroadcast &&
        _index >= 0) {
      return AudioProcessingState.loading;
    }
    return mapped;
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    final playing = _player.playing;
    return PlaybackState(
      controls: _controls(playing: playing),
      systemActions: _kSystemActions,
      androidCompactActionIndices: const [0, 1, 3],
      processingState: _mapProcessing(_player.processingState),
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _index >= 0 ? _index : event.currentIndex,
    );
  }

  Future<void> _loadIndex(int idx) async {
    if (idx < 0 || idx >= _tracks.length) return;
    _allowIdleBroadcast = false;
    _gatePlayerEvents = true;
    _index = idx;
    final track = _tracks[_index];
    String? local = track.localPath;
    if (local == null || !File(local).existsSync()) {
      final resolver = resolveLocalPath;
      if (resolver != null) {
        local = await resolver(track);
        track.localPath = local;
      }
    }
    if (local == null || !File(local).existsSync()) {
      _gatePlayerEvents = false;
      throw StateError('本地文件不可用');
    }
    await _muteForPrep();
    final item = mediaItemFor(track);
    mediaItem.add(item);
    queue.add(_tracks.map(mediaItemFor).toList());
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.loading,
      playing: false,
      controls: _controls(playing: false),
      systemActions: _kSystemActions,
      androidCompactActionIndices: const [0, 1, 3],
      queueIndex: _index,
    ));
    try {
      await _player.setAudioSource(_sourceFor(track, local));
      mediaItem.add(item.copyWith(duration: _player.duration ?? item.duration));
      await play();
      await _unmuteWhenReady();
    } finally {
      _gatePlayerEvents = false;
      playbackState.add(_transformEvent(_player.playbackEvent));
    }
  }

  @override
  Future<void> play() async {
    // Immediate PLAYING broadcast → enterPlayingState / startForeground /
    // mediaSession.setActive(true) before just_audio's event arrives.
    // Do NOT call androidForceEnableMediaButtons here: it plays a STREAM_MUSIC
    // AudioTrack of silence and causes the audible double click/pop on start,
    // and races with ExoPlayer audio focus.
    final proc = _player.processingState == ProcessingState.ready
        ? AudioProcessingState.ready
        : AudioProcessingState.buffering;
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      processingState: proc == AudioProcessingState.idle
          ? AudioProcessingState.buffering
          : proc,
      controls: _controls(playing: true),
      systemActions: _kSystemActions,
      androidCompactActionIndices: const [0, 1, 3],
      updatePosition: _player.position,
      queueIndex: _index >= 0 ? _index : null,
    ));
    _notifLog('play() → playing=true proc=$proc muted=$_mutedForPrep');
    await _player.play();
  }

  @override
  Future<void> pause() async {
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      controls: _controls(playing: false),
      systemActions: _kSystemActions,
      androidCompactActionIndices: const [0, 1, 3],
      updatePosition: _player.position,
    ));
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    _allowIdleBroadcast = true;
    _gatePlayerEvents = false;
    try {
      if (_mutedForPrep) {
        _mutedForPrep = false;
        try {
          await _player.setVolume(1);
        } catch (_) {}
      }
      await _player.stop();
      await super.stop();
    } finally {
      mediaItem.add(null);
      queue.add(const []);
      _index = -1;
      _tracks.clear();
      _allowIdleBroadcast = false;
    }
  }

  /// Do not stop when the Activity task is removed while media FGS runs.
  /// Explicit stop only via pause/stop controls or drawer 「退出应用」.
  @override
  Future<void> onTaskRemoved() async {}

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_index + 1 >= _tracks.length) {
      // Keep session metadata; just pause at end rather than idle/NONE.
      await pause();
      await seek(Duration.zero);
      return;
    }
    await _loadIndex(_index + 1);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    if (_index <= 0) {
      await seek(Duration.zero);
      return;
    }
    await _loadIndex(_index - 1);
  }

  @override
  Future<void> skipToQueueItem(int index) => _loadIndex(index);

  /// Native probe: session / posted notification / channel importance.
  Future<String> probeMediaNotificationNative() async {
    if (kIsWeb || !Platform.isAndroid) {
      return '仅 Android 可探测媒体通知';
    }
    try {
      final raw = await _kAppChannel.invokeMethod<dynamic>(
        'mediaNotificationDiagnostics',
      );
      if (raw is Map) {
        final map = raw.map((k, v) => MapEntry(k.toString(), v));
        final svc = map['audioServiceRunning'] == true;
        final active = map['mediaSessionActive'] == true;
        final posted = map['notificationPosted'] == true;
        final perm = map['notificationsEnabled'];
        final chImp = map['channelImportance'];
        final chName = map['channelId'];
        final ourSessions = map['ourActiveSessionCount'];
        return '服务=${svc ? "运行" : "无"} 会话=${active ? "活跃" : "否"} '
            '通知=${posted ? "已发布" : "未发布"} '
            '系统通知开关=$perm 通道=$chName 重要性=$chImp '
            '本包会话数=$ourSessions';
      }
      return '探测返回: $raw';
    } on MissingPluginException {
      return '原生探测通道不可用（需完整 APK）';
    } on PlatformException catch (e) {
      return '探测失败: ${e.message}';
    }
  }

  /// Debug helper: force a MediaItem + playing state so Settings can verify
  /// that a MediaStyle notification appears without a full library download.
  Future<String> debugForceMediaNotification({String? localPath}) async {
    await _ensureAudioSessionConfigured();
    TrackInfo? track = currentTrack;
    String? path = localPath ?? track?.localPath;
    if (path == null || !File(path).existsSync()) {
      // Prefer any queued track with a readable file.
      for (final t in _tracks) {
        final p = t.localPath;
        if (p != null && File(p).existsSync()) {
          track = t;
          path = p;
          break;
        }
      }
    }
    if (track == null || path == null || !File(path).existsSync()) {
      final probe = await probeMediaNotificationNative();
      return '无可用本地音频。请先播放一首歌，再点测试。\n$probe';
    }
    final idx = _tracks.indexWhere(
      (t) => t.remotePath == track!.remotePath && t.accountId == track.accountId,
    );
    await loadAndPlay(
      playlist: idx >= 0 ? _tracks : [track],
      startIndex: idx >= 0 ? idx : 0,
      localPath: path,
    );
    // Give the platform a beat to post FGS notification.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final st = playbackState.value;
    final probe = await probeMediaNotificationNative();
    return '已强制播放「${track.displayTitle}」 '
        'playing=${st.playing} proc=${st.processingState}\n'
        '$probe\n'
        '请查看通知栏 / 媒体控制中心。';
  }

  Future<void> disposePlayer() async {
    await _eventSub?.cancel();
    await _completeSub?.cancel();
    await _player.dispose();
  }
}

/// Creates and registers the platform audio service (Android/iOS).
/// Must be called before any other [AudioPlayer] is created.
Future<MusicAudioHandler> initMusicAudioService() {
  return AudioService.init<MusicAudioHandler>(
    builder: MusicAudioHandler.new,
    config: AudioServiceConfig(
      // v3: new channel id so IMPORTANCE_DEFAULT applies for upgrades that
      // still had v1/v2 channels from earlier builds.
      androidNotificationChannelId: kMediaNotificationChannelId,
      androidNotificationChannelName: '音乐播放',
      androidNotificationChannelDescription: '正在播放的音乐控制',
      androidNotificationOngoing: true,
      // Keep FGS while paused so Android 12+ does not block restarting
      // startForegroundService when play() races with event-driven pause.
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'drawable/ic_stat_music',
      androidNotificationClickStartsActivity: true,
      androidShowNotificationBadge: false,
    ),
  );
}
