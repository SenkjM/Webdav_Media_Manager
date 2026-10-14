import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/utils/manga_pack_followup.dart';

void main() {
  // accountCanUpload 已重构为 cloudDrive.can(accountId, AccountCaps.write) 的薄封装。
  // 能力判定逻辑由 CloudDriveService.can 本身覆盖，不在此重复测试（2026-10-15）。

  group('pack follow-up markers', () {
    test('round-trips the upload target, including odd source names', () {
      const target = PackUploadTarget(
        uploadSourceName: 'disk a/b',
        originMangaId: 'loose-1',
      );
      final back = parsePackUploadMarker(packUploadMarker(target));
      expect(back?.uploadSourceName, 'disk a/b');
      expect(back?.originMangaId, 'loose-1');
    });

    test('origin and delete markers do not parse as each other', () {
      final origin = packOriginMarker('loose-1');
      final deleteMarker = packDeleteOriginMarker('loose-1');
      expect(parsePackOriginMarker(origin), 'loose-1');
      expect(parsePackDeleteOriginMarker(deleteMarker), 'loose-1');
      expect(parsePackOriginMarker(deleteMarker), isNull);
      expect(parsePackDeleteOriginMarker(origin), isNull);
      expect(parsePackUploadMarker(origin), isNull);
      expect(parsePackOriginMarker('manga:loose-1'), isNull);
    });
  });
}
