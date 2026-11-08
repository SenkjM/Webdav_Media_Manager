import 'dart:convert';
import 'dart:isolate';

import '../models/file_type_config.dart';
import '../models/webdav_item.dart';
import '../services/rust_core_service.dart';

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

  int get effectiveMaxDepth => includeSubdirs ? clampDepth(maxDepth) : minDepth;

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

/// One directory entry returned by `wdmm_account_walk` (Rust).
class WalkEntry {
  const WalkEntry({
    required this.path,
    required this.name,
    required this.size,
    required this.isDirectory,
    this.modified,
  });

  final String path;
  final String name;
  final int size;
  final bool isDirectory;

  /// Remote modification time, null when the driver does not report it.
  final DateTime? modified;

  /// Parent directory of [path] (`/` for a top-level entry).
  String get directory {
    final slash = path.lastIndexOf('/');
    if (slash <= 0) return '/';
    return path.substring(0, slash);
  }

  /// Map to the UI model, classifying files with [fileTypes].
  WebDavItem toItem(FileTypeConfig fileTypes) => WebDavItem(
    name: name,
    path: path,
    isDirectory: isDirectory,
    size: size,
    modified: modified,
    category: isDirectory ? FileCategory.other : fileTypes.categoryFor(name),
  );

  factory WalkEntry.fromJson(Map<String, dynamic> json) => WalkEntry(
    path: json['path'] as String? ?? '',
    name: json['name'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
    isDirectory: json['is_dir'] == true,
    modified: switch (json['mtime']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
      _ => null,
    },
  );
}

/// Recursive remote walk owned by Rust (`wdmm_account_walk`, contract
/// `dart-cutover-slices.md` §Slice 3).
///
/// Callers await [DirectoryWalker.scan]; the Rust side lists the remote tree
/// iteratively, applies the depth/entry fuse, de-duplicates paths and reports
/// the entries. Dart no longer walks directories itself.
class DirectoryWalker {
  DirectoryWalker._({
    required this.rootPath,
    required this.options,
    required this.entries,
    required this.truncated,
    required this.scanned,
  }) {
    for (final entry in entries) {
      _byDirectory.putIfAbsent(entry.directory, () => []).add(entry);
    }
  }

  /// Legacy synchronous planner, retired in favour of [scan].
  ///
  /// Flutter code that still calls `nextDirectory()`/`acceptChildren()` fails
  /// loudly instead of silently walking on the Dart side.
  DirectoryWalker({
    required String rootPath,
    WalkOptions options = const WalkOptions(),
  }) : rootPath = rootPath,
       options = options,
       entries = const [],
       truncated = false,
       scanned = 0 {
    throw UnsupportedError(_legacyHint);
  }

  static const String _legacyHint =
      'DirectoryWalker() no longer walks on the Dart side; '
      'use DirectoryWalker.scan() (Rust wdmm_account_walk).';

  /// Walk [rootPath] of [accountId] in Rust and decode the reply.
  ///
  /// [extensions] overrides the classification tables with the user's
  /// configured extension sets; [kinds] is one of `video`, `audio`, `image`,
  /// `manga`, `any`. A depth/entry fuse trip keeps the partial result and sets
  /// [truncated].
  static Future<DirectoryWalker> scan({
    required String accountId,
    required String rootPath,
    WalkOptions options = const WalkOptions(),
    List<String>? extensions,
    List<String> kinds = const ['any'],
  }) async {
    final kindsJson = jsonEncode({
      'kinds': kinds,
      'extensions': ?extensions,
    });
    // The Dart fuse counts the root as depth 0; Rust counts directory levels
    // with the root at level 1.
    final maxDepth = '${options.effectiveMaxDepth + 1}';
    final maxEntries = '${options.effectiveMaxEntries}';
    final raw = await Isolate.run(
      () => RustCoreService.accountWalk(
        accountId: accountId,
        root: rootPath,
        maxDepth: maxDepth,
        maxEntries: maxEntries,
        kindsJson: kindsJson,
      ),
    );
    if (raw == null) {
      throw StateError(
        'DirectoryWalker.scan: native Rust core is unavailable '
        '(wdmm_account_walk)',
      );
    }
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('DirectoryWalker.scan: unexpected reply: $raw');
    }
    final ok = decoded['ok'] == true;
    final error = decoded['error'];
    if (!ok && error != 'limit') {
      throw StateError('DirectoryWalker.scan: ${error ?? 'unknown error'}');
    }
    final entries = <WalkEntry>[
      for (final rawEntry in decoded['entries'] as List? ?? const [])
        if (rawEntry is Map<String, dynamic>) WalkEntry.fromJson(rawEntry),
    ];
    return DirectoryWalker._(
      rootPath: rootPath,
      options: options,
      entries: entries,
      truncated: !ok || decoded['truncated'] == true,
      scanned: (decoded['scanned'] as num?)?.toInt() ?? 0,
    );
  }

  final String rootPath;
  final WalkOptions options;
  final List<WalkEntry> entries;

  /// True when the Rust depth/entry fuse stopped the walk early.
  final bool truncated;

  /// Directories the Rust walk actually listed.
  final int scanned;

  final Map<String, List<WalkEntry>> _byDirectory = {};

  /// Regular files, in walk (breadth-first) order.
  List<WalkEntry> get files => [
    for (final entry in entries)
      if (!entry.isDirectory) entry,
  ];

  /// Directories, in walk (breadth-first) order.
  List<WalkEntry> get directories => [
    for (final entry in entries)
      if (entry.isDirectory) entry,
  ];

  /// Every entry whose parent is [dir].
  List<WalkEntry> entriesIn(String dir) =>
      List.unmodifiable(_byDirectory[_normDir(dir)] ?? const <WalkEntry>[]);

  /// Regular files whose parent is [dir].
  List<WalkEntry> filesIn(String dir) => [
    for (final entry in entriesIn(dir))
      if (!entry.isDirectory) entry,
  ];

  /// Directory paths that produced at least one entry.
  List<String> get directoryPaths => List.unmodifiable(_byDirectory.keys);

  /// File names grouped by directory (subtitle/sidecar matching).
  Map<String, List<String>> get namesByDirectory => {
    for (final group in _byDirectory.entries)
      group.key: [
        for (final entry in group.value)
          if (!entry.isDirectory) entry.name,
      ],
  };

  String? nextDirectory() => throw UnsupportedError(_legacyHint);

  int acceptChildren(String dirPath, Iterable<String> childDirPaths) =>
      throw UnsupportedError(_legacyHint);

  Set<String> get visited => throw UnsupportedError(_legacyHint);

  int get listedCount => throw UnsupportedError(_legacyHint);

  bool get isDone => throw UnsupportedError(_legacyHint);

  static String _normDir(String path) {
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path.isEmpty ? '/' : path;
  }
}
