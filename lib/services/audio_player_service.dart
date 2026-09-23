import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../models/download_task.dart';
import '../models/webdav_item.dart';
import '../models/webdav_stream.dart';
import 'download_queue_service.dart';
import 'music_audio_handler.dart';
import 'notification_permission_service.dart';

/// Local-file-only player facade. Never streams from WebDAV and never
/// enqueues downloads as part of playback — callers must only start play
/// after a cache file exists.
///
/// On Android/iOS, playback goes through [MusicAudioHandler] so the system
/// MediaStyle notification / media session stays active with metadata.
class AudioPlayerService extends ChangeNotifier {
  AudioPlayerService({
    required DownloadQueueService downloads,
    required MusicAudioHandler handler,
    NotificationPermissionService? notificationPermission,
  })  : _downloads = downloads,
        _notifications = notificationPermission,
        _handler = handler {
    _handler.resolveLocalPath = _resolveLocalPath;
    _posSub = _handler.positionStream.listen((p) {
      _position = p;
      notifyListeners();
    });
    _durSub = _handler.durationStream.listen((d) {
      _duration = d;
      notifyListeners();
    });
    _stateSub = _handler.playbackState.listen((s) {
      _playing = s.playing;
      _processingState = s.processingState;
      notifyListeners();
    });
    _mediaSub = _handler.mediaItem.listen((_) {
      notifyListeners();
    });
  }

  final DownloadQueueService _downloads;
  final NotificationPermissionService? _notifications;
  final MusicAudioHandler _handler;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<MediaItem?>? _mediaSub;

  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  AudioProcessingState _processingState = AudioProcessingState.idle;
  String? _error;

  MusicAudioHandler get handler => _handler;

  TrackInfo? get current => _handler.currentTrack;
  String? get currentRemotePath => current?.remotePath;
  /// 网盘名 of the playing track (cache / identity side).
  String? get currentSourceName => current?.sourceName;
  List<TrackInfo> get queue => _handler.tracks;
  int get index => _handler.index;
  Duration get position => _position;
  Duration? get duration => _duration;
  bool get playing => _playing;
  String? get error => _error;
  AudioProcessingState get processingState => _processingState;

  /// Resolve an already-cached local path. Never enqueues downloads.
  Future<String?> _resolveLocalPath(TrackInfo track) async {
    final existing = track.localPath;
    if (existing != null && File(existing).existsSync()) return existing;
    final audioRemote = track.effectiveAudioRemotePath;
    final task = _downloads.taskForRemote(track.sourceName, audioRemote);
    if (task != null &&
        task.status == DownloadStatus.completed &&
        task.localPath != null &&
        File(task.localPath!).existsSync()) {
      track.localPath = task.localPath;
      return task.localPath;
    }
    return null;
  }

  /// Play a track that is already local. Non-local tracks are rejected —
  /// use the download queue from library / network UI instead.
  Future<void> playTrack(
    TrackInfo track, {
    List<TrackInfo>? playlist,
  }) async {
    _error = null;
    final list = <TrackInfo>[];
    if (playlist != null && playlist.isNotEmpty) {
      list.addAll(playlist);
    } else {
      list.addAll(_handler.tracks);
    }
    var idx = list.indexWhere(
      (t) =>
          t.remotePath == track.remotePath && t.sourceName == track.sourceName,
    );
    if (idx < 0) {
      list.add(track);
      idx = list.length - 1;
    } else {
      // Prefer caller-provided localPath / tags for the selected item.
      list[idx] = track;
    }

    final local = await _resolveLocalPath(list[idx]);
    if (local == null) {
      _error = '本地无缓存，请先下载';
      notifyListeners();
      return;
    }
    list[idx].localPath = local;

    notifyListeners();
    await _ensureNotificationPermission();
    await _loadAndPlay(list, idx);
  }


