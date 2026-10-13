/// One node in the local-only user folder tree (overlay; not track identity).
class UserFolder {
  const UserFolder({
    required this.id,
    this.parentId,
    required this.name,
    this.sortOrder = 0,
    required this.createdAt,
  });

  final String id;

  /// Null = direct child of the virtual root 「我的文件夹」.
  final String? parentId;
  final String name;
  final int sortOrder;
  final DateTime createdAt;

  UserFolder copyWith({
    String? id,
    String? parentId,
    bool clearParent = false,
    String? name,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return UserFolder(
      id: id ?? this.id,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'parent_id': parentId,
    'name': name,
    'sort_order': sortOrder,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  static UserFolder fromMap(Map<String, Object?> map) {
    return UserFolder(
      id: map['id'] as String? ?? '',
      parentId: map['parent_id'] as String?,
      name: map['name'] as String? ?? '',
      sortOrder: (map['sort_order'] as int?) ?? 0,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}

/// Virtual root label key for path display (not a DB row).
const kMyFoldersRootName = '我的文件夹';

/// Stored home of a leaf ref that hangs off the virtual root.
///
/// 「我的文件夹」 has no `user_folders` row, so a ref parked there still needs a
/// concrete `folder_id`. Folder ids are UUID v4 ([UserFolderService.createFolder]),
/// so a fixed token can never collide with a real one.
const kUserFolderRootId = 'root';
