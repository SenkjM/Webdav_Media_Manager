import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cache_policy.dart';
import '../models/file_type_config.dart';
import '../models/library_track.dart';
import '../models/snack_duration.dart';
import '../models/video_settings.dart';
import '../utils/cover_image.dart';

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
  static const _kBackupRemotePath = 'backup_remote_path';
  static const _kLibrarySyncRemotePath = 'library_sync_remote_path';
  static const _kPlaylistRemotePath = 'playlist_remote_path';
  static const _kPlaylistSyncEnabled = 'playlist_sync_enabled';
  static const _kCoverThumbSize = 'cover_thumb_size';
  static const _kFileTypeConfig = 'file_type_config_json';
  static const _kMusicTapAction = 'music_tap_action';
  static const _kVideoTapAction = 'video_tap_action';
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
  static const _kVideoSubtitlePosition = 'video_subtitle_position';
  static const _kVideoSubtitleOffset = 'video_subtitle_offset';
  static const _kVideoSubtitleFontSize = 'video_subtitle_font_size';
  static const _kShareTagRenameEnabled = 'share_tag_rename_enabled';
  static const _kShareTagRenamePattern = 'share_tag_rename_pattern';
  static const _kSyncRemoteRoot = 'sync_remote_root';
  static const _kSyncEncryptPassword = 'sync_encrypt_password';
  static const _kVaultPassphrase = 'vault_passphrase';
  static const _kDeviceId = 'sync_device_id';
  static const _kLastRev = 'sync_last_rev';
  static const _kSnackDuration = 'snack_duration';
  static const _kDownloadNotifications = 'download_notifications';
  static const _kCredentialsAccountId = 'sync_credentials_account_id';
  static const _kPlaylistsAccountId = 'sync_playlists_account_id';
  static const _kLibraryAccountId = 'sync_library_account_id';
  static const _kBackupAccountId = 'sync_backup_account_id';

  /// Default custom retention: 30 days.
  static const int defaultCustomRetentionHours = 24 * 30;

  /// Clamp custom retention to [1 hour, 10 years].
  static const int minCustomRetentionHours = 1;
  static const int maxCustomRetentionHours = 24 * 365 * 10;

  static const String defaultBackupRemotePath = '/WebDAVMusicPlayer/backup/';
  static const String defaultLibrarySyncRemotePath =
      '/WebDAVMusicPlayer/library/';
  static const String defaultPlaylistRemotePath = '/Playlists/';

  /// Video streaming buffer clamp [8 MB, 512 MB]; default 64 MB.
  static const int minVideoBufferMb = 8;
  static const int maxVideoBufferMb = 512;
  static const int defaultVideoBufferMb = 64;

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

  /// Unified sync root on the WebDAV server (holds credentials + backup).
  static const String defaultSyncRemoteRoot = '/WebDAVMusicPlayer/';

  SharedPreferences? _prefs;
  final FlutterSecureStorage _secure;
  CacheRetention _retention = CacheRetention.oneWeek;
  int _customRetentionHours = defaultCustomRetentionHours;
  LibrarySortMode _librarySort = LibrarySortMode.byName;
  String _backupRemotePath = defaultBackupRemotePath;
  String _librarySyncRemotePath = defaultLibrarySyncRemotePath;
  String _playlistRemotePath = defaultPlaylistRemotePath;
  bool _playlistSyncEnabled = true;
  int _coverThumbSize = coverThumbSize;
  FileTypeConfig _fileTypes = FileTypeConfig();
  MusicTapAction _musicTapAction = MusicTapAction.download;
  VideoTapAction _videoTapAction = VideoTapAction.open;
  int _homeTab = 0;
  bool _networkRememberLastPath = false;
  String _networkLastPath = '/';
  VideoGestureAction _videoLeftDoubleTap = VideoGestureAction.back10s;
  VideoGestureAction _videoRightDoubleTap = VideoGestureAction.forward10s;
  VideoGestureAction _videoLongPress = VideoGestureAction.toggleRate2x;
  bool _videoBackgroundPlayback = true;
  bool _videoPipEnabled = false;
  bool _videoHardwareDecoding = true;
  int _videoBufferSizeMb = defaultVideoBufferMb;
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

  // Per-feature sync destinations. Each feature writes to its **own** account, so
  // credentials / playlists / library can each live on a different server instead
  // of everything going to whichever account happens to be selected.
  String? _credentialsAccountId;
  String? _playlistsAccountId;
  String? _libraryAccountId;
  String? _backupAccountId;
  bool _loaded = false;

  CacheRetention get retention => _retention;
  Duration get customRetentionDuration =>
      Duration(hours: _customRetentionHours);
  int get customRetentionHours => _customRetentionHours;
  LibrarySortMode get librarySort => _librarySort;
  String get backupRemotePath => _backupRemotePath;
  String get librarySyncRemotePath => _librarySyncRemotePath;
  String get playlistRemotePath => _playlistRemotePath;
  bool get playlistSyncEnabled => _playlistSyncEnabled;

  /// Square edge (px) for newly compressed cover thumbs.
  int get coverThumbSizePx => _coverThumbSize;
  FileTypeConfig get fileTypes => _fileTypes;
  MusicTapAction get musicTapAction => _musicTapAction;
  VideoTapAction get videoTapAction => _videoTapAction;
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

  /// WebDAV root used by the unified 同步 feature.
  String get syncRemoteRoot => _syncRemoteRoot;

  /// Whether synced/exported WebDAV passwords are encrypted with a passphrase.
  bool get syncEncryptPassword => _syncEncryptPassword;

  /// How long in-app messages stay on screen.
  SnackDuration get snackMode => _snackMode;

  /// Whether the download queue posts system notifications.
  bool get downloadNotificationsEnabled => _downloadNotifications;

  /// Destination accounts per sync feature (null → fall back to the active one).
  String? get credentialsAccountId => _credentialsAccountId;
  String? get playlistsAccountId => _playlistsAccountId;
  String? get libraryAccountId => _libraryAccountId;
  String? get backupAccountId => _backupAccountId;

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
    _backupRemotePath =
        _prefs!.getString(_kBackupRemotePath) ?? defaultBackupRemotePath;
    _librarySyncRemotePath =
        _prefs!.getString(_kLibrarySyncRemotePath) ??
        defaultLibrarySyncRemotePath;
    _playlistRemotePath =
        _prefs!.getString(_kPlaylistRemotePath) ?? defaultPlaylistRemotePath;
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
    _videoHardwareDecoding = _prefs!.getBool(_kVideoHardwareDecoding) ?? true;
    _videoBufferSizeMb = _clampBufferMb(
      _prefs!.getInt(_kVideoBufferSizeMb) ?? defaultVideoBufferMb,
    );
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
      _deviceId = 'dev-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
      await _prefs!.setString(_kDeviceId, _deviceId);
    }
    _lastRev = _prefs!.getInt(_kLastRev) ?? 0;
    _downloadNotifications = _prefs!.getBool(_kDownloadNotifications) ?? true;
    _credentialsAccountId = _prefs!.getString(_kCredentialsAccountId);
    _playlistsAccountId = _prefs!.getString(_kPlaylistsAccountId);
    _libraryAccountId = _prefs!.getString(_kLibraryAccountId);
    _backupAccountId = _prefs!.getString(_kBackupAccountId);
    _loaded = true;
    notifyListeners();
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

  Future<void> setBackupRemotePath(String path) async {
    var p = path.trim();
    if (p.isEmpty) p = defaultBackupRemotePath;
    if (!p.startsWith('/')) p = '/$p';
    if (!p.endsWith('/')) p = '$p/';
    _backupRemotePath = p;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kBackupRemotePath, _backupRemotePath);
    notifyListeners();
  }

  Future<void> setLibrarySyncRemotePath(String path) async {
    var p = path.trim();
    if (p.isEmpty) p = defaultLibrarySyncRemotePath;
    if (!p.startsWith('/')) p = '/$p';
    if (!p.endsWith('/')) p = '$p/';
    _librarySyncRemotePath = p;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kLibrarySyncRemotePath, _librarySyncRemotePath);
    notifyListeners();
  }

  Future<void> setPlaylistRemotePath(String path) async {
    var p = path.trim();
    if (p.isEmpty) p = defaultPlaylistRemotePath;
    if (!p.startsWith('/')) p = '/$p';
    if (!p.endsWith('/')) p = '$p/';
    _playlistRemotePath = p;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kPlaylistRemotePath, _playlistRemotePath);
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

  /// Set the destination account for one sync feature.
  /// [feature] is `credentials` / `playlists` / `library` / `backup`.
  Future<void> setSyncAccount(String feature, String? accountId) async {
    _prefs ??= await SharedPreferences.getInstance();
    switch (feature) {
      case 'credentials':
        _credentialsAccountId = accountId;
        await _prefs!.setString(_kCredentialsAccountId, accountId ?? '');
      case 'playlists':
        _playlistsAccountId = accountId;
        await _prefs!.setString(_kPlaylistsAccountId, accountId ?? '');
      case 'library':
        _libraryAccountId = accountId;
        await _prefs!.setString(_kLibraryAccountId, accountId ?? '');
      case 'backup':
        _backupAccountId = accountId;
        await _prefs!.setString(_kBackupAccountId, accountId ?? '');
    }
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
    'backup_remote_path': _backupRemotePath,
    'playlist_remote_path': _playlistRemotePath,
    'playlist_sync_enabled': _playlistSyncEnabled,
    'cover_thumb_size': _coverThumbSize,
    'file_type_config': _fileTypes.toJson(),
    'music_tap_action': _musicTapAction.storageKey,
    'video_tap_action': _videoTapAction.storageKey,
    'home_tab_index': _homeTab,
    'network_remember_last_path': _networkRememberLastPath,
    'network_last_path': _networkLastPath,
    'video_left_double_tap': _videoLeftDoubleTap.storageKey,
    'video_right_double_tap': _videoRightDoubleTap.storageKey,
    'video_long_press': _videoLongPress.storageKey,
    'video_background_playback': _videoBackgroundPlayback,
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
    if (json['backup_remote_path'] is String) {
      await setBackupRemotePath(json['backup_remote_path'] as String);
    }
    if (json['playlist_remote_path'] is String) {
      await setPlaylistRemotePath(json['playlist_remote_path'] as String);
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
