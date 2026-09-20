import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/download_task.dart';
import '../models/webdav_item.dart';
import 'download_queue_service.dart';

/// Local-file-only player. Never streams from WebDAV.
class AudioPlayerService extends ChangeNotifier {
  AudioPlayerService({
    required DownloadQueueService downloads,
    AudioPlayer? player,
  })  : _downloads = downloads,
        _player = player ?? AudioPlayer() {
    _posSub = _player.positionStream.listen((p) {
      _position = p;
      notifyListeners();
    });
    _durSub = _player.durationStream.listen((d) {
      _duration = d;
      notifyListeners();
    });
    _stateSub = _player.playerStateStream.listen((s) {
      _playing = s.playing;
      _processingState = s.processingState;
      if (s.processingState == ProcessingState.completed) {
        unawaited(skipNext());
      }
      notifyListeners();
    });
  }

  final DownloadQueueService _downloads;
  final AudioPlayer _player;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  final List<TrackInfo> _queue = [];
  int _index = -1;
  TrackInfo? _current;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  ProcessingState _processingState = ProcessingState.idle;
  String? _error;
  bool _preparing = false;

  TrackInfo? get current => _current;
  String? get currentRemotePath => _current?.remotePath;
  String? get currentAccountId => _current?.accountId;
  List<TrackInfo> get queue => List.unmodifiable(_queue);
  int get index => _index;
  Duration get position => _position;
  Duration? get duration => _duration;
  bool get playing => _playing;
  bool get preparing => _preparing;
  String? get error => _error;
  ProcessingState get processingState => _processingState;

  /// Play a track: if not cached, enqueue download then play local file.
  Future<void> playTrack(
    TrackInfo track, {
    List<TrackInfo>? playlist,
  }) async {
    _error = null;
    if (playlist != null) {
      _queue
        ..clear()
        ..addAll(playlist);
      _index = _queue.indexWhere(
        (t) =>
            t.remotePath == track.remotePath && t.accountId == track.accountId,
      );
      if (_index < 0) {
        _queue.insert(0, track);
        _index = 0;
      }
    } else if (_queue.isEmpty) {
      _queue.add(track);
      _index = 0;
    } else {
      final i = _queue.indexWhere(
        (t) =>
            t.remotePath == track.remotePath && t.accountId == track.accountId,
      );
      if (i >= 0) {
        _index = i;
      } else {
        _queue.add(track);
        _index = _queue.length - 1;
      }
    }
    _current = _queue[_index];
    notifyListeners();
    await _loadAndPlay(_current!);
  }

  Future<void> _loadAndPlay(TrackInfo track) async {
    _preparing = true;
    _error = null;
    notifyListeners();
    try {
      String? local = track.localPath;
      if (local == null || !File(local).existsSync()) {
        final task = await _downloads.enqueue(
          track.accountId,
          track.remotePath,
          fileName: track.fileName,
        );
        if (task.status != DownloadStatus.completed || task.localPath == null) {
          throw StateError(task.errorMessage ?? '下载失败');
        }
        local = task.localPath;
        track.localPath = local;
      }
      // CRITICAL: setFilePath — local only, never network URL.
      await _player.setFilePath(local!);
      _current = track;
      await _player.play();
    } catch (e) {
      _error = e.toString();
      await _player.stop();
    } finally {
      _preparing = false;
      notifyListeners();
    }
  }

  Future<void> playPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_current == null && _queue.isNotEmpty) {
        _index = _index < 0 ? 0 : _index;
        await _loadAndPlay(_queue[_index]);
      } else {
        await _player.play();
      }
    }
  }

  Future<void> pause() => _player.pause();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> skipNext() async {
    if (_queue.isEmpty) return;
    if (_index + 1 >= _queue.length) {
      await _player.stop();
      _playing = false;
      notifyListeners();
      return;
    }
    _index++;
    _current = _queue[_index];
    notifyListeners();
    await _loadAndPlay(_current!);
  }

  Future<void> skipPrevious() async {
    if (_queue.isEmpty) return;
    if (_position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    if (_index <= 0) {
      await seek(Duration.zero);
      return;
    }
    _index--;
    _current = _queue[_index];
    notifyListeners();
    await _loadAndPlay(_current!);
  }

  Future<void> stop() async {
    await _player.stop();
    _current = null;
    _index = -1;
    notifyListeners();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
