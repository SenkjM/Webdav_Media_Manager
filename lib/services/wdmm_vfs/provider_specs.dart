// Provider spec data classes — pure form metadata, no network code.
//
// Driver implementations live in Rust (wdmm-core). Verification goes through
// RustCoreService.accountVerify() (wdmm_account_verify FFI). These specs are
// used only for form rendering in the accounts screen.

import '../../models/account_capabilities.dart';
import '../../utils/l10n_host.dart';
import '../wdmm_vfs.dart';

// ── Inline constants (were in deleted driver files) ───────────────────────────

const _kAliyunDefaultRenewApi = 'https://api.oplist.org/alicloud/renewapi';
const _kAliyunDefaultDriveType = 'resource';
const _kAliyunDefaultRemoveWay = 'trash';
const _kAliyunDefaultRoot = 'root';

const _kBaiduDefaultRenewApi = 'https://api.oplist.org/baiduyun/renewapi';

const _k123DefaultRenewApi = 'https://api.oplist.org/123cloud/renewapi';
const _k123DefaultRoot = '0';

const _kNeteaseDefaultSongLimit = 200;

const _kCtFileDefaultListCacheSec = 60;
const _kCtFileDefaultRequestIntervalMs = 400;

// ── BaiduNetdiskSpec ──────────────────────────────────────────────────────────

class BaiduNetdiskSpec extends WdmmVfsSpec {
  const BaiduNetdiskSpec();

  @override
  String get typeId => 'baidu_netdisk';

  @override
  Set<String> get runtimeSecretKeys => const {'access_token'};

  @override
  String get displayName => L10nHost.current.driverNameBaidu;

  @override
  int get capabilities =>
      AccountCaps.list |
      AccountCaps.read |
      AccountCaps.mkdir |
      AccountCaps.move |
      AccountCaps.copy |
      AccountCaps.delete;

  @override
  List<WdmmVfsFormItem> get form => [
    WdmmVfsField(
      key: 'refresh_token',
      label: 'refresh_token',
      hint: L10nHost.current.formHintOpenListDoc('baidu_netdisk'),
      required: true,
      obscure: true,
    ),
    WdmmVfsField(
      key: 'api_url_address',
      label: L10nHost.current.formLabelRenewApi,
      hint: L10nHost.current.formHintRenewApiDefault,
      defaultValue: _kBaiduDefaultRenewApi,
      disabledWhenSwitch: 'local_refresh',
      disabledHint: L10nHost.current.formHintLocalRefreshDisabled,
    ),
    WdmmVfsSwitchField(
      key: 'local_refresh',
      label: L10nHost.current.formLabelLocalRefresh,
      subtitle: L10nHost.current.formSubLocalRefreshBaidu,
    ),
    WdmmVfsField(
      key: 'client_id',
      label: 'Client ID',
      visibleWhenSwitch: 'local_refresh',
    ),
    WdmmVfsField(
      key: 'client_secret',
      label: 'Client Secret',
      obscure: true,
      visibleWhenSwitch: 'local_refresh',
    ),
  ];
}

// ── Driver123OpenSpec ─────────────────────────────────────────────────────────

class Driver123OpenSpec extends WdmmVfsSpec {
  const Driver123OpenSpec();

  @override
  String get typeId => '123_open';

  @override
  Set<String> get runtimeSecretKeys => const {'access_token'};

  @override
  String get displayName => L10nHost.current.driverName123Open;

  @override
  int get capabilities =>
      AccountCaps.list |
      AccountCaps.read |
      AccountCaps.mkdir |
      AccountCaps.move |
      AccountCaps.delete;

