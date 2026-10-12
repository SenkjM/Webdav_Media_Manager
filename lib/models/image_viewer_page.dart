// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io';

import 'webdav_item.dart';

/// Produces a page that has no URL of its own — a CBZ entry, which only comes
/// out of the archive through an HTTP Range read.
///
/// The viewer calls it with the destination it wants the bytes at, and only for
/// the pages inside its prefetch window, so opening a 180-page CBZ no longer
/// costs the whole archive before the first frame appears.
typedef ImagePageLoader = Future<void> Function(File dest);

/// One page in [ImageViewerScreen] — network album or manga pages.
class ImageViewerPage {
  const ImageViewerPage({
    required this.id,
    required this.name,
    this.remotePath,
    this.localPath,
    this.localLoader,
  });

  /// Cache / selection key (stable for the session).
  final String id;

  /// Shown in the chrome title line.
  final String name;

  /// When set, the viewer downloads via WebDAV into prefetch cache.
  final String? remotePath;

  /// Optional already-local file (e.g. extracted CBZ page). With
  /// [localLoader] set this is the path to fill in, not a path that exists.
  final String? localPath;

  /// Fills [localPath] on demand. Set for CBZ pages; null for plain files.
  final ImagePageLoader? localLoader;

  bool get hasRemote => remotePath != null && remotePath!.isNotEmpty;

  bool get hasLocalLoader =>
      localLoader != null && (localPath?.isNotEmpty ?? false);

  factory ImageViewerPage.fromWebDav(WebDavItem item) =>
      ImageViewerPage(id: item.path, name: item.name, remotePath: item.path);
}
