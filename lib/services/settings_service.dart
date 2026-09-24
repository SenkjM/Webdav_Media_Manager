import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cache_policy.dart';
import '../models/file_actions.dart';
import '../models/file_type_config.dart';
import '../models/library_track.dart';
import '../models/music_stream.dart';
import '../models/snack_duration.dart';
import '../models/sync_interval.dart';
import '../models/video_settings.dart';
import '../utils/cover_image.dart';
import 'library_sync_store.dart';

/// App preferences (cache retention, library sort, backup/playlist paths).
/// WebDAV credentials live in AccountsService / flutter_secure_storage.
class SettingsService extends ChangeNotifier {
  SettingsService({
    SharedPreferences? prefs,
    FlutterSecureStorage? secureStorage,
  }) : _prefs = prefs,
       _secure = secureStorage ?? const FlutterSecureStorage();

  static const _kRetention = 'cache_retention';
  static const _kCustomRetentionHours = 'cache_custom_retention_hours';
  static const _kLibrarySort = 'library_sort_mode';
  static const _kPlaylistSyncEnabled = 'playlist_sync_enabled';
  static const _kCoverThumbSize = 'cover_thumb_size';
  static const _kFileTypeConfig = 'file_type_config_json';
  static const _kMusicTapAction = 'music_tap_action';
  static const _kVideoTapAction = 'video_tap_action';
  static const _kFileActionConfig = 'file_action_config_json';
  static const _kHomeTab = 'home_tab_index';
  static const _kNetworkRememberLastPath = 'network_remember_last_path';
  static const _kNetworkLastPath = 'network_last_path';
  static const _kVideoLeftDoubleTap = 'video_left_double_tap';
  static const _kVideoRightDoubleTap = 'video_right_double_tap';
  static const _kVideoLongPress = 'video_long_press';
  static const _kVideoBackgroundPlayback = 'video_background_playback';
  static const _kVideoPipEnabled = 'video_pip_enabled';
  static const _kVideoHardwareDecoding = 'video_hardware_decoding';
  static const _kVideoBufferSizeMb = 'video_buffer_size_mb';
  static const _kVideoLongPressRate = 'video_long_press_rate';
  static const _kVideoLastRate = 'video_last_rate';
  static const _kVideoConfirmExit = 'video_confirm_exit';

  /// 断点续传的半截文件（.part）保留上限：时长与总体积。
  static const _kDownloadPartMaxAgeHours = 'download_part_max_age_hours';
  static const _kDownloadPartMaxMb = 'download_part_max_mb';
  static const _kVideoSubtitlePosition = 'video_subtitle_position';
  static const _kVideoSubtitleOffset = 'video_subtitle_offset';
  static const _kVideoSubtitleFontSize = 'video_subtitle_font_size';
  static const _kShareTagRenameEnabled = 'share_tag_rename_enabled';
  static const _kShareTagRenamePattern = 'share_tag_rename_pattern';
  static const _kSyncRemoteRoot = 'sync_remote_root';
  static const _kSyncEncryptPassword = 'sync_encrypt_password';
  static const _kLibraryRebuildHint = 'library_rebuild_hint_fragments';
  static const _kSyncInterval = 'sync_interval';
  static const _kVaultPassphrase = 'vault_passphrase';
  static const _kDeviceId = 'sync_device_id';
  static const _kLastRev = 'sync_last_rev';
  static const _kSnackDuration = 'snack_duration';
  static const _kDownloadNotifications = 'download_notifications';
  static const _kMusicStreamPlayMode = 'music_stream_play_mode';
  static const _kAudioStreamingEnabled = 'audio_streaming_enabled';
  static const _kAudioScanSubdirs = 'audio_scan_subdirs';
  static const _kVideoScanSubdirs = 'video_scan_subdirs';

  /// **One** destination 网盘 for 凭证 / 歌单 / 音乐库 / 备份.
  static const _kSyncAccountId = 'sync_account_id';

  /// Keys older installs used to store one destination per feature. Read once,
  /// for migration only — nothing writes them any more.
  static const _kLegacySyncAccountKeys = [
    'sync_credentials_account_id',
    'sync_playlists_account_id',
    'sync_library_account_id',
    'sync_backup_account_id',
  ];

  /// Default custom retention: 30 days.
  static const int defaultCustomRetentionHours = 24 * 30;

  /// Clamp custom retention to [1 hour, 10 years].
  static const int minCustomRetentionHours = 1;
  static const int maxCustomRetentionHours = 24 * 365 * 10;

  /// Sub-directories (and the one file) the unified sync writes under
  /// [syncRemoteRoot]. They are derived, never configured separately.
  static const String credentialsFileName = 'credentials.json';
  static const String playlistsSubdir = 'playlists';
  static const String librarySubdir = 'library';
  static const String backupSubdir = 'backup';

  /// Video streaming buffer clamp [8 MB, 512 MB]; default 64 MB.
  static const int minVideoBufferMb = 8;
  static const int maxVideoBufferMb = 512;
  static const int defaultVideoBufferMb = 64;

  static const int defaultDownloadPartMaxAgeHours = 72;
  static const int defaultDownloadPartMaxMb = 2048;

  /// Video playback-rate slider range (0.5×–3.0×).
  static const double minVideoRate = 0.5;
  static const double maxVideoRate = 3.0;

  /// Slider granularity: (3.0 - 0.5) / 0.05 = 50 steps.
  static const int videoRateDivisions = 50;

  /// Long-press speed boost default (temporary 2× while the finger is down).
  static const double defaultVideoLongPressRate = 2.0;
  static const List<double> videoLongPressRatePresets = [
    1.25,
    1.5,
    2.0,
    2.5,
    3.0,
  ];

  /// Distance (dp) between subtitles and the video picture's lower edge when
  /// [VideoSubtitlePosition.insideVideo] is selected. Tune this if subtitles sit
  /// too close to (or too far from) the bottom of the frame.
  static const double defaultVideoSubtitleOffset = 24.0;
  static const double minVideoSubtitleOffset = 0.0;
  static const double maxVideoSubtitleOffset = 160.0;

