// SPDX-License-Identifier: AGPL-3.0-or-later
/// Per-Manga reading progress (page index). Series does not own progress rows.
class MangaProgress {
  const MangaProgress({
    required this.mangaId,
    required this.pageIndex,
    required this.updatedAt,
  });

  final String mangaId;
  final int pageIndex;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => {
        'manga_id': mangaId,
        'page_index': pageIndex,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  static MangaProgress fromMap(Map<String, Object?> map) {
    return MangaProgress(
      mangaId: map['manga_id'] as String? ?? '',
      pageIndex: (map['page_index'] as int?) ?? 0,
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}
