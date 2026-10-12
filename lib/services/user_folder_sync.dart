// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

/// What one user-folder sync pass should do.
enum FolderSyncAction { none, push, pull }

/// User folders sync as **one whole snapshot** (`library/folders/folders.json`)
/// — they are only references (music ids, album / artist names, manga ids,
/// series ids), so the file stays small and a shard / tombstone scheme would
/// buy nothing.
///
/// Rules (whole-snapshot last-write-wins, decided per pass):
/// * no cloud file → push when this device has any folder data or edits;
/// * only this device changed since the last pass → push;
/// * only the cloud changed (its `updatedAt` differs from the one we last
///   saw) → pull, replacing the local overlay;
/// * both changed → the newer side wins as a whole (local edit time vs the
///   cloud `updatedAt`); the losing side's edits are dropped, not merged.
FolderSyncAction planFolderSync({
  required int localChangedAtMs,
  required int lastSyncAtMs,
  required String? cloudUpdatedAt,
  required String? lastSeenCloudUpdatedAt,
  required bool localEmpty,
}) {
  if (cloudUpdatedAt == null) {
    if (localEmpty && localChangedAtMs == 0) return FolderSyncAction.none;
    return FolderSyncAction.push;
  }
  final localDirty = localChangedAtMs > lastSyncAtMs;
  final cloudChanged = cloudUpdatedAt != lastSeenCloudUpdatedAt;
  if (!localDirty && !cloudChanged) return FolderSyncAction.none;
  if (!localDirty) return FolderSyncAction.pull;
  if (!cloudChanged) return FolderSyncAction.push;
  final cloudMs =
      DateTime.tryParse(cloudUpdatedAt)?.millisecondsSinceEpoch ?? 0;
  return localChangedAtMs >= cloudMs
      ? FolderSyncAction.push
      : FolderSyncAction.pull;
}

const String userFoldersFormat = 'wmp_user_folders';
const String userFoldersFileName = 'folders.json';

/// Decoded `folders.json`.
class UserFoldersDoc {
  const UserFoldersDoc({required this.updatedAt, required this.snapshot});

  /// ISO-8601 UTC stamp written by the device that pushed it.
  final String updatedAt;

  /// `{folders: [...], items: [...]}` rows, as [LibraryDatabase] exports them.
  final Map<String, dynamic> snapshot;
}

Uint8List encodeUserFoldersDoc({
  required Map<String, dynamic> snapshot,
  required String updatedAt,
  required String deviceId,
}) => Uint8List.fromList(
  utf8.encode(
    const JsonEncoder.withIndent('  ').convert({
      'format': userFoldersFormat,
      'formatVersion': 1,
      'deviceId': deviceId,
      'updatedAt': updatedAt,
      'folders': snapshot['folders'] ?? const [],
      'items': snapshot['items'] ?? const [],
    }),
  ),
);

UserFoldersDoc? decodeUserFoldersDoc(Uint8List bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map || decoded['format'] != userFoldersFormat) return null;
  return UserFoldersDoc(
    updatedAt: decoded['updatedAt'] as String? ?? '',
    snapshot: {
      'folders': decoded['folders'] as List<dynamic>? ?? const [],
      'items': decoded['items'] as List<dynamic>? ?? const [],
    },
  );
}