  /// Subtitle font size (sp) / line height, adjustable because phones and TV-ish
  /// viewing distances differ a lot.
  static const double defaultVideoSubtitleFontSize = 16.0;
  static const double minVideoSubtitleFontSize = 10.0;
  static const double maxVideoSubtitleFontSize = 40.0;
  static const List<double> videoSubtitleFontSizePresets = [
    12,
    14,
    16,
    20,
    24,
    30,
  ];

  /// Tag-based share renaming: enabled by default with `作者-标题`.
  static const bool defaultShareTagRename = true;
  static const String defaultShareTagRenamePattern = '{artist}-{title}';

  /// Unified remote root on the WebDAV server: 凭证 / 歌单 / 音乐库 / 备份 all
  /// hang below this one directory.
  static const String defaultSyncRemoteRoot = '/WebdavMediaManager/';

  SharedPreferences? _prefs;
  final FlutterSecureStorage _secure;
  CacheRetention _retention = CacheRetention.oneWeek;
  int _customRetentionHours = defaultCustomRetentionHours;
  LibrarySortMode _librarySort = LibrarySortMode.byName;
  bool _playlistSyncEnabled = true;
  int _coverThumbSize = coverThumbSize;
  FileTypeConfig _fileTypes = FileTypeConfig();
  MusicTapAction _musicTapAction = MusicTapAction.download;
  VideoTapAction _videoTapAction = VideoTapAction.open;

  /// 统一文件动作模型（T1）：按后缀类别决定单击行为。
  ///
  /// 旧的 [musicTapAction] / [videoTapAction] 保留为**兼容读**：没有新配置
  /// 的旧安装会按它们迁移一次，之后两者不再参与判定。
  FileActionConfig _fileActions = FileActionConfig();
  int _homeTab = 0;
  bool _networkRememberLastPath = false;
  String _networkLastPath = '/';
  VideoGestureAction _videoLeftDoubleTap = VideoGestureAction.back10s;
  VideoGestureAction _videoRightDoubleTap = VideoGestureAction.forward10s;
  VideoGestureAction _videoLongPress = VideoGestureAction.toggleRate2x;
  bool _videoBackgroundPlayback = true;
  MusicStreamPlayMode _musicStreamPlayMode = MusicStreamPlayMode.sequential;
  bool _audioStreamingEnabled = false;
  bool _audioScanSubdirs = true;
  bool _videoScanSubdirs = true;
  bool _videoPipEnabled = false;
  bool _videoHardwareDecoding = true;
  int _videoBufferSizeMb = defaultVideoBufferMb;
  int _downloadPartMaxAgeHours = defaultDownloadPartMaxAgeHours;
  int _downloadPartMaxMb = defaultDownloadPartMaxMb;
  double _videoLongPressRate = defaultVideoLongPressRate;
  double _videoLastRate = 1.0;
  bool _videoConfirmExit = false;
  VideoSubtitlePosition _videoSubtitlePosition = VideoSubtitlePosition.visible;
  double _videoSubtitleOffset = defaultVideoSubtitleOffset;
  double _videoSubtitleFontSize = defaultVideoSubtitleFontSize;
  bool _shareTagRenameEnabled = defaultShareTagRename;
  String _shareTagRenamePattern = defaultShareTagRenamePattern;
  String _syncRemoteRoot = defaultSyncRemoteRoot;
  bool _syncEncryptPassword = true;

  /// Cloud-library fragment count at which the sync screen suggests a rebuild.
  int _libraryRebuildHintFragments = defaultLibraryRebuildHintFragments;

  /// How often the background scan runs; [SyncInterval.off] (the default)
  /// disables it entirely.
  SyncInterval _syncInterval = SyncIntervalX.fallback;

  /// User-chosen credential-vault key (see [vaultPassphrase]).
  String _vaultPassphrase = '';

  /// Stable id of this install; only used to break exact rev ties.
  String _deviceId = '';

  /// Highest rev handed out or observed on this install.
  int _lastRev = 0;

  /// How long in-app messages stay on screen.
  SnackDuration _snackMode = SnackDuration.normal;

  /// Whether the download queue posts system notifications.
  bool _downloadNotifications = true;

  /// The single 网盘 every sync feature (凭证 / 歌单 / 音乐库 / 备份) writes to;
  /// null means「跟随当前选中的网盘」.
  String? _syncAccountId;
  bool _loaded = false;

  CacheRetention get retention => _retention;
  Duration get customRetentionDuration =>
      Duration(hours: _customRetentionHours);
  int get customRetentionHours => _customRetentionHours;
  LibrarySortMode get librarySort => _librarySort;

  /// WebDAV root shared by 凭证 / 歌单 / 音乐库 / 备份 (设置 → 同步与备份 →
  /// 远端路径). Every other cloud path is derived from it.
  String get syncRemoteRoot => _syncRemoteRoot;

  /// `<远端路径>credentials.json` — the WebDAV credential vault.
  String get credentialsRemotePath =>
      '$_syncRemoteRootBase$credentialsFileName';

  /// `<远端路径>playlists/` — the M3U8 playlist mirror.
  String get playlistRemotePath => _syncSubdir(playlistsSubdir);

  /// `<远端路径>library/` — index.json plus the binary shards.
  String get libraryRemotePath => _syncSubdir(librarySubdir);

  /// `<远端路径>backup/` — 全部备份 archives.
  String get backupRemotePath => _syncSubdir(backupSubdir);

  /// Root guaranteed to end with `/`, so plain concatenation stays correct.
  String get _syncRemoteRootBase =>
      _syncRemoteRoot.endsWith('/') ? _syncRemoteRoot : '$_syncRemoteRoot/';

  String _syncSubdir(String name) => '$_syncRemoteRootBase$name/';

