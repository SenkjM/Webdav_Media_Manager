import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/file_type_config.dart';
import 'package:webdav_media_manager/models/webdav_item.dart';
import 'package:webdav_media_manager/utils/image_album.dart';

void main() {
  test('只留图片，按文件名大小写不敏感排序', () {
    final album = imageAlbumFrom(const [
      WebDavItem(
        name: 'b.jpg',
        path: '/a/b.jpg',
        isDirectory: false,
        category: FileCategory.image,
      ),
      WebDavItem(name: 'Dir', path: '/a/Dir/', isDirectory: true),
      WebDavItem(
        name: 'notes.txt',
        path: '/a/notes.txt',
        isDirectory: false,
        category: FileCategory.other,
      ),
      WebDavItem(
        name: 'A.PNG',
        path: '/a/A.PNG',
        isDirectory: false,
        category: FileCategory.image,
      ),
    ]);
    expect(album.map((e) => e.name), ['A.PNG', 'b.jpg']);
  });

  test('当前图片不在种子里时补上原条目，不伪造视频分类', () {
    const current = WebDavItem(
      name: 'Shot.JPEG',
      path: '/a/Shot.JPEG',
      isDirectory: false,
      category: FileCategory.image,
    );
    final album = imageAlbumFrom(const [
      WebDavItem(
        name: 'a.jpg',
        path: '/a/a.jpg',
        isDirectory: false,
        category: FileCategory.image,
      ),
    ], ensure: current);
    expect(album.map((e) => e.path), ['/a/a.jpg', '/a/Shot.JPEG']);
    expect(album.last.category, FileCategory.image);
    expect(album.every((e) => e.category != FileCategory.video), isTrue);
  });

  test('非图片不会被塞进相册', () {
    const video = WebDavItem(
      name: 'clip.mp4',
      path: '/a/clip.mp4',
      isDirectory: false,
      category: FileCategory.video,
    );
    final album = imageAlbumFrom(const <WebDavItem>[], ensure: video);
    expect(album, isEmpty);
  });
}
