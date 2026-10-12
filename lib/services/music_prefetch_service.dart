import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../models/webdav_item.dart';
import '../models/webdav_stream.dart';
import 'prefetch_cache.dart';
import 'stream_cover_reader.dart';
import 'stream_window.dart';
import 'tag_service.dart';
import 'webdav_service.dart';

/// Prefetch window for the unified music player (tags → covers → audio).
///
/// Does **not** own a player. Neighbors land in [PrefetchCache]; the next
/// [AudioPlayerService] resolve prefers those files. Tag sets go through
/// [onIngestTags] before audio download continues.
///
/// Neighbor-window filtering only gates **new network** cover/audio pulls.
/// It must not remove, skip, or invalidate already-scraped library tags or
/// files already present in `music_cache` (playback resolve checks cache first).
class MusicPrefetchService {
  MusicPrefetchService({
    required this.webDav,
    required this.tracks,
    required this.currentIndex,
    required this.backward,
    required this.forward,
    required this.sidecarEnabled,
    required this.sidecarNames,
    required this.libraryCover,
    required this.namesFor,
    required this.listNames,
    required this.isActive,
    this.onCover,
    this.onTags,
    this.onIngestTags,
  });

  final WebDavService webDav;
  final List<TrackInfo> Function() tracks;
  final int Function() currentIndex;
  final int Function() backward;
  final int Function() forward;
  final bool Function() sidecarEnabled;
  final String Function() sidecarNames;
  final String? Function(TrackInfo track) libraryCover;
  final List<String>? Function(String remotePath) namesFor;
  final Future<List<String>> Function(String remotePath) listNames;
  final bool Function() isActive;
  final void Function(String? path)? onCover;
  final void Function(String remotePath, ReadTags? tags)? onTags;
  final void Function(String remotePath, String fileName, ReadTags tags)?
  onIngestTags;

  String? _accountId;
  final Map<String, WebDavStreamSource> _resolved = {};
  final Set<String> _failed = {};
  final Map<String, ReadTags> _tags = {};
  final StreamCoverReader _covers = StreamCoverReader();
  final TagService _tagService = TagService();

  bool _disposed = false;
  bool _looping = false;
  int _gen = 0;
  CancelToken? _token;

  String? get accountId => _accountId;

