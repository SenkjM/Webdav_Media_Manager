import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../models/webdav_stream.dart';

/// Owns the single media_kit [Player] used for WebDAV video streaming.
///
/// The video screen creates a `VideoController(player)` for rendering and
/// disposes only that controller when it closes; this service keeps the
/// [Player] alive so 「后台播放」can keep audio going after the screen is
/// dismissed. It does NOT post any media notification (unlike music) — video
/// playback is intentionally not surfaced cross-interface.
class VideoPlaybackService extends ChangeNotifier {
  Player? _player;
  WebDavStreamSource? _source;
  bool _active = false;
  String? _lastError;

  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _completedSub;

  Player? get player => _player;
  WebDavStreamSource? get source => _source;
  bool get isActive => _active;
  String? get title => _source?.name;
  String? get lastError => _lastError;

  /// Prepare a fresh [Player] for a new stream (replaces and disposes any
  /// previous player). The caller must create its `VideoController` and then
  /// call `player.open(mediaFor(source))` — media_kit_video needs the video
  /// controller attached *before* the media is opened.
  ///
  /// [bufferSizeMb] becomes `PlayerConfiguration.bufferSize` (libmpv demuxer
  /// cache). Hardware decoding is applied by the screen's `VideoController`,
  /// not here.
  Future<Player> prepare(
    WebDavStreamSource source, {
    required int bufferSizeMb,
  }) async {
    await _disposePlayer();
    final player = Player(
      configuration: PlayerConfiguration(
        bufferSize: bufferSizeMb * 1024 * 1024,
      ),
    );
    _errorSub = player.stream.error.listen((e) {
      _lastError = e;
      notifyListeners();
    });
    _completedSub = player.stream.completed.listen((completed) {
      if (completed) notifyListeners();
    });
    _player = player;
    _source = source;
    _active = true;
    _lastError = null;
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
    await _disposePlayer();
    notifyListeners();
  }

  Future<void> _disposePlayer() async {
    await _errorSub?.cancel();
    await _completedSub?.cancel();
    _errorSub = null;
    _completedSub = null;
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
