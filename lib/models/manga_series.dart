// SPDX-License-Identifier: AGPL-3.0-or-later
import '../utils/manga_identity.dart';

/// A series as the **frontend sees it**: a label shared by the [Manga] rows
/// that carry it — the manga counterpart of an album.
///
/// There is no series table and no series row to create or leave behind. The
/// only stored fact is `mangas.series` (the tag); everything here is derived
/// from the books, so a series always has at least one book and its title can
/// never disagree with what the books say.
///
/// [id] is the deterministic `sha1('mangaSeries' + title)` that folder soft
/// refs (`mangaSeries`) use, so a ref survives as long as the title does.
class MangaSeries {
  const MangaSeries({required this.title});

  final String title;

  String get id => mangaSeriesIdForTitle(title);

  @override
  bool operator ==(Object other) =>
      other is MangaSeries && other.title == title;

  @override
  int get hashCode => title.hashCode;

  @override
  String toString() => 'MangaSeries($title)';
}
