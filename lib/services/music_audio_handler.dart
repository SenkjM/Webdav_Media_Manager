import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../models/webdav_item.dart';
import '../models/webdav_stream.dart';
import 'media_notification_channel.dart';

// The「音乐播放」channel definition lives in media_notification_channel.dart and
// is created at startup by NotificationPermissionService through
// flutter_local_notifications. Re-exported so existing importers (and tests) can
// keep reading the channel id from this file.
export 'media_notification_channel.dart' show kMediaNotificationChannelId;

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

const _kAppChannel = MethodChannel('com.senkjm.media_manager/app');

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

/// Media-control buttons reference app-bundled `drawable/ic_media_*` vectors
/// instead of the audio_service plugin's default `drawable/audio_service_*`
/// icons. On Android 13+ the stop control is turned into a CustomAction whose
/// builder throws "You must specify an icon resource id to build a
/// CustomAction" when the icon resolves to 0, and the plugin's own icons are
/// not reliably merged into this app's release build. App-owned vectors live
/// in the same source set as `ic_stat_music` (which already resolves as the
/// notification small icon), so these always resolve.
const MediaControl _kSkipPreviousControl = MediaControl(
  androidIcon: 'drawable/ic_media_skip_previous',
  label: 'Previous',
  action: MediaAction.skipToPrevious,
);
const MediaControl _kPlayControl = MediaControl(
  androidIcon: 'drawable/ic_media_play',
  label: 'Play',
  action: MediaAction.play,
);
const MediaControl _kPauseControl = MediaControl(
  androidIcon: 'drawable/ic_media_pause',
  label: 'Pause',
  action: MediaAction.pause,
);
const MediaControl _kStopControl = MediaControl(
  androidIcon: 'drawable/ic_media_stop',
  label: 'Stop',
  action: MediaAction.stop,
);
const MediaControl _kSkipNextControl = MediaControl(
  androidIcon: 'drawable/ic_media_skip_next',
  label: 'Next',
  action: MediaAction.skipToNext,
);

/// Which media the shared handler currently drives.
enum AudioHandlerMode {
  /// Local-cache music queue (default).
  music,

  /// Single streamed WebDAV video. Same MediaSession/notification, but only
  /// play/pause + seek controls and no queue.
  video,
}

/// audio_service handler owning the media_kit [Player]s. Pipes their playback
/// events into [playbackState] / [mediaItem] / [queue] so Android keeps an
/// active MediaSession + MediaStyle notification (system media center).
///
/// It drives **two** players: the music player (queue playback of cached
/// local files) and the video player (one streamed WebDAV URL). Only one is
/// active at a time — [mode] selects which; both publish through the same
/// notification so video playback also gets media controls.
///
/// CUE-sheet virtual tracks (clipStart/clipEnd) have no native clipping
/// source in media_kit, so this handler remaps raw player position/duration
/// to be clip-relative itself (seek offsets by clipStart, auto-advances at
/// clipEnd) to match the previous just_audio ClippingAudioSource behavior.
class MusicAudioHandler extends BaseAudioHandler with SeekHandler {
  MusicAudioHandler({Player? player, Player? videoPlayer})
      : _player = player ?? Player(),
        _videoPlayer = videoPlayer {
    _playingSub = _player.stream.playing.listen((_) {
      if (mode == AudioHandlerMode.music) _broadcastState();
    });
    _bufferingSub = _player.stream.buffering.listen((_) {
      if (mode == AudioHandlerMode.music) _broadcastState();
    });
    _positionSub = _player.stream.position.listen(_onPosition);
    _durationSub = _player.stream.duration.listen((raw) {
      if (mode != AudioHandlerMode.music) return;
      final dur = _clipDuration(raw);
      _durationController.add(dur);
      final current = mediaItem.valueOrNull;
      if (current != null) mediaItem.add(current.copyWith(duration: dur));
    });
    _completedSub = _player.stream.completed.listen((completed) {
      if (completed &&
          mode == AudioHandlerMode.music &&
          _index >= 0 &&
          !_gateEvents) {
        unawaited(skipToNext());
      }
    });
    _errorSub = _player.stream.error.listen((e) {
      _notifLog('media_kit error: $e');
    });
    // A pre-built video player (tests) still needs its stream plumbing.
    if (_videoPlayer != null) _bindVideoStreams(_videoPlayer!);
    // audio_service swallows setState/setMediaItem/setQueue platform-channel
    // failures (e.g. NO_SERVICE when the native AudioService binder is null)
    // into this stream instead of throwing — without listening, a broken
    // native bridge silently plays audio with no notification ever posted.
    _asyncErrorSub = AudioService.asyncError.listen((e) {
      _lastAsyncError = e.toString();
      _lastAsyncErrorAt = DateTime.now();
      _notifLog('AudioService.asyncError: $e');
    });
    unawaited(_ensureAudioSessionConfigured());
  }

