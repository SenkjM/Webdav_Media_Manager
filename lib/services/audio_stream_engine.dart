import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:media_kit/media_kit.dart';

import '../models/webdav_item.dart';
import '../models/webdav_stream.dart';
import 'prefetch_cache.dart';
import 'stream_cover_reader.dart';
import 'stream_window.dart';
import 'video_playback_service.dart';
import 'webdav_service.dart';

/// Playlist window and the single prefetch thread for music streaming.
///
/// Playback of the current track uses the shared player and is not paused
/// or cancelled for prefetch. Everything else runs on [_run], one request
/// at a time: the current cover (only that one updates the UI), then every
/// other cover in the same window, then one neighbor audio file at a time.
/// Backward neighbors come before forward neighbors. A window change cancels
/// the in-flight prefetch request so the next pass finishes missing covers
/// before it resumes audio files. A path already in the player list, or
/// already present as a complete audio file, is not downloaded again; its
/// cover is still fetched when the window includes it.
class AudioStreamEngine {
  AudioStreamEngine({
    required this.webDav,
    required this.playback,
    required this.accountId,
    required this.tracks,
    required this.currentIndex,
    required this.backward,
    required this.forward,
    required this.sidecarEnabled,
    required this.sidecarNames,
    required this.onCover,
    required this.namesFor,
    required this.listNames,
    required this.libraryCover,
    required this.isActive,
  });

  final WebDavService webDav;
  final VideoPlaybackService playback;
  String accountId;
  final List<WebDavItem> Function() tracks;
  final int Function() currentIndex;
  final int Function() backward;
  final int Function() forward;
  final bool Function() sidecarEnabled;
  final String Function() sidecarNames;
  final void Function(String? path) onCover;
  final List<String>? Function(String remotePath) namesFor;
  final Future<List<String>> Function(String remotePath) listNames;
  final String? Function(String remotePath) libraryCover;
  final bool Function() isActive;

  final List<String> order = [];
  final Set<String> opened = {};
  final Set<String> _failed = {};
  final Map<String, WebDavStreamSource> _resolved = {};

  Player? _player;
  String? _playing;
  bool _live = false;
  bool _disposed = false;
  bool _looping = false;
  int _gen = 0;
  CancelToken? _token;
  Future<void> _gate = Future<void>.value();
  int _depth = 0;
  final StreamCoverReader _covers = StreamCoverReader();

  Future<Player> start(WebDavStreamSource source) async {
    accountId = source.accountId;
    _resolved[source.remotePath] = source;
    final player = await playback.prepare(source, bufferSizeMb: 48);
    _player = player;
    _gen++;
    _token?.cancel('rebuild');
    _token = CancelToken();
    await _sync(() async {
      final media = await _media(source.remotePath, source.name, source);
      await player.open(media, play: false);
      order
        ..clear()
        ..add(source.remotePath);
      _live = true;
      _playing = source.remotePath;
      opened.add(source.remotePath);
    });
    _ensureLoop();
    return player;
  }

  /// Move playback to [item] without [Player.open] when the playlist is ours.
  Future<Player> activate(WebDavItem item) async {
    final player = _player;
    if (player == null || !_live) {
      final source = await _resolve(item);
      if (source == null) {
        throw StateError('stream');
      }
      return start(source);
    }
    _gen++;
    _token?.cancel('switch');
    _token = CancelToken();
    final cached = await _cached(item.path, item.name);
    WebDavStreamSource? source = _resolved[item.path];
    final Media media;
    if (cached != null) {
      media = Media(cached.path);
    } else {
      source ??= await _resolve(item);
      if (source == null) throw StateError('stream');
      media = Media(source.uri, httpHeaders: source.headers);
    }
    await _sync(() async {
      if (!order.contains(item.path)) {
        await _insert(item.path, media);
      } else if (cached != null && _playing != item.path) {
        // Already listed. Jump uses the entry that was added earlier.
      }
      await _jump(item.path);
      opened.add(item.path);
      playback.retarget(_sourceFor(item, source));
      playback.setStreamArtUri(null);
    });
    if (isActive()) onCover(null);
    _ensureLoop();
    return player;
  }

