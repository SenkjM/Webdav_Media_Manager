import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/webdav_account.dart';
import 'package:webdav_media_manager/utils/backup_paths.dart';

void main() {
  group('backup_paths', () {
    test('per-account dir uses short id + sanitized name', () {
      const a = WebDavAccount(
        id: 'abcdefgh-ijkl-mnop',
        name: 'My Server / A',
        url: 'https://dav.example.com',
        username: 'u',
      );
      final dir = backupAccountDirName(a);
      expect(dir.startsWith('abcdefgh_'), isTrue);
      expect(dir.contains('/'), isFalse);
      expect(dir.contains(' '), isFalse);
    });

    test('perAccountBackupDir nests under root', () {
      const a = WebDavAccount(
        id: 'acc1',
        name: 'Home',
        url: 'https://x',
        username: 'u',
      );
      final path = perAccountBackupDir('/WebdavMediaManager/backup/', a);
      expect(path.startsWith('/WebdavMediaManager/backup/'), isTrue);
      expect(path.contains(backupAccountDirName(a)), isTrue);
      expect(path.endsWith('/'), isTrue);
    });

    test('backupFileNameNow is timestamped', () {
      final name = backupFileNameNow(now: DateTime.utc(2026, 9, 20, 8, 0, 0));
      expect(name, 'backup-20260920T080000Z.wdmm');
    });
  });
}
