import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/webdav_item.dart';

/// audio_service handler that owns a single [AudioPlayer] and publishes
/// MediaItem + PlaybackState so Android shows a MediaStyle notification /
/// system media controls.
class MusicAudioHandler extends BaseAudioHandler with SeekHandler {
  MusicAudioHandler({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _player.playbackEventStream.listen((event) {
      playbackState.add(_transformEvent(event));
    });
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        unawaited(skipToNext());
      }
    });
  }

  final AudioPlayer _player;

  /// Optional resolver used when skipping to a queue item that needs a local path.
  Future<String?> Function(TrackInfo track)? resolveLocalPath;

  final List<TrackInfo> _tracks = [];
  int _index = -1;

  List<TrackInfo> get tracks => List.unmodifiable(_tracks);
  int get index => _index;
  TrackInfo? get currentTrack =>
      (_index >= 0 && _index < _tracks.length) ? _tracks[_index] : null;
  AudioPlayer get player => _player;

  MediaItem mediaItemFor(TrackInfo track) {
    return MediaItem(
      id: '${track.accountId}|${track.remotePath}',
      title: track.displayTitle,
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

  /// Replace queue and start playback at [startIndex] using an already-resolved
  /// local file path for that track.
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
    queue.add(items);
    final item = items[_index];
    // Publish metadata BEFORE play so the FGS notification has title/artist.
    mediaItem.add(item);
    playbackState.add(playbackState.value.copyWith(
      controls: _controls(playing: false),
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1],
      processingState: AudioProcessingState.loading,
      playing: false,
      updatePosition: Duration.zero,
      queueIndex: _index,
    ));

    await _player.setAudioSource(AudioSource.file(localPath));
    mediaItem.add(item.copyWith(duration: _player.duration ?? item.duration));
    await play();
  }

  List<MediaControl> _controls({required bool playing}) {
    return [
      if (_tracks.length > 1 && _index > 0) MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.stop,
      if (_tracks.length > 1 && _index + 1 < _tracks.length)
        MediaControl.skipToNext,
    ];
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    final playing = _player.playing;
    final controls = _controls(playing: playing);
    // Compact view: prefer play/pause (+ skip next when present).
    final compact = <int>[];
    for (var i = 0; i < controls.length; i++) {
      final a = controls[i].action;
      if (a == MediaAction.play ||
          a == MediaAction.pause ||
          a == MediaAction.skipToNext) {
        compact.add(i);
      }
      if (compact.length >= 3) break;
    }
    if (compact.isEmpty) compact.add(0);

    return PlaybackState(
      controls: controls,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: compact,
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
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
    await _player.setAudioSource(AudioSource.file(local));
    mediaItem.add(item.copyWith(duration: _player.duration ?? item.duration));
    await play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

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
      await _player.stop();
      playbackState.add(playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ));
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
    await _player.dispose();
  }
}

/// Creates and registers the platform audio service (Android/iOS).
/// Must be called before any other [AudioPlayer] is created.
Future<MusicAudioHandler> initMusicAudioService() {
  return AudioService.init<MusicAudioHandler>(
    builder: MusicAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId:
          'com.webdav.webdav_music_player.channel.audio',
      androidNotificationChannelName: '音乐播放',
      androidNotificationChannelDescription: '正在播放的音乐控制',
      // ongoing=true requires stopForegroundOnPause=true (audio_service assert).
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      // Adaptive mipmap/ic_launcher is NOT valid as a status-bar small icon.
      androidNotificationIcon: 'drawable/ic_stat_music',
      androidNotificationClickStartsActivity: true,
    ),
  );
}
