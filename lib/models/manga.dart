// SPDX-License-Identifier: AGPL-3.0-or-later
/// One readable manga unit (container or image directory). See docs/99 §19.
class Manga {
  const Manga({
    required this.id,
    required this.sourceName,
    required this.remotePath,
    required this.title,
    this.author,
    this.seriesId,
    this.volume,
    this.chapterNumber,
    this.pageCount = 0,
    this.coverRelpath,
    this.format = MangaFormat.unknown,
    this.remoteMissing = false,
    required this.updatedAt,
  });

  final String id;
  final String sourceName;
  final String remotePath;
  final String title;
  final String? author;
  final String? seriesId;
  final String? volume;
  final String? chapterNumber;
  final int pageCount;
  final String? coverRelpath;
  final String format;
  final bool remoteMissing;
  final DateTime updatedAt;

  String get displayAuthor =>
      (author == null || author!.trim().isEmpty) ? '' : author!.trim();

  Map<String, Object?> toMap() => {
        'id': id,
        'source_name': sourceName,
        'remote_path': remotePath,
        'title': title,
        'author': author,
        'series_id': seriesId,
        'volume': volume,
        'chapter_number': chapterNumber,
        'page_count': pageCount,
        'cover_relpath': coverRelpath,
        'format': format,
        'remote_missing': remoteMissing ? 1 : 0,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  static Manga fromMap(Map<String, Object?> map) {
    return Manga(
      id: map['id'] as String? ?? '',
      sourceName: map['source_name'] as String? ?? '',
      remotePath: map['remote_path'] as String? ?? '',
      title: map['title'] as String? ?? '',
      author: map['author'] as String?,
      seriesId: map['series_id'] as String?,
      volume: map['volume'] as String?,
      chapterNumber: map['chapter_number'] as String?,
      pageCount: (map['page_count'] as int?) ?? 0,
      coverRelpath: map['cover_relpath'] as String?,
      format: map['format'] as String? ?? MangaFormat.unknown,
      remoteMissing: ((map['remote_missing'] as int?) ?? 0) != 0,
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}

/// Stored `mangas.format` values.
abstract final class MangaFormat {
  static const cbz = 'cbz';
  static const cbr = 'cbr';
  static const pdf = 'pdf';
  static const epub = 'epub';
  static const images = 'images';
  static const unknown = 'unknown';
}
