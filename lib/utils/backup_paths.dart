import '../models/webdav_account.dart';

/// Safe WebDAV directory segment for per-account backups.
/// Prefer short accountId prefix + sanitized display name so folders are
/// human-readable and stable across renames of the same id.
String backupAccountDirName(WebDavAccount account) {
  final idPart = account.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
  final shortId = idPart.length <= 8 ? idPart : idPart.substring(0, 8);
  final rawName =
      account.name.trim().isNotEmpty ? account.name.trim() : 'account';
  final buf = StringBuffer();
  for (final rune in rawName.runes) {
    final ch = String.fromCharCode(rune);
    final isAsciiWord = RegExp(r'[a-zA-Z0-9_-]').hasMatch(ch);
    final isCjk = rune >= 0x4e00 && rune <= 0x9fff;
    if (isAsciiWord || isCjk) {
      buf.write(ch);
    } else if (buf.isNotEmpty && !buf.toString().endsWith('_')) {
      buf.write('_');
    }
  }
  var namePart = buf.toString().replaceAll(RegExp(r'_+$'), '');
  if (namePart.isEmpty) namePart = 'account';
  if (namePart.length > 40) namePart = namePart.substring(0, 40);
  return '${shortId}_$namePart';
}

/// UTC stamp used in backup / export file names, e.g. `20260920T080000Z`.
String utcStamp({DateTime? now}) {
  final t = (now ?? DateTime.now()).toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
}

/// Timestamped cloud backup file name, e.g. `backup-20260920T080000Z.wdmm`.
String backupFileNameNow({DateTime? now}) => 'backup-${utcStamp(now: now)}.wdmm';

/// Join base backup root with per-account subdirectory.
String perAccountBackupDir(String backupRoot, WebDavAccount account) {
  var root = backupRoot.trim();
  if (root.isEmpty) root = '/WebdavMediaManager/backup/';
  if (!root.startsWith('/')) root = '/$root';
  if (!root.endsWith('/')) root = '$root/';
  return '$root${backupAccountDirName(account)}/';
}
