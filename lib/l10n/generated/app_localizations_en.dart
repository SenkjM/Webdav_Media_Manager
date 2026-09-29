// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Webdav Media Manager';

  @override
  String get settings => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Follow system';

  @override
  String get languageSimplifiedChinese => 'Simplified Chinese';

  @override
  String get languageTraditionalChinese => 'Traditional Chinese';

  @override
  String get languageEnglish => 'English';

  @override
  String get webdavServer => 'WebDAV server';

  @override
  String get download => 'Downloads';

  @override
  String get homeAndNavigation => 'Library home and navigation';

  @override
  String get videoPlayback => 'Video playback';

  @override
  String get fileTypes => 'File types';

  @override
  String get mediaNotifications => 'Media notifications';

  @override
  String get languageSettingSubtitle =>
      'Choose the app language; your choice is kept after restart';

  @override
  String get library => 'Music library';

  @override
  String get playlists => 'Playlists';

  @override
  String get networkLibrary => 'Network library';

  @override
  String get downloadQueue => 'Download queue';

  @override
  String get aboutAgpl => 'About / AGPL';

  @override
  String get exitApp => 'Exit app';

  @override
  String get cancel => 'Cancel';

  @override
  String get exit => 'Exit';

  @override
  String get cacheOneDay => '1 day';

  @override
  String get cacheOneWeek => '1 week';

  @override
  String get cacheCustom => 'Custom';

  @override
  String get cacheNever => 'Never';

  @override
  String get snackShort => 'Short';

  @override
  String get snackNormal => 'Default';

  @override
  String get snackLong => 'Long';

  @override
  String get snackUntilDismissed => 'Dismiss manually';

  @override
  String get snackOff => 'Off';

  @override
  String get syncOff => 'Off (manual only)';

  @override
  String get syncEvery15m => 'Every 15 minutes';

  @override
  String get syncEvery30m => 'Every 30 minutes';

  @override
  String get syncHourly => 'Every hour';

  @override
  String get syncEvery6h => 'Every 6 hours';

  @override
  String get syncDaily => 'Every 24 hours';

  @override
  String get actionCacheMusic => 'Cache music';

  @override
  String get actionDownload => 'Download';

  @override
  String get actionStream => 'Stream';

  @override
  String get actionReadCue => 'Read CUE';

  @override
  String get actionStreamMusic => 'Stream music';

  @override
  String get actionShortCache => 'Cache';

  @override
  String get actionShortDownload => 'Download';

  @override
  String get actionShortStream => 'Play';

  @override
  String get actionShortCue => 'CUE';

  @override
  String get actionShortStreamMusic => 'Stream';

  @override
  String get targetCache => 'App cache';

  @override
  String get targetGallery => 'System gallery';

  @override
  String get targetDownloads => 'System Downloads';

  @override
  String get musicModeSingle => 'Repeat one';

  @override
  String get musicModeSequential => 'Play in order';

  @override
  String get musicModeLoop => 'Repeat all';

  @override
  String get playbackMode => 'Playback mode';

  @override
  String unboundSource(Object sourceName) {
    return 'Unbound network drive “$sourceName”';
  }

  @override
  String get uncategorized => 'Uncategorized';

  @override
  String get unnamedPlaylist => 'Unnamed playlist';

  @override
  String get defaultServer => 'Default server';

  @override
  String get accountsTitle => 'Cloud account management';

  @override
  String get noAccounts => 'No accounts yet. Tap the add button to create one.';

  @override
  String get setCurrent => 'Set as current';

  @override
  String get edit => 'Edit';

  @override
  String get testConnection => 'Test connection';

  @override
  String get delete => 'Delete';

  @override
  String get connectionSuccess => 'Connection succeeded';

  @override
  String get connectionFailed => 'Connection failed';

  @override
  String get deleteServer => 'Delete server';

  @override
  String confirmDeleteServer(Object name) {
    return 'Delete “$name”? Its tracks will become unbound; adding the same name restores them.';
  }

  @override
  String get audioStreamingTitle => 'Audio streaming';

  @override
  String get streamPlayback => 'Stream playback';

  @override
  String get streamPlaybackHint =>
      'Music is played directly from the network drive without downloading locally.';

  @override
  String get streamMusic => 'Stream music';

  @override
  String get streamMusicHint =>
      'When enabled, music files can use the Stream music action. When disabled, that action falls back to the default.';

  @override
  String get scanList => 'Queue scanning';

  @override
  String get scanListHint =>
      'Choose which files appear in the previous/next list for streaming playback.';

  @override
  String get scanSubdirectories => 'Search subdirectories';

  @override
  String get scanSubdirectoriesHint =>
      'On: include audio in this directory and all subdirectories. Off: list only this directory.';

  @override
  String get downloadPending => 'Waiting';

  @override
  String get downloadActive => 'Downloading';

  @override
  String get downloadCompleted => 'Completed';

  @override
  String get downloadFailed => 'Failed';

  @override
  String get downloadCancelled => 'Cancelled';

  @override
  String get downloadAll => 'Download all';

  @override
  String get wakeWaiting => 'Wake waiting tasks';

  @override
  String get cancelAll => 'Cancel all';

  @override
  String get clearCompleted => 'Clear completed';

  @override
  String get more => 'More';

  @override
  String get noDownloadTasks => 'No download tasks';

  @override
  String get queueCleared => 'Download queue cleared';

  @override
  String get clearAllQueue => 'Clear all queue entries';

  @override
  String get cueAlbum => 'CUE album';

  @override
  String songCount(Object count) {
    return '$count songs';
  }

  @override
  String get inProgress => 'In progress';

  @override
  String retrying(Object current, Object max) {
    return 'Retrying ($current/$max)';
  }

  @override
  String get retry => 'Retry';

  @override
  String get clearQueueConfirm => 'Clear queue?';

  @override
  String clearQueueDetails(Object count, Object runningText) {
    return 'This removes $count queue entries$runningText; downloaded files are kept.';
  }

  @override
  String runningDownloads(Object count) {
    return ' and cancels $count active downloads';
  }

  @override
  String get clearAll => 'Clear all';

  @override
  String get accountAddServer => 'Add server';

  @override
  String get accountEditServer => 'Edit server';

  @override
  String get accountName => 'Name';

  @override
  String get accountNameHint =>
      'The library binds by this name; it must be unique. Renaming is equivalent to changing the drive.';

  @override
  String get accountNameTaken => 'This name is already in use. Choose another.';

  @override
  String get accountType => 'Type';

  @override
  String get accountRemotePath => 'Remote path';

  @override
  String get accountRemotePathHint =>
      'Browse root, default / (empty also means /)';

  @override
  String get accountServerUrl => 'Server URL';

  @override
  String get accountUsername => 'Username';

  @override
  String get accountPassword => 'Password';

  @override
  String get accountPasswordKeep => 'Password (leave empty to keep unchanged)';

  @override
  String get accountPermissions => 'Permissions';

  @override
  String get permissionRead => 'Read';

  @override
  String get permissionWrite => 'Write';

  @override
  String get permissionCreateFolder => 'Create folders';

  @override
  String get permissionMove => 'Move';

  @override
  String get permissionCopy => 'Copy';

  @override
  String get permissionDelete => 'Delete';

  @override
  String get accountFillName => 'Enter a name';

  @override
  String accountUnknownProvider(Object providerType) {
    return 'Unknown drive type: $providerType';
  }

  @override
  String accountFillField(Object label) {
    return 'Enter $label';
  }

  @override
  String accountSelectField(Object label) {
    return 'Select $label';
  }

  @override
  String accountValidationFailed(Object error) {
    return 'Verification failed: $error';
  }

  @override
  String get accountSave => 'Save';

  @override
  String accountAdded(Object name) {
    return 'Added ($name)';
  }

  @override
  String get accountDuplicateTitle => 'Name already in use';

  @override
  String accountDuplicateContent(Object name, Object url) {
    return 'A drive named “$name” already exists:\n$url\n\nThe same name is treated as the same source.';
  }

  @override
  String get accountChangeName => 'Choose another name';

  @override
  String get accountKeepName => 'Use anyway';

  @override
  String get accountRenameTitle => 'Renaming changes the drive';

  @override
  String get accountUsernameChangedTitle => 'Username changed';

  @override
  String accountRenameContent(Object name) {
    return 'Tracks from \"$name\" will become unbound. Restoring the old name can restore them.\nKeep the name unchanged when only changing the address.';
  }

  @override
  String get accountUsernameChangedContent =>
      'The username is not part of the binding. A new username may point to a different directory, so the old path may not exist.';

  @override
  String get accountConfirmChange => 'Confirm change';

  @override
  String get accountBindingHint =>
      'Tracks bind by name + path; renaming is equivalent to changing the drive.';

  @override
  String get manageAccounts => 'Manage server accounts';

  @override
  String get manageAccountsSubtitle => 'Add / edit / delete WebDAV servers';

  @override
  String get downloadQueueSettings => 'Download queue';

  @override
  String get downloadQueueSettingsSubtitle =>
      'Resume-download temporary-file retention and cleanup';

  @override
  String get customHome => 'Custom home';

  @override
  String get customHomeSubtitle => 'Return to this home from other screens';

  @override
  String get rememberNetworkPath => 'Remember last network library path';

  @override
  String get rememberNetworkPathSubtitle =>
      'Restore the last browsed directory when opening the network library';

  @override
  String get videoSettings => 'Video playback settings';

  @override
  String get videoSettingsSubtitle =>
      'Streaming / gestures / background playback / picture-in-picture';

  @override
  String get audioSettings => 'Audio streaming settings';

  @override
  String get audioSettingsSubtitle =>
      'Streaming toggle / search subdirectories';

  @override
  String get fileExtensionSettings => 'File extension management';

  @override
  String get fileExtensionSettingsSubtitle =>
      'Music / video / image / CUE extensions and default actions';

  @override
  String get refreshLibraryTags => 'Update music library tags';

  @override
  String get refreshLibraryTagsSubtitle =>
      'Read tags from cached music files asynchronously and update the library';

  @override
  String get networkNewFolder => 'New folder';

  @override
  String get manageServers => 'Manage servers';

  @override
  String get currentServer => 'Current server';

  @override
  String get networkRetry => 'Retry';

  @override
  String get emptyDirectory => 'Empty directory';

  @override
  String get directory => 'Directory';

  @override
  String get cueFile => 'CUE file';

  @override
  String get playVideo => 'Play video';

  @override
  String get moreActions => 'More actions';

  @override
  String get cancelSelection => 'Clear selection';

  @override
  String get selectAll => 'Select all';

  @override
  String get cacheMusic => 'Cache music';

  @override
  String get copyTo => 'Copy to';

  @override
  String get moveTo => 'Move to';

  @override
  String get downloadAction => 'Download';

  @override
  String get fileQueuedOrSaved => 'This file is already queued or downloaded';

  @override
  String get fileQueuedOrSavedShort => 'This file is already queued or saved';

  @override
  String get accountRequired => 'Add a WebDAV server first';

  @override
  String get syncTitle => 'Sync and backup';

  @override
  String get syncIntro =>
      'Credentials, playlists, and the music library share one remote path. Choose a server and enter the path below.';

  @override
  String get syncAll => 'Sync all';

  @override
  String get scheduledSync => 'Scheduled sync';

  @override
  String get manualOnly => 'Disabled; manual sync only';

  @override
  String autoSync(Object interval) {
    return 'Auto sync $interval';
  }

  @override
  String get remotePath => 'Remote path';

  @override
  String get remotePathSubtitle =>
      'Credentials, music library, playlists, and backups are stored below this path';

  @override
  String get selectServer => '1. Choose server';

  @override
  String get path => '2. Path';

  @override
  String get pathExample =>
      'For example, enter /player; the music library will be under /player/library/';

  @override
  String get apply => 'Apply';

  @override
  String get encryptionKey => 'Unified encryption key (chosen by you)';

  @override
  String get encryptionKeyHint =>
      'Stored only on this device; leaving it empty stores data in plain text.';

  @override
  String get keyNotSet =>
      'Current: not set (passwords in credentials and backups are plain text)';

  @override
  String keySet(Object length) {
    return 'Current: set (length $length)';
  }

  @override
  String get saveKey => 'Save key';

  @override
  String get keySaved => 'Encryption key saved on this device';

  @override
  String operationFailed(Object error) {
    return 'Operation failed: $error';
  }

  @override
  String get rebuildThreshold => 'Rebuild prompt threshold';

  @override
  String get cloudFragmentCount => 'Cloud fragment count';

  @override
  String get rebuildThresholdHint =>
      'Prompt for a rebuild at this count (2–500)';

  @override
  String get confirm => 'Confirm';

  @override
  String get exitConfirm => 'Exit the app? Playback will stop.';

  @override
  String get menu => 'Menu';

  @override
  String get aboutTitle => 'About';

  @override
  String aboutVersion(Object version) {
    return 'Version $version';
  }

  @override
  String get aboutCiVersion =>
      'CI pre-releases write versionName (with a short hash) and an incrementing versionCode for in-place installation.';

  @override
  String get aboutDescription =>
      'Browse network drive folders, download files to the local cache, and play them.';

  @override
  String get aboutCredits => 'Credits';

  @override
  String get aboutImplementation => 'Implementation: Grok Bot';

  @override
  String get aboutConcept => 'Concept and requirements: SenkjM';

  @override
  String get aboutLicense => 'License';

  @override
  String get aboutLicenseText =>
      'This project is licensed under the GNU Affero General Public License v3.0 (AGPL-3.0).\\n\\nYou may use, modify, and distribute this software freely, but modified versions or network services based on it must publish the complete corresponding source under AGPL-3.0. See the LICENSE file in the repository for the full text.';

  @override
  String get fileExtSaved => 'Extension settings saved';

  @override
  String get fileExtIntro =>
      'Files are identified by extension; separate multiple extensions with spaces or commas. Changes take effect after returning to the network library. Each category below has a tap action used by the network library; the multi-select toolbar and More menu follow the same rules.';

  @override
  String get fileCatMusic => 'Music files';

  @override
  String get fileCatVideo => 'Video files';

  @override
  String get fileCatCue => 'CUE files';

  @override
  String get fileCatOther => 'Other files';

  @override
  String fileExtDefaultAction(Object action) {
    return 'Tap action: $action';
  }

  @override
  String fileExtCueNote(Object action) {
    return 'Tap action: $action (CUE reading parses segments and downloads the whole group)';
  }

  @override
  String fileExtOtherNote(Object action) {
    return 'Tap action: $action (extensions not in the three lists above download to the system download folder)';
  }

  @override
  String get fileExtTapAction => 'Tap action';

  @override
  String get fileExtHintExample => 'e.g. mp3 flac m4a';

  @override
  String get fileExtListLabel => 'Extension list';

  @override
  String get restoreDefault => 'Restore default';

  @override
  String get dlPartFilesTitle => 'Resumable download temp files';

  @override
  String get dlPartFilesIntro =>
      'Retries after network interruptions resume from partial files. Files must be kept to resume, so these are limits: anything beyond them is cleaned automatically (orphan files with no download task are also cleaned).';

  @override
  String get dlRetainDuration => 'Retention period';

  @override
  String get unitHours => 'hours';

  @override
  String get dlTotalSizeLimit => 'Total size limit';

  @override
  String get dlCryptSequential => 'Crypt sequential stream';

  @override
  String get dlCryptSequentialSub =>
      'Affects download tasks only; online playback and legacy resume are unchanged';

  @override
  String get dlCleanNow => 'Clean now';

  @override
  String get dlCleanNowSub =>
      'Delete expired partial files per the limits above';

  @override
  String get dlNothingToClean => 'No partial files to clean';

  @override
  String dlCleanedCount(Object count) {
    return 'Cleaned $count partial files';
  }

  @override
  String dlFieldNotNumber(Object field) {
    return 'Enter a number for $field';
  }

  @override
  String dlFieldClamped(
    Object field,
    Object max,
    Object min,
    Object unit,
    Object value,
  ) {
    return '$field must be between $min~$max$unit; saved as $value';
  }

  @override
  String dlRangeHint(Object max, Object min, Object unit) {
    return 'Range $min ~ $max $unit; values outside are saved at the boundary';
  }

  @override
  String get playlistQueueEmpty => 'The current play queue is empty';

  @override
  String playlistQueueDefaultName(Object day, Object month) {
    return 'Playlist $month/$day';
  }

  @override
  String get playlistCreateFromQueue => 'Create from current queue';

  @override
  String playlistCreateFromQueueBody(Object count) {
    return 'Copy $count tracks from the current queue into a new playlist.';
  }

  @override
  String get playlistNameLabel => 'Playlist name';

  @override
  String get create => 'Create';

  @override
  String playlistCreated(Object name) {
    return 'Created playlist \"$name\"';
  }

  @override
  String get playlistNew => 'New playlist';

  @override
  String get nameLabel => 'Name';

  @override
  String get playlistsTitle => 'Playlists';

  @override
  String get playlistSyncTooltip => 'Sync from WebDAV';

  @override
  String get playlistSynced => 'Playlists synced';

  @override
  String playlistSyncFailed(Object error) {
    return 'Sync failed: $error';
  }

  @override
  String get playlistsEmpty =>
      'No playlists yet: tap + in the top-right, or long-press tracks in the library.';

  @override
  String playlistTrackCount(Object count) {
    return '$count tracks';
  }

  @override
  String get playlistRename => 'Rename playlist';

  @override
  String get save => 'Save';

  @override
  String get playlistDelete => 'Delete playlist';

  @override
  String playlistDeleteConfirm(Object name) {
    return 'Delete \"$name\"? The corresponding files on this device and WebDAV will be removed.';
  }

  @override
  String get rename => 'Rename';

  @override
  String get playlistNewEllipsis => 'New playlist…';

  @override
  String get playlistAddTo => 'Add to playlist';

  @override
  String get playlistAdded => 'Added to playlist';

  @override
  String playlistAddMany(Object count) {
    return 'Add $count tracks to playlist';
  }

  @override
  String playlistAddedMany(Object count) {
    return 'Added $count tracks to playlist';
  }

  @override
  String get playlistNotFound => 'Playlist not found';

  @override
  String get playlistAddFromLibrary => 'Add from library';

  @override
  String get playlistEmpty =>
      'This playlist is empty. Add tracks from the library.';

  @override
  String playlistMissingInLibrary(Object name) {
    return 'Not in library · $name';
  }

  @override
  String get libraryEmpty => 'The music library is empty';

  @override
  String get notDownloaded => 'Not downloaded';

  @override
  String get downloaded => 'Downloaded';

  @override
  String get tapToDownload => 'Tap to download';

  @override
  String get streamNotConnected =>
      'WebDAV is not connected; streaming is unavailable';

  @override
  String get playlistSheetTitle => 'Play queue';

  @override
  String get searchList => 'Search list';

  @override
  String get noMatchingTracks => 'No matching tracks';

  @override
  String get streamUrlFailed =>
      'Failed to build the stream URL. Check the account settings.';

  @override
  String get loading => 'Loading…';

  @override
  String get back => 'Back';

  @override
  String get streamingNotCached => 'Streaming · not cached';

  @override
  String seekSeconds(Object seconds) {
    return '${seconds}s';
  }

  @override
  String get previousTrack => 'Previous track';

  @override
  String get pause => 'Pause';

  @override
  String get play => 'Play';

  @override
  String get nextTrack => 'Next track';

  @override
  String playbackFailed(Object error) {
    return 'Playback failed: $error';
  }

  @override
  String get newFolder => 'New folder';

  @override
  String get close => 'Close';

  @override
  String get parentFolder => 'Parent folder';

  @override
  String get pickThisFolder => 'Choose this folder';

  @override
  String get noSubfolders => 'No subfolders in this directory';

  @override
  String movedItems(Object count) {
    return 'Moved $count items';
  }

  @override
  String copiedItems(Object count) {
    return 'Copied $count items';
  }

  @override
  String failedWith(Object reason) {
    return 'Failed: $reason';
  }

  @override
  String movePartialResult(Object done, Object failed, Object reason) {
    return '$done succeeded, $failed failed: $reason';
  }

  @override
  String get nowPlayingQueueTitle => 'Now playing queue';

  @override
  String nowPlayingQueueCount(Object count) {
    return 'Now playing queue ($count)';
  }

  @override
  String get nowPlayingQueueEmpty =>
      'No play queue yet.\nStart playing from the library or network library to fill this.';

  @override
  String playerChipAlbumArtist(Object artist) {
    return 'Album artist · $artist';
  }

  @override
  String playerChipTrackNumber(Object n, Object total) {
    return 'Track $n/$total';
  }

  @override
  String playerChipTrackNoTotal(Object n) {
    return 'Track $n';
  }

  @override
  String playerChipDiscNumber(Object n, Object total) {
    return 'Disc $n/$total';
  }

  @override
  String playerChipDiscNoTotal(Object n) {
    return 'Disc $n';
  }

  @override
  String get playerRowAccount => 'Account';

  @override
  String get playerRowServer => 'Server';

  @override
  String get playerRowRemotePath => 'Remote path';

  @override
  String get playerRowFileName => 'File name';

  @override
  String get playerRowType => 'Type';

  @override
  String get playerRowCueNoteKey => 'Note';

  @override
  String get playerRowCueNote =>
      'Sliced from CUE; playback and cache share the source audio.';

  @override
  String get playerRowCueFile => 'CUE file';

  @override
  String get playerRowSourceAudio => 'Source audio';

  @override
  String get playerRowCueTrackIndex => 'CUE track #';

  @override
  String get playerClipEnd => 'End';

  @override
  String get playerRowClipRange => 'Clip range';

  @override
  String get playerRowLocalCache => 'Local cache';

  @override
  String get playerNotDownloaded => 'Not downloaded';

  @override
  String get playerRowFileSize => 'File size';

  @override
  String get playerFileDetails => 'File details';

  @override
  String get copyAll => 'Copy all';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String copiedKey(Object key) {
    return 'Copied: $key';
  }

  @override
  String get tagsUpdatedFromLocal => 'Tags updated from the local file';

  @override
  String get tagsNeedDownloadFirst =>
      'This track is not cached yet. Download it before refreshing tags.';

  @override
  String get updateThisTrackTags => 'Refresh tags for this track';

  @override
  String get nowPlaying => 'Now playing';

  @override
  String get noTrackSelected => 'No track selected';

  @override
  String get dlSavedToGallery => 'Saved to system gallery';

  @override
  String get dlTargetGallery => 'Target: system gallery';

  @override
  String get dlSavedToDownloads => 'Saved to Downloads';

  @override
  String get dlTargetDownloads => 'Target: Downloads';

  @override
  String get rebuildHintThreshold => 'Rebuild hint threshold';

  @override
  String get cloudFragmentCountLabel => 'Cloud fragments';

  @override
  String get cloudFragmentCountHelper =>
      'A rebuild is suggested when this count is reached (2–500)';

  @override
  String get unifiedEncryptionKey => 'Unified encryption key (you choose)';

  @override
  String get unifiedEncryptionKeyHint =>
      'Stored on this device only; blank stores in plain text.';

  @override
  String get keyNotSetLong =>
      'Current: not set (passwords in credentials and backups are plain text)';

  @override
  String keySetLong(Object length) {
    return 'Current: set (length $length)';
  }

  @override
  String get keySavedNotice => 'Encryption key saved on this device';

  @override
  String get overwriteLibraryTitle => 'Overwrite library from cloud';

  @override
  String get overwriteLibraryBody =>
      'Downloads the library database from the cloud and overwrites the local one.';

  @override
  String get overwriteLibraryNote =>
      'Local index, tags, and unsynced changes are replaced by the cloud copy; downloaded audio, covers, and caches are kept.';

  @override
  String get overwriteLibraryAction => 'Overwrite';

  @override
  String get overwriteLibraryPhrase => 'Type YES to confirm overwriting';

  @override
  String get destroyLibraryTitle => 'Destroy library';

  @override
  String get destroyLibraryBody =>
      'Destroys the local library track by track: each track’s cached audio, covers, and library rows are deleted, leaving one tombstone each.';

  @override
  String get destroyLibraryNote =>
      'Deletion records upload on the next sync; a cloud rebuild cannot restore destroyed content. Auto-sync is turned off afterwards.';

  @override
  String get destroyLibraryAction => 'Destroy';

  @override
  String get destroyLibraryPhrase => 'Type YES to confirm destroying';

  @override
  String destroyLibraryDone(Object count) {
    return 'Destroyed $count tracks; deletion records upload on next sync, scheduled sync off';
  }

  @override
  String readCloudLibraryFailed(Object error) {
    return 'Failed to read cloud library: $error';
  }

  @override
  String get tidyCloudLibraryTitle => 'Tidy cloud library';

  @override
  String get missingFragments =>
      'Some fragments are missing; only a rebuild can fix it.';

  @override
  String missingFragmentName(Object name) {
    return '• Missing $name';
  }

  @override
  String get orphanFiles =>
      'Orphan files: not referenced by the manifest, deletable.';

  @override
  String get auditHealthy => 'Everything is consistent. Nothing to do.';

  @override
  String get deleteOrphans => 'Delete orphans';

  @override
  String get rebuildFromLocal => 'Rebuild from this device';

  @override
  String orphansDeleted(Object count) {
    return 'Deleted $count orphan files';
  }

  @override
  String get restoreConfirmTitle => 'Confirm restore';

  @override
  String get restoreConfirmBody =>
      'The backup will overwrite local account credentials, library, and playlists. Irreversible.';

  @override
  String get restore => 'Restore';

  @override
  String exportedTo(Object fileName, Object location) {
    return 'Exported to $location: $fileName';
  }

  @override
  String exportFailed(Object error) {
    return 'Export failed: $error';
  }

  @override
  String pickFileFailed(Object error) {
    return 'Failed to pick a file: $error';
  }

  @override
  String get pasteBase64First => 'Paste the backup content (Base64) first';

  @override
  String remoteRootUpdated(Object path) {
    return 'Remote path updated: $path';
  }

  @override
  String get derivedPathCredentials => 'Credentials';

  @override
  String get derivedPathPlaylists => 'Playlists';

  @override
  String get derivedPathLibrary => 'Library';

  @override
  String get derivedPathBackups => 'All backups';

  @override
  String get syncAndBackup => 'Backup and sync';

  @override
  String get syncIntroLong =>
      'Credentials, playlists, and the library share one remote path: pick a drive and fill in the path below.';

  @override
  String get scheduledSyncOff => 'Off; manual sync only';

  @override
  String scheduledSyncAuto(Object interval) {
    return '$interval auto sync';
  }

  @override
  String get remotePathSubtitleLong =>
      'Credentials, playlists, library, and backups all live under this path';

  @override
  String get needWebdavServer => 'Add a WebDAV server first.';

  @override
  String get selectCloudDrive => '① Pick a drive';

  @override
  String get pathStep => '② Path';

  @override
  String get pathExampleLong =>
      'e.g. /player puts the library at /player/library/';

  @override
  String get credentialsSection => 'Credentials';

  @override
  String credentialsSectionDesc(Object path) {
    return 'Cloud $path: all drive accounts; password fields encrypted, unsupported account types are skipped when restoring.';
  }

  @override
  String get encryptPasswordField => 'Encrypt password fields';

  @override
  String get encryptPasswordOn =>
      'Passwords left empty when the passphrase mismatches';

  @override
  String get encryptPasswordOff => 'Passwords stored in plain text';

  @override
  String lastAutoScan(Object time) {
    return 'Last auto scan: $time';
  }

  @override
  String get uploadCredentials => 'Upload credentials';

  @override
  String get downloadCredentials => 'Download credentials';

  @override
  String get playlistsSection => 'Playlists';

  @override
  String playlistsSectionDesc(Object path) {
    return 'Two-way M3U8 sync, changes upload instantly: $path';
  }

  @override
  String get syncPlaylistsNow => 'Sync playlists now';

  @override
  String get librarySection => 'Library';

  @override
  String librarySectionDesc(Object path) {
    return '${path}index.json manifest + lib/seg/del shards; only changes upload, deletions land on rebuild.';
  }

  @override
  String cloudFragmentsLine(Object count, Object hint, Object size) {
    return 'Cloud fragments: $count (about $size)$hint';
  }

  @override
  String get cloudFragmentsHint => ' · rebuild suggested';

  @override
  String get syncAction => 'Sync';

  @override
  String get rebuildAction => 'Rebuild';

  @override
  String get tidyAction => 'Tidy';

  @override
  String rebuildHintNow(Object count, Object target) {
    return 'Cloud fragments: $count now; a rebuild is suggested at $target';
  }

  @override
  String rebuildHintTarget(Object target) {
    return 'A rebuild is suggested at $target cloud fragments';
  }

  @override
  String get customThreshold => 'Custom…';

  @override
  String customThresholdValue(Object count) {
    return 'Custom ($count)';
  }

  @override
  String get allBackupsSection => 'All backups';

  @override
  String allBackupsSectionDesc(Object path) {
    return 'Writes credentials + library + playlists into one archive at $path.';
  }

  @override
  String get startBackup => 'Start backup';

  @override
  String get readBackupsUnderPath => 'Read backups under this path';

  @override
  String get backupToRestore => 'Backup to restore';

  @override
  String get restoreFromSelectedBackup => 'Restore from the selected backup';

  @override
  String get localImportExportSection => 'Local import/export';

  @override
  String get localImportExportDesc =>
      'Export and import use the same key above.';

  @override
  String get exportToDownloads => 'Export to system Downloads';

  @override
  String get exportReadableJson =>
      'Export readable JSON (debugging, no covers)';

  @override
  String get importFromLocalFile => 'Import from a local file…';

  @override
  String get pasteBase64Label => 'Or paste backup content (Base64)';

  @override
  String get importFromPaste => 'Import from pasted content';

  @override
  String get processing => 'Working…';

  @override
  String get rebuildCloudLibraryTitle => 'Rebuild cloud library';

  @override
  String get rebuildCloudLibraryDesc =>
      'Rewrites every shard from this device and materialises deletions.';

  @override
  String get tracksPerShard => 'Tracks per shard';

  @override
  String get embedCoversInShards => 'Embed cover thumbnails in shards';

  @override
  String get embedCoversInShardsDesc =>
      'Each track stores its own copy, no dedupe; off means no covers in the cloud';

  @override
  String get estimating => 'Estimating…';

  @override
  String get estimateUnavailable => 'Estimate unavailable';

  @override
  String get fileExtTapBehavior => 'Tap action';

  @override
  String readBackupsListFailed(Object error) {
    return 'Failed to read the backup list: $error';
  }

  @override
  String get trackStateQueued => 'Queued';

  @override
  String get trackStateDownloading => 'Downloading';

  @override
  String get trackStateReady => 'Ready';

  @override
  String get trackStatePlaying => 'Playing';

  @override
  String get trackStateError => 'Error';

  @override
  String get playQueueTitle => 'Play queue';

  @override
  String get webdavErrorPerm => 'Permission error';

  @override
  String get webdavErrorGeneric => 'Operation failed';

  @override
  String get dialogOk => 'OK';

  @override
  String get destroyInProgress => 'Destroying…';

  @override
  String processedOfTotal(Object processed, Object total) {
    return '$processed / $total processed';
  }

  @override
  String get destroyStopHint =>
      'Stop or back will finish after the current track; destroyed tracks will not be restored.';

  @override
  String get actionStop => 'Stop';

  @override
  String get tagRefreshInProgress => 'Updating tags…';

  @override
  String get tagRefreshStopHint =>
      'Reads local cache only; updated tracks are kept after stopping.';

  @override
  String get tagRefreshPreparing => 'Preparing…';

  @override
  String get recoveryTitle => 'Local data recovery needed';

  @override
  String get recoveryHeading => 'Database initialization failed';

  @override
  String get recoveryBody =>
      'Export all local databases first, then clear and re-enter the app.';

  @override
  String get recoveryNothingToExport => 'No local database found to export';

  @override
  String recoveryExportedCount(Object count, Object ok) {
    return 'Exported $ok / $count database files to Downloads';
  }

  @override
  String recoveryExportFailed(Object error) {
    return 'Export failed: $error';
  }

  @override
  String get recoveryClearTitle => 'Clear local databases?';

  @override
  String get recoveryClearContent =>
      'Export first. After clearing, reopen the app and reconfigure cloud accounts and the local index.';

  @override
  String recoveryClearedCount(Object count) {
    return 'Cleared $count database files; please reopen the app';
  }

  @override
  String get recoveryExportAll => 'Export all local databases';

  @override
  String get recoveryClearAndExit => 'Clear and exit';

  @override
  String get recoveryClearAndReenter => 'Clear data and re-enter';

  @override
  String get dialogCancel => 'Cancel';

  @override
  String get fileActionIsFolder =>
      'This is a folder; file actions do not apply';

  @override
  String fileActionNotApplicable(Object action, Object category) {
    return '\"$action\" does not apply to $category';
  }

  @override
  String get fileActionNotApplicableGeneric =>
      'This action does not apply to this file';

  @override
  String get catMusicFile => 'music file';

  @override
  String get catVideoFile => 'video file';

  @override
  String get catCueFile => 'CUE file';

  @override
  String get catOtherFile => 'regular file';

  @override
  String get videoGestureNone => 'None';

  @override
  String get videoGestureBack10s => 'Back 10 s';

  @override
  String get videoGestureForward10s => 'Forward 10 s';

  @override
  String get videoGestureBack30s => 'Back 30 s';

  @override
  String get videoGestureForward30s => 'Forward 30 s';

  @override
  String get videoGestureHoldSpeedUp => 'Hold to speed up (release to restore)';

  @override
  String get videoGesturePlayPause => 'Play / pause';

  @override
  String get videoSubtitleVisible => 'Show subtitles';

  @override
  String get videoSubtitleHidden => 'Hidden';

  @override
  String get videoTapOpen => 'Open video';

  @override
  String get videoTapDownload => 'Download';

  @override
  String get musicTapDownload => 'Download music';

  @override
  String get musicTapPlayCached =>
      'Play (from cache when available, otherwise download)';

  @override
  String get libSortByName => 'By name';

  @override
  String get libSortByAlbumTrack => 'By album track order';

  @override
  String get cueMultiSliceLabel => 'CUE multi-track slice';

  @override
  String get artistUnknown => 'Unknown artist';

  @override
  String get albumUnknown => 'Unknown album';

  @override
  String get snackGotIt => 'Got it';

  @override
  String get rootFolder => 'Root';

  @override
  String folderPickerTitle(Object folder, Object purpose) {
    return '$purpose: $folder';
  }

  @override
  String get webdavErrorPermDetail =>
      'Insufficient permissions or not authorized (401/403)';

  @override
  String itemWithMessage(Object message, Object name) {
    return '$name: $message';
  }

  @override
  String accountWithName(Object name, Object user) {
    return '$name ($user)';
  }

  @override
  String labelValuePair(Object label, Object value) {
    return '$label: $value';
  }

  @override
  String syncOperationFailed(Object error) {
    return 'Operation failed: $error';
  }

  @override
  String get syncUnknownError => 'unknown error';

  @override
  String get syncNoChanges => 'No changes';

  @override
  String get syncListSep => '; ';

  @override
  String get syncNotePrefix => 'Note: ';

  @override
  String get nameJoiner => ', ';

  @override
  String get progressPreparing => 'Preparing…';

  @override
  String get progressDone => 'Done';

  @override
  String get progressScanningCloudCredentials => 'Scanning cloud credentials…';

  @override
  String get progressScanningPlaylists => 'Scanning playlists…';

  @override
  String get progressUploadingCredentials => 'Uploading credentials…';

  @override
  String get progressDownloadingCredentials => 'Downloading credentials…';

  @override
  String get progressMergingPlaylists => 'Merging playlists…';

  @override
  String get progressReadingCloudIndex => 'Reading cloud library index…';

  @override
  String progressAdoptingCloudTracks(Object count) {
    return 'Adopting $count cloud tracks…';
  }

  @override
  String progressUploadingTombstones(Object count) {
    return 'Uploading $count deletion records…';
  }

  @override
  String progressAppendingSegments(Object count) {
    return 'Appending $count tracks to cloud segments…';
  }

  @override
  String get progressUploadingFullShards => 'Uploading full library shards…';

  @override
  String get progressPackingBackup =>
      'Packing credentials / library / playlists…';

  @override
  String get progressDownloadingRestore => 'Downloading and restoring…';

  @override
  String get progressGeneratingBackup => 'Generating backup…';

  @override
  String get progressWritingDownloads => 'Writing to Downloads…';

  @override
  String get progressUnpackingRestore => 'Unpacking and restoring…';

  @override
  String get warnCredentialsSkippedNoKey =>
      'Credential sync skipped (no unified encryption key set)';

  @override
  String warnCredentialScanSkipped(Object e) {
    return 'Credential scan skipped: $e';
  }

  @override
  String warnLeftoverTombstones(Object count) {
    return '$count tombstones remain after rebuild (a live row and tombstone coexist); please inspect the data';
  }

  @override
  String stepPlaylistsMerged(Object count) {
    return 'Playlists merged ($count)';
  }

  @override
  String stepCredentialsUploaded(Object count) {
    return 'Credentials synced to cloud ($count servers)';
  }

  @override
  String get stepCloudNoCredentials => 'No credential file in the cloud';

  @override
  String stepPlaylistsSynced(Object count) {
    return 'Playlists synced ($count)';
  }

  @override
  String get stepIncrementalNoChange =>
      'Incremental sync: no changes (nothing uploaded)';

  @override
  String stepIncrementalUploaded(
    Object adopted,
    Object tombs,
    Object uploaded,
  ) {
    return 'Incremental sync: uploaded $uploaded, adopted $adopted, deleted $tombs';
  }

  @override
  String stepClearedDeadTombstones(Object count) {
    return 'Cleaned up $count stale tombstones';
  }

  @override
  String stepRebuildDone(Object localCount, Object rev, Object shards) {
    return 'Rebuild done: $shards shards, base covers up to rev $rev ($localCount local tracks)';
  }

  @override
  String get stepBackupDone => 'Backup complete';

  @override
  String get stepRestoreDone => 'Restore complete';

  @override
  String get stepLocalBackupImported => 'Local backup imported';

  @override
  String get errNoWebdavAccount => 'Add a WebDAV account first';

  @override
  String vaultSummaryAccounts(Object imported, Object updated) {
    return 'Accounts: $imported added, $updated updated; ';
  }

  @override
  String vaultSummaryPasswords(
    Object passwordsMissing,
    Object passwordsRestored,
  ) {
    return '$passwordsRestored passwords restored, $passwordsMissing left empty';
  }

  @override
  String get vaultSummaryMissingNote =>
      ' (unified decryption key missing; you can fill them in later)';

  @override
  String vaultSummarySkipped(Object count) {
    return '; $count unsupported drive types skipped';
  }

  @override
  String get vaultSyncedEncrypted =>
      'Account credentials synced to cloud (passwords encrypted)';

  @override
  String get vaultSyncedPlaintext =>
      'Account credentials synced to cloud (plaintext passwords)';

  @override
  String vaultCloudNoFile(Object remotePath) {
    return 'No credential file in the cloud ($remotePath); skipped';
  }

  @override
  String vaultRestoredFromCloud(Object summary) {
    return 'Account credentials restored from cloud: $summary';
  }

  @override
  String get errVaultDestNotConfigured =>
      'Credential sync destination drive is not configured';

  @override
  String get errBackupDestNotConfigured =>
      'Backup destination drive is not configured';

  @override
  String backupDoneLatest(Object remote, Object size) {
    return 'Backed up to $remote ($size; latest updated)';
  }

  @override
  String get errBackupEncryptedNeedPassphrase =>
      'This backup is encrypted; enter the passphrase';

  @override
  String get errBackupUnrecognizedContent => 'Unrecognized backup content';

  @override
  String backupRestoredFull(Object count) {
    return 'Backup restored: $count servers, library and playlists written back';
  }

  @override
  String backupRestoredMissingPasswords(Object missing) {
    return 'Backup restored, but passwords for these servers could not be decrypted and were left empty: $missing. Please fill them in under Accounts.';
  }

  @override
  String errNotBackupArchive(Object kind) {
    return 'This is a $kind file, not a backup archive';
  }

  @override
  String estimateLabelWithCovers(Object shards, Object sizeLabel) {
    return '~$shards shards · with covers, about $sizeLabel';
  }

  @override
  String estimateLabelNoCovers(Object shards, Object sizeLabel) {
    return '~$shards shards · without covers, about $sizeLabel';
  }

  @override
  String auditBaseShards(Object count) {
    return '$count base shards';
  }

  @override
  String auditSegments(Object count) {
    return '$count segments';
  }

  @override
  String auditTombstones(Object count) {
    return '$count tombstones';
  }

  @override
  String auditTotalBytes(Object size) {
    return 'total $size';
  }

  @override
  String auditOrphans(Object count) {
    return '$count orphan files';
  }

  @override
  String auditMissing(Object count) {
    return '$count missing files';
  }

  @override
  String get exportErrUnsupportedPlatform =>
      'Current platform cannot write to the system gallery/Downloads';

  @override
  String exportErrSourceMissing(Object detail) {
    return 'Source file does not exist: $detail';
  }

  @override
  String exportErrBadNativeResponse(Object detail) {
    return 'Export failed: native returned $detail';
  }

  @override
  String get exportErrFailed => 'Export failed';

  @override
  String exportErrFailedWith(Object detail) {
    return 'Export failed: $detail';
  }

  @override
  String get exportErrChannelUnavailable =>
      'Native export channel unavailable (full APK required)';

  @override
  String get pickerErrUnsupportedPlatform =>
      'Current platform has no system file picker';

  @override
  String get pickerErrBadResponse =>
      'File picker returned an unexpected response';

  @override
  String get pickerErrFailed => 'File pick failed';

  @override
  String get pickerErrChannelUnavailable =>
      'Native file picker unavailable (full APK required)';

  @override
  String get locationSystemGallery => 'system gallery';

  @override
  String get locationDownloads => 'Downloads';

  @override
  String locationDownloadsSubdir(Object dir) {
    return 'Downloads/$dir';
  }

  @override
  String get dlChannelProgressName => 'Download progress';

  @override
  String get dlChannelProgressDesc => 'Progress of the active download queue';

  @override
  String get dlChannelDoneName => 'Downloads complete';

  @override
  String get dlChannelDoneDesc => 'Summary once all downloads finish';

  @override
  String dlDoneCancelledCount(Object count) {
    return 'Cancelled $count';
  }

  @override
  String dlDoneFailedCount(Object count) {
    return 'Failed $count';
  }

  @override
  String dlDoneOkCount(Object count) {
    return 'Succeeded $count';
  }

  @override
  String get dlDoneSep => ' · ';

  @override
  String dlDoneTitle(Object parts) {
    return 'Downloads complete: $parts';
  }

  @override
  String get dlErrCueMalformed =>
      'Unparseable CUE: standard FILE + TRACK/INDEX required';

  @override
  String get dlErrOffline => 'Network unavailable';

  @override
  String get dlErrQueueCleared => 'Queue cleared';

  @override
  String dlErrQueueSchemaDrift(Object raw) {
    return 'Download queue database schema is too old ($raw). Restart the app to upgrade it.';
  }

  @override
  String dlErrSourceUnbound(Object source) {
    return 'Source drive not bound ($source)';
  }

  @override
  String get dlErrWritePublicFailed => 'Failed to write to public storage';

  @override
  String dlNetworkInterruptedRetry(Object attempts, Object max) {
    return 'Network interrupted, retrying ($attempts/$max)';
  }

  @override
  String dlOfflineRetryWait(Object attempts, Object max, Object seconds) {
    return 'Network unavailable, retrying in ${seconds}s ($attempts/$max)';
  }

  @override
  String dlRetryExhausted(Object max, Object reason) {
    return 'Failed after $max retries: $reason';
  }

  @override
  String netLoadGiveUpFailed(Object err, Object failures) {
    return '$err\n\nGave up after $failures automatic retries; waiting for manual retry.';
  }

  @override
  String netEnqueueFailed(Object err) {
    return 'Failed to enqueue download: $err';
  }

  @override
  String get netStreamingExperimental =>
      'Music streaming is off; enable it in Settings first';

  @override
  String get netParsingCue => 'Parsing CUE…';

  @override
  String netCueReadFailed(Object e) {
    return 'Failed to read CUE: $e';
  }

  @override
  String netCueGroupTitle(Object tracks) {
    return 'Multi-song merged segment · CUE · $tracks tracks';
  }

  @override
  String netCueGroupTitleMulti(Object files, Object tracks) {
    return 'Multi-song merged segment · CUE · $tracks tracks · $files audio files';
  }

  @override
  String get netCueGroupSubtitle =>
      'Import the whole album into the music library as segments.';

  @override
  String netCueDownloadFailed(Object e) {
    return 'CUE download failed: $e';
  }

  @override
  String netItemSubtitle(Object action, Object category) {
    return '$category · Tap = $action';
  }

  @override
  String get netCacheFolderAudio => 'Cache audio in the folder';

  @override
  String get netCacheFolderAudioDesc =>
      'Scan recursively; audio goes to cache and music library';

  @override
  String get netDownloadWholeFolder => 'Download the whole folder';

  @override
  String get netDownloadWholeFolderDesc =>
      'Download the directory tree recursively, regardless of file type';

  @override
  String get netDefaultActionFromSettings => 'Default action from Settings';

  @override
  String get netExperimentalNoDownload => 'No download, not added to library';

  @override
  String get netDownloadToGallery => 'Download to system gallery';

  @override
  String get netDownloadToGalleryDesc => 'Save to Movies/WebdavMediaManager';

  @override
  String get netCopyTo => 'Copy to…';

  @override
  String get netMoveTo => 'Move to…';

  @override
  String get netNewName => 'New name';

  @override
  String get netTapDownload => 'Tap to download';

  @override
  String netSelectedCount(Object n) {
    return '$n selected';
  }

  @override
  String get netCachingMusic => 'Caching music…';

  @override
  String get netNoNewAudio => 'No new audio here';

  @override
  String get netEnqueueing => 'Adding to download queue…';

  @override
  String get netNothingDownloadable =>
      'Nothing in the selection can be downloaded';

  @override
  String netEnqueuedCount(Object n) {
    return 'Added $n items';
  }

  @override
  String netEnqueueFailedFolders(Object n) {
    return 'Failed for $n folders';
  }

  @override
  String get netJoinSep => ', ';

  @override
  String get netFolder => 'Folder';

  @override
  String get netVideo => 'Video';

  @override
  String get netAudio => 'Audio';

  @override
  String get netFile => 'File';

  @override
  String get netConfirmDeleteTitle => 'Confirm deletion';

  @override
  String netConfirmDeleteMsg(Object name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

  @override
  String get ntfAllDone => 'All downloads complete';

  @override
  String ntfDoneCount(Object done, Object total) {
    return 'Completed $done / $total';
  }

  @override
  String ntfDoneCountPercent(Object done, Object percent, Object total) {
    return 'Overall progress $percent% · Completed $done / $total';
  }

  @override
  String get ntfDoneWithFailures => 'Downloads finished (with failures)';

  @override
  String ntfDownloadingTitle(Object index, Object total) {
    return 'Downloading (item $index / $total)';
  }

  @override
  String get ntfImportanceOff => 'Off';

  @override
  String get ntfImportanceMin => 'Min';

  @override
  String get ntfImportanceLow => 'Low';

  @override
  String get ntfImportanceDefault => 'Default';

  @override
  String get ntfImportanceHigh => 'High';

  @override
  String get ntfImportanceMax => 'Max';

  @override
  String get ntfMediaChannelName => 'Music playback';

  @override
  String get ntfMediaChannelDesc => 'Now-playing music controls';

  @override
  String get ntfStatusBlocked =>
      'Off (re-enable in system notification settings)';

  @override
  String get ntfStatusChecking => 'Checking…';

  @override
  String get ntfStatusCreated => 'Created';

  @override
  String ntfStatusCreatedImportance(Object importance) {
    return 'Created · importance $importance';
  }

  @override
  String get ntfStatusNoChannels => 'No notification channels on this platform';

  @override
  String get ntfStatusNotCreated => 'Not created';

  @override
  String ntfSummaryCancelled(Object count) {
    return 'Cancelled: $count';
  }

  @override
  String ntfSummaryFailed(Object count) {
    return 'Failed: $count';
  }

  @override
  String ntfSummaryOk(Object count) {
    return 'Succeeded: $count';
  }

  @override
  String get ntfSelfTestAndroidOnly => 'Android only';

  @override
  String get ntfSelfTestBlocked =>
      'Notifications for this app are turned off by the system';

  @override
  String get ntfSelfTestBody => 'Test notification · 50% · Completed 0 / 1';

  @override
  String get ntfSelfTestSummary => 'Succeeded: 1 (test)';

  @override
  String libQueuedCount(Object count) {
    return 'Added $count downloads';
  }

  @override
  String libQueuedUnavailable(Object count) {
    return '$count sources unavailable';
  }

  @override
  String get libQueuedAdded => 'Added to downloads';

  @override
  String get cueGroupDeleteTitle => 'Delete the entire CUE cache group?';

  @override
  String get cueGroupDeleteTitleMulti => 'Delete multiple CUE cache groups?';

  @override
  String get cueGroupDeleteBodyIntro => 'This will delete the whole group:';

  @override
  String cueGroupDeleteBodyIntroCount(Object count) {
    return 'This will delete $count CUE groups:';
  }

  @override
  String moreFilesCount(Object count) {
    return '…$count files in total';
  }

  @override
  String get cueGroupDeleteWhole => 'Delete group';

  @override
  String cueGroupDeleted(Object count) {
    return 'Deleted CUE cache group ($count files)';
  }

  @override
  String get cacheDeleteTitle => 'Delete local audio cache?';

  @override
  String cacheDeleteBodyOne(Object name) {
    return 'This will delete the audio cache of \"$name\"; tags and covers are kept.';
  }

  @override
  String cacheDeleteBodyMany(Object count) {
    return 'This will delete $count cache files; tags and covers are kept.';
  }

  @override
  String cacheDeletedCount(Object count) {
    return 'Deleted $count local audio caches';
  }

  @override
  String get destroyTracksTitle => 'Destroy the selected tracks?';

  @override
  String destroyTracksBody(Object count) {
    return 'This will delete $count tracks (cache, library records, metadata, and covers). This cannot be undone.';
  }

  @override
  String get destroyTracksCueNote => '(CUE slices deleted as one group)';

  @override
  String get destroyAction => 'Destroy';

  @override
  String destroyedTracksCount(Object count) {
    return 'Destroyed $count tracks';
  }

  @override
  String get shareCueUnsupported => 'CUE tracks cannot be shared';

  @override
  String get shareCueUnsupportedAndNotLocal =>
      'CUE tracks cannot be shared; the remaining tracks are not downloaded';

  @override
  String get shareNotLocalOne =>
      'This track is not downloaded locally and cannot be shared';

  @override
  String get shareNotLocalAll =>
      'None of the selected tracks are downloaded; nothing to share';

  @override
  String shareCueSkipped(Object count) {
    return 'Skipped $count CUE tracks (not shareable)';
  }

  @override
  String shareNotLocalSkipped(Object count) {
    return 'Skipped $count tracks that are not downloaded';
  }

  @override
  String get shareNothingToShare => 'No files to share';

  @override
  String shareDoneCount(Object count) {
    return 'Shared $count files';
  }

  @override
  String shareFailed(Object reason) {
    return 'Share failed: $reason';
  }

  @override
  String get shareNameTitle => 'Share file name';

  @override
  String get shareRenameTemplateHint =>
      'Empty fields remove extra separators; the extension is always kept.';

  @override
  String get fileNameLabel => 'File name';

  @override
  String shareExtFixed(Object ext) {
    return 'The extension is fixed to $ext';
  }

  @override
  String shareOriginalFile(Object name) {
    return 'Original file: $name';
  }

  @override
  String get shareUseOriginalName => 'Use original name';

  @override
  String get shareAction => 'Share';

  @override
  String get searchPlaceholder => 'Search titles / artists / albums';

  @override
  String get searchAction => 'Search';

  @override
  String get closeSearch => 'Close search';

  @override
  String get sortTooltip => 'Sort';

  @override
  String get tabAlbums => 'Albums';

  @override
  String get tabArtists => 'Artists';

  @override
  String get tabTitles => 'Titles';

  @override
  String get tabGenres => 'Genres';

  @override
  String get libraryNoMatch => 'No matching tracks';

  @override
  String get genreEmpty =>
      'No genres yet: they appear after downloading tracks with genre metadata.';

  @override
  String get noMatchResult => 'No results';

  @override
  String get updateCancelled => 'Cancelled';

  @override
  String get updateDone => 'Update finished';

  @override
  String updateSummary(Object a, Object b, Object c, Object d) {
    return '$a: updated $b, skipped $c, failed $d';
  }

  @override
  String get deleteCacheKeepMeta => 'Delete cache (keep metadata & covers)';

  @override
  String get updateTags => 'Update tags';

  @override
  String get downloadUncachedTracks => 'Download uncached tracks';

  @override
  String get libraryTracksEmpty => 'No tracks yet';

  @override
  String get sourceUnbound => 'Source drive not linked';

  @override
  String downloadingPercent(Object p) {
    return 'Downloading $p%';
  }

  @override
  String get libraryEmptyGuide =>
      'No tracks yet: download music from the Network library first.';

  @override
  String get tagTitle => 'Title';

  @override
  String get tagArtist => 'Artist';

  @override
  String get tagAlbumArtist => 'Album artist';

  @override
  String get tagAlbum => 'Album';

  @override
  String get tagTrack => 'Track';

  @override
  String get tagDisc => 'Disc';

  @override
  String get tagYear => 'Year';

  @override
  String get tagGenre => 'Genre';

  @override
  String get tagDuration => 'Duration';

  @override
  String get tagBitrate => 'Bitrate';

  @override
  String get tagSampleRate => 'Sample rate';

  @override
  String get tagLanguage => 'Language';

  @override
  String get tagLyrics => 'Lyrics';

  @override
  String errShardKindMismatch(Object a, Object b) {
    return 'Shard kind mismatch: file header $a, META kind=$b';
  }

  @override
  String get errNotWdmmFile =>
      'Not a Webdav Media Manager file (missing WDMM marker)';

  @override
  String errAccountNotConnected(Object a) {
    return 'Account not connected: $a';
  }

  @override
  String errBigintOverflow(Object a) {
    return 'BigInt value exceeds $a bytes';
  }

  @override
  String errCloudAccountMissing(Object a) {
    return 'Cloud account does not exist: $a';
  }

  @override
  String get errCloudWriteDisabled =>
      'Cloud accounts do not support upload or cloud write sync';

  @override
  String get errContentRangeUnsupported =>
      'This driver does not support range reads';

  @override
  String get errContentStreamUnsupported =>
      'This driver does not support content stream reading';

  @override
  String get errDriverNotReady => 'Cloud driver is not available yet';

  @override
  String errDriverNotReadyInfo(Object a) {
    return 'Cloud driver is not available yet: $a';
  }

  @override
  String errDownloadSizeUnknown(Object a) {
    return 'Cannot determine the size of “$a”; download cancelled';
  }

  @override
  String get errNeteaseRsaKeyLength =>
      'Netease raw RSA key must be exactly 16 bytes';

  @override
  String errStreamSizeUnknown(Object a) {
    return 'Cannot determine the size of “$a”; streaming is not supported yet';
  }

  @override
  String get errWebdavNotConfigured => 'WebDAV is not configured';

  @override
  String get errWebdavSourceNotConnected =>
      'WebDAV is not connected; cannot fetch source content';

  @override
  String errBaiduDirectLinkFailed(Object a) {
    return 'Failed to get the direct download link: $a';
  }

  @override
  String errBaiduRequestFailed(Object a) {
    return 'Baidu Netdisk request failed: $a';
  }

  @override
  String errBaiduRiskControl(Object a) {
    return '$a Baidu Netdisk risk control (a security policy was triggered; it usually clears automatically within minutes to hours). An invalid or unofficial refresh_token can also trigger this; make sure it was obtained via https://api.oplist.org/.';
  }

  @override
  String errDriver123FileNotFound(Object a) {
    return '123 Cloud file not found: $a';
  }

  @override
  String errDriver123NetworkFailed(Object a) {
    return '[123Open] network request failed: $a';
  }

  @override
  String errDriver123RequestFailed(Object a) {
    return '123 Cloud request failed: $a';
  }

  @override
  String get errMissingRefreshToken =>
      '123 Cloud is missing refresh_token: please fill in refresh_token (see the OpenList official docs, 123_open driver page, for how to get one)';

  @override
  String get errMkdirRoot => 'Cannot create the root directory';

  @override
  String errRefreshOnlineFailed(Object a, Object b) {
    return 'Online API refresh failed (HTTP $a): $b. Make sure the refresh_token is a valid token obtained via https://api.oplist.org/.';
  }

  @override
  String errRefreshOnlineFailedNonJson(Object a) {
    return 'Online API refresh failed (HTTP $a): non-JSON response. Make sure the refresh_token is a valid token obtained via https://api.oplist.org/.';
  }

  @override
  String get errRootOp => 'Cannot perform this operation on the root directory';

  @override
  String get errOpen115MissingRefreshToken =>
      '115 Open requires a refresh_token';

  @override
  String errOpen115RefreshFailed(Object a) {
    return '115 Open token refresh failed ($a); make sure the refresh_token is valid.';
  }

  @override
  String errOpen115ApiError(Object a) {
    return '115 Open API error ($a)';
  }

  @override
  String errOpen115NetworkFailed(Object a) {
    return '115 Open network request failed ($a)';
  }

  @override
  String get errOpen115DownurlEmptyData =>
      '115 Open downurl returned no direct-link data (data is empty)';

  @override
  String get errOpen115DownurlEmptyUrl =>
      '115 Open downurl returned no usable direct link (url.url is empty)';

  @override
  String errOpen115MissingPickCode(Object a) {
    return '115 Open entry is missing pick_code; cannot get the direct link: $a';
  }

  @override
  String errOpen115TokenVerifyFailed(Object a) {
    return '115 Open token verification failed: $a. Make sure the access_token / refresh_token is valid.';
  }

  @override
  String errOpen115NetworkConnectFailed(Object a) {
    return '115 Open network connection failed ($a): proapi.115.com may be unreachable from this deployment environment (datacenter IPs may be blocked by 115); retry later or switch environments.';
  }

  @override
  String errOpen115DirectLinkFailed(Object a) {
    return 'Failed to get the 115 Open direct link: $a';
  }

  @override
  String errOpen115CopyRenameFailed(Object a) {
    return '115 Open copy finished but the copy was not found; cannot rename to $a';
  }

  @override
  String errOpen115FolderNotFound(Object a) {
    return '115 Open folder not found: $a';
  }

  @override
  String errOpen115FileNotFound(Object a) {
    return '115 Open file not found: $a';
  }

  @override
  String errAliyunEntryOrLinkFailed(Object a) {
    return 'Cannot get the entry or direct link: $a';
  }

  @override
  String get errAliyunMissingRefreshToken =>
      'Aliyundrive Open is missing a refresh_token: fill in refresh_token in the account form (see the OpenList docs for the aliyundrive_open driver).';

  @override
  String errAliyunNetworkFailed(Object a) {
    return '[AliyundriveOpen] network request failed $a';
  }

  @override
  String get errAliyunNoDirectLink =>
      '[AliyundriveOpen] getDownloadUrl returned no direct link (url / download_url are both empty)';

  @override
  String get errAliyunNoDriveId =>
      '[AliyundriveOpen] getDriveInfo returned no drive_id (resource / default / backup are all empty): make sure Aliyundrive is enabled for the account.';

  @override
  String errAliyunNonJson(Object a) {
    return 'Non-JSON response: $a';
  }

  @override
  String errAliyunRefreshAllFailed(Object a) {
    return '[AliyundriveOpen] All token refresh strategies failed. Check in order: 1) the refresh_token is valid and not expired; 2) api_url_address is reachable; 3) with direct OAuth, the client_id / client_secret are correct. Attempt log: $a';
  }

  @override
  String errTeraboxRedirectFailed(Object a) {
    return 'TeraBox direct-link redirect failed ($a)';
  }

  @override
  String errTeraboxRequestFailed(Object a) {
    return 'TeraBox request failed $a';
  }

  @override
  String get errTeraboxSignKeyEmpty =>
      'TeraBox signing failed: the sign3 key is empty (upstream /api/home/info returned no sign3)';

  @override
  String errNeteaseApiError(Object a) {
    return 'NetEase Cloud Music API error ($a)';
  }

  @override
  String get errNeteaseCookieRequired =>
      'The Cookie must contain both __csrf and MUSIC_U: log in to music.163.com on the web and copy the full Cookie from developer tools';

  @override
  String get errNeteaseCopyUnsupported =>
      'NetEase Cloud Music does not support copying (upstream driver does not implement this operation)';

  @override
  String errNeteaseFileNotFound(Object a) {
    return 'File not found: $a';
  }

  @override
  String errNeteaseLoginExpired(Object a) {
    return 'NetEase Cloud Music login state has expired ($a). The Cookie may be stale: log in again on the web and update the Cookie';
  }

  @override
  String get errNeteaseMkdirUnsupported =>
      'NetEase Cloud Music does not support creating folders (upstream driver does not implement this operation)';

  @override
  String get errNeteaseMoveUnsupported =>
      'NetEase Cloud Music does not support moving (upstream driver does not implement this operation)';

  @override
  String get errNeteaseNoSongLink =>
      'NetEase Cloud Music returned no play link (the song may be VIP-only, region-restricted, or no longer available)';

  @override
  String errNeteaseNonJson(Object a) {
    return 'NetEase Cloud Music returned a non-JSON response: $a';
  }

  @override
  String get errNeteaseRenameUnsupported =>
      'NetEase Cloud Music does not support renaming (upstream driver does not implement this operation)';

  @override
  String errNeteaseRequestFailed(Object a) {
    return 'NetEase Cloud Music request failed: $a';
  }

  @override
  String get errNeteaseRootDelete =>
      'NetEase Cloud Music does not support deleting the root directory';

  @override
  String errNeteaseUnexpectedStructure(Object a) {
    return 'NetEase Cloud Music returned an unexpected structure: $a';
  }

  @override
  String errNeteaseUnknownCrypto(Object a) {
    return 'Unknown crypto method: $a';
  }

  @override
  String errCryptBadCipherLength(Object a) {
    return 'crypt: invalid ciphertext length: $a';
  }

  @override
  String errCryptBlockDecryptFailed(Object a) {
    return 'crypt: failed to decrypt block $a (content corrupted or key mismatch)';
  }

  @override
  String errCryptBlockRangeDecryptFailed(Object a) {
    return 'crypt: failed to decrypt starting from block $a (content corrupted or key mismatch)';
  }

  @override
  String get errCryptDecryptFailed =>
      'crypt: failed to decrypt content (content corrupted or key mismatch)';

  @override
  String errCryptEarlyEof(Object a, Object b, Object c) {
    return 'crypt: content ended early (from block $a: expected $b bytes, got $c bytes)';
  }

  @override
  String errCryptInvalidConfig(Object a) {
    return 'crypt: invalid configuration: $a';
  }

  @override
  String errCryptLengthMismatch(Object a, Object b) {
    return 'crypt: content length mismatch (expected $a, got $b)';
  }

  @override
  String get errCryptNoDirectLinkAnymore =>
      'crypt: the source no longer provides a direct link; cannot continue decrypting';

  @override
  String get errCryptNoDirectLinkDecrypt =>
      'crypt: the source does not provide a direct link; cannot decrypt content';

  @override
  String get errCryptNoDirectLinkStream =>
      'crypt: the source does not provide a direct link; cannot download sequentially';

  @override
  String get errCryptNoHeader =>
      'crypt: incomplete content (file header could not be read)';

  @override
  String get errCryptNoResponseBody =>
      'crypt: sequential download received no response body';

  @override
  String get errCryptNoSourceName =>
      'crypt: no source account name saved; edit the account again and select a source account';

  @override
  String errCryptNotRcloneFile(Object a) {
    return 'Not a valid rclone encrypted file: $a';
  }

  @override
  String get errCryptSizeUnknown =>
      'Cannot determine the encrypted content size (the source provides no length and does not support Range)';

  @override
  String errCryptSourceMissing(Object a) {
    return 'crypt: the source account \"$a\" does not exist or has been deleted; add an account with the same name again to restore it';
  }

  @override
  String get driverNameBaidu => 'Baidu Netdisk';

  @override
  String get driverName123Open => '123 Cloud Drive (Open)';

  @override
  String get driverName115 => '115 Cloud Drive';

  @override
  String get driverNameAliyunOpen => 'Aliyun Drive (Open Platform)';

  @override
  String get driverNameNetease => 'NetEase Cloud Music';

  @override
  String get driverNameCrypt => 'Crypt encrypted folder';

  @override
  String errRefreshOnlineNon200(Object a) {
    return 'Online renewal API returned HTTP $a';
  }

  @override
  String get formLabelRenewApi => 'Online renewal URL';

  @override
  String get formHintRenewApiDefault =>
      'Uses the public service maintained by OpenList by default';

  @override
  String get formHintLocalRefreshDisabled =>
      'Local refresh is on (online renewal paused); switch it off to edit';

  @override
  String get formLabelLocalRefresh => 'Refresh tokens locally';

  @override
  String get formSubLocalRefreshBaidu =>
      'Off: refresh via the online renewal URL. On: refresh with your own Baidu app (Client ID / Secret); online renewal is paused';

  @override
  String get formSubLocalRefresh123 =>
      'Off: online renewal. On: refresh with your own 123 app (Client ID / Secret); online renewal is paused';

  @override
  String get formSubLocalRefreshAliyun =>
      'Off: poll the online renewal URL. On: refresh directly with your own Aliyun app (Client ID / Secret)';

  @override
  String formHintOpenListDoc(Object a) {
    return 'Required; see the OpenList docs ($a driver page) for how to get it';
  }

  @override
  String get formLabelRootId => 'Root folder ID';

  @override
  String formHintRootIdOpaque(Object a) {
    return 'Opaque id, defaults to $a (drive root); combined with the account remote path';
  }

  @override
  String get formHint115RefreshToken =>
      'Required; see the OpenList docs (115 Open driver page). 115 rotates it on every refresh and saves the rotated value automatically';

  @override
  String get formHint115RootId =>
      'Defaults to 0 (global root); a non-zero folder ID mounts the account under it';

  @override
  String get formLabelPageSize => 'Page size';

  @override
  String get formHintPageSize =>
      'Range 1-1150, default 200 (values beyond are clamped; 115 caps one call at 1150)';

  @override
  String get formLabelRateLimit => 'Rate limit (calls/s)';

  @override
  String get formHintRateLimit =>
      '0 (default) means unlimited; a positive value enforces at least 1/value seconds between API calls';

  @override
  String get formLabelDriveType => 'Drive type';

  @override
  String get formHintDriveType =>
      'Resource / default / backup drive, i.e. different drive_id values under one account';

  @override
  String get optionDriveResource => 'Resource drive';

  @override
  String get optionDriveDefault => 'Default drive';

  @override
  String get optionDriveBackup => 'Backup drive';

  @override
  String get formLabelDeleteMode => 'Delete mode';

  @override
  String get formHintDeleteMode =>
      'Trashed files can be recovered in Aliyun Drive; permanent delete cannot be undone';

  @override
  String get optionDeleteTrash => 'Move to trash';

  @override
  String get optionDeletePermanent => 'Delete permanently';

  @override
  String get formHintTeraboxCookie =>
      'Required; paste the TeraBox Cookie copied from the browser; re-paste when it expires';

  @override
  String get formLabelRootPath => 'Root folder path';

  @override
  String get formHintNeteaseCookie =>
      'Required; must contain __csrf and MUSIC_U. Sign in to music.163.com, then copy the full Cookie from the developer tools (see the OpenList netease_music driver docs)';

  @override
  String get formLabelSongLimit => 'Song limit';

  @override
  String formHintSongLimit(Object a) {
    return 'Default $a; the NetEase cloud-drive API lists up to this many per call';
  }

  @override
  String get formLabelSourceAccount => 'Source account';

  @override
  String get formHintSourceAccount =>
      'Choose an existing WebDAV or cloud-drive account as the encryption source';

  @override
  String get formLabelSourceDir => 'Source folder';

  @override
  String get formHintSourceDir =>
      'Folder under the source account browse root, default / (encrypted files live here)';

  @override
  String get formLabelFilenameEncoding => 'Filename encoding';

  @override
  String get formHintFilenameEncoding =>
      'Matches rclone filename_encoding (base32 / base64 / base32768)';

  @override
  String get formLabelEncryptedSuffix => 'Filename suffix';

  @override
  String get formHintEncryptedSuffix =>
      'Takes effect only when filename encryption is off (OpenList encrypted_suffix)';

  @override
  String get formLabelPassword => 'Password';

  @override
  String get formLabelSalt => 'Salt (optional)';

  @override
  String get formHintSalt =>
      'Leave empty to use the rclone built-in default salt; the same password + salt inter-operates with rclone / OpenList';

  @override
  String get formLabelFilenameEncryption => 'Filename encryption';

  @override
  String get optionCryptStandard => 'Standard (EME)';

  @override
  String get optionCryptObfuscate => 'Obfuscate';

  @override
  String get optionCryptOff => 'Off';

  @override
  String get formLabelDirNameEncryption => 'Folder-name encryption';

  @override
  String get formSubDirNameEncryption =>
      'OpenList keeps it off by default; when on, folder names are encrypted too';

  @override
  String get svcNoLocalCache => 'No local cache. Download it first.';

  @override
  String get svcCacheNotInitialized => 'CacheService is not initialized';

  @override
  String get svcBackupAccountMissingId =>
      'Backup account is missing an id; safe restore aborted';

  @override
  String get svcLocalFileUnavailable => 'Local file is unavailable';

  @override
  String get backupTooShort => 'Backup file is too short or corrupted';

  @override
  String backupNotEncrypted(Object magic) {
    return 'Not an encrypted backup (missing $magic header)';
  }

  @override
  String get backupCiphertextDamaged => 'Backup ciphertext is corrupted';

  @override
  String get vaultCiphertextDamaged => 'Credential ciphertext is corrupted';

  @override
  String get vaultNoteEncrypted =>
      'Password-like fields (including cloud driver tokens) are encrypted with AES-256-GCM; other fields are stored in plain text.';

  @override
  String get vaultNotePlain => 'Password-like fields are stored in plain text.';

  @override
  String get mediaArtistWebdav => 'WebDAV streaming';

  @override
  String ntfProbeHint(Object channel) {
    return ' | If still no notification: Settings→Apps→Webdav Media Manager→Battery=Unrestricted; Notifications=Allowed (incl. lock screen/floating); do not disable the \"$channel\" channel';
  }

  @override
  String get ntfProbeRunning => 'running';

  @override
  String get ntfProbeNone => 'none';

  @override
  String get ntfProbeActive => 'active';

  @override
  String get ntfProbeInactive => 'inactive';

  @override
  String get ntfProbePosted => 'posted';

  @override
  String get ntfProbeNotPosted => 'not posted';

  @override
  String get ntfProbeChanMissing => '(not created)';

  @override
  String get ntfProbeChanBlocked => '(disabled)';

  @override
  String ntfProbeReport(
    Object chanState,
    Object channel,
    Object device,
    Object hint,
    Object importance,
    Object perm,
    Object posted,
    Object session,
    Object sessions,
    Object svc,
  ) {
    return 'service=$svc session=$session notification=$posted system switch=$perm channel=$channel$chanState importance=$importance app sessions=$sessions device=$device$hint';
  }

  @override
  String ntfProbeReturn(Object raw) {
    return 'Probe returned: $raw';
  }

  @override
  String get ntfProbeChannelUnavailable =>
      'Native probe channel unavailable (full APK required)';

  @override
  String ntfProbeFailed(Object message) {
    return 'Probe failed: $message';
  }

  @override
  String ntfForceNoAudio(Object error, Object probe) {
    return 'No local audio available. Play a song first, then tap Test.\n$probe$error';
  }

  @override
  String ntfForcePlayed(
    Object error,
    Object probe,
    Object state,
    Object title,
  ) {
    return 'Force-played \"$title\" playing=$state\n$probe$error\nCheck the notification shade / media control center.';
  }

  @override
  String ntfAsyncError(Object error) {
    return '\n⚠ audio_service bridge error: $error';
  }

  @override
  String get phArtist => 'Artist';

  @override
  String get phTitle => 'Title';

  @override
  String get phAlbum => 'Album';

  @override
  String get phAlbumArtist => 'Album artist';

  @override
  String get phTrack => 'Track number';

  @override
  String get phYear => 'Year';

  @override
  String get phGenre => 'Genre';

  @override
  String get phFileName => 'Original file name';

  @override
  String get videoStreamingHint =>
      'Video streams directly without downloading locally.';

  @override
  String get videoHardwareDecoding => 'Hardware decoding';

  @override
  String get videoHardwareDecodingHint =>
      'Software decoding may be more stable on some devices.';

  @override
  String get videoScanSubdirsHint =>
      'Include videos from subdirectories in the playlist';

  @override
  String get videoBufferSize => 'Buffer size';

  @override
  String get videoBufferInput => 'Buffer (MB)';

  @override
  String get videoGestures => 'Gestures';

  @override
  String get videoGestureLeftDoubleTap => 'Double-tap left';

  @override
  String get videoGestureRightDoubleTap => 'Double-tap right';

  @override
  String get videoGestureLongPress => 'Long press';

  @override
  String get videoLongPressRate => 'Temporary long-press speed';

  @override
  String get videoDefaultRate => 'Default playback speed';

  @override
  String get videoSubtitles => 'Subtitles';

  @override
  String get videoSubtitleHint =>
      'When shown, subtitles appear above the controls; when hidden, they sit at the bottom.';

  @override
  String get videoSubtitleSize => 'Subtitle size';

  @override
  String get videoPlaybackBehavior => 'Playback behavior';

  @override
  String get videoBackgroundPlayback => 'Background playback';

  @override
  String get videoBackgroundPlaybackHint =>
      'Continue playing audio after leaving the player';

  @override
  String get videoPip => 'Picture-in-picture';

  @override
  String get videoPipHint =>
      'Show a picture-in-picture button in the player controls (Android 8+)';

  @override
  String get videoBufferSaved =>
      'Buffer size saved; it takes effect on the next playback.';

  @override
  String videoBufferCurrent(Object current, Object max, Object min) {
    return 'Current $current MB (range $min–$max MB)';
  }

  @override
  String videoLongPressCurrent(Object rate) {
    return 'Hold to speed up to $rate×, release to restore';
  }

  @override
  String videoDefaultRateCurrent(Object max, Object min, Object rate) {
    return 'Current $rate× (range $min×–$max×)';
  }

  @override
  String videoSubtitleSizeCurrent(Object max, Object min, Object size) {
    return 'Current $size sp (range $min–$max sp)';
  }

  @override
  String get accountsSubtitle => 'Manage multiple server accounts';

  @override
  String get audioStreamingSubtitle => 'Streaming toggle / subdirectory scan';

  @override
  String get fileTypesManage => 'File extension management';

  @override
  String get fileTypesManageSubtitle =>
      'Music / video / image / CUE extensions and default actions';

  @override
  String get coverThumbSize => 'Cover thumbnail size';

  @override
  String get coverThumbHint =>
      'New covers use this edge length; existing covers must be regenerated.';

  @override
  String get coverSize => 'Edge (px)';

  @override
  String get cacheCleanup => 'Cache cleanup';

  @override
  String get cacheCleanupHint =>
      'Only audio cache is cleared; playback/downloads, tags, and covers are unaffected.';

  @override
  String get currentCacheUsage => 'Current cache usage';

  @override
  String get calculating => 'Calculating…';

  @override
  String get unknown => 'Unknown';

  @override
  String get refresh => 'Refresh';

  @override
  String get customRetentionHint => 'Custom retention (at least 1 hour)';

  @override
  String get days => 'days';

  @override
  String get hours => 'hours';

  @override
  String get autoCleanupDisabled =>
      'Automatic cleanup is off; use the button below to clear manually.';

  @override
  String get clearAudioCache => 'Clear audio cache manually';

  @override
  String get shareRenameHint => 'Rename shared filenames using tags.';

  @override
  String get shareRenameTitle => 'Rename shares using tags';

  @override
  String get shareRenameSubtitle =>
      'Enabled by default; individual filenames can still be changed';

  @override
  String get renameTemplate => 'Rename template';

  @override
  String get syncSettings => 'Sync and backup settings';

  @override
  String get shareRenameTemplate => 'Share rename template';

  @override
  String get videoPrevious => 'Previous video';

  @override
  String get videoNext => 'Next video';

  @override
  String get videoLockScreen => 'Lock screen';

  @override
  String get videoOrientation => 'Switch orientation';

  @override
  String get videoLockHint =>
      'Hide controls and gestures; long-press to unlock';

  @override
  String get videoOrientationLock => 'Lock orientation';

  @override
  String get videoOrientationLockHint =>
      'Keep the current landscape/portrait orientation';

  @override
  String get videoExitConfirm => 'Confirm when exiting';

  @override
  String get videoExitConfirmHint => 'Confirm before returning';

  @override
  String get videoGestureSettingsHint =>
      'Double-tap / long-press actions and hold speed';

  @override
  String cacheCleared(Object count, Object libraryCount) {
    return 'Cleared $count cache files ($libraryCount metadata entries retained)';
  }

  @override
  String get tagRefreshStarted =>
      'Updating tags for cached tracks in the background';

  @override
  String tagRefreshCompleted(Object failed, Object skipped, Object updated) {
    return 'Tag update complete: $updated updated, $skipped skipped, $failed failed';
  }

  @override
  String get notificationEnabled =>
      'Notifications enabled; media controls will appear during playback';

  @override
  String get notificationOpenSettings =>
      'Allow notifications in system settings, then return to the app';

  @override
  String get notificationOpenSettingsFailed =>
      'Could not open system settings; allow notifications manually';

  @override
  String get notificationGranted => 'Notification permission granted';

  @override
  String get notificationDenied =>
      'Notification permission denied; media controls may be unavailable';

  @override
  String retentionDaysHours(Object days, Object hours) {
    return 'Current: keep audio not accessed for ${days}d ${hours}h';
  }

  @override
  String retentionDays(Object days) {
    return 'Current: keep audio not accessed for ${days}d';
  }

  @override
  String retentionHours(Object hours) {
    return 'Current: keep audio not accessed for ${hours}h';
  }

  @override
  String get notificationChecking => 'Checking…';

  @override
  String get notificationStatusAllowed =>
      'Allowed; media controls appear during playback';

  @override
  String get notificationChannelBlocked =>
      'The music channel is blocked; tap to open system settings';

  @override
  String get notificationStatusDenied => 'Denied; tap to open system settings';

  @override
  String get notificationChannelMissing =>
      'Music channel not created; play once or refresh to retry';

  @override
  String get notificationNotGranted => 'Not granted; tap to request permission';

  @override
  String get hintsAndNotifications => 'Hints and notifications';

  @override
  String get hintsSubtitle =>
      'Only one bottom hint is shown at a time; tap “Got it” to dismiss.';

  @override
  String get hintDuration => 'Hint duration';

  @override
  String get downloadNotifications => 'Download queue notifications';

  @override
  String get downloadNotificationsHint =>
      'Download progress and results appear in notifications';

  @override
  String get sendTestNotification => 'Send test notification';

  @override
  String get sendTestNotificationHint =>
      'Send one progress and one completion notification to diagnose blocking';

  @override
  String get testNotificationSent =>
      'Test notifications sent (one progress and one completion)';

  @override
  String testNotificationFailed(Object error) {
    return 'Test notification failed: $error';
  }

  @override
  String get confirmCloseVideo => 'Close this video?';

  @override
  String get webdavNotConnectedPlay => 'WebDAV is not connected; cannot play';

  @override
  String get videoQueueEmpty => 'There is no play queue';

  @override
  String get pipUnsupported => 'Picture-in-picture is not supported';

  @override
  String videoPlayFailed(Object error) {
    return 'Playback failed: $error';
  }

  @override
  String get scanningFolder => 'Scanning folder…';

  @override
  String get buffering => 'Buffering…';

  @override
  String get opening => 'Opening';

  @override
  String get downloadKeepAlive => 'Keep downloads alive in background';

  @override
  String get downloadKeepAliveHint =>
      'While this is on, a download notification stays in the shade for the whole transfer (required by the system), even if download notifications are turned off.';

  @override
  String get streamingSection => 'Streaming';

  @override
  String get imageViewer => 'Image viewer';

  @override
  String get imageViewerSubtitle => 'Slideshow, fit, and prefetch';

  @override
  String get imageSlideshow => 'Slideshow';

  @override
  String get imageSlideshowHint =>
      'Advance automatically. Turning a page by hand restarts the timer and does not turn this off.';

  @override
  String get imageSlideshowInterval => 'Interval';

  @override
  String imageSlideshowSeconds(Object seconds) {
    return '$seconds s';
  }

  @override
  String get imageSlideshowLoop => 'Loop';

  @override
  String get imageSlideshowLoopHint =>
      'After the last image, return to the first';

  @override
  String get imageFit => 'Fit';

  @override
  String get imageFitContain => 'Contain';

  @override
  String get imageFitCover => 'Cover';

  @override
  String get imagePrefetchCount => 'Prefetch count';

  @override
  String get imagePrefetchHint =>
      'How many images to prefetch on each side (previous and next), from 1 to 5. The whole album is not loaded at once. Default is 1 per side.';

  @override
  String get imageScanSubdirs => 'Scan subdirectories';

  @override
  String get imageScanSubdirsHint =>
      'Off by default. When on, the album also includes images in subfolders. Scanning can be slow.';

  @override
  String get actionViewImage => 'View image';

  @override
  String get actionShortViewImage => 'View';

  @override
  String get fileCatImage => 'Image files';

  @override
  String get catImageFile => 'image file';

  @override
  String get netImage => 'Image';

  @override
  String get imageViewerEmpty => 'No images to view in this folder';

  @override
  String imageLoadFailed(Object error) {
    return 'Could not load this image: $error';
  }

  @override
  String get imageViewerRetry => 'Retry';

  @override
  String get imageViewerGestureHint =>
      'Tap left for previous, right for next, center for settings';

  @override
  String imageViewerCount(Object index, Object total) {
    return '$index / $total';
  }

  @override
  String get imageViewerPrevious => 'Previous';

  @override
  String get imageViewerNext => 'Next';

  @override
  String get imageViewerOpenSettings => 'Image settings';

  @override
  String get imageScanningSubdirs => 'Scanning subdirectories…';

  @override
  String get settingsMisc => 'Miscellaneous';

  @override
  String get settingsThumbnails => 'Thumbnails';

  @override
  String get settingsThumbnailsSubtitle =>
      'Cover thumbnail size; only newly written images change';

  @override
  String get settingsShareSubtitle => 'Rename shared files from tags';

  @override
  String get downloadNomedia => 'Exclude from media scan';

  @override
  String get downloadNomediaSubtitle =>
      'When on, writes .nomedia into the download folder so the media scanner skips it. When off, deletes that file.';

  @override
  String get actionShortGallery => 'Gallery';

  @override
  String get netDownloadToGalleryPictures =>
      'Save to Pictures/WebdavMediaManager';
}