  @override
  List<WdmmVfsFormItem> get form => [
    WdmmVfsField(
      key: 'refresh_token',
      label: 'refresh_token',
      hint: L10nHost.current.formHintOpenListDoc('123_open'),
      required: true,
      obscure: true,
    ),
    WdmmVfsField(
      key: 'api_url_address',
      label: L10nHost.current.formLabelRenewApi,
      hint: L10nHost.current.formHintRenewApiDefault,
      defaultValue: _k123DefaultRenewApi,
      disabledWhenSwitch: 'local_refresh',
      disabledHint: L10nHost.current.formHintLocalRefreshDisabled,
    ),
    WdmmVfsSwitchField(
      key: 'local_refresh',
      label: L10nHost.current.formLabelLocalRefresh,
      subtitle: L10nHost.current.formSubLocalRefresh123,
    ),
    WdmmVfsField(
      key: 'client_id',
      label: 'Client ID',
      visibleWhenSwitch: 'local_refresh',
    ),
    WdmmVfsField(
      key: 'client_secret',
      label: 'Client Secret',
      obscure: true,
      visibleWhenSwitch: 'local_refresh',
    ),
    WdmmVfsField(
      key: 'root_folder_id',
      label: L10nHost.current.formLabelRootId,
      hint: L10nHost.current.formHintRootIdOpaque('0'),
      defaultValue: _k123DefaultRoot,
    ),
  ];
}

// ── Open115Spec ───────────────────────────────────────────────────────────────

class Open115Spec extends WdmmVfsSpec {
  const Open115Spec();

  @override
  String get typeId => '115open';

  @override
  String get displayName => L10nHost.current.driverName115;

  @override
  int get capabilities =>
      AccountCaps.list |
      AccountCaps.read |
      AccountCaps.mkdir |
      AccountCaps.move |
      AccountCaps.copy |
      AccountCaps.delete;

  @override
  Set<String> get runtimeSecretKeys => const {'access_token'};

  @override
  List<WdmmVfsFormItem> get form => [
    WdmmVfsField(
      key: 'refresh_token',
      label: 'refresh_token',
      hint: L10nHost.current.formHint115RefreshToken,
      required: true,
      obscure: true,
    ),
    WdmmVfsField(
      key: 'root_id',
      label: L10nHost.current.formLabelRootId,
      hint: L10nHost.current.formHint115RootId,
      defaultValue: '0',
    ),
    WdmmVfsField(
      key: 'page_size',
      label: L10nHost.current.formLabelPageSize,
      hint: L10nHost.current.formHintPageSize,
      defaultValue: '200',
    ),
    WdmmVfsField(
      key: 'limit_rate',
      label: L10nHost.current.formLabelRateLimit,
      hint: L10nHost.current.formHintRateLimit,
      defaultValue: '0',
    ),
  ];
}

// ── AliyundriveOpenSpec ───────────────────────────────────────────────────────

class AliyundriveOpenSpec extends WdmmVfsSpec {
  const AliyundriveOpenSpec();

  @override
  String get typeId => 'aliyundrive_open';

  @override
  String get displayName => L10nHost.current.driverNameAliyunOpen;

  @override
  int get capabilities =>
      AccountCaps.list |
      AccountCaps.read |
      AccountCaps.mkdir |
      AccountCaps.move |
      AccountCaps.copy |
      AccountCaps.delete;

  @override
  Set<String> get runtimeSecretKeys => const {'access_token'};