  /// Prefer a complete prefetch audio file for [track], if any.
  Future<String?> cachedAudioPath(TrackInfo track) async {
    final id = track.accountId;
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
    final coverFailed = <String>{};
    try {
      if (gen != _gen || _disposed) return;
      final queue = tracks();
      final idx = currentIndex();
      if (idx < 0 || idx >= queue.length) return;
      final current = queue[idx];
      await _ensureCover(current, show: true, gen: gen, token: token);
      if (gen != _gen || _disposed) return;

      while (gen == _gen && !_disposed) {
        final coverItem = await _nextMissingCover(coverFailed);
        if (coverItem != null) {
          await _ensureCover(coverItem, show: false, gen: gen, token: token);
          if (gen != _gen || _disposed) return;
          if (!await _hasCover(coverItem)) {
            coverFailed.add(coverItem.effectiveAudioRemotePath);
          }
          continue;
        }
        if (await _nextMissingCover(coverFailed) != null) continue;
        final job = await _pickAudio();
        if (job == null) break;
        try {
          await _downloadAudio(job, token);
          if (gen != _gen || _disposed) break;
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

  Future<TrackInfo?> _nextMissingCover(Set<String> failed) async {
    final queue = tracks();
    final indexes = prefetchNeighborIndexes(
      current: currentIndex(),
      length: queue.length,
      backward: backward(),
      forward: forward(),
    );
    for (final i in indexes) {
      final item = queue[i];
      final key = item.effectiveAudioRemotePath;
      if (failed.contains(key)) continue;
      if (await _hasCover(item)) continue;
      return item;
    }
    return null;
  }

  Future<TrackInfo?> _pickAudio() async {
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

  Future<bool> _hasCover(TrackInfo item) async {
    try {
      final library = libraryCover(item);
      if (library != null && File(library).existsSync()) return true;
      final id = _accountId ?? item.accountId;
      if (id.isEmpty) return false;
      final file = await PrefetchCache.file(
        bucket: 'covers',
        accountId: id,
        remotePath: item.effectiveAudioRemotePath,
        name: 'cover.img',
      );
      // Any cover.* completion under hash prefix — check common names.
      if (PrefetchCache.isComplete(file)) return true;
      for (final ext in ['jpg', 'png', 'webp', 'img']) {
        final f = await PrefetchCache.file(
          bucket: 'covers',
          accountId: id,
          remotePath: item.effectiveAudioRemotePath,
          name: 'cover.$ext',
        );
        if (PrefetchCache.isComplete(f)) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureCover(
    TrackInfo item, {
    required bool show,
    required int gen,
    CancelToken? token,
  }) async {
    try {
      final id = _accountId ?? item.accountId;
      if (id.isEmpty) return;
      var haveCover = false;
      final library = libraryCover(item);
      if (library != null && File(library).existsSync()) {
        if (show) _show(library);
        haveCover = true;
      }

      final key = item.effectiveAudioRemotePath;
      if (!_tags.containsKey(key)) {
        final cached = await cachedAudioPath(item);
        if (cached != null) {
          final tags = await _tagService.readFromFile(cached);
          _tags[key] = tags;
          onIngestTags?.call(key, item.fileName, tags);
          if (show) onTags?.call(key, tags);
        }
      } else if (show) {
        onTags?.call(key, _tags[key]);
      }

      if (!haveCover) {
        final bytes = _tags[key]?.coverBytes;
        if (bytes != null && bytes.isNotEmpty) {
          final ext = _imageExt(bytes);
          final file = await PrefetchCache.writeBytes(
            bucket: 'covers',
            accountId: id,
            remotePath: key,
            name: 'cover.$ext',
            bytes: bytes,
          );
          if (show) _show(file.path);
          haveCover = true;
        }
      }

      if (!_tags.containsKey(key) || !haveCover) {
        final source = await _resolve(item);
        if (gen != _gen || (token?.isCancelled ?? false)) return;
        if (source != null && source.uri.isNotEmpty) {
          final tags = await _covers.extractTags(source, cancel: token);
          if (gen != _gen || (token?.isCancelled ?? false)) return;
          if (tags != null) {
            _tags[key] = tags;
            onIngestTags?.call(key, item.fileName, tags);
            if (show) onTags?.call(key, tags);
            final bytes = tags.coverBytes;
            if (!haveCover && bytes != null && bytes.isNotEmpty) {
              final ext = _imageExt(bytes);
              final file = await PrefetchCache.writeBytes(
                bucket: 'covers',
                accountId: id,
                remotePath: key,
                name: 'cover.$ext',
                bytes: bytes,
              );
              if (show) _show(file.path);
              haveCover = true;
            }
          }
        }
      }

      if (haveCover || !sidecarEnabled()) return;
      final names = namesFor(key) ?? await listNames(key);
      if (gen != _gen || (token?.isCancelled ?? false)) return;
      final match = matchSidecarCover(names, item.fileName, sidecarNames());
      if (match == null) return;
      final dir = directoryOf(key);
      final remote = dir == '/' ? '/$match' : '$dir/$match';
      final dest = await PrefetchCache.file(
        bucket: 'covers',
        accountId: id,
        remotePath: remote,
        name: match,
      );
      if (!PrefetchCache.isComplete(dest)) {
        final part = File('${dest.path}.part');
        if (part.existsSync()) part.deleteSync();
        await webDav.downloadToFile(id, remote, part, cancelToken: token);
        if (gen != _gen || (token?.isCancelled ?? false)) return;
        if (!part.existsSync() || part.lengthSync() <= 0) return;
        if (dest.existsSync()) dest.deleteSync();
        await part.rename(dest.path);
      }
      if (show && PrefetchCache.isComplete(dest)) _show(dest.path);
    } catch (e) {
      if (_isCancel(e) || gen != _gen) return;
    }
  }

  Future<void> _downloadAudio(TrackInfo item, CancelToken? token) async {
    final id = _accountId ?? item.accountId;
    if (id.isEmpty) return;
    final key = item.effectiveAudioRemotePath;
    // Tags first (ingest) before audio bytes.
    if (!_tags.containsKey(key)) {
      await _ensureCover(item, show: false, gen: _gen, token: token);
    }
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

  Future<WebDavStreamSource?> _resolve(TrackInfo item) async {
    final key = item.effectiveAudioRemotePath;
    final cached = _resolved[key];
    if (cached != null && cached.uri.isNotEmpty) return cached;
    final id = _accountId ?? item.accountId;
    if (id.isEmpty) return null;
    final source = await webDav.resolveStreamSource(
      remotePath: key,
      name: item.fileName,
      accountId: id,
      kind: StreamKind.music,
    );
    if (source != null) _resolved[key] = source;
    return source;
  }

  void _show(String path) {
    if (!isActive()) return;
    onCover?.call(path);
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
