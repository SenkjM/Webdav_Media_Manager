// SPDX-License-Identifier: AGPL-3.0-or-later
/// Frozen page order for one [Manga] (relative path inside the container).
class MangaPage {
  const MangaPage({
    required this.mangaId,
    required this.pageIndex,
    required this.relPath,
  });

  final String mangaId;
  final int pageIndex;
  final String relPath;

  Map<String, Object?> toMap() => {
        'manga_id': mangaId,
        'page_index': pageIndex,
        'rel_path': relPath,
      };

  static MangaPage fromMap(Map<String, Object?> map) {
    return MangaPage(
      mangaId: map['manga_id'] as String? ?? '',
      pageIndex: (map['page_index'] as int?) ?? 0,
      relPath: map['rel_path'] as String? ?? '',
    );
  }
}
