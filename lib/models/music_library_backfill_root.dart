/// One network folder the music library may auto-scrape when auto-backfill is on.
class MusicLibraryBackfillRoot {
  const MusicLibraryBackfillRoot({
    required this.accountId,
    required this.path,
  });

  final String accountId;

  /// Remote folder path (e.g. `/Music`). Always normalized with a leading `/`.
  final String path;

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'path': path,
      };

  factory MusicLibraryBackfillRoot.fromJson(Map<String, dynamic> json) {
    final rawPath = (json['path'] as String?)?.trim() ?? '/';
    return MusicLibraryBackfillRoot(
      accountId: (json['accountId'] as String?)?.trim() ?? '',
      path: _normalizePath(rawPath),
    );
  }

  static String _normalizePath(String path) {
    if (path.isEmpty || path == '/') return '/';
    var p = path.startsWith('/') ? path : '/$path';
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  /// Stable identity for prefs dedupe.
  String get identityKey => '$accountId|$path';

  @override
  bool operator ==(Object other) =>
      other is MusicLibraryBackfillRoot &&
      other.accountId == accountId &&
      other.path == path;

  @override
  int get hashCode => Object.hash(accountId, path);
}
