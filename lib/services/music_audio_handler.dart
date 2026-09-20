import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
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

/// Actions Android 13+ / lock screen / control center read from PlaybackState.
/// Controls (notification buttons) + systemActions together must expose
/// PLAY / PAUSE / PLAY_PAUSE / SKIP_* / SEEK.
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
  MusicAudioHandler({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    // Official example pattern: transform playback events → playbackState.
    _eventSub = _player.playbackEventStream.map(_transformEvent).listen(
      (state) {
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
      if (state == ProcessingState.completed) {
        unawaited(skipToNext());
      }
    });
  }

  final AudioPlayer _player;
  StreamSubscription<PlaybackState>? _eventSub;
  StreamSubscription<ProcessingState>? _completeSub;

  /// Optional resolver when skipping to a queue item that needs a local path.
  Future<String?> Function(TrackInfo track)? resolveLocalPath;

  final List<TrackInfo> _tracks = [];
  int _index = -1;

  List<TrackInfo> get tracks => List.unmodifiable(_tracks);
  int get index => _index;
  TrackInfo? get currentTrack =>
      (_index >= 0 && _index < _tracks.length) ? _tracks[_index] : null;
  AudioPlayer get player => _player;

  AudioSource _sourceFor(TrackInfo track, String localPath) {
    final start = track.clipStart;
    final end = track.clipEnd;
    final fileSrc = AudioSource.file(localPath);
    if (start != null || end != null) {
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
    _tracks
      ..clear()
      ..addAll(playlist);
    _index = idx;
    _tracks[_index].localPath = localPath;

    final items = _tracks.map(mediaItemFor).toList();
    // Real queue enables skipToNext/Previous for MediaSession callbacks.
    queue.add(items);
    final item = items[_index];
    mediaItem.add(item);
    _notifLog('mediaItem set title=${item.title} artist=${item.artist}');

    playbackState.add(playbackState.value.copyWith(
      controls: _controls(playing: false),
      systemActions: _kSystemActions,
      androidCompactActionIndices: const [0, 1, 3],
      processingState: AudioProcessingState.loading,
      playing: false,
      updatePosition: Duration.zero,
      queueIndex: _index,
    ));

    await _player.setAudioSource(_sourceFor(_tracks[_index], localPath));
    mediaItem.add(item.copyWith(duration: _player.duration ?? item.duration));
    await play();
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

  PlaybackState _transformEvent(PlaybackEvent event) {
    final playing = _player.playing;
    final proc = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[_player.processingState]!;

    return PlaybackState(
      controls: _controls(playing: playing),
      systemActions: _kSystemActions,
      androidCompactActionIndices: const [0, 1, 3],
      processingState: proc,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _index >= 0 ? _index : event.currentIndex,
    );
  }

  Future<void> _loadIndex(int idx) async {
    if (idx < 0 || idx >= _tracks.length) return;
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
      throw StateError('本地文件不可用');
    }
    final item = mediaItemFor(track);
    mediaItem.add(item);
    queue.add(_tracks.map(mediaItemFor).toList());
    await _player.setAudioSource(_sourceFor(track, local));
    mediaItem.add(item.copyWith(duration: _player.duration ?? item.duration));
    await play();
  }

  @override
  Future<void> play() async {
    // Immediate PLAYING broadcast → enterPlayingState / startForeground /
    // mediaSession.setActive(true) before just_audio's event arrives.
    final proc = _player.processingState == ProcessingState.ready
        ? AudioProcessingState.ready
        : AudioProcessingState.buffering;
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      processingState: proc,
      controls: _controls(playing: true),
      systemActions: _kSystemActions,
      androidCompactActionIndices: const [0, 1, 3],
      updatePosition: _player.position,
      queueIndex: _index >= 0 ? _index : null,
    ));
    _notifLog('play() → playing=true proc=$proc');
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
    await _player.stop();
    await super.stop();
    mediaItem.add(null);
    _index = -1;
  }

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
    config: const AudioServiceConfig(
      // applicationId-style channel; new id so IMPORTANCE_DEFAULT from the
      // vendored patch applies (existing LOW channels are not updated in-place).
      androidNotificationChannelId: 'com.webdav.webdav_music_player.audio',
      androidNotificationChannelName: '音乐播放',
      androidNotificationChannelDescription: '正在播放的音乐控制',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'drawable/ic_stat_music_white',
      androidNotificationClickStartsActivity: true,
      androidShowNotificationBadge: false,
    ),
  );
}
