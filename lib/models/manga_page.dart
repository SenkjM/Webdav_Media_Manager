// SPDX-License-Identifier: AGPL-3.0-or-later
/// Frozen page order for one [Manga].
///
/// [relPath] means one of two things, decided by the book format:
/// * container (`cbz`, …): the entry name inside the archive, and the book's
///   own `remote_path` is that archive;
/// * loose images: the image's path **relative to the source root**, carrying
///   its own leading `/`. The page list *is* the book's membership, so it must
///   not depend on the folder the book was built from — that folder is only a
///   re-scan hint.
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