  bool get playlistSyncEnabled => _playlistSyncEnabled;

  /// Square edge (px) for newly compressed cover thumbs.
  int get coverThumbSizePx => _coverThumbSize;
  FileTypeConfig get fileTypes => _fileTypes;
  MusicTapAction get musicTapAction => _musicTapAction;
  VideoTapAction get videoTapAction => _videoTapAction;
  FileActionConfig get fileActions => _fileActions;
  int get homeTab => _homeTab;
  bool get networkRememberLastPath => _networkRememberLastPath;
  String get networkLastPath => _networkLastPath;
  VideoGestureAction get videoLeftDoubleTap => _videoLeftDoubleTap;
  VideoGestureAction get videoRightDoubleTap => _videoRightDoubleTap;
  VideoGestureAction get videoLongPress => _videoLongPress;
  bool get videoBackgroundPlayback => _videoBackgroundPlayback;
  bool get videoPipEnabled => _videoPipEnabled;
  bool get videoHardwareDecoding => _videoHardwareDecoding;
  int get videoBufferSizeMb => _videoBufferSizeMb;

  int get downloadPartMaxAgeHours => _downloadPartMaxAgeHours;
  int get downloadPartMaxMb => _downloadPartMaxMb;

  /// 流式音乐页的播放模式（单曲循环 / 顺序 / 列表循环）。
  MusicStreamPlayMode get musicStreamPlayMode => _musicStreamPlayMode;

  /// 音乐是否走流式传输。原来只有「文件后缀管理」页能改，现在归音频流式设置页。
  bool get audioStreamingEnabled => _audioStreamingEnabled;

  /// 流式扫描是否递归子目录。音频与视频各一份，默认都开（等于旧行为）。
  bool get audioScanSubdirs => _audioScanSubdirs;
  bool get videoScanSubdirs => _videoScanSubdirs;

  /// Temporary playback rate applied while the video screen is long-pressed.
  double get videoLongPressRate => _videoLongPressRate;

  /// Last rate the user picked in the video speed slider.
  double get videoLastRate => _videoLastRate;

  /// Whether leaving the video player asks「确认关闭视频吗？」first.
  bool get videoConfirmExit => _videoConfirmExit;

  /// Where subtitles are drawn (inside the picture / below it / hidden).
  VideoSubtitlePosition get videoSubtitlePosition => _videoSubtitlePosition;

  /// Offset (dp) from the picture's lower edge in
  /// [VideoSubtitlePosition.insideVideo] mode.
  double get videoSubtitleOffset => _videoSubtitleOffset;

  /// Subtitle font size (sp).
  double get videoSubtitleFontSize => _videoSubtitleFontSize;

  /// Whether sharing a cached audio file offers a tag-based default name.
  bool get shareTagRenameEnabled => _shareTagRenameEnabled;

  /// Rename pattern, e.g. `{artist}-{title}`; supports `{album}`, `{track}`.
  String get shareTagRenamePattern => _shareTagRenamePattern;

  /// Whether synced/exported WebDAV passwords are encrypted with a passphrase.
  bool get syncEncryptPassword => _syncEncryptPassword;

  /// Cloud-library fragment count (delta + tombstone parts) at which the sync
  /// screen suggests a rebuild. The hint is advisory — nothing is compacted
  /// automatically.
  static const int defaultLibraryRebuildHintFragments =
      LibrarySyncStore.suggestRebuildAtFragments;

  /// Choices offered in Settings.
  static const List<int> rebuildHintPresets = [10, 20, 30, 50];

  static int _clampRebuildHint(int value) => value.clamp(2, 500);

  int get libraryRebuildHintFragments => _libraryRebuildHintFragments;

  SyncInterval get syncInterval => _syncInterval;

