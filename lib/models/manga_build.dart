/// Directory-listing fuse for loose-image builds.
///
/// The walk helpers in `lib/utils/manga_scan_walk.dart` default to 2000. The
/// worker used to rebuild its [WalkOptions] without this field, so the walk
/// silently fell back to 500 and cut big folders short.
const int kMangaBuildMaxEntries = 2000;

/// How a loose-image folder is turned into books.
///
/// [merged] makes the folder itself one book (every image below it, sorted);
/// [perDir] makes one book per image directory found under it.
enum MangaBuildMode {
  merged,
  perDir;

  String get storageKey => switch (this) {
    MangaBuildMode.merged => 'merged',
    MangaBuildMode.perDir => 'per_dir',
  };

  static MangaBuildMode fromStorageKey(String? key) =>
      key == 'per_dir' ? MangaBuildMode.perDir : MangaBuildMode.merged;
}

/// Parameters of a [TaskKind.mangaBuild] job, persisted as a sidecar JSON.
///
/// The front end never walks the folder. It collects metadata, enqueues this,
/// and the worker lists the folder once while the queue shows the progress —
/// the same shape the music scan uses for a selected folder.
class MangaBuildPayload {
  const MangaBuildPayload({
    required this.mode,
    required this.accountId,
    required this.sourceName,
    required this.remotePath,
    required this.folderName,
    required this.title,
    this.author,
    this.seriesTitle,
    this.includeSubdirs = true,
    this.maxDepth = 1,
    this.maxEntries = kMangaBuildMaxEntries,
    this.imageExtensions = const [],
    this.targetMangaId,
  });

  final MangaBuildMode mode;
  final String accountId;
  final String sourceName;
  final String remotePath;
  final String folderName;
  final String title;
  final String? author;
  final String? seriesTitle;
  final bool includeSubdirs;
  final int maxDepth;

  /// Directory-listing fuse of the walk. Carried explicitly because the
  /// worker's own [WalkOptions] would otherwise fall back to 500 and silently
  /// clamp the walk helpers' 2000.
  final int maxEntries;
  final List<String> imageExtensions;

  /// Set when the job re-scans a book the user already owns (the 丙 rule: the
  /// target id is explicit, so its progress and hand-edited metadata survive).
  /// Null means 「build a new book」 — a fresh surrogate id is minted.
  final String? targetMangaId;

  Map<String, dynamic> toJson() => {
    'mode': mode.storageKey,
    'accountId': accountId,
    'sourceName': sourceName,
    'remotePath': remotePath,
    'folderName': folderName,
    'title': title,
    if (author != null) 'author': author,
    if (seriesTitle != null) 'seriesTitle': seriesTitle,
    'includeSubdirs': includeSubdirs,
    'maxDepth': maxDepth,
    'maxEntries': maxEntries,
    'imageExtensions': imageExtensions,
    if (targetMangaId != null) 'targetMangaId': targetMangaId,
  };

  static MangaBuildPayload? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final remotePath = m['remotePath'] as String?;
    final sourceName = m['sourceName'] as String?;
    if (remotePath == null || sourceName == null) return null;
    final exts = m['imageExtensions'];
    final folderName = (m['folderName'] as String?) ?? '';
    return MangaBuildPayload(
      mode: MangaBuildMode.fromStorageKey(m['mode'] as String?),
      accountId: (m['accountId'] as String?) ?? '',
      sourceName: sourceName,
      remotePath: remotePath,
      folderName: folderName,
      title: (m['title'] as String?) ?? folderName,
      author: m['author'] as String?,
      seriesTitle: m['seriesTitle'] as String?,
      includeSubdirs: (m['includeSubdirs'] as bool?) ?? true,
      maxDepth: (m['maxDepth'] as num?)?.toInt() ?? 1,
      maxEntries: (m['maxEntries'] as num?)?.toInt() ?? kMangaBuildMaxEntries,
      imageExtensions: exts is List
          ? [
              for (final e in exts)
                if (e is String) e,
            ]
          : const [],
      targetMangaId: m['targetMangaId'] as String?,
    );
  }
}
