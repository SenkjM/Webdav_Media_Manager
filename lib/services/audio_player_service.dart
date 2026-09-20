import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/download_task.dart';
import '../models/webdav_item.dart';
import 'download_queue_service.dart';
import 'music_audio_handler.dart';
import 'notification_permission_service.dart';

/// Local-file-only player facade. Never streams from WebDAV.
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
    _posSub = _handler.player.positionStream.listen((p) {
      _position = p;
      notifyListeners();
    });
    _durSub = _handler.player.durationStream.listen((d) {
      _duration = d;
      notifyListeners();
    });
    _stateSub = _handler.player.playerStateStream.listen((s) {
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
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<MediaItem?>? _mediaSub;

  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  ProcessingState _processingState = ProcessingState.idle;
  String? _error;
  bool _preparing = false;
  bool _notificationPrompted = false;

  MusicAudioHandler get handler => _handler;

  TrackInfo? get current => _handler.currentTrack;
  String? get currentRemotePath => current?.remotePath;
  String? get currentAccountId => current?.accountId;
  List<TrackInfo> get queue => _handler.tracks;
  int get index => _handler.index;
  Duration get position => _position;
  Duration? get duration => _duration;
  bool get playing => _playing;
  bool get preparing => _preparing;
  String? get error => _error;
  ProcessingState get processingState => _processingState;

  Future<String?> _resolveLocalPath(TrackInfo track) async {
    final existing = track.localPath;
    if (existing != null && File(existing).existsSync()) return existing;
    if (track.isCueVirtual && track.cueRemotePath != null) {
      await _downloads.enqueueCueGroup(
        accountId: track.accountId,
        cueRemotePath: track.cueRemotePath!,
      );
      final audioRemote = track.effectiveAudioRemotePath;
      final audioTask = _downloads.taskForRemote(track.accountId, audioRemote);
      if (audioTask?.localPath != null && File(audioTask!.localPath!).existsSync()) {
        track.localPath = audioTask.localPath;
        return track.localPath;
      }
    }
    final task = await _downloads.enqueue(
      track.accountId,
      track.isCueVirtual ? track.effectiveAudioRemotePath : track.remotePath,
      fileName: track.fileName,
      cacheGroupId: track.cacheGroupId,
    );
    if (task.status != DownloadStatus.completed || task.localPath == null) {
      throw StateError(task.errorMessage ?? '下载失败');
    }
    track.localPath = task.localPath;
    return task.localPath;
  }

  /// Play a track: if not cached, enqueue download then play local file.
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
          t.remotePath == track.remotePath && t.accountId == track.accountId,
    );
    if (idx < 0) {
      list.add(track);
      idx = list.length - 1;
    } else {
      // Prefer caller-provided localPath / tags for the selected item.
      list[idx] = track;
    }
    notifyListeners();
    await _ensureNotificationPermission();
    await _loadAndPlay(list, idx);
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

  Future<void> _loadAndPlay(List<TrackInfo> playlist, int index) async {
    _preparing = true;
    _error = null;
    notifyListeners();
    try {
      final track = playlist[index];
      final local = await _resolveLocalPath(track);
      if (local == null) {
        throw StateError('下载失败');
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
      _preparing = false;
      notifyListeners();
    }
  }

  Future<void> playPause() async {
    if (_handler.player.playing) {
      await _handler.pause();
    } else {
      if (current == null && _handler.tracks.isNotEmpty) {
        final idx = _handler.index < 0 ? 0 : _handler.index;
        await _ensureNotificationPermission();
        await _loadAndPlay(_handler.tracks, idx);
      } else {
        await _ensureNotificationPermission();
        await _handler.play();
      }
    }
  }

  Future<void> pause() => _handler.pause();

  Future<void> seek(Duration position) => _handler.seek(position);

  Future<void> skipNext() => _handler.skipToNext();

  Future<void> skipPrevious() => _handler.skipToPrevious();

  Future<void> stop() async {
    await _handler.stop();
    notifyListeners();
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
