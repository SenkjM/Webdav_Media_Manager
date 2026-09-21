import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../models/webdav_stream.dart';
import 'music_audio_handler.dart';

/// Owns the single media_kit [Player] used for WebDAV video streaming.
///
/// The video screen creates a `VideoController(player)` for rendering and
/// disposes only that controller when it closes; this service keeps the
/// [Player] alive so background playback can continue after the screen is
/// dismissed.
///
/// The player itself is owned by [MusicAudioHandler], which takes over the
/// MediaSession / media notification for the duration of video playback, so
/// the notification bar, lock screen and system media controls all show the
/// video with play/pause — that foreground service is also what keeps video
/// playing after pressing Home.
class VideoPlaybackService extends ChangeNotifier {
  VideoPlaybackService({required MusicAudioHandler handler}) : _handler = handler {
    // Music playback takes the MediaSession back by calling exitVideoMode()
    // directly; keep our own state in sync so the screen/lifecycle stops
    // treating the (now idle) video player as active.
    _modeSub = _handler.playbackState.listen((state) {
      if (!_active) return;
      if (_handler.isVideoMode) return;
      _active = false;
      _source = null;
      _boosting = false;
      notifyListeners();
    });
  }

  final MusicAudioHandler _handler;
  StreamSubscription<PlaybackState>? _modeSub;

  WebDavStreamSource? _source;
  bool _active = false;
  String? _lastError;
  double _lastRate = 1.0;

  /// Last non-temporary playback rate (the user's slider choice).
  double get lastRate => _lastRate;

  /// Whether a long-press speed boost is currently applied.
  bool _boosting = false;
  bool get boosting => _boosting;

  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _completedSub;

  /// The streaming player (owned by the shared audio handler).
  Player? get player =>
      _handler.isVideoMode || _active ? _handler.videoPlayer : null;
  WebDavStreamSource? get source => _source;
  bool get isActive => _active;
  String? get title => _source?.name;
  String? get lastError => _lastError;

  /// Take over the media session for [source] and return the video player.
  ///
  /// [bufferSizeMb] becomes `PlayerConfiguration.bufferSize` (libmpv demuxer
  /// cache). Hardware decoding is applied by the screen's `VideoController`,
  /// not here.
  Future<Player> prepare(
    WebDavStreamSource source, {
    required int bufferSizeMb,
    double? initialRate,
  }) async {
    final player = _handler.videoPlayer;
    await _errorSub?.cancel();
    await _completedSub?.cancel();
    _errorSub = player.stream.error.listen((e) {
      _lastError = e;
      notifyListeners();
    });
    _completedSub = player.stream.completed.listen((completed) {
      if (completed) notifyListeners();
    });
    _source = source;
    _active = true;
    _lastError = null;
    _boosting = false;
    // Remember the user's chosen speed so a long-press release can restore it.
    _lastRate = initialRate ?? 1.0;
    // Publish the notification / MediaItem before the media is opened, so the
    // native foreground service is already alive while libmpv buffers.
    await _handler.enterVideoMode(source, media: mediaFor(source));
    notifyListeners();
    return player;
  }

  /// The [Media] to open for [source] (HTTP Basic auth headers included).
  Media mediaFor(WebDavStreamSource source) =>
      Media(source.uri, httpHeaders: source.headers);

  Future<void> stop() async {
    _active = false;
    _source = null;
    _lastError = null;
    _boosting = false;
    await _errorSub?.cancel();
    await _completedSub?.cancel();
    _errorSub = null;
    _completedSub = null;
    // Tears down the notification / MediaSession video session; the player is
    // owned by the handler and stays alive for the next stream.
    await _handler.exitVideoMode();
    notifyListeners();
  }

  /// Apply the user's speed choice and remember it for the next video.
  Future<void> setRate(double rate) async {
    final p = player;
    if (p == null) return;
    _lastRate = rate;
    await p.setRate(rate);
    notifyListeners();
  }

  /// Long-press speed boost: raise to [rate] while held, restore on release.
  Future<void> beginBoost(double rate) async {
    final p = player;
    if (p == null) return;
    _boosting = true;
    await p.setRate(rate);
    notifyListeners();
  }

  Future<void> endBoost() async {
    final p = player;
    if (p == null) return;
    if (!_boosting) return;
    _boosting = false;
    await p.setRate(_lastRate);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_modeSub?.cancel());
    unawaited(_errorSub?.cancel());
    unawaited(_completedSub?.cancel());
    super.dispose();
  }
}