  @override
  List<WdmmVfsFormItem> get form => [
    WdmmVfsField(
      key: 'refresh_token',
      label: 'refresh_token',
      hint: L10nHost.current.formHintOpenListDoc('aliyundrive_open'),
      required: true,
      obscure: true,
    ),
    WdmmVfsSelectField(
      key: 'drive_type',
      label: L10nHost.current.formLabelDriveType,
      hint: L10nHost.current.formHintDriveType,
      options: [
        ('resource', L10nHost.current.optionDriveResource),
        ('default', L10nHost.current.optionDriveDefault),
        ('backup', L10nHost.current.optionDriveBackup),
      ],
      defaultValue: _kAliyunDefaultDriveType,
      required: true,
    ),
    WdmmVfsField(
      key: 'api_url_address',
      label: L10nHost.current.formLabelRenewApi,
      hint: L10nHost.current.formHintRenewApiDefault,
      defaultValue: _kAliyunDefaultRenewApi,
      disabledWhenSwitch: 'local_refresh',
      disabledHint: L10nHost.current.formHintLocalRefreshDisabled,
    ),
    WdmmVfsSwitchField(
      key: 'local_refresh',
      label: L10nHost.current.formLabelLocalRefresh,
      subtitle: L10nHost.current.formSubLocalRefreshAliyun,
    ),
    WdmmVfsField(
      key: 'client_id',
      label: 'Client ID',
      visibleWhenSwitch: 'local_refresh',
    ),
    WdmmVfsField(
      key: 'client_secret',
      label: 'Client Secret',
      obscure: true,
      visibleWhenSwitch: 'local_refresh',
    ),
    WdmmVfsSelectField(
      key: 'remove_way',
      label: L10nHost.current.formLabelDeleteMode,
      hint: L10nHost.current.formHintDeleteMode,
      options: [
        ('trash', L10nHost.current.optionDeleteTrash),
        ('delete', L10nHost.current.optionDeletePermanent),
      ],
      defaultValue: _kAliyunDefaultRemoveWay,
    ),
    WdmmVfsField(
      key: 'root_folder_id',
      label: L10nHost.current.formLabelRootId,
      hint: L10nHost.current.formHintRootIdOpaque('root'),
      defaultValue: _kAliyunDefaultRoot,
    ),
  ];
}

// ── TeraboxSpec ───────────────────────────────────────────────────────────────

class TeraboxSpec extends WdmmVfsSpec {
  const TeraboxSpec();

  @override
  String get typeId => 'terabox';

  @override
  String get displayName => 'TeraBox';

  @override
  int get capabilities =>
      AccountCaps.list |
      AccountCaps.read |
      AccountCaps.mkdir |
      AccountCaps.move |
      AccountCaps.copy |
      AccountCaps.delete;

  @override
  List<WdmmVfsFormItem> get form => [
    WdmmVfsField(
      key: 'cookie',
      label: 'Cookie',
      hint: L10nHost.current.formHintTeraboxCookie,
      required: true,
      obscure: true,
    ),
    WdmmVfsField(
      key: 'root_folder_path',
      label: L10nHost.current.formLabelRootPath,
      defaultValue: '/',
    ),
  ];
}

// ── NeteaseMusicSpec ──────────────────────────────────────────────────────────

class NeteaseMusicSpec extends WdmmVfsSpec {
  const NeteaseMusicSpec();

  @override
  String get typeId => 'netease_music';

  @override
  String get displayName => L10nHost.current.driverNameNetease;

  @override
  int get capabilities =>
      AccountCaps.list | AccountCaps.read | AccountCaps.delete;

  @override
  List<WdmmVfsFormItem> get form => [
    WdmmVfsField(
      key: 'cookie',
      label: 'Cookie',
      hint: L10nHost.current.formHintNeteaseCookie,
      required: true,
      obscure: true,
    ),
    WdmmVfsField(
      key: 'song_limit',
      label: L10nHost.current.formLabelSongLimit,
      hint: L10nHost.current.formHintSongLimit('$_kNeteaseDefaultSongLimit'),
      defaultValue: '$_kNeteaseDefaultSongLimit',
    ),
  ];
}

// ── CtFileSpec ────────────────────────────────────────────────────────────────

class CtFileSpec extends WdmmVfsSpec {
  const CtFileSpec();

  @override
  String get typeId => 'ctfile';

  @override
  String get displayName => L10nHost.current.driverNameCtFile;

  @override
  int get capabilities =>
      AccountCaps.list |
      AccountCaps.read |
      AccountCaps.write |
      AccountCaps.mkdir |
      AccountCaps.move |
      AccountCaps.copy |
      AccountCaps.delete;