  void nudge() {
    if (_disposed || !_live) return;
    _gen++;
    _token?.cancel('window');
    _token = CancelToken();
    _ensureLoop();
  }

  Future<void> dispose() async {
    _disposed = true;
    _gen++;
    _token?.cancel('dispose');
  }

  void _ensureLoop() {
    if (_looping || _disposed || !_live) return;
    _looping = true;
    final gen = _gen;
    unawaited(_run(gen));
  }

  Future<void> _run(int gen) async {
    final token = _token;
    // Failures are only for this pass. The next pass (switch, settings, or
    // a queue change) may retry a cover, but a miss must not block audio.
    final coverFailed = <String>{};
    try {
      if (gen != _gen || _disposed) return;
      final cancelled = await _cover(gen, token);
      if (cancelled || gen != _gen || _disposed) return;
      while (gen == _gen && !_disposed) {
        final coverItem = await _nextMissingCover(coverFailed);
        if (coverItem != null) {
          // Covers outrank neighbor audio. If a file download is what the
          // previous pass was doing, its token was already cancelled.
          final coverCancelled = await _ensureCover(
            coverItem,
            show: false,
            gen: gen,
            token: token,
          );
          if (coverCancelled || gen != _gen || _disposed) return;
          if (!await _hasCover(coverItem)) coverFailed.add(coverItem.path);
          continue;
        }
        final adopt = await _pick(cachedOnly: true);
        if (adopt != null) {
          final file = await _cached(adopt.path, adopt.name);
          if (file == null || gen != _gen) break;
          await _sync(() async {
            if (gen != _gen || order.contains(adopt.path)) return;
            await _insert(adopt.path, Media(file.path));
          });
          continue;
        }
        // Do not start an audio file while a window cover is still missing.
        if (await _nextMissingCover(coverFailed) != null) continue;
        final job = await _pick(cachedOnly: false);
        if (job == null) break;
        try {
          final file = await _download(job, token);
          if (gen != _gen || _disposed) break;
          await _sync(() async {
            if (gen != _gen || order.contains(job.path)) return;
            await _insert(job.path, Media(file.path));
          });
        } catch (e) {
          // Window change or a newer pass cancels this file. Playback of
          // the current track is a different request and stays up. The next
          // [_run] fetches covers before it resumes audio.
          if (gen != _gen || _isCancel(e)) break;
          _failed.add(job.path);
          final part = await _partFile(job.path, job.name);
          if (part.existsSync()) {
            try {
              part.deleteSync();
            } catch (_) {}
          }
        }
      }
    } finally {
      _looping = false;
      if (!_disposed && gen != _gen) _ensureLoop();
    }
  }

  Future<WebDavItem?> _pick({required bool cachedOnly}) async {
    final queue = tracks();
    final current = currentIndex();
    final length = queue.length;
    final indexes = <int>[];
    for (var delta = 1; delta <= backward(); delta++) {
      final i = current - delta;
      if (i < 0) break;
      indexes.add(i);
    }
    for (var delta = 1; delta <= forward(); delta++) {
      final i = current + delta;
      if (i >= length) break;
      indexes.add(i);
    }
    for (final i in indexes) {
      final item = queue[i];
      if (order.contains(item.path) || item.path == _playing) continue;
      final complete = await _isCached(item.path, item.name);
      if (cachedOnly) {
        if (complete) return item;
        continue;
      }
      if (opened.contains(item.path) || _failed.contains(item.path)) continue;
      if (complete) continue;
      return item;
    }
    return null;
  }

  Future<bool> _isCached(String remotePath, String name) async {
    final file = await PrefetchCache.file(
      bucket: 'audio',
      accountId: accountId,
      remotePath: remotePath,
      name: name,
    );
    return PrefetchCache.isComplete(file);
  }

  Future<File?> _cached(String remotePath, String name) async {
    final file = await PrefetchCache.file(
      bucket: 'audio',
      accountId: accountId,
      remotePath: remotePath,
      name: name,
    );
    return PrefetchCache.isComplete(file) ? file : null;
  }