  final Player _player;

  /// Created lazily on the first video stream so audio-only usage (and tests)
  /// never pay for a second libmpv instance.
  Player? _videoPlayer;

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<bool>? _videoPlayingSub;
  StreamSubscription<bool>? _videoBufferingSub;
  StreamSubscription<Duration>? _videoPositionSub;
  StreamSubscription<Duration?>? _videoDurationSub;
  StreamSubscription<double>? _videoRateSub;
  StreamSubscription<String>? _videoErrorSub;

  AudioHandlerMode _mode = AudioHandlerMode.music;

  /// Which player the transport controls currently address.
  AudioHandlerMode get mode => _mode;
  bool get isVideoMode => _mode == AudioHandlerMode.video;

  /// The video player, creating it on first use.
  ///
  /// Owned by this handler (and therefore by `audio_service` on mobile) — the
  /// video screen only ever borrows it for a `VideoController`.
  Player get videoPlayer => _videoPlayer ??= _createVideoPlayer();
  Player _createVideoPlayer() {
    final p = Player();
    _bindVideoStreams(p);
    return p;
  }

  void _bindVideoStreams(Player p) {
    _videoPlayingSub = p.stream.playing.listen((_) {
      if (mode == AudioHandlerMode.video) _broadcastState();
    });
    _videoBufferingSub = p.stream.buffering.listen((_) {
      if (mode == AudioHandlerMode.video) _broadcastState();
    });
    _videoPositionSub = p.stream.position.listen(_onVideoPosition);
    _videoDurationSub = p.stream.duration.listen((raw) {
      if (mode != AudioHandlerMode.video) return;
      final dur = raw == Duration.zero ? null : raw;
      _durationController.add(dur);
      final current = mediaItem.valueOrNull;
      if (current != null) mediaItem.add(current.copyWith(duration: dur));
    });
    _videoRateSub = p.stream.rate.listen((_) {
      if (mode == AudioHandlerMode.video) _broadcastState();
    });
    _videoErrorSub = p.stream.error.listen((e) {
      _notifLog('video media_kit error: $e');
    });
  }

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<Object>? _asyncErrorSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  String? _lastAsyncError;
  DateTime? _lastAsyncErrorAt;

  /// Suppresses transient stream events while a source swap is in flight.
  bool _gateEvents = false;
  bool _duckedByInterruption = false;
  bool _pausedByInterruption = false;

  bool _audioSessionConfigured = false;

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();

  /// Optional resolver when skipping to a queue item that needs a local path.
  Future<String?> Function(TrackInfo track)? resolveLocalPath;

  final List<TrackInfo> _tracks = [];
  int _index = -1;

  List<TrackInfo> get tracks => List.unmodifiable(_tracks);
  int get index => _index;
  TrackInfo? get currentTrack =>
      (_index >= 0 && _index < _tracks.length) ? _tracks[_index] : null;

  /// Active player: video while streaming, otherwise the music queue player.
  Player get player => _mode == AudioHandlerMode.video
      ? (_videoPlayer ?? _player)
      : _player;

  bool get playing => player.state.playing;

  /// Clip-relative position (0-based within clipStart..clipEnd); raw for video.
  Duration get position => _mode == AudioHandlerMode.video
      ? (_videoPlayer?.state.position ?? Duration.zero)
      : _clipRelative(_player.state.position);
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;