  /// 实验性：直接流式播放一个远端音频文件（不下载、不入队、不缓存）。
  ///
  /// 复用视频那套远端流管线（同一个 `media_kit` Player、同一个媒体会话），
  /// 所以后台播放、锁屏控制、耳机按键都跟着工作；区别只在会话文案与是否
  /// 暴露切歌。要退回流式播放，调用 [stopRemoteMusic] 或开始本地播放。
  ///
  /// 封面与时长刻意不做：流式播放拿不到本地文件来解析标签。取舍见
  /// docs/99 的《音乐流式传输可行性分析》。
  Future<bool> playRemoteMusic({
    required WebDavStreamSource source,
    String? artist,
  }) async {
    if (source.kind != StreamKind.music) {
      _error = '这条流不是音频';
      notifyListeners();
      return false;
    }
    try {
      _error = null;
      notifyListeners();
      await _ensureNotificationPermission();
      await _handler.enterVideoMode(
        source,
        media: Media(source.uri, httpHeaders: source.headers),
      );
      await _handler.play();
      notifyListeners();
      return true;
    } catch (e) {
      _error = '流式播放失败：$e';
      notifyListeners();
      return false;
    }
  }

  /// 结束远端流（音频或视频）：释放媒体会话并退回本地音乐状态。
  Future<void> stopRemoteMusic() async {
    if (!_handler.isVideoMode) return;
    await _handler.exitVideoMode();
    notifyListeners();
  }

  Future<void> _ensureNotificationPermission() async {
    final svc = _notifications;
    if (svc == null || _notificationPrompted) return;
    _notificationPrompted = true;
    if (!svc.loaded) {
      await svc.refresh();
    }
    if (!svc.isGranted) {
      await svc.request();
    }
  }

  bool _notificationPrompted = false;

  Future<void> _loadAndPlay(List<TrackInfo> playlist, int index) async {
    _error = null;
    notifyListeners();
    try {
      // Video and music never play together: taking back the media session for
      // music ends any active video stream first.
      if (_handler.isVideoMode) {
        await _handler.exitVideoMode();
      }
      final track = playlist[index];
      final local = await _resolveLocalPath(track);
      if (local == null) {
        throw StateError('本地无缓存，请先下载');
      }
      await _handler.loadAndPlay(
        playlist: playlist,
        startIndex: index,
        localPath: local,
      );
    } catch (e) {
      _error = e.toString();
      try {
        await _handler.stop();
      } catch (_) {}
    } finally {
      notifyListeners();
    }
  }

  Future<void> playPause() async {
    if (_handler.playing) {
      await _handler.pause();
    } else {
      if (current == null && _handler.tracks.isNotEmpty) {
        final idx = _handler.index < 0 ? 0 : _handler.index;
        final local = await _resolveLocalPath(_handler.tracks[idx]);
        if (local == null) {
          _error = '本地无缓存，请先下载';
          notifyListeners();
          return;
        }
        await _ensureNotificationPermission();
        await _loadAndPlay(_handler.tracks, idx);
      } else {
        await _ensureNotificationPermission();
        await _handler.play();
      }
    }
  }

  Future<void> pause() => _handler.pause();

  /// Pause music because video playback is taking over the media session.
  ///
  /// Unlike [stop] this keeps the music queue, so the user can resume the same
  /// track after leaving the video player. No-op when nothing is playing.
  Future<void> pauseForVideo() async {
    if (!_handler.playing) return;
    await _handler.pause();
    notifyListeners();
  }

  Future<void> seek(Duration position) => _handler.seek(position);

  Future<void> skipNext() => _handler.skipToNext();

  Future<void> skipPrevious() => _handler.skipToPrevious();

  Future<void> stop() async {
    await _handler.stop();
    notifyListeners();
  }

  /// Settings debug: force MediaSession + play so a MediaStyle notification
  /// must appear when the OS path is healthy.
  Future<String> debugForceMediaNotification() async {
    await _ensureNotificationPermission();
    // Allow re-prompt path on next play if user denied then granted in settings.
    _notificationPrompted = false;
    await _ensureNotificationPermission();
    final msg = await _handler.debugForceMediaNotification();
    notifyListeners();
    return msg;
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _mediaSub?.cancel();
    // Handler player lifetime is owned by AudioService on mobile; only dispose
    // when this service created a standalone handler (tests / desktop).
    super.dispose();
  }
}
