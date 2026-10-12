import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/library_tag_dimension.dart';
import '../models/user_folder.dart';
import '../models/user_folder_item.dart';
import 'library_database.dart';

/// Local-only user folder tree overlay (99 §18).
///
/// Does not own track identity — membership is soft refs into library groups.
class UserFolderService extends ChangeNotifier {
  UserFolderService({required LibraryDatabase db}) : _db = db;

  final LibraryDatabase _db;
  final _uuid = const Uuid();

  final List<UserFolder> _folders = [];
  final List<UserFolderItem> _items = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<UserFolder> get folders => List.unmodifiable(_folders);
  List<UserFolderItem> get items => List.unmodifiable(_items);

  Future<void> init() async {
    await reload();
  }

  Future<void> reload() async {
    _folders
      ..clear()
      ..addAll(await _db.loadUserFolders());
    _items
      ..clear()
      ..addAll(await _db.loadUserFolderItems());
    _loaded = true;
    notifyListeners();
  }

  /// Children of [parentId] (null = virtual root 「我的文件夹」).
  List<UserFolder> childrenOf(String? parentId) {
    final list = [
      for (final f in _folders)
        if (f.parentId == parentId) f,
    ];
    list.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  UserFolder? folderById(String id) {
    for (final f in _folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  List<UserFolderItem> itemsIn(String folderId) {
    final list = [
      for (final i in _items)
        if (i.folderId == folderId) i,
    ];
    list.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.addedAt.compareTo(b.addedAt);
    });
    return list;
  }

  /// Path segments from virtual root to [folderId] (names only).
  /// Empty [folderId] / unknown → just the virtual root.
  List<String> pathNames(String? folderId) {
    final names = <String>[kMyFoldersRootName];
    if (folderId == null || folderId.isEmpty) return names;
    final chain = <UserFolder>[];
    var id = folderId;
    final guard = <String>{};
    while (id.isNotEmpty && guard.add(id)) {
      final f = folderById(id);
      if (f == null) break;
      chain.add(f);
      id = f.parentId ?? '';
    }
    for (final f in chain.reversed) {
      names.add(f.name);
    }
    return names;
  }

  String pathDisplay(String? folderId, {String sep = ' / '}) =>
      pathNames(folderId).join(sep);

  Future<UserFolder> createFolder({
    String? parentId,
    required String name,
  }) async {
    final trimmed = name.trim().isEmpty ? '新文件夹' : name.trim();
    final siblings = childrenOf(parentId);
    final folder = UserFolder(
      id: _uuid.v4(),
      parentId: parentId,
      name: trimmed,
      sortOrder: siblings.isEmpty ? 0 : siblings.last.sortOrder + 1,
      createdAt: DateTime.now(),
    );
    await _db.upsertUserFolder(folder);
    _folders.add(folder);
    notifyListeners();
    return folder;
  }

  Future<void> renameFolder(String id, String name) async {
    final f = folderById(id);
    if (f == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final updated = f.copyWith(name: trimmed);
    await _db.upsertUserFolder(updated);
    final idx = _folders.indexWhere((x) => x.id == id);
    if (idx >= 0) _folders[idx] = updated;
    notifyListeners();
  }

  Future<void> deleteFolder(String id) async {
    await _db.deleteUserFolder(id);
    final dropIds = <String>{id};
    // Collect descendants already removed from DB recursively.
    var grew = true;
    while (grew) {
      grew = false;
      for (final f in _folders) {
        if (f.parentId != null &&
            dropIds.contains(f.parentId) &&
            dropIds.add(f.id)) {
          grew = true;
        }
      }
    }
    _folders.removeWhere((f) => dropIds.contains(f.id));
    _items.removeWhere((i) => dropIds.contains(i.folderId));
    notifyListeners();
  }

  Future<int> addRefs({
    required String folderId,
    required String refKind,
    required Iterable<String> refKeys,
  }) async {
    if (!UserFolderRefKind.isKnown(refKind)) return 0;
    if (folderById(folderId) == null) return 0;
    var added = 0;
    final existing = {
      for (final i in _items)
        if (i.folderId == folderId && i.refKind == refKind) i.refKey,
    };
    var order = itemsIn(folderId).length;
    for (final key in refKeys) {
      final k = key.trim();
      if (k.isEmpty || existing.contains(k)) continue;
      final item = UserFolderItem(
        folderId: folderId,
        refKind: refKind,
        refKey: k,
        sortOrder: order++,
        addedAt: DateTime.now(),
      );
      await _db.upsertUserFolderItem(item);
      _items.add(item);
      existing.add(k);
      added++;
    }
    if (added > 0) notifyListeners();
    return added;
  }

  Future<void> removeRef({
    required String folderId,
    required String refKind,
    required String refKey,
  }) async {
    await _db.deleteUserFolderItem(
      folderId: folderId,
      refKind: refKind,
      refKey: refKey,
    );
    _items.removeWhere(
      (i) =>
          i.folderId == folderId && i.refKind == refKind && i.refKey == refKey,
    );
    notifyListeners();
  }

  /// Descendants of [folderId] including itself.
  Set<String> descendantIds(String folderId) {
    final dropIds = <String>{folderId};
    var grew = true;
    while (grew) {
      grew = false;
      for (final f in _folders) {
        if (f.parentId != null &&
            dropIds.contains(f.parentId) &&
            dropIds.add(f.id)) {
          grew = true;
        }
      }
    }
    return dropIds;
  }

  /// Move folder under [newParentId] (null = virtual root). Refuses self/descendant.
  Future<bool> moveFolder(String folderId, {String? newParentId}) async {
    if (folderId.isEmpty) return false;
    if (newParentId != null && descendantIds(folderId).contains(newParentId)) {
      return false;
    }
    final f = folderById(folderId);
    if (f == null) return false;
    if (f.parentId == newParentId) return true;
    final siblings = childrenOf(newParentId);
    final updated = f.copyWith(
      parentId: newParentId,
      clearParent: newParentId == null,
      sortOrder: siblings.isEmpty ? 0 : siblings.last.sortOrder + 1,
    );
    await _db.upsertUserFolder(updated);
    final idx = _folders.indexWhere((x) => x.id == folderId);
    if (idx >= 0) _folders[idx] = updated;
    notifyListeners();
    return true;
  }

  /// Move soft-ref to another folder (delete+add).
  Future<bool> moveRef({
    required String fromFolderId,
    required String toFolderId,
    required String refKind,
    required String refKey,
  }) async {
    if (fromFolderId == toFolderId) return true;
    if (folderById(toFolderId) == null) return false;
    await removeRef(folderId: fromFolderId, refKind: refKind, refKey: refKey);
    final n = await addRefs(
      folderId: toFolderId,
      refKind: refKind,
      refKeys: [refKey],
    );
    return n > 0;
  }

  /// Copy soft-ref (reference copy) into [toFolderId].
  Future<bool> copyRef({
    required String toFolderId,
    required String refKind,
    required String refKey,
  }) async {
    final n = await addRefs(
      folderId: toFolderId,
      refKind: refKind,
      refKeys: [refKey],
    );
    return n > 0;
  }
}
