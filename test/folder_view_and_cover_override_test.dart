import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/folder_view_mode.dart';
import 'package:webdav_media_manager/utils/library_group_cover.dart';

void main() {
  test('FolderViewMode storage round-trip covers list and 2–5 grid', () {
    for (final mode in FolderViewMode.values) {
      expect(
        FolderViewModeX.fromStorageKey(mode.storageKey),
        mode,
      );
    }
    expect(FolderViewModeX.fromStorageKey(null), FolderViewMode.list);
    expect(FolderViewModeX.fromStorageKey('nope'), FolderViewMode.list);
    expect(FolderViewMode.list.crossAxisCount, isNull);
    expect(FolderViewMode.grid5.crossAxisCount, 5);
    expect(FolderViewMode.grid2.isGrid, isTrue);
    expect(FolderViewMode.list.isGrid, isFalse);
  });

  test('LibraryGroupCoverOverrides.resolver is nullable extension point', () {
    expect(LibraryGroupCoverOverrides.resolver, isNull);
    LibraryGroupCoverOverrides.resolver = ({
      required dimensionId,
      required groupKey,
    }) =>
        dimensionId == 'genre' && groupKey == 'Rock' ? '/tmp/rock.jpg' : null;
    expect(
      LibraryGroupCoverOverrides.resolver!(
        dimensionId: 'genre',
        groupKey: 'Rock',
      ),
      '/tmp/rock.jpg',
    );
    expect(
      LibraryGroupCoverOverrides.resolver!(
        dimensionId: 'artist',
        groupKey: 'x',
      ),
      isNull,
    );
    LibraryGroupCoverOverrides.resolver = null;
  });
}
