import 'package:flutter_test/flutter_test.dart';

import 'package:webdav_media_manager/models/library_sentinels.dart';
import 'package:webdav_media_manager/models/library_tag_dimension.dart';
import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/models/user_folder.dart';
import 'package:webdav_media_manager/services/user_folder_service.dart';

void main() {
  test('path display starts at virtual root', () async {
    final svc = UserFolderService();
    await svc.init();
    expect(svc.pathDisplay(null), kMyFoldersRootName);
    final a = await svc.createFolder(name: '摇滚');
    final b = await svc.createFolder(parentId: a.id, name: '2020');
    expect(svc.pathDisplay(b.id), '$kMyFoldersRootName / 摇滚 / 2020');
  });

  test('add album/artist/track refs and skip duplicates', () async {
    final svc = UserFolderService();
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

  test('refs can hang off the virtual root', () async {
    final svc = UserFolderService();
    await svc.init();
    expect(
      await svc.addRefs(
        folderId: kUserFolderRootId,
        refKind: UserFolderRefKind.album,
        refKeys: ['A'],
      ),
      1,
    );
    expect(svc.itemsIn(kUserFolderRootId), hasLength(1));
    expect(svc.itemsIn(kUserFolderRootId).single.folderId, kUserFolderRootId);
  });

  test('a ref can move to the virtual root and back', () async {
    final svc = UserFolderService();
    await svc.init();
    final folder = await svc.createFolder(name: '收藏');
    await svc.addRefs(
      folderId: folder.id,
      refKind: UserFolderRefKind.album,
      refKeys: ['A'],
    );
    expect(
      await svc.moveRef(
        fromFolderId: folder.id,
        toFolderId: kUserFolderRootId,
        refKind: UserFolderRefKind.album,
        refKey: 'A',
      ),
      isTrue,
    );
    expect(svc.itemsIn(kUserFolderRootId), hasLength(1));
    expect(svc.itemsIn(folder.id), isEmpty);
    expect(
      await svc.moveRef(
        fromFolderId: kUserFolderRootId,
        toFolderId: folder.id,
        refKind: UserFolderRefKind.album,
        refKey: 'A',
      ),
      isTrue,
    );
    expect(svc.itemsIn(folder.id), hasLength(1));
  });

  test('refs still refuse an unknown folder id', () async {
    final svc = UserFolderService();
    await svc.init();
    expect(
      await svc.addRefs(
        folderId: 'nope',
        refKind: UserFolderRefKind.album,
        refKeys: ['A'],
      ),
      0,
    );
    final folder = await svc.createFolder(name: '收藏');
    await svc.addRefs(
      folderId: folder.id,
      refKind: UserFolderRefKind.album,
      refKeys: ['A'],
    );
    expect(
      await svc.moveRef(
        fromFolderId: folder.id,
        toFolderId: 'nope',
        refKind: UserFolderRefKind.album,
        refKey: 'A',
      ),
      isFalse,
    );
  });

  test('LibraryTagDimension v1 registers album, artist and genre', () {
    expect(LibraryTagDimension.v1TagDimensions.map((d) => d.id).toList(), [
      UserFolderRefKind.album,
      UserFolderRefKind.artist,
      UserFolderRefKind.genre,
    ]);
    final genre = LibraryTagDimension.byId('genre');
    expect(genre, isNotNull);
    final track = LibraryTrack(
      sourceName: 'src',
      remotePath: '/ Music/a.mp3',
      fileName: 'a.mp3',
      genre: 'Rock',
    );
    expect(genre!.groupKey(track), 'Rock');
    final untagged = LibraryTrack(
      sourceName: 'src',
      remotePath: '/Music/b.mp3',
      fileName: 'b.mp3',
    );
    expect(genre.groupKey(untagged), kUncategorizedGenre);
  });
}
