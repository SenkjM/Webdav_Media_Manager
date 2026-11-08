// SPDX-License-Identifier: AGPL-3.0-or-later

import 'cover_state.dart';

/// One readable manga unit (container or image directory). See docs/99 §19.
///
/// A series is **not** an entity of its own: [series] is a plain tag on the
/// row, exactly like `album` on a track. The series list, its covers and its
/// book count are all derived from the books that carry the tag, so an empty
/// series cannot exist.
class Manga {
  const Manga({
    required this.id,
    required this.sourceName,
    required this.remotePath,
    required this.title,
    this.author,
    this.series,
    this.volume,
    this.chapterNumber,
    this.pageCount = 0,
    this.coverState = 0,
    this.format = MangaFormat.unknown,
    this.remoteMissing = false,
    this.pageTurn,
    required this.updatedAt,
    this.rev = 0,
  });

  final String id;
  final String sourceName;
  final String remotePath;
  final String title;
  final String? author;

  /// Series tag (trimmed, never empty — unset is `null`). The book's series is
  /// this string; the album-like grouping is derived from it.
  final String? series;
  final String? volume;
  final String? chapterNumber;
  final int pageCount;

  /// Cover availability state: 0=unknown, 1=none, 2=present (see [CoverState]).
  /// The local thumb path is derived from identity via [CacheService]; never
  /// persisted as a path column.
  final int coverState;

  /// Convenience accessor.
  CoverState get coverStateEnum => CoverState.fromInt(coverState);

  final String format;
  final bool remoteMissing;

  /// Per-manga page-turn override (`ltr` / `rtl`); null = follow global.
  final String? pageTurn;

  final DateTime updatedAt;

  /// Sync version (same [RevClock] scale as music rows). Assigned by the
  /// database on every local write; kept verbatim when adopting a cloud row.
  final int rev;

  String get displayAuthor =>
      (author == null || author!.trim().isEmpty) ? '' : author!.trim();

  Map<String, Object?> toMap() => {
    'id': id,
    'source_name': sourceName,
    'remote_path': remotePath,
    'title': title,
    'author': author,
    'series': series,
    'volume': volume,
    'chapter_number': chapterNumber,
    'page_count': pageCount,
    'cover_state': coverState,
    'format': format,
    'remote_missing': remoteMissing ? 1 : 0,
    'page_turn': pageTurn,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'rev': rev,
  };

  static Manga fromMap(Map<String, Object?> map) {
    final rawTurn = map['page_turn'] as String?;
    // Legacy migration: non-empty cover_relpath → present(2), empty → unknown(0).
    final legacyRelpath = map['cover_relpath'] as String?;
    final legacyCoverState =
        (legacyRelpath != null && legacyRelpath.isNotEmpty) ? 2 : 0;
    return Manga(
      id: map['id'] as String? ?? '',
      sourceName: map['source_name'] as String? ?? '',
      remotePath: map['remote_path'] as String? ?? '',
      title: map['title'] as String? ?? '',
      author: map['author'] as String?,
      series: normalizeMangaSeriesTag(map['series'] as String?),
      volume: map['volume'] as String?,
      chapterNumber: map['chapter_number'] as String?,
      pageCount: (map['page_count'] as int?) ?? 0,
      coverState: (map['cover_state'] as int?) ?? legacyCoverState,
      format: map['format'] as String? ?? MangaFormat.unknown,
      remoteMissing: ((map['remote_missing'] as int?) ?? 0) != 0,
      pageTurn: (rawTurn == null || rawTurn.trim().isEmpty) ? null : rawTurn,
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      rev: (map['rev'] as int?) ?? 0,
    );
  }

  Manga copyWith({
    String? remotePath,
    String? title,
    String? author,
    bool clearAuthor = false,
    String? series,
    bool clearSeries = false,
    String? volume,
    String? chapterNumber,
    int? pageCount,
    int? coverState,
    String? format,
    bool? remoteMissing,
    String? pageTurn,
    bool clearPageTurn = false,
    DateTime? updatedAt,
    int? rev,
  }) {
    return Manga(
      id: id,
      sourceName: sourceName,
      remotePath: remotePath ?? this.remotePath,
      title: title ?? this.title,
      author: clearAuthor ? null : (author ?? this.author),
      series: clearSeries
          ? null
          : normalizeMangaSeriesTag(series ?? this.series),
      volume: volume ?? this.volume,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      pageCount: pageCount ?? this.pageCount,
      coverState: coverState ?? this.coverState,
      format: format ?? this.format,
      remoteMissing: remoteMissing ?? this.remoteMissing,
      pageTurn: clearPageTurn ? null : (pageTurn ?? this.pageTurn),
      updatedAt: updatedAt ?? this.updatedAt,
      rev: rev ?? this.rev,
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

/// Canonical form of the series tag: trimmed, blank collapses to `null`.
///
/// Callers that also want to treat a display sentinel as "unset" (the service
/// does, for 「未指定」) apply that on top of this.
String? normalizeMangaSeriesTag(String? raw) {
  final trimmed = raw?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
