// SPDX-License-Identifier: AGPL-3.0-or-later
/// Soft grouping of [Manga] rows (album-like). Progress stays per-Manga.
class MangaSeries {
  const MangaSeries({
    required this.id,
    required this.title,
    this.author,
    this.sortTitle,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String? author;
  final String? sortTitle;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'author': author,
        'sort_title': sortTitle ?? title,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  static MangaSeries fromMap(Map<String, Object?> map) {
    return MangaSeries(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      author: map['author'] as String?,
      sortTitle: map['sort_title'] as String?,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}