  Duration get _clipStartOf => currentTrack?.clipStart ?? Duration.zero;
  Duration? get _clipEndOf => currentTrack?.clipEnd;

  Duration _clipRelative(Duration raw) {
    final rel = raw - _clipStartOf;
    return rel.isNegative ? Duration.zero : rel;
  }

  Duration? _clipDuration(Duration? rawDuration) {
    final end = _clipEndOf;
    if (end != null) return end - _clipStartOf;
    if (rawDuration == null || rawDuration == Duration.zero) return null;
    final d = rawDuration - _clipStartOf;
    return d.isNegative ? Duration.zero : d;
  }

  void _onPosition(Duration raw) {
    if (_gateEvents || _mode != AudioHandlerMode.music) return;
    final rel = _clipRelative(raw);
    _positionController.add(rel);
    playbackState.add(playbackState.value.copyWith(updatePosition: rel));
    final end = _clipEndOf;
    if (end != null && raw >= end && _index >= 0) {
      unawaited(skipToNext());
    }
  }

  void _onVideoPosition(Duration raw) {
    if (_mode != AudioHandlerMode.video) return;
    _positionController.add(raw);
    playbackState.add(playbackState.value.copyWith(updatePosition: raw));
  }

  AudioSession? _audioSession;

  Future<void> _ensureAudioSessionConfigured() async {
    if (_audioSessionConfigured) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _interruptionSub = session.interruptionEventStream.listen(_onInterruption);
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        unawaited(pause());
      });
      _audioSession = session;
      _audioSessionConfigured = true;
      _notifLog('AudioSession configured (music) once');
    } catch (e) {
      _notifLog('AudioSession configure failed: $e');
    }
  }

  /// media_kit/libmpv has no automatic OS audio-focus handling like
  /// ExoPlayer, so interruptions (calls, other apps' media) must be applied
  /// manually via audio_session's recipe.
  ///
  /// Ignored while a video is streaming: the same session is active but the
  /// video must never be paused/ducked by the music-side recipe.
  void _onInterruption(AudioInterruptionEvent event) {
    if (_mode == AudioHandlerMode.video) return;
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          _duckedByInterruption = true;
          unawaited(_player.setVolume((_player.state.volume * 0.5).clamp(0.0, 100.0)));
          break;
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          if (_player.state.playing) {
            _pausedByInterruption = true;
            unawaited(pause());
          }
      }
    } else {
      switch (event.type) {
        case AudioInterruptionType.duck:
          if (_duckedByInterruption) {
            _duckedByInterruption = false;
            unawaited(_player.setVolume(100));
          }
          break;
        case AudioInterruptionType.pause:
          if (_pausedByInterruption) {
            _pausedByInterruption = false;
            unawaited(play());
          }
          break;
        case AudioInterruptionType.unknown:
          _pausedByInterruption = false;
      }
    }
  }

  MediaItem mediaItemFor(TrackInfo track) {
    // Title is required for system media center; never leave empty.
    final title = track.displayTitle.trim().isEmpty
        ? track.fileName
        : track.displayTitle;
    final clipEnd = track.clipEnd;
    final duration = clipEnd != null
        ? clipEnd - (track.clipStart ?? Duration.zero)
        : track.duration;
    return MediaItem(
      id: '${track.accountId}|${track.remotePath}',
      title: title,
      album: track.album,
      artist: track.displayArtist,
      duration: duration,
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

  /// mpv trims to [start]..[end] natively (via an on_load hook) — no
  /// separate play-then-seek blip like a manual seek-after-open would cause.
  Media _mediaFor(TrackInfo track, String localPath) {
    return Media(localPath, start: track.clipStart, end: track.clipEnd);
  }

  /// Replace queue and start playback at [startIndex] with a resolved local path.
  Future<void> loadAndPlay({
    required List<TrackInfo> playlist,
    required int startIndex,
    required String localPath,
  }) async {
    if (playlist.isEmpty) return;
    final idx = startIndex.clamp(0, playlist.length - 1);
    _gateEvents = true;
    // Music and video share one MediaSession: taking the queue back over ends
    // any video session first (the video player object itself is untouched).
    if (_mode == AudioHandlerMode.video) {
      _mode = AudioHandlerMode.music;
      _videoSource = null;
    }
    _tracks
      ..clear()
      ..addAll(playlist);
    _index = idx;
    _tracks[_index].localPath = localPath;

    await _ensureAudioSessionConfigured();

    final items = _tracks.map(mediaItemFor).toList();
    // Real queue enables skipToNext/Previous for MediaSession callbacks.
    queue.add(items);
    final item = items[_index];
    mediaItem.add(item);
    _notifLog('mediaItem set title=${item.title} artist=${item.artist}');

    // Publish non-idle BEFORE open(). A transient idle broadcast here would
    // make native audio_service call AudioService.stop() and kill the
    // MediaStyle notification.
    playbackState.add(playbackState.value.copyWith(
      controls: _controls(playing: false),
      systemActions: _kSystemActions,
      androidCompactActionIndices: const [0, 1, 3],
      processingState: AudioProcessingState.buffering,
      playing: false,
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      queueIndex: _index,
    ));

    try {
      await _player.open(_mediaFor(_tracks[_index], localPath), play: false);
      final dur = _clipDuration(_player.state.duration);
      _durationController.add(dur);
      mediaItem.add(item.copyWith(duration: dur ?? item.duration));
      await play();
    } finally {
      _gateEvents = false;
      _broadcastState();
    }
  }

  /// Always expose skip + play/pause + stop so PlaybackState actions stay rich
  /// for Android 13+ system media buttons (not only notification addAction).
  List<MediaControl> _controls({required bool playing}) {
    return [
      _kSkipPreviousControl,
      if (playing) _kPauseControl else _kPlayControl,
      _kStopControl,
      _kSkipNextControl,
    ];
  }

  /// Video has no queue: play/pause + stop only, and no seek system actions.
  List<MediaControl> _videoControls({required bool playing}) {
    return [
      if (playing) _kPauseControl else _kPlayControl,
      _kStopControl,
    ];
  }

  static const Set<MediaAction> _kVideoSystemActions = {
    MediaAction.play,
    MediaAction.pause,
    MediaAction.playPause,
    MediaAction.stop,
    MediaAction.seek,
  };

  void _broadcastState() {
    if (_mode == AudioHandlerMode.video) {
      _broadcastVideoState();
      return;
    }
    if (_gateEvents) return;
    final playingNow = _player.state.playing;
    final AudioProcessingState proc;
    if (_index < 0) {
      proc = AudioProcessingState.idle;
    } else if (_player.state.completed) {
      proc = AudioProcessingState.completed;
    } else if (_player.state.buffering) {
      proc = AudioProcessingState.buffering;
    } else {
      proc = AudioProcessingState.ready;
    }
    playbackState.add(playbackState.value.copyWith(
      controls: _controls(playing: playingNow),
      systemActions: _kSystemActions,
      androidCompactActionIndices: const [0, 1, 3],
      processingState: proc,
      playing: playingNow,
      updatePosition: position,
      bufferedPosition: _clipRelative(_player.state.buffer),
      speed: _player.state.rate,
      queueIndex: _index >= 0 ? _index : null,
    ));
    _notifLog('playbackState playing=$playingNow proc=$proc idx=$_index');
  }

  void _broadcastVideoState() {
    final vp = _videoPlayer;
    if (_videoSource == null || vp == null) return;
    final playingNow = vp.state.playing;
    final AudioProcessingState proc;
    if (vp.state.completed) {
      proc = AudioProcessingState.completed;
    } else if (vp.state.buffering) {
      proc = AudioProcessingState.buffering;
    } else {
      proc = AudioProcessingState.ready;
    }
    playbackState.add(playbackState.value.copyWith(
      controls: _videoControls(playing: playingNow),
      systemActions: _kVideoSystemActions,
      androidCompactActionIndices: const [0, 1],
      processingState: proc,
      playing: playingNow,
      updatePosition: vp.state.position,
      bufferedPosition: vp.state.buffer,
      speed: vp.state.rate,
      queueIndex: null,
    ));
    _notifLog('video playbackState playing=$playingNow proc=$proc');
  }

  // --- Video mode -------------------------------------------------------

  WebDavStreamSource? _videoSource;

  /// Currently streamed video (null outside video mode).
  WebDavStreamSource? get videoSource => _videoSource;

  /// Take over the MediaSession / notification for a single streamed video.
  ///
  /// Publishes the video as the current [mediaItem] with a play/pause-only
  /// control set. The paused music queue (`_tracks` / `_index`) is **kept**, so
  /// leaving the video restores the music session exactly where it was paused.
  /// Must be paired with [exitVideoMode].
  Future<void> enterVideoMode(
    WebDavStreamSource source, {
    Media? media,
  }) async {
    _gateEvents = true;
    try {
      _mode = AudioHandlerMode.video;
      _videoSource = source;
      await _ensureAudioSessionConfigured();

      final item = MediaItem(
        id: 'video|${source.accountId}|${source.remotePath}',
        title: source.name,
        album: '视频',
        artist: 'WebDAV 流媒体',
        extras: {
          'kind': 'video',
          'accountId': source.accountId,
          'remotePath': source.remotePath,
        },
      );
      mediaItem.add(item);
      // A queue-less session keeps the notification but hides skip controls.
      queue.add(const []);

      playbackState.add(playbackState.value.copyWith(
        controls: _videoControls(playing: false),
        systemActions: _kVideoSystemActions,
        androidCompactActionIndices: const [0, 1],
        processingState: AudioProcessingState.buffering,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        queueIndex: null,
      ));
      if (media != null) {
        await videoPlayer.open(media, play: false);
        final dur = videoPlayer.state.duration;
        mediaItem.add(
          item.copyWith(duration: dur == Duration.zero ? null : dur),
        );
      }
    } finally {
      _gateEvents = false;
      _broadcastVideoState();
    }
  }

  /// Leave video mode.
  ///
  /// Restores the music session: if a music queue was paused when the video
  /// started, its MediaItem / queue / paused state come back so the user can
  /// hit play in the notification and continue. Otherwise the session goes idle
  /// and the foreground notification for the video is torn down.
  Future<void> exitVideoMode() async {
    if (_mode != AudioHandlerMode.video && _videoSource == null) return;
    _gateEvents = true;
    try {
      try {
        await _videoPlayer?.stop();
      } catch (_) {}
      _mode = AudioHandlerMode.music;
      _videoSource = null;

      final track = currentTrack;
      if (track != null) {
        final items = _tracks.map(mediaItemFor).toList();
        queue.add(items);
        mediaItem.add(items[_index]);
        _durationController.add(_clipDuration(_player.state.duration));
        playbackState.add(playbackState.value.copyWith(
          controls: _controls(playing: false),
          systemActions: _kSystemActions,
          androidCompactActionIndices: const [0, 1, 3],
          processingState: AudioProcessingState.ready,
          playing: false,
          updatePosition: position,
          bufferedPosition: _clipRelative(_player.state.buffer),
          speed: _player.state.rate,
          queueIndex: _index,
        ));
      } else {
        mediaItem.add(null);
        queue.add(const []);
        _durationController.add(null);
        playbackState.add(playbackState.value.copyWith(
          controls: _controls(playing: false),
          systemActions: _kSystemActions,
          androidCompactActionIndices: const [0, 1, 3],
          processingState: AudioProcessingState.idle,
          playing: false,
          updatePosition: Duration.zero,
          queueIndex: null,
        ));
      }
    } finally {
      _gateEvents = false;
    }
    _notifLog('exitVideoMode (musicRestored=${currentTrack != null})');
  }

  /// Stop any in-flight music session without touching the video player.
  /// Used to enforce "video playback pauses music".
  Future<void> pauseMusicForVideo() async {
    try {
      if (_player.state.playing) await _player.pause();
    } catch (_) {}
  }

  Future<void> _loadIndex(int idx) async {
    if (idx < 0 || idx >= _tracks.length) return;
    _gateEvents = true;
    _index = idx;
    // Music and video share the session: taking the queue back over ends the
    // video session bookkeeping (the video player object is left to its owner).
    if (_mode == AudioHandlerMode.video) {
      _mode = AudioHandlerMode.music;
      _videoSource = null;
    }
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
      _gateEvents = false;
      throw StateError('本地文件不可用');
    }
    final item = mediaItemFor(track);
    mediaItem.add(item);
    queue.add(_tracks.map(mediaItemFor).toList());
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.buffering,
      playing: false,
      controls: _controls(playing: false),
      systemActions: _kSystemActions,
      androidCompactActionIndices: const [0, 1, 3],
      queueIndex: _index,
    ));
    try {
      await _player.open(_mediaFor(track, local), play: false);
      final dur = _clipDuration(_player.state.duration);
      _durationController.add(dur);
      mediaItem.add(item.copyWith(duration: dur ?? item.duration));
      await play();
    } finally {
      _gateEvents = false;
      _broadcastState();
    }
  }

  @override
  Future<void> play() async {
    if (_mode == AudioHandlerMode.video) {
      playbackState.add(playbackState.value.copyWith(
        playing: true,
        controls: _videoControls(playing: true),
        systemActions: _kVideoSystemActions,
        androidCompactActionIndices: const [0, 1],
        processingState: playbackState.value.processingState ==
                AudioProcessingState.idle
            ? AudioProcessingState.buffering
            : playbackState.value.processingState,
        updatePosition: videoPlayer.state.position,
      ));
      unawaited(_audioSession?.setActive(true));
      await videoPlayer.play();
      return;
    }
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      processingState: playbackState.value.processingState == AudioProcessingState.idle
          ? AudioProcessingState.buffering
          : playbackState.value.processingState,
      controls: _controls(playing: true),
      systemActions: _kSystemActions,
      androidCompactActionIndices: const [0, 1, 3],
      updatePosition: position,
      queueIndex: _index >= 0 ? _index : null,
    ));
    _notifLog('play() -> playing=true');
    unawaited(_audioSession?.setActive(true));
    await _player.play();
  }

  @override
  Future<void> pause() async {
    if (_mode == AudioHandlerMode.video) {
      playbackState.add(playbackState.value.copyWith(
        playing: false,
        controls: _videoControls(playing: false),
        systemActions: _kVideoSystemActions,
        androidCompactActionIndices: const [0, 1],
        updatePosition: videoPlayer.state.position,
      ));
      await videoPlayer.pause();
      return;
    }
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      controls: _controls(playing: false),
      systemActions: _kSystemActions,
      androidCompactActionIndices: const [0, 1, 3],
      updatePosition: position,
    ));
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    // Video owns its own teardown (VideoPlaybackService calls exitVideoMode),
    // so a stop while streaming must not touch the music queue.
    if (_mode == AudioHandlerMode.video) {
      await exitVideoMode();
      return;
    }
    // Stay gated through the native reset so its own stream events (which
    // fire synchronously against the stale, about-to-be-cleared queue/index)
    // don't race our explicit idle broadcast below. The next loadAndPlay/
    // _loadIndex re-gates anyway.
    _gateEvents = true;
    try {
      await _player.stop();
      await super.stop();
      unawaited(_audioSession?.setActive(false));
    } finally {
      mediaItem.add(null);
      queue.add(const []);
      _index = -1;
      _tracks.clear();
      _durationController.add(null);
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        queueIndex: null,
      ));
    }
  }

  /// Do not stop when the Activity task is removed while media FGS runs.
  /// Explicit stop only via pause/stop controls or drawer 「退出应用」.
  @override
  Future<void> onTaskRemoved() async {}

  @override
  Future<void> seek(Duration position) {
    if (_mode == AudioHandlerMode.video) {
      return videoPlayer.seek(position);
    }
    return _player.seek(_clipStartOf + position);
  }

  @override
  Future<void> skipToNext() async {
    if (_mode == AudioHandlerMode.video) return;
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
    if (_mode == AudioHandlerMode.video) return;
    if (position > const Duration(seconds: 3)) {
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
  Future<void> skipToQueueItem(int index) {
    if (_mode == AudioHandlerMode.video) return Future<void>.value();
    return _loadIndex(index);
  }

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
        final channelExists = map['channelExists'] == true;
        final channelBlocked = map['channelBlocked'] == true;
        final mfr = map['manufacturer']?.toString() ?? '';
        final model = map['model']?.toString() ?? '';
        final sdk = map['sdk'];
        final hint = (!posted || channelBlocked)
            ? ' | 若仍无通知: 设置→应用→Webdav Media Manager→耗电管理=不限制;'
                '通知=允许(含锁屏/悬浮); 通道「音乐播放」勿关闭'
            : '';
        return '服务=${svc ? "运行" : "无"} 会话=${active ? "活跃" : "否"} '
            '通知=${posted ? "已发布" : "未发布"} '
            '系统通知开关=$perm 通道=$chName'
            '${channelExists ? "" : "(未创建)"}'
            '${channelBlocked ? "(已关闭)" : ""} 重要性=$chImp '
            '本包会话数=$ourSessions '
            '设备=$mfr $model sdk=$sdk$hint';
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
      return '无可用本地音频。请先播放一首歌，再点测试。\n$probe$_asyncErrorSuffix';
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
        '$probe$_asyncErrorSuffix\n'
        '请查看通知栏 / 媒体控制中心。';
  }

  /// Reports the last error audio_service swallowed from a platform-channel
  /// call (e.g. "NO_SERVICE" — native AudioService binder is null), if recent.
  String get _asyncErrorSuffix {
    final err = _lastAsyncError;
    final at = _lastAsyncErrorAt;
    if (err == null || at == null) return '';
    if (DateTime.now().difference(at) > const Duration(minutes: 2)) return '';
    return '\n\u26a0 audio_service 桥接错误: $err';
  }

  Future<void> disposePlayer() async {
    await _playingSub?.cancel();
    await _bufferingSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _completedSub?.cancel();
    await _errorSub?.cancel();
    await _videoPlayingSub?.cancel();
    await _videoBufferingSub?.cancel();
    await _videoPositionSub?.cancel();
    await _videoDurationSub?.cancel();
    await _videoRateSub?.cancel();
    await _videoErrorSub?.cancel();
    await _asyncErrorSub?.cancel();
    await _interruptionSub?.cancel();
    await _becomingNoisySub?.cancel();
    await _positionController.close();
    await _durationController.close();
    await _player.dispose();
    await _videoPlayer?.dispose();
    _videoPlayer = null;
  }
}

