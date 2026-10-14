// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

/// Stashed on the pack row: which account receives the CBZ, and which loose
/// book to delete after that CBZ has been scraped.
const packUploadPrefix = 'wmm-pack-up:';

/// Stashed on the upload row so a retry still knows which loose book started
/// the pack. Scrape is enqueued only after the bytes land.
const packOriginPrefix = 'wmm-pack-origin:';

/// Stashed on the scrape row. The loose book is deleted only after this scrape
/// finishes, not when the upload is queued, and not when the scrape fails.
const packDeletePrefix = 'wmm-pack-del:';

class PackUploadTarget {
  const PackUploadTarget({
    required this.uploadSourceName,
    required this.originMangaId,
  });

  final String uploadSourceName;
  final String originMangaId;
}

String packUploadMarker(PackUploadTarget target) {
  return packUploadPrefix +
      jsonEncode({
        'dest': target.uploadSourceName,
        'origin': target.originMangaId,
      });
}

PackUploadTarget? parsePackUploadMarker(String? raw) {
  if (raw == null || !raw.startsWith(packUploadPrefix)) return null;
  try {
    final decoded = jsonDecode(raw.substring(packUploadPrefix.length));
    if (decoded is! Map) return null;
    final dest = decoded['dest'];
    final origin = decoded['origin'];
    if (dest is! String || dest.isEmpty) return null;
    if (origin is! String || origin.isEmpty) return null;
    return PackUploadTarget(uploadSourceName: dest, originMangaId: origin);
  } catch (_) {
    return null;
  }
}

String packOriginMarker(String originMangaId) =>
    packOriginPrefix + jsonEncode(originMangaId);

String? parsePackOriginMarker(String? raw) => _parseId(raw, packOriginPrefix);

String packDeleteOriginMarker(String originMangaId) =>
    packDeletePrefix + jsonEncode(originMangaId);

String? parsePackDeleteOriginMarker(String? raw) =>
    _parseId(raw, packDeletePrefix);

String? _parseId(String? raw, String prefix) {
  if (raw == null || !raw.startsWith(prefix)) return null;
  try {
    final decoded = jsonDecode(raw.substring(prefix.length));
    if (decoded is! String || decoded.isEmpty) return null;
    return decoded;
  } catch (_) {
    return null;
  }
}
