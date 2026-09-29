import '../models/webdav_item.dart';

/// Images for the viewer, ordered like [WebDavService.listDirectory]:
/// case-insensitive filename. Directories are dropped, so the directory-first
/// half of that sort does not apply.
///
/// [ensure] is inserted only when it is itself an image and not already
/// present. This never fabricates a stand-in item (the video queue's
/// `_resolveCurrent` injects a fake `FileCategory.video` entry; do not copy that).
List<WebDavItem> imageAlbumFrom(
  Iterable<WebDavItem> items, {
  WebDavItem? ensure,
}) {
  final out = <WebDavItem>[];
  final seen = <String>{};
  for (final item in items) {
    if (item.isDirectory || !item.isImage) continue;
    if (seen.add(item.path)) out.add(item);
  }
  if (ensure != null &&
      !ensure.isDirectory &&
      ensure.isImage &&
      seen.add(ensure.path)) {
    out.add(ensure);
  }
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}