/// Creates and registers the platform audio service (Android/iOS).
/// Must be called before any other media_kit [Player] is created.
Future<MusicAudioHandler> initMusicAudioService() {
  return AudioService.init<MusicAudioHandler>(
    builder: MusicAudioHandler.new,
    config: AudioServiceConfig(
      // v4: fresh channel so IMPORTANCE_DEFAULT + lockscreen visibility apply
      // (Android never upgrades an existing channel in-place; ColorOS may
      // have silenced v3). The channel itself is created by
      // NotificationPermissionService via flutter_local_notifications; these
      // values must mirror `kMediaNotificationChannel`.
      androidNotificationChannelId: kMediaNotificationChannelId,
      androidNotificationChannelName: kMediaNotificationChannelName,
      androidNotificationChannelDescription:
          kMediaNotificationChannelDescription,
      // MUST stay false while androidStopForegroundOnPause is false:
      // audio_service asserts `!androidNotificationOngoing ||
      // androidStopForegroundOnPause` in its constructor, and that assertion is
      // evaluated in main() *before* runApp — throwing it leaves a permanently
      // blank Flutter surface with no visible error (no crash dialog, just a
      // black screen; only logcat shows the unhandled exception).
      //
      // "Ongoing" only means the notification cannot be dismissed by the user;
      // keeping the FGS alive across pause is what
      // androidStopForegroundOnPause: false already does, so nothing is lost.
      androidNotificationOngoing: false,
      // Keep FGS while paused so Android 12+ does not block restarting
      // startForegroundService when play() races with event-driven pause.
      androidStopForegroundOnPause: false,
      androidNotificationIcon: kMediaNotificationIcon,
      androidNotificationClickStartsActivity: true,
      androidShowNotificationBadge: false,
    ),
  );
}
