import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../models/webdav_item.dart';
import 'prefetch_cache.dart';
import 'webdav_service.dart';

/// Audio-only lookahead for the unified music player.
///
/// The prefetch window now only downloads **audio bytes** so skipping around
/// stays smooth; it no longer reads tags/covers and never writes the library.
/// Metadata comes from the persistent library/scan path instead. Files land in
/// the system-managed [PrefetchCache] (cleared on every app start), so no
/// manual cleanup or cap is needed.
class MusicPrefetchService {
  MusicPrefetchService({
    required this.webDav,
    required this.tracks,
    required this.currentIndex,
    required this.backward,
    required this.forward,
  });

  final WebDavService webDav;
  final List<TrackInfo> Function() tracks;
  final int Function() currentIndex;
  final int Function() backward;
  final int Function() forward;

  String? _accountId;
  final Set<String> _failed = {};
  bool _disposed = false;
  bool _looping = false;
  int _gen = 0;
  CancelToken? _token;

  String? get accountId => _accountId;

  /// Complete prefetch audio file for [track], if any.
  Future<String?> cachedAudioPath(TrackInfo track) async {
    final id = _accountId ?? track.accountId;
    if (id.isEmpty) return null;
    final file = await PrefetchCache.file(
      bucket: 'audio',
      accountId: id,
      remotePath: track.effectiveAudioRemotePath,
      name: track.fileName,
    );
    return PrefetchCache.isComplete(file) ? file.path : null;
  }

  void start({required String accountId}) {
    _accountId = accountId;
    _disposed = false;
    _gen++;
    _token?.cancel('rebuild');
    _token = CancelToken();
    _ensureLoop();
  }

  void nudge() {
    if (_disposed || _accountId == null) return;
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
    if (_looping || _disposed || _accountId == null) return;
    _looping = true;
    final gen = _gen;
    unawaited(_run(gen));
  }

  Future<void> _run(int gen) async {
    final token = _token;
    try {
      while (gen == _gen && !_disposed) {
        final job = await _pickAudio();
        if (job == null) break;
        try {
          await _downloadAudio(job, token);
        } catch (e) {
          if (gen != _gen || _isCancel(e)) break;
          _failed.add(job.effectiveAudioRemotePath);
        }
      }
    } finally {
      _looping = false;
      if (!_disposed && gen != _gen) _ensureLoop();
    }
  }

  Future<TrackInfo?> _pickAudio() async {
    final queue = tracks();
    final current = currentIndex();
    if (current < 0 || current >= queue.length) return null;
    final indexes = <int>[];
    for (var delta = 1; delta <= backward(); delta++) {
      final i = current - delta;
      if (i < 0) break;
      indexes.add(i);
    }
    for (var delta = 1; delta <= forward(); delta++) {
      final i = current + delta;
      if (i >= queue.length) break;
      indexes.add(i);
    }
    for (final i in indexes) {
      final item = queue[i];
      final key = item.effectiveAudioRemotePath;
      if (_failed.contains(key)) continue;
      if (item.localPath != null && File(item.localPath!).existsSync()) {
        continue;
      }
      if (await cachedAudioPath(item) != null) continue;
      return item;
    }
    return null;
  }

  Future<void> _downloadAudio(TrackInfo item, CancelToken? token) async {
    final id = _accountId ?? item.accountId;
    if (id.isEmpty) return;
    final key = item.effectiveAudioRemotePath;
    final dest = await PrefetchCache.file(
      bucket: 'audio',
      accountId: id,
      remotePath: key,
      name: item.fileName,
    );
    if (PrefetchCache.isComplete(dest)) return;
    final part = File('${dest.path}.part');
    if (part.existsSync()) part.deleteSync();
    await webDav.downloadToFile(id, key, part, cancelToken: token);
    if (!part.existsSync() || part.lengthSync() <= 0) return;
    if (dest.existsSync()) dest.deleteSync();
    await part.rename(dest.path);
  }
}

bool _isCancel(Object error) =>
    error is DioException && CancelToken.isCancel(error);