  Future<File> _download(WebDavItem item, CancelToken? token) async {
    final dest = await PrefetchCache.file(
      bucket: 'audio',
      accountId: accountId,
      remotePath: item.path,
      name: item.name,
    );
    if (PrefetchCache.isComplete(dest)) return dest;
    final part = File('${dest.path}.part');
    if (part.existsSync()) part.deleteSync();
    await webDav.downloadToFile(accountId, item.path, part, cancelToken: token);
    if (!part.existsSync() || part.lengthSync() <= 0) {
      throw StateError('empty');
    }
    if (dest.existsSync()) dest.deleteSync();
    await part.rename(dest.path);
    return dest;
  }

  Future<File> _partFile(String remotePath, String name) async {
    final dest = await PrefetchCache.file(
      bucket: 'audio',
      accountId: accountId,
      remotePath: remotePath,
      name: name,
    );
    return File('${dest.path}.part');
  }

  Future<void> _insert(String path, Media media) async {
    final player = _player;
    if (player == null || order.contains(path)) return;
    final queue = [for (final item in tracks()) item.path];
    final at = playlistInsertAt(order: order, queue: queue, path: path);
    await player.add(media);
    if (at < order.length) {
      await player.move(order.length, at);
      order.insert(at, path);
    } else {
      order.add(path);
    }
  }

  Future<void> _jump(String path) async {
    final player = _player;
    final index = order.indexOf(path);
    if (player == null || index < 0 || _playing == path) return;
    await player.jump(index);
    _playing = path;
  }

  Future<Media> _media(
    String path,
    String name,
    WebDavStreamSource source,
  ) async {
    final cached = await _cached(path, name);
    if (cached != null) return Media(cached.path);
    return Media(source.uri, httpHeaders: source.headers);
  }

  Future<WebDavStreamSource?> _resolve(WebDavItem item) async {
    final cached = _resolved[item.path];
    if (cached != null && cached.uri.isNotEmpty) return cached;
    final source = await webDav.resolveStreamSource(
      remotePath: item.path,
      name: item.name,
      accountId: accountId,
      kind: StreamKind.music,
    );
    if (source != null) _resolved[item.path] = source;
    return source;
  }

  WebDavStreamSource _sourceFor(WebDavItem item, WebDavStreamSource? source) {
    if (source != null) return source;
    final known = _resolved[item.path];
    if (known != null) return known;
    return WebDavStreamSource(
      uri: '',
      headers: const {},
      name: item.name,
      remotePath: item.path,
      accountId: accountId,
      kind: StreamKind.music,
    );
  }

  Future<WebDavItem?> _nextMissingCover(Set<String> failed) async {
    final queue = tracks();
    final indexes = prefetchNeighborIndexes(
      current: currentIndex(),
      length: queue.length,
      backward: backward(),
      forward: forward(),
    );
    for (final i in indexes) {
      final item = queue[i];
      if (failed.contains(item.path)) continue;
      if (await _hasCover(item)) continue;
      return item;
    }
    return null;
  }

