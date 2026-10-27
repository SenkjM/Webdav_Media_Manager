import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/library_tag_dimension.dart';
import '../models/user_folder.dart';
import '../models/user_folder_item.dart';
import 'rust_core_service.dart';

/// Local-only user folder tree overlay (99 §18).
///
/// Does not own track identity — membership is soft refs into library groups.
///
/// A ref whose [UserFolderItem.folderId] is [kUserFolderRootId] hangs off the
/// virtual root 「我的文件夹」, which has no `user_folders` row.
///
/// **Wave B cutover**: persistence now lives in the Rust core via
/// [RustCoreService] FFI. The sqflite user_folder tables are no longer
/// written; the sqflite read fallback has been removed.
class UserFolderService extends ChangeNotifier {
  UserFolderService();
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
    // Prefer the Rust core. On non-Android hosts where the FFI is not loaded,
    // leave state empty and mark loaded so callers don't retry.
    if (RustCoreService.userFolderListChildren(kUserFolderRootId) != null) {
      _reloadFromFfi();
      return;
    }
    _loaded = true;
    notifyListeners();
  }

  /// BFS-load the whole tree from the Rust core.
  ///
  /// [wdmm_user_folder_list_children] returns only direct children, so we walk
  /// from the virtual root outward, loading items per folder along the way.
  void _reloadFromFfi() {
    final allFolders = <UserFolder>[];
    final allItems = <UserFolderItem>[];

    // Items parked on the virtual root itself.
    final rootItemsJson =
        RustCoreService.userFolderListItems(kUserFolderRootId) ?? '[]';
    allItems.addAll(_parseItems(rootItemsJson));

    // BFS over the folder tree. Start at the virtual root.
    final queue = <String>[kUserFolderRootId];
    final visited = <String>{kUserFolderRootId};
    while (queue.isNotEmpty) {
      final parentId = queue.removeAt(0);
      final childrenJson =
          RustCoreService.userFolderListChildren(parentId) ?? '[]';
      final children = _parseFolders(childrenJson);
      for (final child in children) {
        allFolders.add(child);
        final itemsJson = RustCoreService.userFolderListItems(child.id) ?? '[]';
        allItems.addAll(_parseItems(itemsJson));
        if (visited.add(child.id)) queue.add(child.id);
      }
    }

    _folders
      ..clear()
      ..addAll(allFolders);
    _items
      ..clear()
      ..addAll(allItems);
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
  /// [kUserFolderRootId] / unknown → just the virtual root.
  List<String> pathNames(String? folderId) {
    final names = <String>[kMyFoldersRootName];
    if (folderId == null || folderId == kUserFolderRootId) return names;
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
    final sortOrder = siblings.isEmpty ? 0 : siblings.last.sortOrder + 1;

    final payload = jsonEncode({
      'name': trimmed,
      'parent_id': parentId,
      'sort_order': sortOrder,
    });
    final resultJson = RustCoreService.userFolderCreate(payload);
    final folder = resultJson == null || resultJson.startsWith('error:')
        // FFI unavailable or rejected — keep a local-only placeholder so the
        // UI is not blocked. The next reload() will resync with the core.
        ? UserFolder(
            id: _uuid.v4(),
            parentId: parentId,
            name: trimmed,
            sortOrder: sortOrder,
            createdAt: DateTime.now(),
          )
        : _parseFolderObject(jsonDecode(resultJson) as Map<String, dynamic>);
    _folders.add(folder);
    if (resultJson != null && !resultJson.startsWith('error:')) {
      _stampChanged();
    }
    notifyListeners();
    return folder;
  }

  Future<void> renameFolder(String id, String name) async {
    final f = folderById(id);
    if (f == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final res = RustCoreService.userFolderRename(id, trimmed);
    final updated = f.copyWith(name: trimmed);
    final idx = _folders.indexWhere((x) => x.id == id);
    if (idx >= 0) _folders[idx] = updated;
    if (res != null && !res.startsWith('error:')) _stampChanged();
    notifyListeners();
  }

  Future<void> deleteFolder(String id) async {
    // Rust cascades descendants + items atomically.
    final res = RustCoreService.userFolderDelete(id);
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
    if (res != null && !res.startsWith('error:')) _stampChanged();
    notifyListeners();
  }

  Future<int> addRefs({
    required String folderId,
    required String refKind,
    required Iterable<String> refKeys,
  }) async {
    if (!UserFolderRefKind.isKnown(refKind)) return 0;
    // The virtual root is a legal home for a ref.
    if (folderId != kUserFolderRootId && folderById(folderId) == null) {
      return 0;
    }
    var added = 0;
    final existing = {
      for (final i in _items)
        if (i.folderId == folderId && i.refKind == refKind) i.refKey,
    };
    var order = itemsIn(folderId).length;
    for (final key in refKeys) {
      final k = key.trim();
      if (k.isEmpty || existing.contains(k)) continue;
      final payload = jsonEncode({
        'folder_id': folderId,
        'ref_kind': refKind,
        'ref_key': k,
        'sort_order': order,
      });
      final res = RustCoreService.userFolderAddItem(payload);
      if (res != null && res.startsWith('error:')) continue;
      final item = UserFolderItem(
        folderId: folderId,
        refKind: refKind,
        refKey: k,
        sortOrder: order++,
        addedAt: DateTime.now(),
      );
      _items.add(item);
      existing.add(k);
      added++;
    }
    if (added > 0) {
      _stampChanged();
      notifyListeners();
    }
    return added;
  }

  Future<void> removeRef({
    required String folderId,
    required String refKind,
    required String refKey,
  }) async {
    final res =
        RustCoreService.userFolderRemoveItem(folderId, refKind, refKey);
    _items.removeWhere(
      (i) =>
          i.folderId == folderId && i.refKind == refKind && i.refKey == refKey,
    );
    if (res != null && !res.startsWith('error:')) _stampChanged();
    notifyListeners();
  }

  /// Move one ref up/down inside its folder (delta -1/+1).
  ///
  /// `sort_order` is rewritten for the whole folder so the visual order is the
  /// stored order (same rule the tree already uses for folders). We rewrite
  /// the core store atomically via [wdmm_user_folder_set_items].
  Future<bool> moveRefWithinFolder({
    required String folderId,
    required String refKind,
    required String refKey,
    required int delta,
  }) async {
    final list = itemsIn(folderId);
    final index = list.indexWhere(
      (i) => i.refKind == refKind && i.refKey == refKey,
    );
    if (index < 0) return false;
    final target = index + delta;
    if (target < 0 || target >= list.length) return false;
    final next = List<UserFolderItem>.from(list);
    final moved = next.removeAt(index);
    next.insert(target, moved);
    // Persist the full ordered set to the core.
    final arr = [
      for (var i = 0; i < next.length; i++)
        {
          'ref_kind': next[i].refKind,
          'ref_key': next[i].refKey,
          'sort_order': i,
        },
    ];
    RustCoreService.userFolderSetItems(folderId, jsonEncode(arr));
    // Mirror into in-memory state with new sort orders.
    _items.removeWhere((i) => i.folderId == folderId);
    for (var i = 0; i < next.length; i++) {
      _items.add(UserFolderItem(
        folderId: folderId,
        refKind: next[i].refKind,
        refKey: next[i].refKey,
        sortOrder: i,
        addedAt: next[i].addedAt,
      ));
    }
    _stampChanged();
    notifyListeners();
    return true;
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
    final sortOrder = siblings.isEmpty ? 0 : siblings.last.sortOrder + 1;
    // Core expects "root"/"" for the virtual root.
    final newParentKey = newParentId ?? kUserFolderRootId;
    final res = RustCoreService.userFolderMove(folderId, newParentKey);
    if (res != null && res.startsWith('error:')) return false;
    final updated = f.copyWith(
      parentId: newParentId,
      clearParent: newParentId == null,
      sortOrder: sortOrder,
    );
    final idx = _folders.indexWhere((x) => x.id == folderId);
    if (idx >= 0) _folders[idx] = updated;
    if (res != null && !res.startsWith('error:')) _stampChanged();
    notifyListeners();
    return true;
  }
  ///
  /// Returns the id of the new root folder, or null when the copy is
  /// refused (unknown source, or a target inside the source subtree — the
  /// twin would have to be created inside the folder it is copying).
  ///
  /// [name] overrides the twin root only; descendants keep their own names.
  /// Refs travel as reference copies, so the two trees stay independent.
  Future<String?> copyFolder(
    String folderId, {
    String? newParentId,
    String? name,
  }) async {
    if (folderId.isEmpty) return null;
    if (newParentId != null && descendantIds(folderId).contains(newParentId)) {
      return null;
    }
    final source = folderById(folderId);
    if (source == null) return null;

    final wanted = name?.trim() ?? '';
    String? newRootId;
    // Breadth-first, so a twin's parent always exists before the twin.
    final pending = <(UserFolder, String?, String)>[
      (source, newParentId, wanted.isEmpty ? source.name : wanted),
    ];
    for (var head = 0; head < pending.length; head++) {
      final (folder, parentId, folderName) = pending[head];
      final twin = await createFolder(parentId: parentId, name: folderName);
      newRootId ??= twin.id;
      for (final item in itemsIn(folder.id)) {
        await addRefs(
          folderId: twin.id,
          refKind: item.refKind,
          refKeys: [item.refKey],
        );
      }
      for (final child in childrenOf(folder.id)) {
        pending.add((child, twin.id, child.name));
      }
    }
    return newRootId;
  }

  /// Move soft-ref to another folder (delete+add).
  Future<bool> moveRef({
    required String fromFolderId,
    required String toFolderId,
    required String refKind,
    required String refKey,
  }) async {
    if (fromFolderId == toFolderId) return true;
    if (toFolderId != kUserFolderRootId && folderById(toFolderId) == null) {
      return false;
    }
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

  // ── FFI JSON parsing helpers ─────────────────────────────────────────────
  //
  // The core uses Unix timestamps (int seconds) for `created_at` / `added_at`;
  // the Dart models use [DateTime]. We convert on the way in.

  static List<UserFolder> _parseFolders(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return [
      for (final e in list) _parseFolderObject(Map<String, dynamic>.from(e as Map)),
    ];
  }

  static UserFolder _parseFolderObject(Map<String, dynamic> m) {
    return UserFolder(
      id: m['id'] as String? ?? '',
      parentId: m['parent_id'] as String?,
      name: m['name'] as String? ?? '',
      sortOrder: m['sort_order'] as int? ?? 0,
      createdAt: _parseUnixOrIso(m['created_at']),
    );
  }

  static List<UserFolderItem> _parseItems(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return [
      for (final e in list)
        UserFolderItem(
          folderId: (e as Map)['folder_id'] as String? ?? kUserFolderRootId,
          refKind: e['ref_kind'] as String? ?? '',
          refKey: e['ref_key'] as String? ?? '',
          sortOrder: e['sort_order'] as int? ?? 0,
          addedAt: _parseUnixOrIso(e['added_at']),
        ),
    ];
  }

  /// Accept either a Unix timestamp (int seconds) or an ISO8601 string.
  static DateTime _parseUnixOrIso(Object? raw) {
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
    }
    return DateTime.tryParse(raw as String? ?? '') ?? DateTime.now();
  }

  // ── Sync helpers ──────────────────────────────────────────────────────────

  /// Stamp `folders_changed_at` in the Core KV store to mark a local mutation.
  /// Only called when the Core call that triggered the mutation succeeded
  /// (non-null, non-error: result).
  static void _stampChanged() {
    RustCoreService.kvSet(
      'folders_changed_at',
      '${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  /// Whole user-folder overlay as JSON-friendly maps, suitable for WebDAV sync.
  ///
  /// Uses in-memory state directly — callers should ensure [reload()] was
  /// called recently if staleness is a concern.
  Map<String, dynamic> exportSnapshot() => {
    'folders': [for (final f in _folders) f.toMap()],
    'items': [for (final i in _items) i.toMap()],
  };

  /// Replace the whole user-folder overlay from [snap] via Core FFI, then
  /// reload in-memory state.
  ///
  /// Throws [StateError] if Core FFI is unavailable or returns an error.
  /// Does **not** bump `folders_changed_at` — adopting a cloud snapshot is
  /// not a local edit.
  Future<void> importSnapshot(Map<String, dynamic> snap) async {
    final json = jsonEncode(snap);
    final result = RustCoreService.userFolderReplaceSnapshot(json);
    if (result == null || result.startsWith('error:')) {
      throw StateError('userFolderReplaceSnapshot failed: $result');
    }
    await reload();
  }
}
