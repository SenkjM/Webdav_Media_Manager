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
    this.imageExtensions = const [],
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
  final List<String> imageExtensions;

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
    'imageExtensions': imageExtensions,
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
      imageExtensions: exts is List
          ? [
              for (final e in exts)
                if (e is String) e,
            ]
          : const [],
    );
  }
}