  Future<void> setSyncInterval(SyncInterval value) async {
    if (value == _syncInterval) return;
    _syncInterval = value;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kSyncInterval, value.storageKey);
    notifyListeners();
  }

  Future<void> setLibraryRebuildHintFragments(int value) async {
    final next = _clampRebuildHint(value);
    if (next == _libraryRebuildHintFragments) return;
    _libraryRebuildHintFragments = next;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_kLibraryRebuildHint, next);
    notifyListeners();
  }

  /// How long in-app messages stay on screen.
  SnackDuration get snackMode => _snackMode;

  /// Whether the download queue posts system notifications.
  bool get downloadNotificationsEnabled => _downloadNotifications;

  /// 网盘 every sync feature writes to (null → the active account).
  String? get syncAccountId => _syncAccountId;

  bool get loaded => _loaded;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _retention = CacheRetentionX.fromStorageKey(_prefs!.getString(_kRetention));
    final storedHours = _prefs!.getInt(_kCustomRetentionHours);
    _customRetentionHours = _clampCustomHours(
      storedHours ?? defaultCustomRetentionHours,
    );
    _librarySort = LibrarySortModeX.fromStorageKey(
      _prefs!.getString(_kLibrarySort),
    );
    _playlistSyncEnabled = _prefs!.getBool(_kPlaylistSyncEnabled) ?? true;
    _coverThumbSize = clampCoverThumbSize(
      _prefs!.getInt(_kCoverThumbSize) ?? coverThumbSize,
    );
    _fileTypes = _readFileTypes();
    _musicTapAction = MusicTapActionX.fromStorageKey(
      _prefs!.getString(_kMusicTapAction),
    );
    _videoTapAction = VideoTapActionX.fromStorageKey(
      _prefs!.getString(_kVideoTapAction),
    );
    _fileActions = _readFileActions();
    _audioStreamingEnabled =
        _prefs!.getBool(_kAudioStreamingEnabled) ??
        _legacyMusicStreaming(_prefs!.getString(_kFileActionConfig));
    _homeTab = (_prefs!.getInt(_kHomeTab) ?? 0).clamp(0, 4);
    _networkRememberLastPath =
        _prefs!.getBool(_kNetworkRememberLastPath) ?? false;
    _networkLastPath = _prefs!.getString(_kNetworkLastPath) ?? '/';
    _videoLeftDoubleTap = VideoGestureActionX.fromStorageKey(
      _prefs!.getString(_kVideoLeftDoubleTap),
    );
    _videoRightDoubleTap = VideoGestureActionX.fromStorageKey(
      _prefs!.getString(_kVideoRightDoubleTap),
    );
    _videoLongPress = VideoGestureActionX.fromStorageKey(
      _prefs!.getString(_kVideoLongPress),
    );
    _videoBackgroundPlayback =
        _prefs!.getBool(_kVideoBackgroundPlayback) ?? true;
    _videoPipEnabled = _prefs!.getBool(_kVideoPipEnabled) ?? false;
    _musicStreamPlayMode = MusicStreamPlayModeX.fromStorageKey(
      _prefs!.getString(_kMusicStreamPlayMode),
    );
    _audioScanSubdirs = _prefs!.getBool(_kAudioScanSubdirs) ?? true;
    _videoScanSubdirs = _prefs!.getBool(_kVideoScanSubdirs) ?? true;
    _videoHardwareDecoding = _prefs!.getBool(_kVideoHardwareDecoding) ?? true;
    _videoBufferSizeMb = _clampBufferMb(
      _prefs!.getInt(_kVideoBufferSizeMb) ?? defaultVideoBufferMb,
    );
    _downloadPartMaxAgeHours =
        (_prefs!.getInt(_kDownloadPartMaxAgeHours) ??
                defaultDownloadPartMaxAgeHours)
            .clamp(1, 720);
    _downloadPartMaxMb =
        (_prefs!.getInt(_kDownloadPartMaxMb) ?? defaultDownloadPartMaxMb)
            .clamp(64, 1024 * 64);
    _videoLongPressRate = _clampRate(
      _prefs!.getDouble(_kVideoLongPressRate) ?? defaultVideoLongPressRate,
    );
    _videoLastRate = _clampRate(_prefs!.getDouble(_kVideoLastRate) ?? 1.0);
    _videoConfirmExit = _prefs!.getBool(_kVideoConfirmExit) ?? false;
    _videoSubtitlePosition = VideoSubtitlePositionX.fromStorageKey(
      _prefs!.getString(_kVideoSubtitlePosition),
    );
    _videoSubtitleOffset = _clampSubtitleOffset(
      _prefs!.getDouble(_kVideoSubtitleOffset) ?? defaultVideoSubtitleOffset,
    );
    _videoSubtitleFontSize = _clampSubtitleFontSize(
      _prefs!.getDouble(_kVideoSubtitleFontSize) ??
          defaultVideoSubtitleFontSize,
    );
    _shareTagRenameEnabled =
        _prefs!.getBool(_kShareTagRenameEnabled) ?? defaultShareTagRename;
    _shareTagRenamePattern =
        _prefs!.getString(_kShareTagRenamePattern) ??
        defaultShareTagRenamePattern;
    _syncRemoteRoot =
        _prefs!.getString(_kSyncRemoteRoot) ?? defaultSyncRemoteRoot;
    _syncEncryptPassword = _prefs!.getBool(_kSyncEncryptPassword) ?? true;
    _syncInterval = SyncIntervalX.fromStorageKey(
      _prefs!.getString(_kSyncInterval),
    );
    _libraryRebuildHintFragments = _clampRebuildHint(
      _prefs!.getInt(_kLibraryRebuildHint) ??
          defaultLibraryRebuildHintFragments,
    );
    // The vault key lives in secure storage (Keystore), like account passwords.
    try {
      _vaultPassphrase = await _secure.read(key: _kVaultPassphrase) ?? '';
    } catch (e) {
      debugPrint('SettingsService: vault passphrase read failed: $e');
      _vaultPassphrase = '';
    }
    _snackMode = SnackDurationX.fromStorageKey(
      _prefs!.getString(_kSnackDuration),
    );
    // Device id + rev high-water mark: the `rev` clock survives restarts, and an
    // exact tie between two devices is broken by the id.
    _deviceId = _prefs!.getString(_kDeviceId) ?? '';
    if (_deviceId.isEmpty) {
      _deviceId =
          'dev-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
      await _prefs!.setString(_kDeviceId, _deviceId);
    }
    _lastRev = _prefs!.getInt(_kLastRev) ?? 0;
    _downloadNotifications = _prefs!.getBool(_kDownloadNotifications) ?? true;
    _syncAccountId = _readSyncAccountId();
    _loaded = true;
    notifyListeners();
  }

  /// The single sync destination 网盘.
  ///
  /// Older installs stored one destination per feature; the first non-empty one
  /// is carried over so an existing choice is not silently dropped. Nothing
  /// writes the legacy keys any more.
  String? _readSyncAccountId() {
    final stored = _prefs!.getString(_kSyncAccountId);
    if (stored != null && stored.isNotEmpty) return stored;
    for (final key in _kLegacySyncAccountKeys) {
      final legacy = _prefs!.getString(key);
      if (legacy != null && legacy.isNotEmpty) return legacy;
    }
    return null;
  }

  FileTypeConfig _readFileTypes() {
    final raw = _prefs!.getString(_kFileTypeConfig);
    if (raw == null || raw.isEmpty) return FileTypeConfig();
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) return FileTypeConfig.fromJson(json);
    } catch (_) {}
    return FileTypeConfig();
  }

  Future<void> setRetention(CacheRetention retention) async {
    _retention = retention;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kRetention, retention.storageKey);
    notifyListeners();
  }

  /// Persist custom retention window (used when mode is [CacheRetention.custom]).
  Future<void> setCustomRetentionDuration(Duration duration) async {
    _customRetentionHours = _clampCustomHours(duration.inHours);
    // Ensure at least 1 hour even if caller passed sub-hour duration.
    if (duration > Duration.zero && _customRetentionHours < 1) {
      _customRetentionHours = 1;
    }
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_kCustomRetentionHours, _customRetentionHours);
    notifyListeners();
  }

  Future<void> setLibrarySort(LibrarySortMode mode) async {
    _librarySort = mode;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kLibrarySort, mode.storageKey);
    notifyListeners();
  }

  Future<void> setPlaylistSyncEnabled(bool enabled) async {
    _playlistSyncEnabled = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kPlaylistSyncEnabled, enabled);
    notifyListeners();
  }

  /// Persist square cover-thumb edge. Presets: 100 / 300; custom clamped to
  /// [minCoverThumbSize]–[maxCoverThumbSize]. Applies to NEW thumbs only;
  /// existing files keep old size until re-download/re-ingest (or destroy).
  Future<void> setCoverThumbSize(int size) async {
    _coverThumbSize = clampCoverThumbSize(size);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_kCoverThumbSize, _coverThumbSize);
    notifyListeners();
  }

  /// 读统一动作配置；没有就按旧的 music/video 单击行为迁移一次。
  ///
  /// 迁移只发生一次：写完新键之后旧键不再被读。旧语义 → 新动作：
  /// 音乐 `play`（已缓存则播放，否则下载）与 `download` 都是「缓存音乐」，
  /// 视频 `open` → 流式传输、`download` → 下载。
  FileActionConfig _readFileActions() {
    final raw = _prefs!.getString(_kFileActionConfig);
    // 流式开关原来只有 `experimental_music_streaming` 一处。新键存在就用新键，
    // 否则拿旧值当默认——用户点过一次的开关不该再点第二次。
    final streaming =
        _prefs!.getBool(_kAudioStreamingEnabled) ?? _legacyMusicStreaming(raw);
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw);
        if (json is Map<String, dynamic>) {
          final parsed = FileActionConfig.fromJson(
            json,
            allowMusicStreaming: streaming,
          );
          if (parsed != null) return parsed;
        }
      } catch (_) {
        // fall through to the legacy migration
      }
    }
    return FileActionConfig(
      allowMusicStreaming: streaming,
      actions: {
        // 旧音乐语义（download / play）都是「先缓存再播」，统一映射到缓存音乐。
        FileCategory.music: FileAction.cacheMusic,
        FileCategory.video: _videoTapAction == VideoTapAction.download
            ? FileAction.download
            : FileAction.stream,
        FileCategory.cue: FileAction.readCue,
        FileCategory.other: FileAction.download,
      },
    );
  }

  /// 旧安装的流式开关存在 `file_action_config_json` 的
  /// `experimental_music_streaming` 里，读一次做迁移。
  bool _legacyMusicStreaming(String? rawConfig) {
    if (rawConfig == null || rawConfig.isEmpty) return false;
    try {
      final json = jsonDecode(rawConfig);
      if (json is Map<String, dynamic>) {
        return json['experimental_music_streaming'] as bool? ?? false;
      }
    } catch (_) {
      // 坏配置按默认处理
    }
    return false;
  }

  Future<void> setFileActions(FileActionConfig config) async {
    _fileActions = config.copyWith();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kFileActionConfig, jsonEncode(config.toJson()));
    notifyListeners();
  }

  /// 改一个类别的单击行为。
  Future<void> setFileAction(FileCategory category, FileAction action) =>
      setFileActions(_fileActions.withAction(category, action));

  /// 音乐流式传输实验开关（T6）。
  Future<void> setExperimentalMusicStreaming(bool enabled) =>
      setAudioStreamingEnabled(enabled);

  Future<void> setFileTypes(FileTypeConfig config) async {
    _fileTypes = config;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kFileTypeConfig, jsonEncode(config.toJson()));
    notifyListeners();
  }

  Future<void> setMusicTapAction(MusicTapAction action) async {
    _musicTapAction = action;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kMusicTapAction, action.storageKey);
    notifyListeners();
  }

  Future<void> setVideoTapAction(VideoTapAction action) async {
    _videoTapAction = action;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kVideoTapAction, action.storageKey);
    notifyListeners();
  }

  Future<void> setHomeTab(int index) async {
    _homeTab = index.clamp(0, 4);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_kHomeTab, _homeTab);
    notifyListeners();
  }

  Future<void> setNetworkRememberLastPath(bool enabled) async {
    _networkRememberLastPath = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kNetworkRememberLastPath, enabled);
    notifyListeners();
  }

  Future<void> setNetworkLastPath(String path) async {
    var p = path.trim();
    if (p.isEmpty) p = '/';
    if (!p.startsWith('/')) p = '/$p';
    _networkLastPath = p;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kNetworkLastPath, p);
    // Avoid notifyListeners() spam on every folder navigation.
  }

  Future<void> setVideoLeftDoubleTap(VideoGestureAction action) async {
    _videoLeftDoubleTap = action;
    await _persistGesture(_kVideoLeftDoubleTap, action);
  }

  Future<void> setVideoRightDoubleTap(VideoGestureAction action) async {
    _videoRightDoubleTap = action;
    await _persistGesture(_kVideoRightDoubleTap, action);
  }

  Future<void> setVideoLongPress(VideoGestureAction action) async {
    _videoLongPress = action;
    await _persistGesture(_kVideoLongPress, action);
  }

  Future<void> _persistGesture(String key, VideoGestureAction action) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(key, action.storageKey);
    notifyListeners();
  }

  Future<void> setMusicStreamPlayMode(MusicStreamPlayMode mode) async {
    _musicStreamPlayMode = mode;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kMusicStreamPlayMode, mode.storageKey);
    notifyListeners();
  }

  /// 音乐流式传输开关。旧配置键 `experimental_music_streaming`（存在
  /// `file_action_config_json` 里）保留为**兼容读**，见 [_readFileActions]。
  Future<void> setAudioStreamingEnabled(bool enabled) async {
    _audioStreamingEnabled = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kAudioStreamingEnabled, enabled);
    // 关掉时重建一次动作配置：`copyWith()` 会走一遍解析，把已经选中的
    // 「流式传输（音乐）」退回默认。否则界面里会留着一个点了没反应的动作。
    if (!enabled) {
      _fileActions = _fileActions.copyWith();
      await _prefs!.setString(
        _kFileActionConfig,
        jsonEncode(_fileActions.toJson()),
      );
    }
    notifyListeners();
  }

  Future<void> setAudioScanSubdirs(bool enabled) async {
    _audioScanSubdirs = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kAudioScanSubdirs, enabled);
    notifyListeners();
  }

  Future<void> setVideoScanSubdirs(bool enabled) async {
    _videoScanSubdirs = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kVideoScanSubdirs, enabled);
    notifyListeners();
  }

  Future<void> setVideoBackgroundPlayback(bool enabled) async {
    _videoBackgroundPlayback = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kVideoBackgroundPlayback, enabled);
    notifyListeners();
  }

  Future<void> setVideoPipEnabled(bool enabled) async {
    _videoPipEnabled = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kVideoPipEnabled, enabled);
    notifyListeners();
  }

  Future<void> setVideoHardwareDecoding(bool enabled) async {
    _videoHardwareDecoding = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kVideoHardwareDecoding, enabled);
    notifyListeners();
  }

  Future<void> setVideoBufferSizeMb(int mb) async {
    _videoBufferSizeMb = _clampBufferMb(mb);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_kVideoBufferSizeMb, _videoBufferSizeMb);
    notifyListeners();
  }

  Future<void> setDownloadPartMaxAgeHours(int hours) async {
    _downloadPartMaxAgeHours = hours.clamp(1, 720);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_kDownloadPartMaxAgeHours, _downloadPartMaxAgeHours);
    notifyListeners();
  }

  Future<void> setDownloadPartMaxMb(int mb) async {
    _downloadPartMaxMb = mb.clamp(64, 1024 * 64);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_kDownloadPartMaxMb, _downloadPartMaxMb);
    notifyListeners();
  }

  static int _clampBufferMb(int mb) {
    if (mb < minVideoBufferMb) return minVideoBufferMb;
    if (mb > maxVideoBufferMb) return maxVideoBufferMb;
    return mb;
  }

  /// Persist the long-press speed boost rate (used while long-pressing video).
  Future<void> setVideoLongPressRate(double rate) async {
    _videoLongPressRate = _clampRate(rate);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble(_kVideoLongPressRate, _videoLongPressRate);
    notifyListeners();
  }

  /// Remember the user's last chosen video speed for the next session.
  Future<void> setVideoLastRate(double rate) async {
    _videoLastRate = _clampRate(rate);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble(_kVideoLastRate, _videoLastRate);
    // No notifyListeners: only the video screen reads this on open.
  }

  /// Ask before closing the video player (default off; the dialog only asks
  /// whether to confirm the close).
  Future<void> setVideoConfirmExit(bool enabled) async {
    _videoConfirmExit = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kVideoConfirmExit, enabled);
    notifyListeners();
  }

  /// Where subtitles are drawn (inside the picture / below it / hidden).
  Future<void> setVideoSubtitlePosition(VideoSubtitlePosition position) async {
    _videoSubtitlePosition = position;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kVideoSubtitlePosition, position.storageKey);
    notifyListeners();
  }

  /// Distance (dp) between subtitles and the picture's lower edge.
  Future<void> setVideoSubtitleOffset(double dp) async {
    _videoSubtitleOffset = _clampSubtitleOffset(dp);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble(_kVideoSubtitleOffset, _videoSubtitleOffset);
    notifyListeners();
  }

  static double _clampSubtitleOffset(double dp) {
    if (dp.isNaN) return defaultVideoSubtitleOffset;
    if (dp < minVideoSubtitleOffset) return minVideoSubtitleOffset;
    if (dp > maxVideoSubtitleOffset) return maxVideoSubtitleOffset;
    return dp;
  }

  /// Subtitle font size (sp).
  Future<void> setVideoSubtitleFontSize(double sp) async {
    _videoSubtitleFontSize = _clampSubtitleFontSize(sp);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble(_kVideoSubtitleFontSize, _videoSubtitleFontSize);
    notifyListeners();
  }

  static double _clampSubtitleFontSize(double sp) {
    if (sp.isNaN) return defaultVideoSubtitleFontSize;
    if (sp < minVideoSubtitleFontSize) return minVideoSubtitleFontSize;
    if (sp > maxVideoSubtitleFontSize) return maxVideoSubtitleFontSize;
    return sp;
  }

  /// Toggle download-queue system notifications.
  Future<void> setDownloadNotificationsEnabled(bool enabled) async {
    _downloadNotifications = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kDownloadNotifications, enabled);
    notifyListeners();
  }

  /// Persist the in-app message duration.
  Future<void> setSnackMode(SnackDuration mode) async {
    _snackMode = mode;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kSnackDuration, mode.storageKey);
    notifyListeners();
  }

  /// Point every sync feature at one 网盘; empty/null means「跟随当前选中」.
  Future<void> setSyncAccountId(String? accountId) async {
    _syncAccountId = (accountId == null || accountId.isEmpty)
        ? null
        : accountId;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kSyncAccountId, _syncAccountId ?? '');
    notifyListeners();
  }

  Future<void> setShareTagRenameEnabled(bool enabled) async {
    _shareTagRenameEnabled = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kShareTagRenameEnabled, enabled);
    notifyListeners();
  }

  Future<void> setShareTagRenamePattern(String pattern) async {
    final trimmed = pattern.trim();
    _shareTagRenamePattern = trimmed.isEmpty
        ? defaultShareTagRenamePattern
        : trimmed;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kShareTagRenamePattern, _shareTagRenamePattern);
    notifyListeners();
  }

  /// 远端总路径：凭证、歌单、音乐库与备份共同的云端根。
  Future<void> setSyncRemoteRoot(String path) async {
    var value = path.trim();
    if (value.isEmpty) value = defaultSyncRemoteRoot;
    if (!value.startsWith('/')) value = '/$value';
    if (!value.endsWith('/')) value = '$value/';
    _syncRemoteRoot = value;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kSyncRemoteRoot, _syncRemoteRoot);
    notifyListeners();
  }

  Future<void> setSyncEncryptPassword(bool enabled) async {
    _syncEncryptPassword = enabled;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kSyncEncryptPassword, enabled);
    notifyListeners();
  }

  /// The **user-chosen** key used to encrypt WebDAV passwords before they leave
  /// the device (credential vault on the cloud, backup archives, local exports).
  ///
  /// This must never be derived from anything else in the app: it used to be the
  /// destination account's own WebDAV password, which meant changing that
  /// password (or picking another destination disk) silently made every
  /// previously synced password undecryptable.
  ///
  /// Kept on this device only — deliberately **not** part of
  /// [exportForBackup], because exporting the key next to the ciphertext would
  /// defeat the point. A device that does not know it restores accounts with
  /// empty passwords.
  String get vaultPassphrase => _vaultPassphrase;

  /// Stable id of this install (tie-breaker for identical `rev` values).
  String get deviceId => _deviceId;

  /// Highest `rev` this install has handed out or observed.
  int get lastRev => _lastRev;

  Future<void> setLastRev(int value) async {
    if (value <= _lastRev) return;
    _lastRev = value;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_kLastRev, value);
  }

  /// Whether a unified decryption key is configured.
  bool get hasVaultPassphrase => _vaultPassphrase.isNotEmpty;

  Future<void> setVaultPassphrase(String value) async {
    if (_vaultPassphrase == value) return;
    _vaultPassphrase = value;
    try {
      if (value.isEmpty) {
        await _secure.delete(key: _kVaultPassphrase);
      } else {
        await _secure.write(key: _kVaultPassphrase, value: value);
      }
    } catch (e) {
      debugPrint('SettingsService: vault passphrase write failed: $e');
    }
    notifyListeners();
  }

  /// Clamp a playback rate into the supported 0.5×–3.0× window.
  static double clampVideoRate(double rate) => _clampRate(rate);

  static double _clampRate(double rate) {
    if (rate.isNaN) return 1.0;
    if (rate < minVideoRate) return minVideoRate;
    if (rate > maxVideoRate) return maxVideoRate;
    return rate;
  }

  Map<String, dynamic> exportForBackup() => {
    'cache_retention': _retention.storageKey,
    'cache_custom_retention_hours': _customRetentionHours,
    'library_sort_mode': _librarySort.storageKey,
    'playlist_sync_enabled': _playlistSyncEnabled,
    'cover_thumb_size': _coverThumbSize,
    'file_type_config': _fileTypes.toJson(),
    'file_action_config': _fileActions.toJson(),
    // 兼容字段：旧版本恢复到本机时仍能读懂，判定一律走 file_action_config。
    'music_tap_action': _musicTapAction.storageKey,
    'video_tap_action': _videoTapAction.storageKey,
    'home_tab_index': _homeTab,
    'network_remember_last_path': _networkRememberLastPath,
    'network_last_path': _networkLastPath,
    'video_left_double_tap': _videoLeftDoubleTap.storageKey,
    'video_right_double_tap': _videoRightDoubleTap.storageKey,
    'video_long_press': _videoLongPress.storageKey,
    'video_background_playback': _videoBackgroundPlayback,
    'music_stream_play_mode': _musicStreamPlayMode.storageKey,
    'audio_streaming_enabled': _audioStreamingEnabled,
    'audio_scan_subdirs': _audioScanSubdirs,
    'video_scan_subdirs': _videoScanSubdirs,
    'video_pip_enabled': _videoPipEnabled,
    'video_hardware_decoding': _videoHardwareDecoding,
    'video_buffer_size_mb': _videoBufferSizeMb,
    'video_long_press_rate': _videoLongPressRate,
    'video_last_rate': _videoLastRate,
    'video_confirm_exit': _videoConfirmExit,
    'video_subtitle_position': _videoSubtitlePosition.storageKey,
    'video_subtitle_offset': _videoSubtitleOffset,
    'video_subtitle_font_size': _videoSubtitleFontSize,
    'share_tag_rename_enabled': _shareTagRenameEnabled,
    'share_tag_rename_pattern': _shareTagRenamePattern,
    'library_rebuild_hint_fragments': _libraryRebuildHintFragments,
    'sync_interval': _syncInterval.storageKey,
    'sync_remote_root': _syncRemoteRoot,
    'sync_encrypt_password': _syncEncryptPassword,
    'snack_duration': _snackMode.storageKey,
    'download_notifications': _downloadNotifications,
  };

  Future<Map<String, dynamic>> exportForBackupAsync() async =>
      exportForBackup();

  Future<void> importFromBackup(Map<String, dynamic> json) async {
    _prefs ??= await SharedPreferences.getInstance();
    if (json['cache_retention'] != null) {
      await setRetention(
        CacheRetentionX.fromStorageKey(json['cache_retention'] as String?),
      );
    }
    if (json['cache_custom_retention_hours'] is int) {
      await setCustomRetentionDuration(
        Duration(hours: json['cache_custom_retention_hours'] as int),
      );
    }
    if (json['library_sort_mode'] != null) {
      await setLibrarySort(
        LibrarySortModeX.fromStorageKey(json['library_sort_mode'] as String?),
      );
    }
    if (json['playlist_sync_enabled'] is bool) {
      await setPlaylistSyncEnabled(json['playlist_sync_enabled'] as bool);
    }
    if (json['cover_thumb_size'] is int) {
      await setCoverThumbSize(json['cover_thumb_size'] as int);
    }
    if (json['file_type_config'] is Map) {
      await setFileTypes(
        FileTypeConfig.fromJson(
          Map<String, dynamic>.from(json['file_type_config'] as Map),
        ),
      );
    }
    if (json['file_action_config'] is Map) {
      final parsed = FileActionConfig.fromJson(
        Map<String, dynamic>.from(json['file_action_config'] as Map),
      );
      if (parsed != null) await setFileActions(parsed);
    } else if (json['music_tap_action'] != null ||
        json['video_tap_action'] != null) {
      await setFileActions(
        FileActionConfig(
          actions: {
            FileCategory.music: FileAction.cacheMusic,
            FileCategory.video:
                VideoTapActionX.fromStorageKey(
                      json['video_tap_action'] as String?,
                    ) ==
                    VideoTapAction.download
                ? FileAction.download
                : FileAction.stream,
            FileCategory.cue: FileAction.readCue,
            FileCategory.other: FileAction.download,
          },
        ),
      );
    }
    if (json['music_tap_action'] != null) {
      await setMusicTapAction(
        MusicTapActionX.fromStorageKey(json['music_tap_action'] as String?),
      );
    }
    if (json['video_tap_action'] != null) {
      await setVideoTapAction(
        VideoTapActionX.fromStorageKey(json['video_tap_action'] as String?),
      );
    }
    if (json['home_tab_index'] is int) {
      await setHomeTab(json['home_tab_index'] as int);
    }
    if (json['network_remember_last_path'] is bool) {
      await setNetworkRememberLastPath(
        json['network_remember_last_path'] as bool,
      );
    }
    if (json['network_last_path'] is String) {
      await setNetworkLastPath(json['network_last_path'] as String);
    }
    if (json['video_left_double_tap'] != null) {
      await setVideoLeftDoubleTap(
        VideoGestureActionX.fromStorageKey(
          json['video_left_double_tap'] as String?,
        ),
      );
    }
    if (json['video_right_double_tap'] != null) {
      await setVideoRightDoubleTap(
        VideoGestureActionX.fromStorageKey(
          json['video_right_double_tap'] as String?,
        ),
      );
    }
    if (json['video_long_press'] != null) {
      await setVideoLongPress(
        VideoGestureActionX.fromStorageKey(json['video_long_press'] as String?),
      );
    }
    if (json['music_stream_play_mode'] is String) {
      await setMusicStreamPlayMode(
        MusicStreamPlayModeX.fromStorageKey(
          json['music_stream_play_mode'] as String?,
        ),
      );
    }
    if (json['audio_streaming_enabled'] is bool) {
      await setAudioStreamingEnabled(json['audio_streaming_enabled'] as bool);
    }
    if (json['audio_scan_subdirs'] is bool) {
      await setAudioScanSubdirs(json['audio_scan_subdirs'] as bool);
    }
    if (json['video_scan_subdirs'] is bool) {
      await setVideoScanSubdirs(json['video_scan_subdirs'] as bool);
    }
    if (json['video_background_playback'] is bool) {
      await setVideoBackgroundPlayback(
        json['video_background_playback'] as bool,
      );
    }
    if (json['video_pip_enabled'] is bool) {
      await setVideoPipEnabled(json['video_pip_enabled'] as bool);
    }
    if (json['video_hardware_decoding'] is bool) {
      await setVideoHardwareDecoding(json['video_hardware_decoding'] as bool);
    }
    if (json['video_buffer_size_mb'] is int) {
      await setVideoBufferSizeMb(json['video_buffer_size_mb'] as int);
    }
    if (json['video_long_press_rate'] is num) {
      await setVideoLongPressRate(
        (json['video_long_press_rate'] as num).toDouble(),
      );
    }
    if (json['video_last_rate'] is num) {
      await setVideoLastRate((json['video_last_rate'] as num).toDouble());
    }
    if (json['video_confirm_exit'] is bool) {
      await setVideoConfirmExit(json['video_confirm_exit'] as bool);
    }
    if (json['video_subtitle_position'] != null) {
      await setVideoSubtitlePosition(
        VideoSubtitlePositionX.fromStorageKey(
          json['video_subtitle_position'] as String?,
        ),
      );
    }
    if (json['video_subtitle_offset'] is num) {
      await setVideoSubtitleOffset(
        (json['video_subtitle_offset'] as num).toDouble(),
      );
    }
    if (json['video_subtitle_font_size'] is num) {
      await setVideoSubtitleFontSize(
        (json['video_subtitle_font_size'] as num).toDouble(),
      );
    }
    if (json['share_tag_rename_enabled'] is bool) {
      await setShareTagRenameEnabled(json['share_tag_rename_enabled'] as bool);
    }
    if (json['share_tag_rename_pattern'] is String) {
      await setShareTagRenamePattern(
        json['share_tag_rename_pattern'] as String,
      );
    }
    if (json['sync_interval'] is String) {
      await setSyncInterval(
        SyncIntervalX.fromStorageKey(json['sync_interval'] as String),
      );
    }
    if (json['library_rebuild_hint_fragments'] is num) {
      await setLibraryRebuildHintFragments(
        (json['library_rebuild_hint_fragments'] as num).toInt(),
      );
    }
    if (json['sync_remote_root'] is String) {
      await setSyncRemoteRoot(json['sync_remote_root'] as String);
    }
    if (json['sync_encrypt_password'] is bool) {
      await setSyncEncryptPassword(json['sync_encrypt_password'] as bool);
    }
    if (json['download_notifications'] is bool) {
      await setDownloadNotificationsEnabled(
        json['download_notifications'] as bool,
      );
    }
    if (json['snack_duration'] != null) {
      await setSnackMode(
        SnackDurationX.fromStorageKey(json['snack_duration'] as String?),
      );
    }
  }

  static int _clampCustomHours(int hours) {
    if (hours < minCustomRetentionHours) return minCustomRetentionHours;
    if (hours > maxCustomRetentionHours) return maxCustomRetentionHours;
    return hours;
  }
}
