import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/file_type_config.dart';
import '../models/webdav_item.dart';
import 'webdav_service.dart';

/// Progressive video queue for the player.
///
/// The queue is seeded with whatever the caller already knows (the video files
/// in the folder the user tapped) so playback can start **immediately**, then a
/// background scan walks the folder subtree and merges newly discovered videos
/// in as they arrive — it never blocks the first frame on a full listing.
///
/// Ordering is by name (case-insensitive), so the merged queue is identical to
/// what a full scan would have produced; a partially scanned queue is simply a
/// prefix.
class VideoQueueController extends ChangeNotifier {
  VideoQueueController({
    required WebDavService webDav,
    required this.accountId,
    required this.rootPath,
    required List<WebDavItem> seed,
    required String initialRemotePath,
    FileTypeConfig? fileTypes,
    this.autoAdvance = true,
  })  : _webDav = webDav,
        _fileTypes = fileTypes ?? FileTypeConfig() {
    _merge(seed);
    _currentRemotePath = _resolveCurrent(initialRemotePath);
  }

  final WebDavService _webDav;
  final String accountId;
  final String rootPath;
  final FileTypeConfig _fileTypes;

  /// Whether finishing a video moves on to the next one in the folder.
  final bool autoAdvance;

  final List<WebDavItem> _tracks = [];
  final Set<String> _knownPaths = {};
  String? _currentRemotePath;
  bool _scanning = false;
  bool _scanComplete = false;
  bool _cancelled = false;
  String? _scanError;
  int _discovered = 0;

  List<WebDavItem> get tracks => List.unmodifiable(_tracks);
  bool get scanning => _scanning;
  bool get scanComplete => _scanComplete;
  String? get scanError => _scanError;

  /// How many extra videos the background scan has added so far.
  int get discovered => _discovered;

  String get currentRemotePath => _currentRemotePath ?? '';

  int get length => _tracks.length;

  int get index =>
      _tracks.indexWhere((t) => t.path == _currentRemotePath);

  WebDavItem? get current {
    final i = index;
    return i >= 0 ? _tracks[i] : null;
  }

  bool get hasPrevious => index > 0;
  bool get hasNext {
    final i = index;
    return i >= 0 && i + 1 < _tracks.length;
  }

  WebDavItem? get next {
    final i = index;
    if (i < 0 || i + 1 >= _tracks.length) return null;
    return _tracks[i + 1];
  }

  WebDavItem? get previous {
    final i = index;
    if (i <= 0) return null;
    return _tracks[i - 1];
  }

  /// Move to another queue entry. Returns the new current item, or null when
  /// the index is out of range.
  WebDavItem? selectIndex(int i) {
    if (i < 0 || i >= _tracks.length) return null;
    _currentRemotePath = _tracks[i].path;
    notifyListeners();
    return _tracks[i];
  }

  WebDavItem? selectRemotePath(String remotePath) =>
      selectIndex(_tracks.indexWhere((t) => t.path == remotePath));

  /// Kick off the background scan. Safe to call more than once.
  void startScan() {
    if (_scanning || _scanComplete) return;
    _scanning = true;
    notifyListeners();
    unawaited(_scan());
  }

  void cancelScan() {
    _cancelled = true;
    _scanning = false;
  }

  /// Depth-first walk of [rootPath]; merges on every directory listing so the
  /// queue grows while the user is already watching.
  Future<void> _scan() async {
    final pending = <String>[rootPath];
    var failed = 0;
    try {
      while (pending.isNotEmpty) {
        if (_cancelled) return;
        final dir = pending.removeAt(0);
        try {
          final items = await _webDav.listDirectory(accountId, dir, fileTypes: _fileTypes);
          final videos = items.where((e) => e.isVideo).toList();
          final dirs = items.where((e) => e.isDirectory).map((e) => e.path);
          pending.addAll(dirs);
          if (videos.isNotEmpty) _merge(videos);
        } catch (e) {
          failed++;
          if (failed == 1) _scanError = e.toString();
        }
      }
    } finally {
      if (!_cancelled) {
        _scanning = false;
        _scanComplete = true;
        notifyListeners();
      }
    }
  }

  /// Insert [items] into the name-sorted queue, ignoring known paths.
  void _merge(List<WebDavItem> items) {
    var added = 0;
    for (final item in items) {
      if (!_knownPaths.add(item.path)) continue;
      _tracks.add(item);
      added++;
    }
    if (added == 0) return;
    _tracks.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    _discovered += added;
    notifyListeners();
  }

  /// Keep the tapped video selected even if the seed did not contain it (e.g.
  /// it was opened from a folder listing that has since changed).
  String _resolveCurrent(String remotePath) {
    if (_knownPaths.contains(remotePath)) return remotePath;
    final name = remotePath.split('/').last;
    final item = WebDavItem(
      name: name,
      path: remotePath,
      isDirectory: false,
      category: FileCategory.video,
    );
    _tracks.add(item);
    _knownPaths.add(remotePath);
    _tracks.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return remotePath;
  }

  @override
  void dispose() {
    cancelScan();
    super.dispose();
  }
}
