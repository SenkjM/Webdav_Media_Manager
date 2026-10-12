import 'package:flutter_test/flutter_test.dart';

import 'package:webdav_media_manager/models/library_tag_dimension.dart';
import 'package:webdav_media_manager/models/user_folder.dart';
import 'package:webdav_media_manager/models/user_folder_item.dart';
import 'package:webdav_media_manager/services/library_database.dart';
import 'package:webdav_media_manager/services/user_folder_service.dart';

class _MemDb extends LibraryDatabase {
  final folders = <UserFolder>[];
  final items = <UserFolderItem>[];

  @override
  Future<List<UserFolder>> loadUserFolders() async => List.of(folders);

  @override
  Future<List<UserFolderItem>> loadUserFolderItems({String? folderId}) async {
    if (folderId == null) return List.of(items);
    return [for (final i in items) if (i.folderId == folderId) i];
  }

  @override
  Future<void> upsertUserFolder(UserFolder folder) async {
    folders.removeWhere((f) => f.id == folder.id);
    folders.add(folder);
  }

  @override
  Future<void> deleteUserFolder(String id) async {
    final drop = <String>{id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final f in folders) {
        if (f.parentId != null && drop.contains(f.parentId) && drop.add(f.id)) {
          grew = true;
        }
      }
    }
    folders.removeWhere((f) => drop.contains(f.id));
    items.removeWhere((i) => drop.contains(i.folderId));
  }

  @override
  Future<void> upsertUserFolderItem(UserFolderItem item) async {
    items.removeWhere(
      (i) =>
          i.folderId == item.folderId &&
          i.refKind == item.refKind &&
          i.refKey == item.refKey,
    );
    items.add(item);
  }

  @override
  Future<void> deleteUserFolderItem({
    required String folderId,
    required String refKind,
    required String refKey,
  }) async {
    items.removeWhere(
      (i) =>
          i.folderId == folderId &&
          i.refKind == refKind &&
          i.refKey == refKey,
    );
  }
}

void main() {
  test('path display starts at virtual root', () async {
    final db = _MemDb();
    final svc = UserFolderService(db: db);
    await svc.init();
    expect(svc.pathDisplay(null), kMyFoldersRootName);
    final a = await svc.createFolder(name: '摇滚');
    final b = await svc.createFolder(parentId: a.id, name: '2020');
    expect(svc.pathDisplay(b.id), '$kMyFoldersRootName / 摇滚 / 2020');
  });

  test('add album/artist/track refs and skip duplicates', () async {
    final db = _MemDb();
    final svc = UserFolderService(db: db);
    await svc.init();
    final folder = await svc.createFolder(name: '收藏');
    expect(
      await svc.addRefs(
        folderId: folder.id,
        refKind: UserFolderRefKind.album,
        refKeys: ['A', 'B', 'A'],
      ),
      2,
    );
    expect(
      await svc.addRefs(
        folderId: folder.id,
        refKind: UserFolderRefKind.artist,
        refKeys: ['X'],
      ),
      1,
    );
    expect(
      await svc.addRefs(
        folderId: folder.id,
        refKind: UserFolderRefKind.track,
        refKeys: ['mid1'],
      ),
      1,
    );
    expect(svc.itemsIn(folder.id), hasLength(4));
  });

  test('LibraryTagDimension v1 registers album and artist only', () {
    expect(LibraryTagDimension.v1TagDimensions.map((d) => d.id).toList(), [
      UserFolderRefKind.album,
      UserFolderRefKind.artist,
    ]);
    expect(LibraryTagDimension.byId('genre'), isNull);
  });
}
