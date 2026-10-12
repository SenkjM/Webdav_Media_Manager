import 'dart:collection';

import '../services/stream_window.dart' show normDir;

/// Shared directory-walk limits for playlists and (later) library scrape.
///
/// Prefs keep **separate** keys per surface; this type only carries the values.
class WalkOptions {
  const WalkOptions({
    this.includeSubdirs = false,
    this.maxDepth = defaultMaxDepth,
    this.maxEntries = defaultMaxEntries,
  });

  /// When false, only the root directory is listed ([effectiveMaxDepth] = 0).
  final bool includeSubdirs;

  /// Max depth relative to root: `0` = root only, `1` = root + one child level.
  final int maxDepth;

  /// Safety fuse: maximum directories that will be listed (including root).
  final int maxEntries;

  static const int defaultMaxDepth = 1;
  static const int defaultMaxEntries = 500;
  static const int minDepth = 0;
  static const int maxDepthClamp = 20;
  static const int minEntries = 1;
  static const int maxEntriesClamp = 50000;

  static int clampDepth(int value) =>
      value.clamp(minDepth, maxDepthClamp).toInt();

  static int clampMaxEntries(int value) =>
      value.clamp(minEntries, maxEntriesClamp).toInt();

  int get effectiveMaxDepth =>
      includeSubdirs ? clampDepth(maxDepth) : minDepth;

  int get effectiveMaxEntries => clampMaxEntries(maxEntries);

  WalkOptions copyWith({
    bool? includeSubdirs,
    int? maxDepth,
    int? maxEntries,
  }) => WalkOptions(
    includeSubdirs: includeSubdirs ?? this.includeSubdirs,
    maxDepth: maxDepth ?? this.maxDepth,
    maxEntries: maxEntries ?? this.maxEntries,
  );
}

class _PendingDir {
  const _PendingDir(this.path, this.depth);
  final String path;
  final int depth;
}

/// Pure BFS walk planner: visited-set cycle guard, depth cap, entry fuse.
///
/// Call [nextDirectory] → list that path remotely → [acceptChildren] with the
/// child directory paths. Unit-tested without I/O.
class DirectoryWalker {
  DirectoryWalker({
    required String rootPath,
    this.options = const WalkOptions(),
  }) : _root = normDir(rootPath) {
    _enqueue(_root, 0);
  }

  final WalkOptions options;
  final String _root;
  final Queue<_PendingDir> _pending = Queue<_PendingDir>();
  final Set<String> _visited = {};
  final Set<String> _queued = {};
  final Map<String, int> _depthOf = {};
  int _listed = 0;

  /// Normalized paths already handed to the caller for listing.
  Set<String> get visited => Set.unmodifiable(_visited);

  int get listedCount => _listed;

  bool get isDone =>
      _pending.isEmpty || _listed >= options.effectiveMaxEntries;

  void _enqueue(String path, int depth) {
    final n = normDir(path);
    if (_visited.contains(n) || _queued.contains(n)) return;
    if (depth > options.effectiveMaxDepth) return;
    _pending.add(_PendingDir(n, depth));
    _queued.add(n);
    _depthOf[n] = depth;
  }

  /// Next directory to list, or `null` when finished / fuse tripped.
  String? nextDirectory() {
    while (_pending.isNotEmpty) {
      if (_listed >= options.effectiveMaxEntries) {
        _pending.clear();
        return null;
      }
      final next = _pending.removeFirst();
      _queued.remove(next.path);
      if (!_visited.add(next.path)) continue;
      _listed++;
      _depthOf[next.path] = next.depth;
      return next.path;
    }
    return null;
  }

  /// After listing [dirPath], enqueue child directories within depth / cycle rules.
  ///
  /// Returns how many new children were enqueued.
  int acceptChildren(String dirPath, Iterable<String> childDirPaths) {
    final parent = normDir(dirPath);
    final parentDepth = _depthOf[parent] ?? 0;
    if (parentDepth >= options.effectiveMaxDepth) return 0;

    final before = _queued.length;
    for (final raw in childDirPaths) {
      final child = normDir(raw);
      if (child.isEmpty) continue;
      _enqueue(child, parentDepth + 1);
    }
    return _queued.length - before;
  }
}
