import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/account_capabilities.dart';
import 'package:webdav_media_manager/utils/manga_pack_followup.dart';
import 'package:webdav_media_manager/utils/upload_backend.dart';

void main() {
  group('accountCanUpload', () {
    test('WebDAV with write can upload', () {
      expect(
        accountCanUpload(
          providerType: 'webdav',
          capabilities: AccountCaps.all,
        ),
        isTrue,
      );
    });

    test('WebDAV without write cannot upload', () {
      expect(
        accountCanUpload(
          providerType: 'webdav',
          capabilities: AccountCaps.list | AccountCaps.read,
        ),
        isFalse,
      );
    });

    test('a cloud drive cannot upload even if a write bit is set', () {
      expect(
        accountCanUpload(
          providerType: 'aliyundrive_open',
          capabilities: AccountCaps.all,
        ),
        isFalse,
      );
    });
  });

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
