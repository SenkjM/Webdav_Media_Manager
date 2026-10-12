import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/utils/manga_file_types.dart';

void main() {
  test('ZipDecoder lists image entries in natural order', () {
    final archive = Archive();
    void add(String name, String body) {
      final data = Uint8List.fromList(body.codeUnits);
      archive.addFile(ArchiveFile.bytes(name, data));
    }

    add('page10.jpg', 'x');
    add('page2.jpg', 'y');
    add('page1.jpg', 'z');
    add('readme.txt', 'nope');

    final encoded = ZipEncoder().encode(archive);
    expect(encoded, isNotNull);
    final decoded = ZipDecoder().decodeBytes(encoded!);
    final images = [
      for (final f in decoded)
        if (!f.isDirectory && isMangaImageFileName(f.name)) f.name,
    ]..sort((a, b) => mangaPageSortKey(a).compareTo(mangaPageSortKey(b)));
    expect(images, ['page1.jpg', 'page2.jpg', 'page10.jpg']);
  });
}