  /// Library file, embedded bytes already in the covers bucket, or a sidecar
  /// image already downloaded. No network.
  Future<bool> _hasCover(WebDavItem item) async {
    try {
      final library = libraryCover(item.path);
      if (library != null && File(library).existsSync()) return true;
      if (await _cachedCoverFile(item.path) != null) return true;
      if (await _cachedSidecar(item) != null) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<File?> _cachedCoverFile(String remotePath) async {
    for (final name in const [
      'cover.jpg',
      'cover.png',
      'cover.webp',
      'cover.img',
    ]) {
      final file = await PrefetchCache.file(
        bucket: 'covers',
        accountId: accountId,
        remotePath: remotePath,
        name: name,
      );
      if (PrefetchCache.isComplete(file)) return file;
    }
    return null;
  }

  /// Sidecar cache hit from a listing we already have. Does not list again.
  Future<File?> _cachedSidecar(WebDavItem item) async {
    final names = namesFor(item.path);
    if (names == null) return null;
    final match = matchSidecarCover(names, item.name, sidecarNames());
    if (match == null) return null;
    final dir = directoryOf(item.path);
    final remote = dir == '/' ? '/$match' : '$dir/$match';
    final dest = await PrefetchCache.file(
      bucket: 'covers',
      accountId: accountId,
      remotePath: remote,
      name: match,
    );
    return PrefetchCache.isComplete(dest) ? dest : null;
  }

  Future<bool> _cover(int gen, CancelToken? token) async {
    final index = currentIndex();
    final queue = tracks();
    if (index < 0 || index >= queue.length) return false;
    return _ensureCover(queue[index], show: true, gen: gen, token: token);
  }

  /// Cache [item]'s cover. [show] is only for the track that is current when
  /// this pass started; neighbors must not touch the player artwork.
  /// Returns true when the pass was cancelled.
  Future<bool> _ensureCover(
    WebDavItem item, {
    required bool show,
    required int gen,
    required CancelToken? token,
  }) async {
    try {
      final library = libraryCover(item.path);
      if (library != null && File(library).existsSync()) {
        if (gen != _gen) return true;
        if (show) _show(library);
        return false;
      }
      final cached = await _cachedCoverFile(item.path);
      if (gen != _gen || (token?.isCancelled ?? false)) return true;
      if (cached != null) {
        if (show) _show(cached.path);
        return false;
      }
      final sidecarHit = await _cachedSidecar(item);
      if (gen != _gen || (token?.isCancelled ?? false)) return true;
      if (sidecarHit != null) {
        if (show) _show(sidecarHit.path);
        return false;
      }
      var source = _resolved[item.path];
      if (source == null || source.uri.isEmpty) {
        source = await _resolve(item);
      }
      if (gen != _gen || (token?.isCancelled ?? false)) return true;
      if (source != null && source.uri.isNotEmpty) {
        final bytes = await _covers.extract(source, cancel: token);
        if (gen != _gen || (token?.isCancelled ?? false)) return true;
        if (bytes != null && bytes.isNotEmpty) {
          final ext = _imageExt(bytes);
          final file = await PrefetchCache.writeBytes(
            bucket: 'covers',
            accountId: accountId,
            remotePath: item.path,
            name: 'cover.$ext',
            bytes: bytes,
          );
          if (gen != _gen) return true;
          if (show) _show(file.path);
          return false;
        }
      }
      if (!sidecarEnabled()) return false;
      final names = namesFor(item.path) ?? await listNames(item.path);
      if (gen != _gen || (token?.isCancelled ?? false)) return true;
      final match = matchSidecarCover(names, item.name, sidecarNames());
      if (match == null) return false;
      final dir = directoryOf(item.path);
      final remote = dir == '/' ? '/$match' : '$dir/$match';
      final dest = await PrefetchCache.file(
        bucket: 'covers',
        accountId: accountId,
        remotePath: remote,
        name: match,
      );
      if (!PrefetchCache.isComplete(dest)) {
        final part = File('${dest.path}.part');
        if (part.existsSync()) part.deleteSync();
        await webDav.downloadToFile(
          accountId,
          remote,
          part,
          cancelToken: token,
        );
        if (gen != _gen || (token?.isCancelled ?? false)) return true;
        if (!part.existsSync() || part.lengthSync() <= 0) return false;
        if (dest.existsSync()) dest.deleteSync();
        await part.rename(dest.path);
      }
      if (gen != _gen) return true;
      if (show && PrefetchCache.isComplete(dest)) _show(dest.path);
      return false;
    } catch (e) {
      if (_isCancel(e) || gen != _gen) return true;
      return false;
    }
  }

  void _show(String path) {
    if (!isActive()) return;
    onCover(path);
    playback.setStreamArtUri(Uri.file(path));
  }

  Future<T> _sync<T>(Future<T> Function() op) async {
    if (_depth > 0) return op();
    final previous = _gate;
    final done = Completer<void>();
    _gate = done.future;
    await previous;
    _depth++;
    try {
      return await op();
    } finally {
      _depth--;
      done.complete();
    }
  }
}

bool _isCancel(Object error) =>
    error is DioException && CancelToken.isCancel(error);

String _imageExt(List<int> bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8) return 'jpg';
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return 'png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46) {
    return 'webp';
  }
  return 'img';
}
