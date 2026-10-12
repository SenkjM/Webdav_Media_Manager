// SPDX-License-Identifier: AGPL-3.0-or-later
import 'webdav_item.dart';

/// One page in [ImageViewerScreen] — network album or manga pages.
class ImageViewerPage {
  const ImageViewerPage({
    required this.id,
    required this.name,
    this.remotePath,
    this.localPath,
  });

  /// Cache / selection key (stable for the session).
  final String id;

  /// Shown in the chrome title line.
  final String name;

  /// When set, the viewer downloads via WebDAV into prefetch cache.
  final String? remotePath;

  /// Optional already-local file (e.g. extracted CBZ page).
  final String? localPath;

  bool get hasRemote => remotePath != null && remotePath!.isNotEmpty;

  factory ImageViewerPage.fromWebDav(WebDavItem item) => ImageViewerPage(
        id: item.path,
        name: item.name,
        remotePath: item.path,
      );
}
