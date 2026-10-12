// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'track_identity.dart';

/// Stable offline manga id: path-index, not a content hash.
///
/// `sha1('manga' + sourceName + normalized remotePath)`.
String mangaIdForRemote(String sourceName, String remotePath) {
  final key =
      'manga\u0000${normalizeSourceName(sourceName)}\u0000'
      '${normalizeRemotePath(remotePath)}';
  return sha1.convert(utf8.encode(key)).toString();
}
