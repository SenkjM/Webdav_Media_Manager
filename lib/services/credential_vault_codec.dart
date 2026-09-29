import 'dart:convert';
import 'dart:typed_data';

import '../utils/wmp_container.dart';

/// Codec for the credential vault document (`WDMMCV01`).
///
/// Layout (docs/10 §4.2.1):
/// * `META` — [WmpVaultMeta.formatVersion] (data-model version, not the file
///   layout), [WmpMeta.count], [WmpMeta.deviceId], [WmpMeta.createdAt].
/// * `CREDENTIALS` — one tag/value record per account.
///
/// **Encryption stays field-level and unchanged.** The URL and username are
/// plaintext by design; a password is either plaintext or an `AESGCMv1:` blob,
/// and a cloud driver's secret fields are already encrypted individually before
/// they reach this codec. The container itself is not an encryption layer — it
/// is only a denser encoding of the same values the old JSON file carried, so
/// recovery semantics (empty secret when no key is available) are untouched.
class CredentialVaultCodec {
  CredentialVaultCodec._();

  /// Magic code of a vault document (`WDMMCV01`).
  static const String magicKind = WmpFileKind.vault;

  /// One account entry in the container.
  ///
  /// Deliberately a plain data holder: identity, crypto and providers are the
  /// service's business, not the codec's.
  static Map<int, Object?> entryToRecord(VaultRecord entry) => {
    WmpVaultAccount.id: entry.id,
    WmpVaultAccount.name: entry.name,
    WmpVaultAccount.providerType: entry.providerType,
    WmpVaultAccount.url: entry.url,
    WmpVaultAccount.username: entry.username,
    WmpVaultAccount.password: entry.password,
    WmpVaultAccount.passwordEncrypted: entry.passwordEncrypted ? 1 : 0,
    WmpVaultAccount.remotePath: entry.remotePath,
    WmpVaultAccount.driverConfig: entry.driverConfig == null
        ? null
        : jsonEncode(entry.driverConfig),
  };

  static VaultRecord recordToEntry(Map<int, Object?> record) {
    final configRaw = record[WmpVaultAccount.driverConfig];
    Map<String, dynamic>? driverConfig;
    if (configRaw is String && configRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(configRaw);
        if (decoded is Map) {
          driverConfig = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // A driver config we cannot parse is dropped rather than fatal: the
        // account itself (name / address) is still restorable, and losing one
        // config must never block the whole vault.
        driverConfig = null;
      }
    }
    return VaultRecord(
      id: (record[WmpVaultAccount.id] as String?) ?? '',
      name: (record[WmpVaultAccount.name] as String?) ?? '',
      providerType: (record[WmpVaultAccount.providerType] as String?) ?? 'webdav',
      url: (record[WmpVaultAccount.url] as String?) ?? '',
      username: (record[WmpVaultAccount.username] as String?) ?? '',
      password: (record[WmpVaultAccount.password] as String?) ?? '',
      passwordEncrypted:
          ((record[WmpVaultAccount.passwordEncrypted] as int?) ?? 0) != 0,
      remotePath: (record[WmpVaultAccount.remotePath] as String?) ?? '/',
      driverConfig: driverConfig,
    );
  }

  /// Encode the vault into a self-contained `WDMMCV01` document.
  static Uint8List encode(
    List<VaultRecord> entries, {
    required int formatVersion,
    String deviceId = '',
  }) {
    final meta = encodeRecords([
      {
        WmpMeta.kind: WmpKind.vault,
        WmpMeta.count: entries.length,
        WmpMeta.deviceId: deviceId,
        WmpMeta.createdAt: DateTime.now().toUtc().toIso8601String(),
        WmpVaultMeta.formatVersion: formatVersion,
      },
    ]);
    final records = [for (final e in entries) entryToRecord(e)];
    return WmpContainer.encode(
      {
        WmpSections.meta: meta,
        WmpSections.credentials: encodeRecords(records),
      },
      kind: magicKind,
    );
  }

  /// Decode a `WDMMCV01` document.
  ///
  /// Throws [WmpFormatException] when the magic and `META.kind` disagree — that
  /// is the guard against feeding, say, a library shard into the vault restore
  /// path.
  static DecodedVault decode(Uint8List bytes) {
    final container = WmpContainer.fromBytes(bytes);
    final metaRaw = container.readSection(WmpSections.meta);
    final meta = metaRaw == null
        ? const <int, Object?>{}
        : (decodeRecords(metaRaw, intTags: kVaultMetaIntTags).firstOrNull ??
              const <int, Object?>{});

    final kind = (meta[WmpMeta.kind] as int?) ?? WmpKind.vault;
    if (WmpFileKind.metaKindOf(container.kind) != kind) {
      throw WmpFormatException('err.vaultKindMismatch|${container.kind}|$kind');
    }

    final raw = container.readSection(WmpSections.credentials);
    final records = raw == null
        ? const <Map<int, Object?>>[]
        : decodeRecords(raw, intTags: kVaultAccountIntTags);

    return DecodedVault(
      formatVersion:
          (meta[WmpVaultMeta.formatVersion] as int?) ?? 1,
      deviceId: (meta[WmpMeta.deviceId] as String?) ?? '',
      createdAt: (meta[WmpMeta.createdAt] as String?) ?? '',
      entries: [for (final r in records) recordToEntry(r)],
    );
  }
}

/// One vault account as stored in the container.
class VaultRecord {
  const VaultRecord({
    required this.id,
    required this.name,
    required this.providerType,
    required this.url,
    required this.username,
    required this.password,
    required this.passwordEncrypted,
    required this.remotePath,
    this.driverConfig,
  });

  final String id;
  final String name;
  final String providerType;

  /// Plaintext by design.
  final String url;

  /// Plaintext by design.
  final String username;

  /// Plaintext, or an `AESGCMv1:` blob when [passwordEncrypted].
  final String password;
  final bool passwordEncrypted;
  final String remotePath;

  /// Cloud drivers only; secret fields already encrypted individually.
  final Map<String, dynamic>? driverConfig;

  bool get isCloud => providerType != 'webdav';
}

/// A decoded `WDMMCV01` document.
class DecodedVault {
  const DecodedVault({
    required this.formatVersion,
    required this.deviceId,
    required this.createdAt,
    required this.entries,
  });

  /// Data-model version of the payload (see
  /// `CredentialVaultService.formatVersion`); not the container layout.
  final int formatVersion;
  final String deviceId;
  final String createdAt;
  final List<VaultRecord> entries;

  int get entryCount => entries.length;
}