  @override
  Set<String> get runtimeSecretKeys => const {};

  @override
  List<WdmmVfsFormItem> get form => [
    WdmmVfsField(
      key: 'session',
      label: 'Session',
      hint: L10nHost.current.formHintCtFileSession,
      required: true,
      obscure: true,
    ),
    WdmmVfsSelectField(
      key: 'cloud_type',
      label: L10nHost.current.formLabelCloudType,
      defaultValue: 'public',
      options: [
        ('public', L10nHost.current.formOptionCtFilePublic),
        ('private', L10nHost.current.formOptionCtFilePrivate),
      ],
    ),
    WdmmVfsField(
      key: 'list_cache_sec',
      label: L10nHost.current.formLabelCtFileListCacheSec,
      hint: L10nHost.current.formHintCtFileListCacheSec,
      defaultValue: '$_kCtFileDefaultListCacheSec',
    ),
    WdmmVfsField(
      key: 'request_interval_ms',
      label: L10nHost.current.formLabelCtFileRequestIntervalMs,
      hint: L10nHost.current.formHintCtFileRequestIntervalMs,
      defaultValue: '$_kCtFileDefaultRequestIntervalMs',
    ),
  ];
}

// ── CryptSpec ─────────────────────────────────────────────────────────────────

class CryptSpec extends WdmmVfsSpec {
  const CryptSpec();

  @override
  String get typeId => 'crypt';

  @override
  String get displayName => L10nHost.current.driverNameCrypt;

  @override
  bool get isWrapper => true;

  @override
  int get capabilities =>
      AccountCaps.list |
      AccountCaps.read |
      AccountCaps.mkdir |
      AccountCaps.move |
      AccountCaps.copy |
      AccountCaps.delete;

  @override
  List<WdmmVfsFormItem> get form => [
    WdmmVfsAccountField(
      key: 'source_account_id',
      label: L10nHost.current.formLabelSourceAccount,
      required: true,
      hint: L10nHost.current.formHintSourceAccount,
    ),
    WdmmVfsField(
      key: 'source_dir',
      label: L10nHost.current.formLabelSourceDir,
      hint: L10nHost.current.formHintSourceDir,
    ),
    WdmmVfsSelectField(
      key: 'filename_encoding',
      label: L10nHost.current.formLabelFilenameEncoding,
      required: true,
      defaultValue: 'base64',
      options: [
        ('base64', 'Base64'),
        ('base32', 'Base32'),
        ('base32768', 'Base32768'),
      ],
      hint: L10nHost.current.formHintFilenameEncoding,
    ),
    WdmmVfsField(
      key: 'encrypted_suffix',
      label: L10nHost.current.formLabelEncryptedSuffix,
      defaultValue: '.bin',
      hint: L10nHost.current.formHintEncryptedSuffix,
    ),
    WdmmVfsField(
      key: 'password',
      label: L10nHost.current.formLabelPassword,
      required: true,
      obscure: true,
    ),
    WdmmVfsField(
      key: 'salt',
      label: L10nHost.current.formLabelSalt,
      obscure: true,
      hint: L10nHost.current.formHintSalt,
    ),
    WdmmVfsSelectField(
      key: 'filename_encryption',
      label: L10nHost.current.formLabelFilenameEncryption,
      required: true,
      defaultValue: 'off',
      options: [
        ('standard', L10nHost.current.optionCryptStandard),
        ('obfuscate', L10nHost.current.optionCryptObfuscate),
        ('off', L10nHost.current.optionCryptOff),
      ],
    ),
    WdmmVfsSwitchField(
      key: 'directory_name_encryption',
      label: L10nHost.current.formLabelDirNameEncryption,
      subtitle: L10nHost.current.formSubDirNameEncryption,
      defaultValue: false,
    ),
  ];
}
