import 'user_folder.dart';

/// One membership row: a folder leaf references an album / artist / track.
class UserFolderItem {
  const UserFolderItem({
    required this.folderId,
    required this.refKind,
    required this.refKey,
    this.sortOrder = 0,
    required this.addedAt,
  });

  final String folderId;

  /// [UserFolderRefKind] value.
  final String refKind;

  /// Album/artist grouping key, or track `music_id`.
  final String refKey;
  final int sortOrder;
  final DateTime addedAt;

  Map<String, Object?> toMap() => {
    'folder_id': folderId,
    'ref_kind': refKind,
    'ref_key': refKey,
    'sort_order': sortOrder,
    'added_at': addedAt.toUtc().toIso8601String(),
  };

  static UserFolderItem fromMap(Map<String, Object?> map) {
    return UserFolderItem(
      folderId: map['folder_id'] as String? ?? kUserFolderRootId,
      refKind: map['ref_kind'] as String? ?? '',
      refKey: map['ref_key'] as String? ?? '',
      sortOrder: (map['sort_order'] as int?) ?? 0,
      addedAt:
          DateTime.tryParse(map['added_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}
