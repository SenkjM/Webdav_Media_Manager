import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'Webdav Media Manager'**
  String get appTitle;

  /// No description provided for @settings.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In zh_CN, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In zh_CN, this message translates to:
  /// **'跟随系统'**
  String get languageSystem;

  /// No description provided for @languageSimplifiedChinese.
  ///
  /// In zh_CN, this message translates to:
  /// **'简体中文'**
  String get languageSimplifiedChinese;

  /// No description provided for @languageTraditionalChinese.
  ///
  /// In zh_CN, this message translates to:
  /// **'繁体中文'**
  String get languageTraditionalChinese;

  /// No description provided for @languageEnglish.
  ///
  /// In zh_CN, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @webdavServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'WebDAV 服务器'**
  String get webdavServer;

  /// No description provided for @download.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载'**
  String get download;

  /// No description provided for @homeAndNavigation.
  ///
  /// In zh_CN, this message translates to:
  /// **'主页与导航'**
  String get homeAndNavigation;

  /// No description provided for @videoPlayback.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频播放'**
  String get videoPlayback;

  /// No description provided for @fileTypes.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件类型'**
  String get fileTypes;

  /// No description provided for @mediaNotifications.
  ///
  /// In zh_CN, this message translates to:
  /// **'媒体通知'**
  String get mediaNotifications;

  /// No description provided for @languageSettingSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择应用显示语言，重启后仍会保留'**
  String get languageSettingSubtitle;

  /// No description provided for @library.
  ///
  /// In zh_CN, this message translates to:
  /// **'音乐库'**
  String get library;

  /// No description provided for @playlists.
  ///
  /// In zh_CN, this message translates to:
  /// **'歌单'**
  String get playlists;

  /// No description provided for @networkLibrary.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络库'**
  String get networkLibrary;

  /// No description provided for @downloadQueue.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载队列'**
  String get downloadQueue;

  /// No description provided for @aboutAgpl.
  ///
  /// In zh_CN, this message translates to:
  /// **'关于 / AGPL'**
  String get aboutAgpl;

  /// No description provided for @exitApp.
  ///
  /// In zh_CN, this message translates to:
  /// **'退出应用'**
  String get exitApp;

  /// No description provided for @cancel.
  ///
  /// In zh_CN, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @exit.
  ///
  /// In zh_CN, this message translates to:
  /// **'退出'**
  String get exit;

  /// No description provided for @cacheOneDay.
  ///
  /// In zh_CN, this message translates to:
  /// **'1 天'**
  String get cacheOneDay;

  /// No description provided for @cacheOneWeek.
  ///
  /// In zh_CN, this message translates to:
  /// **'1 周'**
  String get cacheOneWeek;

  /// No description provided for @cacheCustom.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义'**
  String get cacheCustom;

  /// No description provided for @cacheNever.
  ///
  /// In zh_CN, this message translates to:
  /// **'永不'**
  String get cacheNever;

  /// No description provided for @snackShort.
  ///
  /// In zh_CN, this message translates to:
  /// **'很短'**
  String get snackShort;

  /// No description provided for @snackNormal.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认'**
  String get snackNormal;

  /// No description provided for @snackLong.
  ///
  /// In zh_CN, this message translates to:
  /// **'较长'**
  String get snackLong;

  /// No description provided for @snackUntilDismissed.
  ///
  /// In zh_CN, this message translates to:
  /// **'点击才消失'**
  String get snackUntilDismissed;

  /// No description provided for @snackOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭'**
  String get snackOff;

  /// No description provided for @syncOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭（仅手动）'**
  String get syncOff;

  /// No description provided for @syncEvery15m.
  ///
  /// In zh_CN, this message translates to:
  /// **'每 15 分钟'**
  String get syncEvery15m;

  /// No description provided for @syncEvery30m.
  ///
  /// In zh_CN, this message translates to:
  /// **'每 30 分钟'**
  String get syncEvery30m;

  /// No description provided for @syncHourly.
  ///
  /// In zh_CN, this message translates to:
  /// **'每 1 小时'**
  String get syncHourly;

  /// No description provided for @syncEvery6h.
  ///
  /// In zh_CN, this message translates to:
  /// **'每 6 小时'**
  String get syncEvery6h;

  /// No description provided for @syncDaily.
  ///
  /// In zh_CN, this message translates to:
  /// **'每 24 小时'**
  String get syncDaily;

  /// No description provided for @actionCacheMusic.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存音乐'**
  String get actionCacheMusic;

  /// No description provided for @actionDownload.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载'**
  String get actionDownload;

  /// No description provided for @actionStream.
  ///
  /// In zh_CN, this message translates to:
  /// **'流式传输'**
  String get actionStream;

  /// No description provided for @actionReadCue.
  ///
  /// In zh_CN, this message translates to:
  /// **'CUE 读取'**
  String get actionReadCue;

  /// No description provided for @actionStreamMusic.
  ///
  /// In zh_CN, this message translates to:
  /// **'流式传输（音乐）'**
  String get actionStreamMusic;

  /// No description provided for @actionShortCache.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存'**
  String get actionShortCache;

  /// No description provided for @actionShortDownload.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载'**
  String get actionShortDownload;

  /// No description provided for @actionShortStream.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放'**
  String get actionShortStream;

  /// No description provided for @actionShortCue.
  ///
  /// In zh_CN, this message translates to:
  /// **'CUE'**
  String get actionShortCue;

  /// No description provided for @actionShortStreamMusic.
  ///
  /// In zh_CN, this message translates to:
  /// **'流播'**
  String get actionShortStreamMusic;

  /// No description provided for @targetCache.
  ///
  /// In zh_CN, this message translates to:
  /// **'应用缓存'**
  String get targetCache;

  /// No description provided for @targetGallery.
  ///
  /// In zh_CN, this message translates to:
  /// **'系统相册'**
  String get targetGallery;

  /// No description provided for @targetDownloads.
  ///
  /// In zh_CN, this message translates to:
  /// **'系统下载目录'**
  String get targetDownloads;

  /// No description provided for @musicModeSingle.
  ///
  /// In zh_CN, this message translates to:
  /// **'单曲循环'**
  String get musicModeSingle;

  /// No description provided for @musicModeSequential.
  ///
  /// In zh_CN, this message translates to:
  /// **'顺序播放'**
  String get musicModeSequential;

  /// No description provided for @musicModeLoop.
  ///
  /// In zh_CN, this message translates to:
  /// **'列表循环'**
  String get musicModeLoop;

  /// No description provided for @playbackMode.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放模式'**
  String get playbackMode;

  /// No description provided for @unboundSource.
  ///
  /// In zh_CN, this message translates to:
  /// **'未绑定网盘「{sourceName}」'**
  String unboundSource(Object sourceName);

  /// No description provided for @uncategorized.
  ///
  /// In zh_CN, this message translates to:
  /// **'未分类'**
  String get uncategorized;

  /// No description provided for @unnamedPlaylist.
  ///
  /// In zh_CN, this message translates to:
  /// **'未命名歌单'**
  String get unnamedPlaylist;

  /// No description provided for @defaultServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认服务器'**
  String get defaultServer;

  /// No description provided for @accountsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'网盘账号'**
  String get accountsTitle;

  /// No description provided for @noAccounts.
  ///
  /// In zh_CN, this message translates to:
  /// **'尚未添加账号。点击右下角添加。'**
  String get noAccounts;

  /// No description provided for @setCurrent.
  ///
  /// In zh_CN, this message translates to:
  /// **'设为当前'**
  String get setCurrent;

  /// No description provided for @edit.
  ///
  /// In zh_CN, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @testConnection.
  ///
  /// In zh_CN, this message translates to:
  /// **'测试连接'**
  String get testConnection;

  /// No description provided for @delete.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @connectionSuccess.
  ///
  /// In zh_CN, this message translates to:
  /// **'连接成功'**
  String get connectionSuccess;

  /// No description provided for @connectionFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'连接失败'**
  String get connectionFailed;

  /// No description provided for @deleteServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除服务器'**
  String get deleteServer;

  /// No description provided for @confirmDeleteServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'确定删除「{name}」？其曲目会变成「未绑定网盘」，加回同名即可恢复。'**
  String confirmDeleteServer(Object name);

  /// No description provided for @audioStreamingTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频流式'**
  String get audioStreamingTitle;

  /// No description provided for @streamPlayback.
  ///
  /// In zh_CN, this message translates to:
  /// **'流式播放'**
  String get streamPlayback;

  /// No description provided for @streamPlaybackHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'音乐不下载到本地，直接从网盘边听边传。'**
  String get streamPlaybackHint;

  /// No description provided for @streamMusic.
  ///
  /// In zh_CN, this message translates to:
  /// **'流式传输音乐'**
  String get streamMusic;

  /// No description provided for @streamMusicHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'打开后音乐的文件动作里可以选「流式传输（音乐）」。关掉时该动作会被退回默认。'**
  String get streamMusicHint;

  /// No description provided for @scanList.
  ///
  /// In zh_CN, this message translates to:
  /// **'列表扫描'**
  String get scanList;

  /// No description provided for @scanListHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'决定流式播放的「上一首 / 下一首」列表里都有什么。'**
  String get scanListHint;

  /// No description provided for @scanSubdirectories.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索子目录'**
  String get scanSubdirectories;

  /// No description provided for @scanSubdirectoriesHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'打开：当前目录及其所有子目录里的音频都进列表。关闭：只列当前这一层。'**
  String get scanSubdirectoriesHint;

  /// No description provided for @downloadPending.
  ///
  /// In zh_CN, this message translates to:
  /// **'等待中'**
  String get downloadPending;

  /// No description provided for @downloadActive.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载中'**
  String get downloadActive;

  /// No description provided for @downloadCompleted.
  ///
  /// In zh_CN, this message translates to:
  /// **'已完成'**
  String get downloadCompleted;

  /// No description provided for @downloadFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'失败'**
  String get downloadFailed;

  /// No description provided for @downloadCancelled.
  ///
  /// In zh_CN, this message translates to:
  /// **'已取消'**
  String get downloadCancelled;

  /// No description provided for @downloadAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部下载'**
  String get downloadAll;

  /// No description provided for @wakeWaiting.
  ///
  /// In zh_CN, this message translates to:
  /// **'唤醒等待中任务'**
  String get wakeWaiting;

  /// No description provided for @cancelAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部取消'**
  String get cancelAll;

  /// No description provided for @clearCompleted.
  ///
  /// In zh_CN, this message translates to:
  /// **'清除已完成'**
  String get clearCompleted;

  /// No description provided for @more.
  ///
  /// In zh_CN, this message translates to:
  /// **'更多'**
  String get more;

  /// No description provided for @noDownloadTasks.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无下载任务'**
  String get noDownloadTasks;

  /// No description provided for @queueCleared.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载队列已清空'**
  String get queueCleared;

  /// No description provided for @clearAllQueue.
  ///
  /// In zh_CN, this message translates to:
  /// **'清除所有队列'**
  String get clearAllQueue;

  /// No description provided for @cueAlbum.
  ///
  /// In zh_CN, this message translates to:
  /// **'CUE 专辑'**
  String get cueAlbum;

  /// No description provided for @songCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'{count} 首歌'**
  String songCount(Object count);

  /// No description provided for @inProgress.
  ///
  /// In zh_CN, this message translates to:
  /// **'进行中'**
  String get inProgress;

  /// No description provided for @retrying.
  ///
  /// In zh_CN, this message translates to:
  /// **'重试中（{current}/{max}）'**
  String retrying(Object current, Object max);

  /// No description provided for @retry.
  ///
  /// In zh_CN, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @clearQueueConfirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'清除队列？'**
  String get clearQueueConfirm;

  /// No description provided for @clearQueueDetails.
  ///
  /// In zh_CN, this message translates to:
  /// **'将移除 {count} 条队列记录{runningText}；已下载的文件保留。'**
  String clearQueueDetails(Object count, Object runningText);

  /// No description provided for @runningDownloads.
  ///
  /// In zh_CN, this message translates to:
  /// **'，并取消 {count} 个进行中的下载'**
  String runningDownloads(Object count);

  /// No description provided for @clearAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'清除全部'**
  String get clearAll;

  /// No description provided for @accountAddServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加服务器'**
  String get accountAddServer;

  /// No description provided for @accountEditServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'编辑服务器'**
  String get accountEditServer;

  /// No description provided for @accountName.
  ///
  /// In zh_CN, this message translates to:
  /// **'名称'**
  String get accountName;

  /// No description provided for @accountNameHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'曲库按此名称绑定，必须唯一；改名等同换盘'**
  String get accountNameHint;

  /// No description provided for @accountNameTaken.
  ///
  /// In zh_CN, this message translates to:
  /// **'该名称已被占用，建议换一个'**
  String get accountNameTaken;

  /// No description provided for @accountType.
  ///
  /// In zh_CN, this message translates to:
  /// **'类型'**
  String get accountType;

  /// No description provided for @accountRemotePath.
  ///
  /// In zh_CN, this message translates to:
  /// **'远程路径'**
  String get accountRemotePath;

  /// No description provided for @accountRemotePathHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'浏览根，默认 /（空置也是 /）'**
  String get accountRemotePathHint;

  /// No description provided for @accountServerUrl.
  ///
  /// In zh_CN, this message translates to:
  /// **'服务器 URL'**
  String get accountServerUrl;

  /// No description provided for @accountUsername.
  ///
  /// In zh_CN, this message translates to:
  /// **'用户名'**
  String get accountUsername;

  /// No description provided for @accountPassword.
  ///
  /// In zh_CN, this message translates to:
  /// **'密码'**
  String get accountPassword;

  /// No description provided for @accountPasswordKeep.
  ///
  /// In zh_CN, this message translates to:
  /// **'密码（留空则不修改）'**
  String get accountPasswordKeep;

  /// No description provided for @accountPermissions.
  ///
  /// In zh_CN, this message translates to:
  /// **'权限'**
  String get accountPermissions;

  /// No description provided for @permissionRead.
  ///
  /// In zh_CN, this message translates to:
  /// **'读取'**
  String get permissionRead;

  /// No description provided for @permissionWrite.
  ///
  /// In zh_CN, this message translates to:
  /// **'写入'**
  String get permissionWrite;

  /// No description provided for @permissionCreateFolder.
  ///
  /// In zh_CN, this message translates to:
  /// **'创建文件夹'**
  String get permissionCreateFolder;

  /// No description provided for @permissionMove.
  ///
  /// In zh_CN, this message translates to:
  /// **'移动'**
  String get permissionMove;

  /// No description provided for @permissionCopy.
  ///
  /// In zh_CN, this message translates to:
  /// **'复制'**
  String get permissionCopy;

  /// No description provided for @permissionDelete.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除'**
  String get permissionDelete;

  /// No description provided for @accountFillName.
  ///
  /// In zh_CN, this message translates to:
  /// **'请填写名称'**
  String get accountFillName;

  /// No description provided for @accountUnknownProvider.
  ///
  /// In zh_CN, this message translates to:
  /// **'未知云盘类型：{providerType}'**
  String accountUnknownProvider(Object providerType);

  /// No description provided for @accountFillField.
  ///
  /// In zh_CN, this message translates to:
  /// **'请填写 {label}'**
  String accountFillField(Object label);

  /// No description provided for @accountSelectField.
  ///
  /// In zh_CN, this message translates to:
  /// **'请选择 {label}'**
  String accountSelectField(Object label);

  /// No description provided for @accountValidationFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'验证失败：{error}'**
  String accountValidationFailed(Object error);

  /// No description provided for @accountSave.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存'**
  String get accountSave;

  /// No description provided for @accountAdded.
  ///
  /// In zh_CN, this message translates to:
  /// **'成功添加（{name}）'**
  String accountAdded(Object name);

  /// No description provided for @accountDuplicateTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'名称已被占用'**
  String get accountDuplicateTitle;

  /// No description provided for @accountDuplicateContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'已有同名网盘「{name}」：\n{url}\n\n同名会被当成同一来源。'**
  String accountDuplicateContent(Object name, Object url);

  /// No description provided for @accountChangeName.
  ///
  /// In zh_CN, this message translates to:
  /// **'改个名字'**
  String get accountChangeName;

  /// No description provided for @accountKeepName.
  ///
  /// In zh_CN, this message translates to:
  /// **'仍然使用'**
  String get accountKeepName;

  /// No description provided for @accountRenameTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'改名等同于换盘'**
  String get accountRenameTitle;

  /// No description provided for @accountUsernameChangedTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'用户名已修改'**
  String get accountUsernameChangedTitle;

  /// No description provided for @accountRenameContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'「{name}」的曲目将变为「未绑定网盘」，改回原名即可恢复。\n仅改地址时请保持名称不变。'**
  String accountRenameContent(Object name);

  /// No description provided for @accountUsernameChangedContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'用户名不参与绑定；新用户名对应别的目录时原路径可能不存在。'**
  String get accountUsernameChangedContent;

  /// No description provided for @accountConfirmChange.
  ///
  /// In zh_CN, this message translates to:
  /// **'确认修改'**
  String get accountConfirmChange;

  /// No description provided for @accountBindingHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'曲目按「名称 + 路径」绑定；改名等同于换盘。'**
  String get accountBindingHint;

  /// No description provided for @manageAccounts.
  ///
  /// In zh_CN, this message translates to:
  /// **'管理多服务器账号'**
  String get manageAccounts;

  /// No description provided for @manageAccountsSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加 / 编辑 / 删除 WebDAV 服务器'**
  String get manageAccountsSubtitle;

  /// No description provided for @downloadQueueSettings.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载队列'**
  String get downloadQueueSettings;

  /// No description provided for @downloadQueueSettingsSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'断点续传的临时文件保留上限与清理'**
  String get downloadQueueSettingsSubtitle;

  /// No description provided for @customHome.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义主页'**
  String get customHome;

  /// No description provided for @customHomeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'从其他界面返回时回到此主页'**
  String get customHomeSubtitle;

  /// No description provided for @rememberNetworkPath.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络库记住上次路径'**
  String get rememberNetworkPath;

  /// No description provided for @rememberNetworkPathSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'下次进入网络库时恢复上次浏览的目录'**
  String get rememberNetworkPathSubtitle;

  /// No description provided for @videoSettings.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频播放设置'**
  String get videoSettings;

  /// No description provided for @videoSettingsSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'流式参数 / 手势 / 后台播放 / 画中画'**
  String get videoSettingsSubtitle;

  /// No description provided for @audioSettings.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频流式设置'**
  String get audioSettings;

  /// No description provided for @audioSettingsSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'流式传输开关 / 搜索子目录'**
  String get audioSettingsSubtitle;

  /// No description provided for @fileExtensionSettings.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件后缀管理'**
  String get fileExtensionSettings;

  /// No description provided for @fileExtensionSettingsSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'音乐 / 视频 / CUE 后缀与默认操作'**
  String get fileExtensionSettingsSubtitle;

  /// No description provided for @refreshLibraryTags.
  ///
  /// In zh_CN, this message translates to:
  /// **'手动更新音乐库标签'**
  String get refreshLibraryTags;

  /// No description provided for @refreshLibraryTagsSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'异步读取已缓存音乐文件的标签并更新曲库'**
  String get refreshLibraryTagsSubtitle;

  /// No description provided for @networkNewFolder.
  ///
  /// In zh_CN, this message translates to:
  /// **'新建文件夹'**
  String get networkNewFolder;

  /// No description provided for @manageServers.
  ///
  /// In zh_CN, this message translates to:
  /// **'管理服务器'**
  String get manageServers;

  /// No description provided for @currentServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前服务器'**
  String get currentServer;

  /// No description provided for @networkRetry.
  ///
  /// In zh_CN, this message translates to:
  /// **'重试'**
  String get networkRetry;

  /// No description provided for @emptyDirectory.
  ///
  /// In zh_CN, this message translates to:
  /// **'空目录'**
  String get emptyDirectory;

  /// No description provided for @directory.
  ///
  /// In zh_CN, this message translates to:
  /// **'目录'**
  String get directory;

  /// No description provided for @cueFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'CUE 文件'**
  String get cueFile;

  /// No description provided for @playVideo.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放视频'**
  String get playVideo;

  /// No description provided for @moreActions.
  ///
  /// In zh_CN, this message translates to:
  /// **'更多操作'**
  String get moreActions;

  /// No description provided for @cancelSelection.
  ///
  /// In zh_CN, this message translates to:
  /// **'取消全选'**
  String get cancelSelection;

  /// No description provided for @selectAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'全选'**
  String get selectAll;

  /// No description provided for @cacheMusic.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存音乐'**
  String get cacheMusic;

  /// No description provided for @copyTo.
  ///
  /// In zh_CN, this message translates to:
  /// **'复制到'**
  String get copyTo;

  /// No description provided for @moveTo.
  ///
  /// In zh_CN, this message translates to:
  /// **'移动到'**
  String get moveTo;

  /// No description provided for @downloadAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载'**
  String get downloadAction;

  /// No description provided for @fileQueuedOrSaved.
  ///
  /// In zh_CN, this message translates to:
  /// **'该文件已在下载队列或已下载'**
  String get fileQueuedOrSaved;

  /// No description provided for @fileQueuedOrSavedShort.
  ///
  /// In zh_CN, this message translates to:
  /// **'该文件已在队列或已保存'**
  String get fileQueuedOrSavedShort;

  /// No description provided for @accountRequired.
  ///
  /// In zh_CN, this message translates to:
  /// **'请先添加 WebDAV 服务器'**
  String get accountRequired;

  /// No description provided for @syncTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'同步与备份'**
  String get syncTitle;

  /// No description provided for @syncIntro.
  ///
  /// In zh_CN, this message translates to:
  /// **'凭证、歌单与音乐库共用一条远端路径：在下面选网盘、填路径即可。'**
  String get syncIntro;

  /// No description provided for @syncAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部同步'**
  String get syncAll;

  /// No description provided for @scheduledSync.
  ///
  /// In zh_CN, this message translates to:
  /// **'定时同步'**
  String get scheduledSync;

  /// No description provided for @manualOnly.
  ///
  /// In zh_CN, this message translates to:
  /// **'已关闭，仅手动同步'**
  String get manualOnly;

  /// No description provided for @autoSync.
  ///
  /// In zh_CN, this message translates to:
  /// **'{interval} 自动同步'**
  String autoSync(Object interval);

  /// No description provided for @remotePath.
  ///
  /// In zh_CN, this message translates to:
  /// **'远端路径'**
  String get remotePath;

  /// No description provided for @remotePathSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'凭证、音乐库、歌单与备份都放在这条路径下面'**
  String get remotePathSubtitle;

  /// No description provided for @selectServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'① 选择网盘'**
  String get selectServer;

  /// No description provided for @path.
  ///
  /// In zh_CN, this message translates to:
  /// **'② 路径'**
  String get path;

  /// No description provided for @pathExample.
  ///
  /// In zh_CN, this message translates to:
  /// **'例如填 /player，音乐库就在 /player/library/'**
  String get pathExample;

  /// No description provided for @apply.
  ///
  /// In zh_CN, this message translates to:
  /// **'应用'**
  String get apply;

  /// No description provided for @encryptionKey.
  ///
  /// In zh_CN, this message translates to:
  /// **'统一加密密钥（由你指定）'**
  String get encryptionKey;

  /// No description provided for @encryptionKeyHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'只保存在本机；留空则以明文存储。'**
  String get encryptionKeyHint;

  /// No description provided for @keyNotSet.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前：未设置（凭证与备份里的密码为明文）'**
  String get keyNotSet;

  /// No description provided for @keySet.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前：已设置（长度 {length}）'**
  String keySet(Object length);

  /// No description provided for @saveKey.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存密钥'**
  String get saveKey;

  /// No description provided for @keySaved.
  ///
  /// In zh_CN, this message translates to:
  /// **'加密密钥已保存到本机'**
  String get keySaved;

  /// No description provided for @operationFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'操作失败：{error}'**
  String operationFailed(Object error);

  /// No description provided for @rebuildThreshold.
  ///
  /// In zh_CN, this message translates to:
  /// **'重建提示阈值'**
  String get rebuildThreshold;

  /// No description provided for @cloudFragmentCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'云端分片数'**
  String get cloudFragmentCount;

  /// No description provided for @rebuildThresholdHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'达到这个数量时提示重建（2–500）'**
  String get rebuildThresholdHint;

  /// No description provided for @confirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'确定'**
  String get confirm;

  /// No description provided for @exitConfirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'确定退出？播放将停止。'**
  String get exitConfirm;

  /// No description provided for @menu.
  ///
  /// In zh_CN, this message translates to:
  /// **'菜单'**
  String get menu;

  /// No description provided for @aboutTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'关于'**
  String get aboutTitle;

  /// No description provided for @aboutVersion.
  ///
  /// In zh_CN, this message translates to:
  /// **'版本 {version}'**
  String aboutVersion(Object version);

  /// No description provided for @aboutCiVersion.
  ///
  /// In zh_CN, this message translates to:
  /// **'CI 预发布写入 versionName（含短 hash）与递增 versionCode，可覆盖安装。'**
  String get aboutCiVersion;

  /// No description provided for @aboutDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'浏览网盘目录，下载到本地缓存后播放。'**
  String get aboutDescription;

  /// No description provided for @aboutCredits.
  ///
  /// In zh_CN, this message translates to:
  /// **'作者与致谢'**
  String get aboutCredits;

  /// No description provided for @aboutImplementation.
  ///
  /// In zh_CN, this message translates to:
  /// **'实现：Grok Bot'**
  String get aboutImplementation;

  /// No description provided for @aboutConcept.
  ///
  /// In zh_CN, this message translates to:
  /// **'创意与需求框架：SenkjM'**
  String get aboutConcept;

  /// No description provided for @aboutLicense.
  ///
  /// In zh_CN, this message translates to:
  /// **'许可证'**
  String get aboutLicense;

  /// No description provided for @aboutLicenseText.
  ///
  /// In zh_CN, this message translates to:
  /// **'本项目采用 GNU Affero General Public License v3.0（AGPL-3.0）授权。\\n\\n你可以自由使用、修改与分发本软件，但若发布修改版，或通过网络提供基于本软件的服务，必须按 AGPL-3.0 公开对应完整源代码。完整文本见仓库 LICENSE 文件。'**
  String get aboutLicenseText;

  /// No description provided for @fileExtSaved.
  ///
  /// In zh_CN, this message translates to:
  /// **'后缀配置已保存'**
  String get fileExtSaved;

  /// No description provided for @fileExtIntro.
  ///
  /// In zh_CN, this message translates to:
  /// **'按后缀识别文件类型；多个后缀用空格或逗号分隔。返回网络库刷新后生效。下面每一类的「单击行为」就是网络库点按该文件时的动作，多选工具栏与「更多」菜单遵循同一套判定。'**
  String get fileExtIntro;

  /// No description provided for @fileCatMusic.
  ///
  /// In zh_CN, this message translates to:
  /// **'音乐文件'**
  String get fileCatMusic;

  /// No description provided for @fileCatVideo.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频文件'**
  String get fileCatVideo;

  /// No description provided for @fileCatCue.
  ///
  /// In zh_CN, this message translates to:
  /// **'CUE 文件'**
  String get fileCatCue;

  /// No description provided for @fileCatOther.
  ///
  /// In zh_CN, this message translates to:
  /// **'普通文件'**
  String get fileCatOther;

  /// No description provided for @fileExtDefaultAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'点按默认动作：{action}'**
  String fileExtDefaultAction(Object action);

  /// No description provided for @fileExtCueNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'点按默认动作：{action}（CUE 读取会解析分片并整组下载）'**
  String fileExtCueNote(Object action);

  /// No description provided for @fileExtOtherNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'点按默认动作：{action}（不在上面三张列表里的后缀，下载到系统下载目录）'**
  String fileExtOtherNote(Object action);

  /// No description provided for @fileExtTapAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'点按行为'**
  String get fileExtTapAction;

  /// No description provided for @fileExtHintExample.
  ///
  /// In zh_CN, this message translates to:
  /// **'例如：mp3 flac m4a'**
  String get fileExtHintExample;

  /// No description provided for @fileExtListLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'后缀列表'**
  String get fileExtListLabel;

  /// No description provided for @restoreDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'恢复默认'**
  String get restoreDefault;

  /// No description provided for @dlPartFilesTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'断点续传的临时文件'**
  String get dlPartFilesTitle;

  /// No description provided for @dlPartFilesIntro.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络中断重试时会从半截文件接着下。文件留着才续得上，所以这里配的是上限：超过上限的部分会被自动清掉（没有对应下载任务的孤儿文件也会清）。'**
  String get dlPartFilesIntro;

  /// No description provided for @dlRetainDuration.
  ///
  /// In zh_CN, this message translates to:
  /// **'保留时长'**
  String get dlRetainDuration;

  /// No description provided for @unitHours.
  ///
  /// In zh_CN, this message translates to:
  /// **'小时'**
  String get unitHours;

  /// No description provided for @dlTotalSizeLimit.
  ///
  /// In zh_CN, this message translates to:
  /// **'总体积上限'**
  String get dlTotalSizeLimit;

  /// No description provided for @dlCryptSequential.
  ///
  /// In zh_CN, this message translates to:
  /// **'Crypt 顺序流'**
  String get dlCryptSequential;

  /// No description provided for @dlCryptSequentialSub.
  ///
  /// In zh_CN, this message translates to:
  /// **'仅影响下载任务，在线播放和传统续传不变'**
  String get dlCryptSequentialSub;

  /// No description provided for @dlCleanNow.
  ///
  /// In zh_CN, this message translates to:
  /// **'立即清理'**
  String get dlCleanNow;

  /// No description provided for @dlCleanNowSub.
  ///
  /// In zh_CN, this message translates to:
  /// **'按上面的上限删掉过期的半截文件'**
  String get dlCleanNowSub;

  /// No description provided for @dlNothingToClean.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有需要清理的半截文件'**
  String get dlNothingToClean;

  /// No description provided for @dlCleanedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已清理 {count} 个半截文件'**
  String dlCleanedCount(Object count);

  /// No description provided for @dlFieldNotNumber.
  ///
  /// In zh_CN, this message translates to:
  /// **'{field}请填数字'**
  String dlFieldNotNumber(Object field);

  /// No description provided for @dlFieldClamped.
  ///
  /// In zh_CN, this message translates to:
  /// **'{field}只能在 {min}~{max}{unit} 之间，已按 {value} 保存'**
  String dlFieldClamped(
    Object field,
    Object max,
    Object min,
    Object unit,
    Object value,
  );

  /// No description provided for @dlRangeHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'范围 {min} ~ {max} {unit}，超范围按边界保存'**
  String dlRangeHint(Object max, Object min, Object unit);

  /// No description provided for @playlistQueueEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前播放列表为空'**
  String get playlistQueueEmpty;

  /// No description provided for @playlistQueueDefaultName.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放列表 {month}/{day}'**
  String playlistQueueDefaultName(Object day, Object month);

  /// No description provided for @playlistCreateFromQueue.
  ///
  /// In zh_CN, this message translates to:
  /// **'从当前播放列表创建'**
  String get playlistCreateFromQueue;

  /// No description provided for @playlistCreateFromQueueBody.
  ///
  /// In zh_CN, this message translates to:
  /// **'复制当前队列 {count} 首到新歌单。'**
  String playlistCreateFromQueueBody(Object count);

  /// No description provided for @playlistNameLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'歌单名称'**
  String get playlistNameLabel;

  /// No description provided for @create.
  ///
  /// In zh_CN, this message translates to:
  /// **'创建'**
  String get create;

  /// No description provided for @playlistCreated.
  ///
  /// In zh_CN, this message translates to:
  /// **'已创建歌单「{name}」'**
  String playlistCreated(Object name);

  /// No description provided for @playlistNew.
  ///
  /// In zh_CN, this message translates to:
  /// **'新建歌单'**
  String get playlistNew;

  /// No description provided for @nameLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'名称'**
  String get nameLabel;

  /// No description provided for @playlistsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'歌单'**
  String get playlistsTitle;

  /// No description provided for @playlistSyncTooltip.
  ///
  /// In zh_CN, this message translates to:
  /// **'从 WebDAV 同步'**
  String get playlistSyncTooltip;

  /// No description provided for @playlistSynced.
  ///
  /// In zh_CN, this message translates to:
  /// **'已同步歌单'**
  String get playlistSynced;

  /// No description provided for @playlistSyncFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'同步失败：{error}'**
  String playlistSyncFailed(Object error);

  /// No description provided for @playlistsEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无歌单：右上角「+」新建，或在音乐库长按曲目添加。'**
  String get playlistsEmpty;

  /// No description provided for @playlistTrackCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'{count} 首'**
  String playlistTrackCount(Object count);

  /// No description provided for @playlistRename.
  ///
  /// In zh_CN, this message translates to:
  /// **'重命名歌单'**
  String get playlistRename;

  /// No description provided for @save.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @playlistDelete.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除歌单'**
  String get playlistDelete;

  /// No description provided for @playlistDeleteConfirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'确定删除「{name}」？本地与 WebDAV 上的对应文件都会删除。'**
  String playlistDeleteConfirm(Object name);

  /// No description provided for @rename.
  ///
  /// In zh_CN, this message translates to:
  /// **'重命名'**
  String get rename;

  /// No description provided for @playlistNewEllipsis.
  ///
  /// In zh_CN, this message translates to:
  /// **'新建歌单…'**
  String get playlistNewEllipsis;

  /// No description provided for @playlistAddTo.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加到歌单'**
  String get playlistAddTo;

  /// No description provided for @playlistAdded.
  ///
  /// In zh_CN, this message translates to:
  /// **'已添加到歌单'**
  String get playlistAdded;

  /// No description provided for @playlistAddMany.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加 {count} 首到歌单'**
  String playlistAddMany(Object count);

  /// No description provided for @playlistAddedMany.
  ///
  /// In zh_CN, this message translates to:
  /// **'已添加 {count} 首到歌单'**
  String playlistAddedMany(Object count);

  /// No description provided for @playlistNotFound.
  ///
  /// In zh_CN, this message translates to:
  /// **'歌单不存在'**
  String get playlistNotFound;

  /// No description provided for @playlistAddFromLibrary.
  ///
  /// In zh_CN, this message translates to:
  /// **'从音乐库添加'**
  String get playlistAddFromLibrary;

  /// No description provided for @playlistEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'歌单为空，可从音乐库添加。'**
  String get playlistEmpty;

  /// No description provided for @playlistMissingInLibrary.
  ///
  /// In zh_CN, this message translates to:
  /// **'库中暂无 · {name}'**
  String playlistMissingInLibrary(Object name);

  /// No description provided for @libraryEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'音乐库中没有曲目'**
  String get libraryEmpty;

  /// No description provided for @notDownloaded.
  ///
  /// In zh_CN, this message translates to:
  /// **'未下载'**
  String get notDownloaded;

  /// No description provided for @downloaded.
  ///
  /// In zh_CN, this message translates to:
  /// **'已下载'**
  String get downloaded;

  /// No description provided for @tapToDownload.
  ///
  /// In zh_CN, this message translates to:
  /// **'点按加入下载'**
  String get tapToDownload;

  /// No description provided for @streamNotConnected.
  ///
  /// In zh_CN, this message translates to:
  /// **'WebDAV 未连接，无法流式播放'**
  String get streamNotConnected;

  /// No description provided for @playlistSheetTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放列表'**
  String get playlistSheetTitle;

  /// No description provided for @searchList.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索列表'**
  String get searchList;

  /// No description provided for @noMatchingTracks.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有匹配的曲目'**
  String get noMatchingTracks;

  /// No description provided for @streamUrlFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'无法建立流式地址，请检查账户配置'**
  String get streamUrlFailed;

  /// No description provided for @loading.
  ///
  /// In zh_CN, this message translates to:
  /// **'加载中…'**
  String get loading;

  /// No description provided for @back.
  ///
  /// In zh_CN, this message translates to:
  /// **'返回'**
  String get back;

  /// No description provided for @streamingNotCached.
  ///
  /// In zh_CN, this message translates to:
  /// **'流式传输 · 未缓存'**
  String get streamingNotCached;

  /// No description provided for @seekSeconds.
  ///
  /// In zh_CN, this message translates to:
  /// **'{seconds} 秒'**
  String seekSeconds(Object seconds);

  /// No description provided for @previousTrack.
  ///
  /// In zh_CN, this message translates to:
  /// **'上一首'**
  String get previousTrack;

  /// No description provided for @pause.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂停'**
  String get pause;

  /// No description provided for @play.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放'**
  String get play;

  /// No description provided for @nextTrack.
  ///
  /// In zh_CN, this message translates to:
  /// **'下一首'**
  String get nextTrack;

  /// No description provided for @playbackFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放失败：{error}'**
  String playbackFailed(Object error);

  /// No description provided for @newFolder.
  ///
  /// In zh_CN, this message translates to:
  /// **'新建文件夹'**
  String get newFolder;

  /// No description provided for @close.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @parentFolder.
  ///
  /// In zh_CN, this message translates to:
  /// **'上一级'**
  String get parentFolder;

  /// No description provided for @pickThisFolder.
  ///
  /// In zh_CN, this message translates to:
  /// **'到此文件夹'**
  String get pickThisFolder;

  /// No description provided for @noSubfolders.
  ///
  /// In zh_CN, this message translates to:
  /// **'这个目录里没有子文件夹'**
  String get noSubfolders;

  /// No description provided for @movedItems.
  ///
  /// In zh_CN, this message translates to:
  /// **'已移动 {count} 项'**
  String movedItems(Object count);

  /// No description provided for @copiedItems.
  ///
  /// In zh_CN, this message translates to:
  /// **'已复制 {count} 项'**
  String copiedItems(Object count);

  /// No description provided for @failedWith.
  ///
  /// In zh_CN, this message translates to:
  /// **'失败：{reason}'**
  String failedWith(Object reason);

  /// No description provided for @movePartialResult.
  ///
  /// In zh_CN, this message translates to:
  /// **'成功 {done} 项，失败 {failed} 项：{reason}'**
  String movePartialResult(Object done, Object failed, Object reason);

  /// No description provided for @nowPlayingQueueTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前播放列表'**
  String get nowPlayingQueueTitle;

  /// No description provided for @nowPlayingQueueCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前播放列表（{count}）'**
  String nowPlayingQueueCount(Object count);

  /// No description provided for @nowPlayingQueueEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前没有播放队列。\n从音乐库或网络库开始播放后会出现在此。'**
  String get nowPlayingQueueEmpty;

  /// No description provided for @playerChipAlbumArtist.
  ///
  /// In zh_CN, this message translates to:
  /// **'专辑艺人 · {artist}'**
  String playerChipAlbumArtist(Object artist);

  /// No description provided for @playerChipTrackNumber.
  ///
  /// In zh_CN, this message translates to:
  /// **'曲目 {n}/{total}'**
  String playerChipTrackNumber(Object n, Object total);

  /// No description provided for @playerChipTrackNoTotal.
  ///
  /// In zh_CN, this message translates to:
  /// **'曲目 {n}'**
  String playerChipTrackNoTotal(Object n);

  /// No description provided for @playerChipDiscNumber.
  ///
  /// In zh_CN, this message translates to:
  /// **'碟 {n}/{total}'**
  String playerChipDiscNumber(Object n, Object total);

  /// No description provided for @playerChipDiscNoTotal.
  ///
  /// In zh_CN, this message translates to:
  /// **'碟 {n}'**
  String playerChipDiscNoTotal(Object n);

  /// No description provided for @playerRowAccount.
  ///
  /// In zh_CN, this message translates to:
  /// **'账号'**
  String get playerRowAccount;

  /// No description provided for @playerRowServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'服务器'**
  String get playerRowServer;

  /// No description provided for @playerRowRemotePath.
  ///
  /// In zh_CN, this message translates to:
  /// **'远程路径'**
  String get playerRowRemotePath;

  /// No description provided for @playerRowFileName.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件名'**
  String get playerRowFileName;

  /// No description provided for @playerRowType.
  ///
  /// In zh_CN, this message translates to:
  /// **'类型'**
  String get playerRowType;

  /// No description provided for @playerRowCueNoteKey.
  ///
  /// In zh_CN, this message translates to:
  /// **'说明'**
  String get playerRowCueNoteKey;

  /// No description provided for @playerRowCueNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'来自 CUE 分片，播放与缓存共用源音频。'**
  String get playerRowCueNote;

  /// No description provided for @playerRowCueFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'CUE 文件'**
  String get playerRowCueFile;

  /// No description provided for @playerRowSourceAudio.
  ///
  /// In zh_CN, this message translates to:
  /// **'源音频'**
  String get playerRowSourceAudio;

  /// No description provided for @playerRowCueTrackIndex.
  ///
  /// In zh_CN, this message translates to:
  /// **'CUE 曲序'**
  String get playerRowCueTrackIndex;

  /// No description provided for @playerClipEnd.
  ///
  /// In zh_CN, this message translates to:
  /// **'结尾'**
  String get playerClipEnd;

  /// No description provided for @playerRowClipRange.
  ///
  /// In zh_CN, this message translates to:
  /// **'分片区间'**
  String get playerRowClipRange;

  /// No description provided for @playerRowLocalCache.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地缓存'**
  String get playerRowLocalCache;

  /// No description provided for @playerNotDownloaded.
  ///
  /// In zh_CN, this message translates to:
  /// **'未下载'**
  String get playerNotDownloaded;

  /// No description provided for @playerRowFileSize.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件大小'**
  String get playerRowFileSize;

  /// No description provided for @playerFileDetails.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件详情'**
  String get playerFileDetails;

  /// No description provided for @copyAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'复制全部'**
  String get copyAll;

  /// No description provided for @copiedToClipboard.
  ///
  /// In zh_CN, this message translates to:
  /// **'已复制到剪贴板'**
  String get copiedToClipboard;

  /// No description provided for @copiedKey.
  ///
  /// In zh_CN, this message translates to:
  /// **'已复制：{key}'**
  String copiedKey(Object key);

  /// No description provided for @tagsUpdatedFromLocal.
  ///
  /// In zh_CN, this message translates to:
  /// **'已从本地文件更新标签'**
  String get tagsUpdatedFromLocal;

  /// No description provided for @tagsNeedDownloadFirst.
  ///
  /// In zh_CN, this message translates to:
  /// **'该曲目尚未缓存，请先下载后再更新标签'**
  String get tagsNeedDownloadFirst;

  /// No description provided for @updateThisTrackTags.
  ///
  /// In zh_CN, this message translates to:
  /// **'更新此曲标签'**
  String get updateThisTrackTags;

  /// No description provided for @nowPlaying.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在播放'**
  String get nowPlaying;

  /// No description provided for @noTrackSelected.
  ///
  /// In zh_CN, this message translates to:
  /// **'未选择曲目'**
  String get noTrackSelected;

  /// No description provided for @dlSavedToGallery.
  ///
  /// In zh_CN, this message translates to:
  /// **'已存入系统相册'**
  String get dlSavedToGallery;

  /// No description provided for @dlTargetGallery.
  ///
  /// In zh_CN, this message translates to:
  /// **'目标：系统相册'**
  String get dlTargetGallery;

  /// No description provided for @dlSavedToDownloads.
  ///
  /// In zh_CN, this message translates to:
  /// **'已存入下载目录'**
  String get dlSavedToDownloads;

  /// No description provided for @dlTargetDownloads.
  ///
  /// In zh_CN, this message translates to:
  /// **'目标：下载目录'**
  String get dlTargetDownloads;

  /// No description provided for @rebuildHintThreshold.
  ///
  /// In zh_CN, this message translates to:
  /// **'重建提示阈值'**
  String get rebuildHintThreshold;

  /// No description provided for @cloudFragmentCountLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'云端分片数'**
  String get cloudFragmentCountLabel;

  /// No description provided for @cloudFragmentCountHelper.
  ///
  /// In zh_CN, this message translates to:
  /// **'达到这个数量时提示重建（2–500）'**
  String get cloudFragmentCountHelper;

  /// No description provided for @unifiedEncryptionKey.
  ///
  /// In zh_CN, this message translates to:
  /// **'统一加密密钥（由你指定）'**
  String get unifiedEncryptionKey;

  /// No description provided for @unifiedEncryptionKeyHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'只保存在本机；留空则以明文存储。'**
  String get unifiedEncryptionKeyHint;

  /// No description provided for @keyNotSetLong.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前：未设置（凭证与备份里的密码为明文）'**
  String get keyNotSetLong;

  /// No description provided for @keySetLong.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前：已设置（长度 {length}）'**
  String keySetLong(Object length);

  /// No description provided for @keySavedNotice.
  ///
  /// In zh_CN, this message translates to:
  /// **'加密密钥已保存到本机'**
  String get keySavedNotice;

  /// No description provided for @overwriteLibraryTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'从云端覆写音乐库'**
  String get overwriteLibraryTitle;

  /// No description provided for @overwriteLibraryBody.
  ///
  /// In zh_CN, this message translates to:
  /// **'会从云端下载音乐库数据库并覆写本地。'**
  String get overwriteLibraryBody;

  /// No description provided for @overwriteLibraryNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地索引、标签与尚未同步的改动会被云端那份替换；已下载的音频、封面与缓存不会删除。'**
  String get overwriteLibraryNote;

  /// No description provided for @overwriteLibraryAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'覆写'**
  String get overwriteLibraryAction;

  /// No description provided for @overwriteLibraryPhrase.
  ///
  /// In zh_CN, this message translates to:
  /// **'如果确认覆写请输入 YES'**
  String get overwriteLibraryPhrase;

  /// No description provided for @destroyLibraryTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'销毁音乐库'**
  String get destroyLibraryTitle;

  /// No description provided for @destroyLibraryBody.
  ///
  /// In zh_CN, this message translates to:
  /// **'会逐条销毁本地音乐库：每一首的缓存音频、封面与库记录都会被删除，并各留一条墓碑。'**
  String get destroyLibraryBody;

  /// No description provided for @destroyLibraryNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除记录会在下次同步时上传到云端，云端重建也恢复不了这次销毁的内容。此操作后会关闭自动同步。'**
  String get destroyLibraryNote;

  /// No description provided for @destroyLibraryAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'销毁'**
  String get destroyLibraryAction;

  /// No description provided for @destroyLibraryPhrase.
  ///
  /// In zh_CN, this message translates to:
  /// **'如果确认销毁请输入 YES'**
  String get destroyLibraryPhrase;

  /// No description provided for @destroyLibraryDone.
  ///
  /// In zh_CN, this message translates to:
  /// **'已销毁 {count} 首；下次同步上传删除记录，定时同步已关闭'**
  String destroyLibraryDone(Object count);

  /// No description provided for @readCloudLibraryFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'读取云端库失败：{error}'**
  String readCloudLibraryFailed(Object error);

  /// No description provided for @tidyCloudLibraryTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'整理云端音乐库'**
  String get tidyCloudLibraryTitle;

  /// No description provided for @missingFragments.
  ///
  /// In zh_CN, this message translates to:
  /// **'有分片缺失，只能重建。'**
  String get missingFragments;

  /// No description provided for @missingFragmentName.
  ///
  /// In zh_CN, this message translates to:
  /// **'• 缺 {name}'**
  String missingFragmentName(Object name);

  /// No description provided for @orphanFiles.
  ///
  /// In zh_CN, this message translates to:
  /// **'孤儿文件：清单没引用，可删除。'**
  String get orphanFiles;

  /// No description provided for @auditHealthy.
  ///
  /// In zh_CN, this message translates to:
  /// **'一切一致，无需处理。'**
  String get auditHealthy;

  /// No description provided for @deleteOrphans.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除孤儿文件'**
  String get deleteOrphans;

  /// No description provided for @rebuildFromLocal.
  ///
  /// In zh_CN, this message translates to:
  /// **'以本机为准重建'**
  String get rebuildFromLocal;

  /// No description provided for @orphansDeleted.
  ///
  /// In zh_CN, this message translates to:
  /// **'已删除 {count} 个孤儿文件'**
  String orphansDeleted(Object count);

  /// No description provided for @restoreConfirmTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'确认恢复'**
  String get restoreConfirmTitle;

  /// No description provided for @restoreConfirmBody.
  ///
  /// In zh_CN, this message translates to:
  /// **'将用备份覆盖本机账号凭证、音乐库与歌单，不可撤销。'**
  String get restoreConfirmBody;

  /// No description provided for @restore.
  ///
  /// In zh_CN, this message translates to:
  /// **'恢复'**
  String get restore;

  /// No description provided for @exportedTo.
  ///
  /// In zh_CN, this message translates to:
  /// **'已导出到{location}：{fileName}'**
  String exportedTo(Object fileName, Object location);

  /// No description provided for @exportFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'导出失败：{error}'**
  String exportFailed(Object error);

  /// No description provided for @pickFileFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择文件失败：{error}'**
  String pickFileFailed(Object error);

  /// No description provided for @pasteBase64First.
  ///
  /// In zh_CN, this message translates to:
  /// **'请先粘贴备份内容（Base64）'**
  String get pasteBase64First;

  /// No description provided for @remoteRootUpdated.
  ///
  /// In zh_CN, this message translates to:
  /// **'远端路径已更新：{path}'**
  String remoteRootUpdated(Object path);

  /// No description provided for @derivedPathCredentials.
  ///
  /// In zh_CN, this message translates to:
  /// **'账号凭证'**
  String get derivedPathCredentials;

  /// No description provided for @derivedPathPlaylists.
  ///
  /// In zh_CN, this message translates to:
  /// **'歌单'**
  String get derivedPathPlaylists;

  /// No description provided for @derivedPathLibrary.
  ///
  /// In zh_CN, this message translates to:
  /// **'音乐库'**
  String get derivedPathLibrary;

  /// No description provided for @derivedPathBackups.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部备份'**
  String get derivedPathBackups;

  /// No description provided for @syncAndBackup.
  ///
  /// In zh_CN, this message translates to:
  /// **'同步与备份'**
  String get syncAndBackup;

  /// No description provided for @syncIntroLong.
  ///
  /// In zh_CN, this message translates to:
  /// **'凭证、歌单与音乐库共用一条远端路径：在下面选网盘、填路径即可。'**
  String get syncIntroLong;

  /// No description provided for @scheduledSyncOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'已关闭，仅手动同步'**
  String get scheduledSyncOff;

  /// No description provided for @scheduledSyncAuto.
  ///
  /// In zh_CN, this message translates to:
  /// **'{interval} 自动同步'**
  String scheduledSyncAuto(Object interval);

  /// No description provided for @remotePathSubtitleLong.
  ///
  /// In zh_CN, this message translates to:
  /// **'凭证、歌单、音乐库与备份都放在这条路径下面'**
  String get remotePathSubtitleLong;

  /// No description provided for @needWebdavServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'请先添加 WebDAV 服务器。'**
  String get needWebdavServer;

  /// No description provided for @selectCloudDrive.
  ///
  /// In zh_CN, this message translates to:
  /// **'① 选择网盘'**
  String get selectCloudDrive;

  /// No description provided for @pathStep.
  ///
  /// In zh_CN, this message translates to:
  /// **'② 路径'**
  String get pathStep;

  /// No description provided for @pathExampleLong.
  ///
  /// In zh_CN, this message translates to:
  /// **'例如填 /player，音乐库就在 /player/library/'**
  String get pathExampleLong;

  /// No description provided for @credentialsSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'账号凭证'**
  String get credentialsSection;

  /// No description provided for @credentialsSectionDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'云端 {path}：全部网盘账号；密码类字段加密，不支持类型的账号恢复时自动跳过。'**
  String credentialsSectionDesc(Object path);

  /// No description provided for @encryptPasswordField.
  ///
  /// In zh_CN, this message translates to:
  /// **'加密密码类字段'**
  String get encryptPasswordField;

  /// No description provided for @encryptPasswordOn.
  ///
  /// In zh_CN, this message translates to:
  /// **'口令不匹配时密码留空'**
  String get encryptPasswordOn;

  /// No description provided for @encryptPasswordOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'明文保存密码'**
  String get encryptPasswordOff;

  /// No description provided for @lastAutoScan.
  ///
  /// In zh_CN, this message translates to:
  /// **'上次自动扫描：{time}'**
  String lastAutoScan(Object time);

  /// No description provided for @uploadCredentials.
  ///
  /// In zh_CN, this message translates to:
  /// **'上传凭证'**
  String get uploadCredentials;

  /// No description provided for @downloadCredentials.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载凭证'**
  String get downloadCredentials;

  /// No description provided for @playlistsSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'歌单'**
  String get playlistsSection;

  /// No description provided for @playlistsSectionDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'双向 M3U8 同步，改动即时上传：{path}'**
  String playlistsSectionDesc(Object path);

  /// No description provided for @syncPlaylistsNow.
  ///
  /// In zh_CN, this message translates to:
  /// **'立即同步歌单'**
  String get syncPlaylistsNow;

  /// No description provided for @librarySection.
  ///
  /// In zh_CN, this message translates to:
  /// **'音乐库'**
  String get librarySection;

  /// No description provided for @librarySectionDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'{path}index.json 清单 + lib/seg/del 分片；只传变化，删除在重建时落实。'**
  String librarySectionDesc(Object path);

  /// No description provided for @cloudFragmentsLine.
  ///
  /// In zh_CN, this message translates to:
  /// **'云端分片：{count} 个（约 {size}）{hint}'**
  String cloudFragmentsLine(Object count, Object hint, Object size);

  /// No description provided for @cloudFragmentsHint.
  ///
  /// In zh_CN, this message translates to:
  /// **' · 建议重建'**
  String get cloudFragmentsHint;

  /// No description provided for @syncAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'同步'**
  String get syncAction;

  /// No description provided for @rebuildAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'重建'**
  String get rebuildAction;

  /// No description provided for @tidyAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'整理'**
  String get tidyAction;

  /// No description provided for @rebuildHintNow.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前云端分片 {count} 个，达到 {target} 个时提示重建'**
  String rebuildHintNow(Object count, Object target);

  /// No description provided for @rebuildHintTarget.
  ///
  /// In zh_CN, this message translates to:
  /// **'云端分片达到 {target} 个时提示重建'**
  String rebuildHintTarget(Object target);

  /// No description provided for @customThreshold.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义…'**
  String get customThreshold;

  /// No description provided for @customThresholdValue.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义（{count}）'**
  String customThresholdValue(Object count);

  /// No description provided for @allBackupsSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部备份'**
  String get allBackupsSection;

  /// No description provided for @allBackupsSectionDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'把凭证 + 音乐库 + 歌单写成一个归档到 {path}。'**
  String allBackupsSectionDesc(Object path);

  /// No description provided for @startBackup.
  ///
  /// In zh_CN, this message translates to:
  /// **'开始备份'**
  String get startBackup;

  /// No description provided for @readBackupsUnderPath.
  ///
  /// In zh_CN, this message translates to:
  /// **'读取该路径下的备份'**
  String get readBackupsUnderPath;

  /// No description provided for @backupToRestore.
  ///
  /// In zh_CN, this message translates to:
  /// **'要恢复的备份'**
  String get backupToRestore;

  /// No description provided for @restoreFromSelectedBackup.
  ///
  /// In zh_CN, this message translates to:
  /// **'从所选备份恢复'**
  String get restoreFromSelectedBackup;

  /// No description provided for @localImportExportSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地导入导出'**
  String get localImportExportSection;

  /// No description provided for @localImportExportDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'导出、导入同样使用上面那把密钥。'**
  String get localImportExportDesc;

  /// No description provided for @exportToDownloads.
  ///
  /// In zh_CN, this message translates to:
  /// **'导出到系统下载目录'**
  String get exportToDownloads;

  /// No description provided for @exportReadableJson.
  ///
  /// In zh_CN, this message translates to:
  /// **'导出可读 JSON（排障，不含封面）'**
  String get exportReadableJson;

  /// No description provided for @importFromLocalFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'从本地文件导入…'**
  String get importFromLocalFile;

  /// No description provided for @pasteBase64Label.
  ///
  /// In zh_CN, this message translates to:
  /// **'或粘贴备份内容（Base64）'**
  String get pasteBase64Label;

  /// No description provided for @importFromPaste.
  ///
  /// In zh_CN, this message translates to:
  /// **'从粘贴内容导入'**
  String get importFromPaste;

  /// No description provided for @processing.
  ///
  /// In zh_CN, this message translates to:
  /// **'处理中…'**
  String get processing;

  /// No description provided for @rebuildCloudLibraryTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'重建云端音乐库'**
  String get rebuildCloudLibraryTitle;

  /// No description provided for @rebuildCloudLibraryDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'以本机为准重写全部分片，并落实删除。'**
  String get rebuildCloudLibraryDesc;

  /// No description provided for @tracksPerShard.
  ///
  /// In zh_CN, this message translates to:
  /// **'每个分片包含歌曲数'**
  String get tracksPerShard;

  /// No description provided for @embedCoversInShards.
  ///
  /// In zh_CN, this message translates to:
  /// **'把封面缩略图写进分片'**
  String get embedCoversInShards;

  /// No description provided for @embedCoversInShardsDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'每首歌独立存一份，不去重；关闭则云端不含封面'**
  String get embedCoversInShardsDesc;

  /// No description provided for @estimating.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在估算…'**
  String get estimating;

  /// No description provided for @estimateUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'估算不可用'**
  String get estimateUnavailable;

  /// No description provided for @fileExtTapBehavior.
  ///
  /// In zh_CN, this message translates to:
  /// **'点按行为'**
  String get fileExtTapBehavior;

  /// No description provided for @readBackupsListFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'读取备份列表失败：{error}'**
  String readBackupsListFailed(Object error);

  /// No description provided for @trackStateQueued.
  ///
  /// In zh_CN, this message translates to:
  /// **'排队'**
  String get trackStateQueued;

  /// No description provided for @trackStateDownloading.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载中'**
  String get trackStateDownloading;

  /// No description provided for @trackStateReady.
  ///
  /// In zh_CN, this message translates to:
  /// **'就绪'**
  String get trackStateReady;

  /// No description provided for @trackStatePlaying.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放中'**
  String get trackStatePlaying;

  /// No description provided for @trackStateError.
  ///
  /// In zh_CN, this message translates to:
  /// **'错误'**
  String get trackStateError;

  /// No description provided for @playQueueTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放列表'**
  String get playQueueTitle;

  /// No description provided for @webdavErrorPerm.
  ///
  /// In zh_CN, this message translates to:
  /// **'权限错误'**
  String get webdavErrorPerm;

  /// No description provided for @webdavErrorGeneric.
  ///
  /// In zh_CN, this message translates to:
  /// **'操作失败'**
  String get webdavErrorGeneric;

  /// No description provided for @dialogOk.
  ///
  /// In zh_CN, this message translates to:
  /// **'确定'**
  String get dialogOk;

  /// No description provided for @destroyInProgress.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在销毁'**
  String get destroyInProgress;

  /// No description provided for @processedOfTotal.
  ///
  /// In zh_CN, this message translates to:
  /// **'已处理 {processed} / {total} 首'**
  String processedOfTotal(Object processed, Object total);

  /// No description provided for @destroyStopHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'「终止」或直接返回都会停在当前这首之后；已经销毁的不会恢复。'**
  String get destroyStopHint;

  /// No description provided for @actionStop.
  ///
  /// In zh_CN, this message translates to:
  /// **'终止'**
  String get actionStop;

  /// No description provided for @tagRefreshInProgress.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在更新标签'**
  String get tagRefreshInProgress;

  /// No description provided for @tagRefreshStopHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'只读取本地缓存；终止后保留已更新的曲目。'**
  String get tagRefreshStopHint;

  /// No description provided for @tagRefreshPreparing.
  ///
  /// In zh_CN, this message translates to:
  /// **'准备中'**
  String get tagRefreshPreparing;

  /// No description provided for @recoveryTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'需要恢复本地数据'**
  String get recoveryTitle;

  /// No description provided for @recoveryHeading.
  ///
  /// In zh_CN, this message translates to:
  /// **'数据库初始化失败'**
  String get recoveryHeading;

  /// No description provided for @recoveryBody.
  ///
  /// In zh_CN, this message translates to:
  /// **'请先导出全部本地数据库，再清除并重新进入应用。'**
  String get recoveryBody;

  /// No description provided for @recoveryNothingToExport.
  ///
  /// In zh_CN, this message translates to:
  /// **'未找到可导出的本地数据库'**
  String get recoveryNothingToExport;

  /// No description provided for @recoveryExportedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已导出 {ok} / {count} 个数据库文件到下载目录'**
  String recoveryExportedCount(Object count, Object ok);

  /// No description provided for @recoveryExportFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'导出失败：{error}'**
  String recoveryExportFailed(Object error);

  /// No description provided for @recoveryClearTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'清除本地数据库？'**
  String get recoveryClearTitle;

  /// No description provided for @recoveryClearContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'建议先导出数据库。清除后请重新打开应用，网盘账号和本地索引需要重新配置。'**
  String get recoveryClearContent;

  /// No description provided for @recoveryClearedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已清除 {count} 个数据库文件，请重新打开应用'**
  String recoveryClearedCount(Object count);

  /// No description provided for @recoveryExportAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'导出全部本地数据库'**
  String get recoveryExportAll;

  /// No description provided for @recoveryClearAndExit.
  ///
  /// In zh_CN, this message translates to:
  /// **'清除并退出'**
  String get recoveryClearAndExit;

  /// No description provided for @recoveryClearAndReenter.
  ///
  /// In zh_CN, this message translates to:
  /// **'清除数据并重新进入'**
  String get recoveryClearAndReenter;

  /// No description provided for @dialogCancel.
  ///
  /// In zh_CN, this message translates to:
  /// **'取消'**
  String get dialogCancel;

  /// No description provided for @fileActionIsFolder.
  ///
  /// In zh_CN, this message translates to:
  /// **'这是文件夹，不能按文件动作处理'**
  String get fileActionIsFolder;

  /// No description provided for @fileActionNotApplicable.
  ///
  /// In zh_CN, this message translates to:
  /// **'「{action}」不适用于{category}'**
  String fileActionNotApplicable(Object action, Object category);

  /// No description provided for @fileActionNotApplicableGeneric.
  ///
  /// In zh_CN, this message translates to:
  /// **'该动作不适用于这个文件'**
  String get fileActionNotApplicableGeneric;

  /// No description provided for @catMusicFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'音乐文件'**
  String get catMusicFile;

  /// No description provided for @catVideoFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频文件'**
  String get catVideoFile;

  /// No description provided for @catCueFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'CUE 文件'**
  String get catCueFile;

  /// No description provided for @catOtherFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'普通文件'**
  String get catOtherFile;

  /// No description provided for @videoGestureNone.
  ///
  /// In zh_CN, this message translates to:
  /// **'无操作'**
  String get videoGestureNone;

  /// No description provided for @videoGestureBack10s.
  ///
  /// In zh_CN, this message translates to:
  /// **'后退 10 秒'**
  String get videoGestureBack10s;

  /// No description provided for @videoGestureForward10s.
  ///
  /// In zh_CN, this message translates to:
  /// **'前进 10 秒'**
  String get videoGestureForward10s;

  /// No description provided for @videoGestureBack30s.
  ///
  /// In zh_CN, this message translates to:
  /// **'后退 30 秒'**
  String get videoGestureBack30s;

  /// No description provided for @videoGestureForward30s.
  ///
  /// In zh_CN, this message translates to:
  /// **'前进 30 秒'**
  String get videoGestureForward30s;

  /// No description provided for @videoGestureHoldSpeedUp.
  ///
  /// In zh_CN, this message translates to:
  /// **'长按临时加速（松手恢复）'**
  String get videoGestureHoldSpeedUp;

  /// No description provided for @videoGesturePlayPause.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放 / 暂停'**
  String get videoGesturePlayPause;

  /// No description provided for @videoSubtitleVisible.
  ///
  /// In zh_CN, this message translates to:
  /// **'显示字幕'**
  String get videoSubtitleVisible;

  /// No description provided for @videoSubtitleHidden.
  ///
  /// In zh_CN, this message translates to:
  /// **'不显示'**
  String get videoSubtitleHidden;

  /// No description provided for @videoTapOpen.
  ///
  /// In zh_CN, this message translates to:
  /// **'打开视频'**
  String get videoTapOpen;

  /// No description provided for @videoTapDownload.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载'**
  String get videoTapDownload;

  /// No description provided for @musicTapDownload.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载音乐'**
  String get musicTapDownload;

  /// No description provided for @musicTapPlayCached.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放（已缓存则播放，否则下载）'**
  String get musicTapPlayCached;

  /// No description provided for @libSortByName.
  ///
  /// In zh_CN, this message translates to:
  /// **'按名称'**
  String get libSortByName;

  /// No description provided for @libSortByAlbumTrack.
  ///
  /// In zh_CN, this message translates to:
  /// **'按曲序'**
  String get libSortByAlbumTrack;

  /// No description provided for @cueMultiSliceLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'多歌曲合并分片'**
  String get cueMultiSliceLabel;

  /// No description provided for @artistUnknown.
  ///
  /// In zh_CN, this message translates to:
  /// **'未知艺术家'**
  String get artistUnknown;

  /// No description provided for @albumUnknown.
  ///
  /// In zh_CN, this message translates to:
  /// **'未知专辑'**
  String get albumUnknown;

  /// No description provided for @snackGotIt.
  ///
  /// In zh_CN, this message translates to:
  /// **'知道了'**
  String get snackGotIt;

  /// No description provided for @rootFolder.
  ///
  /// In zh_CN, this message translates to:
  /// **'根目录'**
  String get rootFolder;

  /// No description provided for @folderPickerTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'{purpose}：{folder}'**
  String folderPickerTitle(Object folder, Object purpose);

  /// No description provided for @webdavErrorPermDetail.
  ///
  /// In zh_CN, this message translates to:
  /// **'权限不足或未授权（401/403）'**
  String get webdavErrorPermDetail;

  /// No description provided for @itemWithMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'{name}：{message}'**
  String itemWithMessage(Object message, Object name);

  /// No description provided for @accountWithName.
  ///
  /// In zh_CN, this message translates to:
  /// **'{name}（{user}）'**
  String accountWithName(Object name, Object user);

  /// No description provided for @labelValuePair.
  ///
  /// In zh_CN, this message translates to:
  /// **'{label}：{value}'**
  String labelValuePair(Object label, Object value);

  /// No description provided for @syncOperationFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'操作失败：{error}'**
  String syncOperationFailed(Object error);

  /// No description provided for @syncUnknownError.
  ///
  /// In zh_CN, this message translates to:
  /// **'未知错误'**
  String get syncUnknownError;

  /// No description provided for @syncNoChanges.
  ///
  /// In zh_CN, this message translates to:
  /// **'无变更'**
  String get syncNoChanges;

  /// No description provided for @syncListSep.
  ///
  /// In zh_CN, this message translates to:
  /// **'；'**
  String get syncListSep;

  /// No description provided for @syncNotePrefix.
  ///
  /// In zh_CN, this message translates to:
  /// **'注意：'**
  String get syncNotePrefix;

  /// No description provided for @nameJoiner.
  ///
  /// In zh_CN, this message translates to:
  /// **'、'**
  String get nameJoiner;

  /// No description provided for @progressPreparing.
  ///
  /// In zh_CN, this message translates to:
  /// **'准备中…'**
  String get progressPreparing;

  /// No description provided for @progressDone.
  ///
  /// In zh_CN, this message translates to:
  /// **'完成'**
  String get progressDone;

  /// No description provided for @progressScanningCloudCredentials.
  ///
  /// In zh_CN, this message translates to:
  /// **'扫描云端凭证…'**
  String get progressScanningCloudCredentials;

  /// No description provided for @progressScanningPlaylists.
  ///
  /// In zh_CN, this message translates to:
  /// **'扫描歌单…'**
  String get progressScanningPlaylists;

  /// No description provided for @progressUploadingCredentials.
  ///
  /// In zh_CN, this message translates to:
  /// **'上传凭证…'**
  String get progressUploadingCredentials;

  /// No description provided for @progressDownloadingCredentials.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载凭证…'**
  String get progressDownloadingCredentials;

  /// No description provided for @progressMergingPlaylists.
  ///
  /// In zh_CN, this message translates to:
  /// **'合并歌单…'**
  String get progressMergingPlaylists;

  /// No description provided for @progressReadingCloudIndex.
  ///
  /// In zh_CN, this message translates to:
  /// **'读取云端曲库索引…'**
  String get progressReadingCloudIndex;

  /// No description provided for @progressAdoptingCloudTracks.
  ///
  /// In zh_CN, this message translates to:
  /// **'采纳云端 {count} 首…'**
  String progressAdoptingCloudTracks(Object count);

  /// No description provided for @progressUploadingTombstones.
  ///
  /// In zh_CN, this message translates to:
  /// **'上传 {count} 条删除记录…'**
  String progressUploadingTombstones(Object count);

  /// No description provided for @progressAppendingSegments.
  ///
  /// In zh_CN, this message translates to:
  /// **'追加 {count} 首到云端增量分片…'**
  String progressAppendingSegments(Object count);

  /// No description provided for @progressUploadingFullShards.
  ///
  /// In zh_CN, this message translates to:
  /// **'上传完整曲库分片…'**
  String get progressUploadingFullShards;

  /// No description provided for @progressPackingBackup.
  ///
  /// In zh_CN, this message translates to:
  /// **'打包凭证 / 音乐库 / 歌单…'**
  String get progressPackingBackup;

  /// No description provided for @progressDownloadingRestore.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载并恢复…'**
  String get progressDownloadingRestore;

  /// No description provided for @progressGeneratingBackup.
  ///
  /// In zh_CN, this message translates to:
  /// **'生成备份…'**
  String get progressGeneratingBackup;

  /// No description provided for @progressWritingDownloads.
  ///
  /// In zh_CN, this message translates to:
  /// **'写入下载目录…'**
  String get progressWritingDownloads;

  /// No description provided for @progressUnpackingRestore.
  ///
  /// In zh_CN, this message translates to:
  /// **'解包并恢复…'**
  String get progressUnpackingRestore;

  /// No description provided for @warnCredentialsSkippedNoKey.
  ///
  /// In zh_CN, this message translates to:
  /// **'凭证同步已跳过（未设置统一加密密钥）'**
  String get warnCredentialsSkippedNoKey;

  /// No description provided for @warnCredentialScanSkipped.
  ///
  /// In zh_CN, this message translates to:
  /// **'凭证扫描跳过：{e}'**
  String warnCredentialScanSkipped(Object e);

  /// No description provided for @warnLeftoverTombstones.
  ///
  /// In zh_CN, this message translates to:
  /// **'重建后仍残留 {count} 条墓碑（有活行与墓碑同时存在），建议检查数据'**
  String warnLeftoverTombstones(Object count);

  /// No description provided for @stepPlaylistsMerged.
  ///
  /// In zh_CN, this message translates to:
  /// **'歌单已合并（{count} 个）'**
  String stepPlaylistsMerged(Object count);

  /// No description provided for @stepCredentialsUploaded.
  ///
  /// In zh_CN, this message translates to:
  /// **'凭证已同步到云端（{count} 个服务器）'**
  String stepCredentialsUploaded(Object count);

  /// No description provided for @stepCloudNoCredentials.
  ///
  /// In zh_CN, this message translates to:
  /// **'云端暂无凭证文件'**
  String get stepCloudNoCredentials;

  /// No description provided for @stepPlaylistsSynced.
  ///
  /// In zh_CN, this message translates to:
  /// **'歌单已同步（{count} 个）'**
  String stepPlaylistsSynced(Object count);

  /// No description provided for @stepIncrementalNoChange.
  ///
  /// In zh_CN, this message translates to:
  /// **'增量同步：无变化（未上传任何内容）'**
  String get stepIncrementalNoChange;

  /// No description provided for @stepIncrementalUploaded.
  ///
  /// In zh_CN, this message translates to:
  /// **'增量同步：上传 {uploaded} 首，采纳 {adopted} 首，删除 {tombs} 条'**
  String stepIncrementalUploaded(Object adopted, Object tombs, Object uploaded);

  /// No description provided for @stepClearedDeadTombstones.
  ///
  /// In zh_CN, this message translates to:
  /// **'清理了 {count} 条已失效的墓碑'**
  String stepClearedDeadTombstones(Object count);

  /// No description provided for @stepRebuildDone.
  ///
  /// In zh_CN, this message translates to:
  /// **'重建完成：{shards} 个分片，base 覆盖到 rev {rev}（本机 {localCount} 首）'**
  String stepRebuildDone(Object localCount, Object rev, Object shards);

  /// No description provided for @stepBackupDone.
  ///
  /// In zh_CN, this message translates to:
  /// **'备份完成'**
  String get stepBackupDone;

  /// No description provided for @stepRestoreDone.
  ///
  /// In zh_CN, this message translates to:
  /// **'恢复完成'**
  String get stepRestoreDone;

  /// No description provided for @stepLocalBackupImported.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地备份已导入'**
  String get stepLocalBackupImported;

  /// No description provided for @errNoWebdavAccount.
  ///
  /// In zh_CN, this message translates to:
  /// **'请先添加 WebDAV 账号'**
  String get errNoWebdavAccount;

  /// No description provided for @vaultSummaryAccounts.
  ///
  /// In zh_CN, this message translates to:
  /// **'账号：新增 {imported}，更新 {updated}；'**
  String vaultSummaryAccounts(Object imported, Object updated);

  /// No description provided for @vaultSummaryPasswords.
  ///
  /// In zh_CN, this message translates to:
  /// **'密码恢复 {passwordsRestored}，留空 {passwordsMissing}'**
  String vaultSummaryPasswords(
    Object passwordsMissing,
    Object passwordsRestored,
  );

  /// No description provided for @vaultSummaryMissingNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'（缺少统一解密密钥，可稍后手动填写）'**
  String get vaultSummaryMissingNote;

  /// No description provided for @vaultSummarySkipped.
  ///
  /// In zh_CN, this message translates to:
  /// **'；跳过 {count} 个不支持的网盘类型'**
  String vaultSummarySkipped(Object count);

  /// No description provided for @vaultSyncedEncrypted.
  ///
  /// In zh_CN, this message translates to:
  /// **'账号凭证已同步到云端（密码已加密）'**
  String get vaultSyncedEncrypted;

  /// No description provided for @vaultSyncedPlaintext.
  ///
  /// In zh_CN, this message translates to:
  /// **'账号凭证已同步到云端（明文密码）'**
  String get vaultSyncedPlaintext;

  /// No description provided for @vaultCloudNoFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'云端暂无凭证文件（{remotePath}），已跳过'**
  String vaultCloudNoFile(Object remotePath);

  /// No description provided for @vaultRestoredFromCloud.
  ///
  /// In zh_CN, this message translates to:
  /// **'已从云端恢复账号凭证：{summary}'**
  String vaultRestoredFromCloud(Object summary);

  /// No description provided for @errVaultDestNotConfigured.
  ///
  /// In zh_CN, this message translates to:
  /// **'凭证同步目的地网盘未配置'**
  String get errVaultDestNotConfigured;

  /// No description provided for @errBackupDestNotConfigured.
  ///
  /// In zh_CN, this message translates to:
  /// **'备份目的地网盘未配置'**
  String get errBackupDestNotConfigured;

  /// No description provided for @backupDoneLatest.
  ///
  /// In zh_CN, this message translates to:
  /// **'已备份到 {remote}（{size}；并更新 latest）'**
  String backupDoneLatest(Object remote, Object size);

  /// No description provided for @errBackupEncryptedNeedPassphrase.
  ///
  /// In zh_CN, this message translates to:
  /// **'此备份已加密，请输入口令'**
  String get errBackupEncryptedNeedPassphrase;

  /// No description provided for @errBackupUnrecognizedContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'无法识别的备份内容'**
  String get errBackupUnrecognizedContent;

  /// No description provided for @backupRestoredFull.
  ///
  /// In zh_CN, this message translates to:
  /// **'备份已恢复：{count} 个服务器、音乐库与歌单已写回'**
  String backupRestoredFull(Object count);

  /// No description provided for @backupRestoredMissingPasswords.
  ///
  /// In zh_CN, this message translates to:
  /// **'备份已恢复，但以下服务器的密码无法解密并已留空：{missing}。请在账号管理中补填。'**
  String backupRestoredMissingPasswords(Object missing);

  /// No description provided for @errNotBackupArchive.
  ///
  /// In zh_CN, this message translates to:
  /// **'这是 {kind} 类文件，不是备份归档'**
  String errNotBackupArchive(Object kind);

  /// No description provided for @estimateLabelWithCovers.
  ///
  /// In zh_CN, this message translates to:
  /// **'预计 {shards} 个分片 · 含封面约 {sizeLabel}'**
  String estimateLabelWithCovers(Object shards, Object sizeLabel);

  /// No description provided for @estimateLabelNoCovers.
  ///
  /// In zh_CN, this message translates to:
  /// **'预计 {shards} 个分片 · 不含封面约 {sizeLabel}'**
  String estimateLabelNoCovers(Object shards, Object sizeLabel);

  /// No description provided for @auditBaseShards.
  ///
  /// In zh_CN, this message translates to:
  /// **'基础分片 {count} 个'**
  String auditBaseShards(Object count);

  /// No description provided for @auditSegments.
  ///
  /// In zh_CN, this message translates to:
  /// **'增量 {count} 个'**
  String auditSegments(Object count);

  /// No description provided for @auditTombstones.
  ///
  /// In zh_CN, this message translates to:
  /// **'墓碑 {count} 个'**
  String auditTombstones(Object count);

  /// No description provided for @auditTotalBytes.
  ///
  /// In zh_CN, this message translates to:
  /// **'合计 {size}'**
  String auditTotalBytes(Object size);

  /// No description provided for @auditOrphans.
  ///
  /// In zh_CN, this message translates to:
  /// **'孤儿文件 {count} 个'**
  String auditOrphans(Object count);

  /// No description provided for @auditMissing.
  ///
  /// In zh_CN, this message translates to:
  /// **'缺失文件 {count} 个'**
  String auditMissing(Object count);

  /// No description provided for @exportErrUnsupportedPlatform.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前平台不支持写入系统相册/下载目录'**
  String get exportErrUnsupportedPlatform;

  /// No description provided for @exportErrSourceMissing.
  ///
  /// In zh_CN, this message translates to:
  /// **'源文件不存在：{detail}'**
  String exportErrSourceMissing(Object detail);

  /// No description provided for @exportErrBadNativeResponse.
  ///
  /// In zh_CN, this message translates to:
  /// **'导出失败：原生返回 {detail}'**
  String exportErrBadNativeResponse(Object detail);

  /// No description provided for @exportErrFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'导出失败'**
  String get exportErrFailed;

  /// No description provided for @exportErrFailedWith.
  ///
  /// In zh_CN, this message translates to:
  /// **'导出失败：{detail}'**
  String exportErrFailedWith(Object detail);

  /// No description provided for @exportErrChannelUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'原生导出通道不可用（需完整 APK）'**
  String get exportErrChannelUnavailable;

  /// No description provided for @pickerErrUnsupportedPlatform.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前平台不支持系统文件选择器'**
  String get pickerErrUnsupportedPlatform;

  /// No description provided for @pickerErrBadResponse.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件选择返回异常'**
  String get pickerErrBadResponse;

  /// No description provided for @pickerErrFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件选择失败'**
  String get pickerErrFailed;

  /// No description provided for @pickerErrChannelUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'原生文件选择器不可用（需完整 APK）'**
  String get pickerErrChannelUnavailable;

  /// No description provided for @locationSystemGallery.
  ///
  /// In zh_CN, this message translates to:
  /// **'系统相册'**
  String get locationSystemGallery;

  /// No description provided for @locationDownloads.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载目录'**
  String get locationDownloads;

  /// No description provided for @locationDownloadsSubdir.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载目录/{dir}'**
  String locationDownloadsSubdir(Object dir);

  /// No description provided for @dlChannelProgressName.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载进度'**
  String get dlChannelProgressName;

  /// No description provided for @dlChannelProgressDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载队列进行中的进度'**
  String get dlChannelProgressDesc;

  /// No description provided for @dlChannelDoneName.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载完成'**
  String get dlChannelDoneName;

  /// No description provided for @dlChannelDoneDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部下载完成后的结果汇总'**
  String get dlChannelDoneDesc;

  /// No description provided for @dlDoneCancelledCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'取消 {count}'**
  String dlDoneCancelledCount(Object count);

  /// No description provided for @dlDoneFailedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'失败 {count}'**
  String dlDoneFailedCount(Object count);

  /// No description provided for @dlDoneOkCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'成功 {count}'**
  String dlDoneOkCount(Object count);

  /// No description provided for @dlDoneSep.
  ///
  /// In zh_CN, this message translates to:
  /// **' · '**
  String get dlDoneSep;

  /// No description provided for @dlDoneTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载完成：{parts}'**
  String dlDoneTitle(Object parts);

  /// No description provided for @dlErrCueMalformed.
  ///
  /// In zh_CN, this message translates to:
  /// **'无法解析的 CUE：需要标准 FILE + TRACK/INDEX'**
  String get dlErrCueMalformed;

  /// No description provided for @dlErrOffline.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络不可用'**
  String get dlErrOffline;

  /// No description provided for @dlErrQueueCleared.
  ///
  /// In zh_CN, this message translates to:
  /// **'队列已清空'**
  String get dlErrQueueCleared;

  /// No description provided for @dlErrQueueSchemaDrift.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载队列数据库结构过旧（{raw}）。请重启应用以升级数据库。'**
  String dlErrQueueSchemaDrift(Object raw);

  /// No description provided for @dlErrSourceUnbound.
  ///
  /// In zh_CN, this message translates to:
  /// **'来源网盘未绑定（{source}）'**
  String dlErrSourceUnbound(Object source);

  /// No description provided for @dlErrWritePublicFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'写入公共目录失败'**
  String get dlErrWritePublicFailed;

  /// No description provided for @dlNetworkInterruptedRetry.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络中断，正在重试 ({attempts}/{max})'**
  String dlNetworkInterruptedRetry(Object attempts, Object max);

  /// No description provided for @dlOfflineRetryWait.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络不可用，{seconds} 秒后重试 ({attempts}/{max})'**
  String dlOfflineRetryWait(Object attempts, Object max, Object seconds);

  /// No description provided for @dlRetryExhausted.
  ///
  /// In zh_CN, this message translates to:
  /// **'重试 {max} 次仍失败：{reason}'**
  String dlRetryExhausted(Object max, Object reason);

  /// No description provided for @netLoadGiveUpFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'{err}\n\n已自动重试 {failures} 次仍失败，等待手动重试。'**
  String netLoadGiveUpFailed(Object err, Object failures);

  /// No description provided for @netEnqueueFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'加入下载失败：{err}'**
  String netEnqueueFailed(Object err);

  /// No description provided for @netStreamingExperimental.
  ///
  /// In zh_CN, this message translates to:
  /// **'音乐流式传输是实验功能，请先在设置里打开'**
  String get netStreamingExperimental;

  /// No description provided for @netParsingCue.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在解析 CUE…'**
  String get netParsingCue;

  /// No description provided for @netCueReadFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'读取 CUE 失败：{e}'**
  String netCueReadFailed(Object e);

  /// No description provided for @netCueGroupTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'多歌曲合并分片 · CUE · {tracks} 曲'**
  String netCueGroupTitle(Object tracks);

  /// No description provided for @netCueGroupTitleMulti.
  ///
  /// In zh_CN, this message translates to:
  /// **'多歌曲合并分片 · CUE · {tracks} 曲 · {files} 个音频文件'**
  String netCueGroupTitleMulti(Object files, Object tracks);

  /// No description provided for @netCueGroupSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'将整张专辑按分片导入音乐库。'**
  String get netCueGroupSubtitle;

  /// No description provided for @netCueDownloadFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'CUE 下载失败：{e}'**
  String netCueDownloadFailed(Object e);

  /// No description provided for @netItemSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'{category} · 点按＝{action}'**
  String netItemSubtitle(Object action, Object category);

  /// No description provided for @netCacheFolderAudio.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存文件夹中的音频'**
  String get netCacheFolderAudio;

  /// No description provided for @netCacheFolderAudioDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'递归扫描，音频进缓存并进音乐库'**
  String get netCacheFolderAudioDesc;

  /// No description provided for @netDownloadWholeFolder.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载整个文件夹'**
  String get netDownloadWholeFolder;

  /// No description provided for @netDownloadWholeFolderDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'递归下载目录树，不挑文件类型'**
  String get netDownloadWholeFolderDesc;

  /// No description provided for @netDefaultActionFromSettings.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置里的默认动作'**
  String get netDefaultActionFromSettings;

  /// No description provided for @netExperimentalNoDownload.
  ///
  /// In zh_CN, this message translates to:
  /// **'实验性：不下载、不进音乐库'**
  String get netExperimentalNoDownload;

  /// No description provided for @netDownloadToGallery.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载到系统相册'**
  String get netDownloadToGallery;

  /// No description provided for @netDownloadToGalleryDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存到 Movies/WebdavMediaManager'**
  String get netDownloadToGalleryDesc;

  /// No description provided for @netCopyTo.
  ///
  /// In zh_CN, this message translates to:
  /// **'复制到…'**
  String get netCopyTo;

  /// No description provided for @netMoveTo.
  ///
  /// In zh_CN, this message translates to:
  /// **'移动到…'**
  String get netMoveTo;

  /// No description provided for @netNewName.
  ///
  /// In zh_CN, this message translates to:
  /// **'新名称'**
  String get netNewName;

  /// No description provided for @netTapDownload.
  ///
  /// In zh_CN, this message translates to:
  /// **'点按下载'**
  String get netTapDownload;

  /// No description provided for @netSelectedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已选 {n} 项'**
  String netSelectedCount(Object n);

  /// No description provided for @netCachingMusic.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在缓存音乐…'**
  String get netCachingMusic;

  /// No description provided for @netNoNewAudio.
  ///
  /// In zh_CN, this message translates to:
  /// **'这里没有新的音频'**
  String get netNoNewAudio;

  /// No description provided for @netEnqueueing.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在加入下载队列…'**
  String get netEnqueueing;

  /// No description provided for @netNothingDownloadable.
  ///
  /// In zh_CN, this message translates to:
  /// **'所选内容里没有可下载的文件'**
  String get netNothingDownloadable;

  /// No description provided for @netEnqueuedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已加入 {n} 项'**
  String netEnqueuedCount(Object n);

  /// No description provided for @netEnqueueFailedFolders.
  ///
  /// In zh_CN, this message translates to:
  /// **'失败 {n} 个文件夹'**
  String netEnqueueFailedFolders(Object n);

  /// No description provided for @netJoinSep.
  ///
  /// In zh_CN, this message translates to:
  /// **'，'**
  String get netJoinSep;

  /// No description provided for @netFolder.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件夹'**
  String get netFolder;

  /// No description provided for @netVideo.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频'**
  String get netVideo;

  /// No description provided for @netAudio.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频'**
  String get netAudio;

  /// No description provided for @netFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件'**
  String get netFile;

  /// No description provided for @netConfirmDeleteTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'确认删除'**
  String get netConfirmDeleteTitle;

  /// No description provided for @netConfirmDeleteMsg.
  ///
  /// In zh_CN, this message translates to:
  /// **'确定删除「{name}」？此操作不可撤销。'**
  String netConfirmDeleteMsg(Object name);

  /// No description provided for @ntfAllDone.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部下载完成'**
  String get ntfAllDone;

  /// No description provided for @ntfDoneCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已完成 {done} / {total}'**
  String ntfDoneCount(Object done, Object total);

  /// No description provided for @ntfDoneCountPercent.
  ///
  /// In zh_CN, this message translates to:
  /// **'总进度 {percent}% · 已完成 {done} / {total}'**
  String ntfDoneCountPercent(Object done, Object percent, Object total);

  /// No description provided for @ntfDoneWithFailures.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载结束（有失败）'**
  String get ntfDoneWithFailures;

  /// No description provided for @ntfDownloadingTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在下载（第 {index} / {total} 个）'**
  String ntfDownloadingTitle(Object index, Object total);

  /// No description provided for @ntfImportanceOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'已关闭'**
  String get ntfImportanceOff;

  /// No description provided for @ntfImportanceMin.
  ///
  /// In zh_CN, this message translates to:
  /// **'最低'**
  String get ntfImportanceMin;

  /// No description provided for @ntfImportanceLow.
  ///
  /// In zh_CN, this message translates to:
  /// **'低'**
  String get ntfImportanceLow;

  /// No description provided for @ntfImportanceDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认'**
  String get ntfImportanceDefault;

  /// No description provided for @ntfImportanceHigh.
  ///
  /// In zh_CN, this message translates to:
  /// **'高'**
  String get ntfImportanceHigh;

  /// No description provided for @ntfImportanceMax.
  ///
  /// In zh_CN, this message translates to:
  /// **'最高'**
  String get ntfImportanceMax;

  /// No description provided for @ntfMediaChannelName.
  ///
  /// In zh_CN, this message translates to:
  /// **'音乐播放'**
  String get ntfMediaChannelName;

  /// No description provided for @ntfMediaChannelDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在播放的音乐控制'**
  String get ntfMediaChannelDesc;

  /// No description provided for @ntfStatusBlocked.
  ///
  /// In zh_CN, this message translates to:
  /// **'已关闭（请在系统通知设置中重新开启）'**
  String get ntfStatusBlocked;

  /// No description provided for @ntfStatusChecking.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在检查…'**
  String get ntfStatusChecking;

  /// No description provided for @ntfStatusCreated.
  ///
  /// In zh_CN, this message translates to:
  /// **'已创建'**
  String get ntfStatusCreated;

  /// No description provided for @ntfStatusCreatedImportance.
  ///
  /// In zh_CN, this message translates to:
  /// **'已创建 · 重要性 {importance}'**
  String ntfStatusCreatedImportance(Object importance);

  /// No description provided for @ntfStatusNoChannels.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前平台无通知通道'**
  String get ntfStatusNoChannels;

  /// No description provided for @ntfStatusNotCreated.
  ///
  /// In zh_CN, this message translates to:
  /// **'未创建'**
  String get ntfStatusNotCreated;

  /// No description provided for @ntfSummaryCancelled.
  ///
  /// In zh_CN, this message translates to:
  /// **'取消：{count} 个'**
  String ntfSummaryCancelled(Object count);

  /// No description provided for @ntfSummaryFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'失败：{count} 个'**
  String ntfSummaryFailed(Object count);

  /// No description provided for @ntfSummaryOk.
  ///
  /// In zh_CN, this message translates to:
  /// **'成功：{count} 个'**
  String ntfSummaryOk(Object count);

  /// No description provided for @ntfSelfTestAndroidOnly.
  ///
  /// In zh_CN, this message translates to:
  /// **'仅 Android 支持'**
  String get ntfSelfTestAndroidOnly;

  /// No description provided for @ntfSelfTestBlocked.
  ///
  /// In zh_CN, this message translates to:
  /// **'系统已关闭本应用的通知'**
  String get ntfSelfTestBlocked;

  /// No description provided for @ntfSelfTestBody.
  ///
  /// In zh_CN, this message translates to:
  /// **'测试通知 · 50% · 已完成 0 / 1'**
  String get ntfSelfTestBody;

  /// No description provided for @ntfSelfTestSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'成功：1 个（测试）'**
  String get ntfSelfTestSummary;

  /// No description provided for @libQueuedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已加入 {count} 项下载'**
  String libQueuedCount(Object count);

  /// No description provided for @libQueuedUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'{count} 项来源不可用'**
  String libQueuedUnavailable(Object count);

  /// No description provided for @libQueuedAdded.
  ///
  /// In zh_CN, this message translates to:
  /// **'已加入下载'**
  String get libQueuedAdded;

  /// No description provided for @cueGroupDeleteTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除整个 CUE 缓存组？'**
  String get cueGroupDeleteTitle;

  /// No description provided for @cueGroupDeleteTitleMulti.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除多个 CUE 缓存组？'**
  String get cueGroupDeleteTitleMulti;

  /// No description provided for @cueGroupDeleteBodyIntro.
  ///
  /// In zh_CN, this message translates to:
  /// **'将删除整组：'**
  String get cueGroupDeleteBodyIntro;

  /// No description provided for @cueGroupDeleteBodyIntroCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'将删除 {count} 个 CUE 组：'**
  String cueGroupDeleteBodyIntroCount(Object count);

  /// No description provided for @moreFilesCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'…共 {count} 个文件'**
  String moreFilesCount(Object count);

  /// No description provided for @cueGroupDeleteWhole.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除整组'**
  String get cueGroupDeleteWhole;

  /// No description provided for @cueGroupDeleted.
  ///
  /// In zh_CN, this message translates to:
  /// **'已删除 CUE 缓存组（{count} 个文件）'**
  String cueGroupDeleted(Object count);

  /// No description provided for @cacheDeleteTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除本地音频缓存？'**
  String get cacheDeleteTitle;

  /// No description provided for @cacheDeleteBodyOne.
  ///
  /// In zh_CN, this message translates to:
  /// **'将删除「{name}」的音频缓存，标签与封面保留。'**
  String cacheDeleteBodyOne(Object name);

  /// No description provided for @cacheDeleteBodyMany.
  ///
  /// In zh_CN, this message translates to:
  /// **'将删除 {count} 个缓存文件，标签与封面保留。'**
  String cacheDeleteBodyMany(Object count);

  /// No description provided for @cacheDeletedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已删除 {count} 个本地音频缓存'**
  String cacheDeletedCount(Object count);

  /// No description provided for @destroyTracksTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'销毁所选曲目？'**
  String get destroyTracksTitle;

  /// No description provided for @destroyTracksBody.
  ///
  /// In zh_CN, this message translates to:
  /// **'将删除 {count} 首曲目（缓存、库记录、元数据与封面），不可恢复。'**
  String destroyTracksBody(Object count);

  /// No description provided for @destroyTracksCueNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'（CUE 分片整组删除）'**
  String get destroyTracksCueNote;

  /// No description provided for @destroyAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'销毁'**
  String get destroyAction;

  /// No description provided for @destroyedTracksCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已销毁 {count} 首曲目'**
  String destroyedTracksCount(Object count);

  /// No description provided for @shareCueUnsupported.
  ///
  /// In zh_CN, this message translates to:
  /// **'CUE 音轨不支持分享'**
  String get shareCueUnsupported;

  /// No description provided for @shareCueUnsupportedAndNotLocal.
  ///
  /// In zh_CN, this message translates to:
  /// **'CUE 音轨不支持分享；其余曲目尚未下载到本地'**
  String get shareCueUnsupportedAndNotLocal;

  /// No description provided for @shareNotLocalOne.
  ///
  /// In zh_CN, this message translates to:
  /// **'该曲目尚未下载到本地，无法分享'**
  String get shareNotLocalOne;

  /// No description provided for @shareNotLocalAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'所选曲目均未下载到本地，无法分享'**
  String get shareNotLocalAll;

  /// No description provided for @shareCueSkipped.
  ///
  /// In zh_CN, this message translates to:
  /// **'已跳过 {count} 首 CUE 音轨（不支持分享）'**
  String shareCueSkipped(Object count);

  /// No description provided for @shareNotLocalSkipped.
  ///
  /// In zh_CN, this message translates to:
  /// **'已跳过 {count} 首未下载曲目'**
  String shareNotLocalSkipped(Object count);

  /// No description provided for @shareNothingToShare.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有可分享的文件'**
  String get shareNothingToShare;

  /// No description provided for @shareDoneCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已分享 {count} 个文件'**
  String shareDoneCount(Object count);

  /// No description provided for @shareFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'分享失败：{reason}'**
  String shareFailed(Object reason);

  /// No description provided for @shareNameTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'分享文件名'**
  String get shareNameTitle;

  /// No description provided for @shareRenameTemplateHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'留空字段自动去掉多余分隔符，扩展名始终保留。'**
  String get shareRenameTemplateHint;

  /// No description provided for @fileNameLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件名'**
  String get fileNameLabel;

  /// No description provided for @shareExtFixed.
  ///
  /// In zh_CN, this message translates to:
  /// **'扩展名固定为 {ext}'**
  String shareExtFixed(Object ext);

  /// No description provided for @shareOriginalFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'原文件：{name}'**
  String shareOriginalFile(Object name);

  /// No description provided for @shareUseOriginalName.
  ///
  /// In zh_CN, this message translates to:
  /// **'用原文件名'**
  String get shareUseOriginalName;

  /// No description provided for @shareAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'分享'**
  String get shareAction;

  /// No description provided for @searchPlaceholder.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索标题 / 艺术家 / 专辑'**
  String get searchPlaceholder;

  /// No description provided for @searchAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索'**
  String get searchAction;

  /// No description provided for @closeSearch.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭搜索'**
  String get closeSearch;

  /// No description provided for @sortTooltip.
  ///
  /// In zh_CN, this message translates to:
  /// **'排序'**
  String get sortTooltip;

  /// No description provided for @tabAlbums.
  ///
  /// In zh_CN, this message translates to:
  /// **'专辑'**
  String get tabAlbums;

  /// No description provided for @tabArtists.
  ///
  /// In zh_CN, this message translates to:
  /// **'作者'**
  String get tabArtists;

  /// No description provided for @tabTitles.
  ///
  /// In zh_CN, this message translates to:
  /// **'音乐名'**
  String get tabTitles;

  /// No description provided for @tabGenres.
  ///
  /// In zh_CN, this message translates to:
  /// **'流派'**
  String get tabGenres;

  /// No description provided for @libraryNoMatch.
  ///
  /// In zh_CN, this message translates to:
  /// **'无匹配曲目'**
  String get libraryNoMatch;

  /// No description provided for @genreEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无流派：下载带流派元数据的曲目后出现。'**
  String get genreEmpty;

  /// No description provided for @noMatchResult.
  ///
  /// In zh_CN, this message translates to:
  /// **'无匹配结果'**
  String get noMatchResult;

  /// No description provided for @updateCancelled.
  ///
  /// In zh_CN, this message translates to:
  /// **'已终止'**
  String get updateCancelled;

  /// No description provided for @updateDone.
  ///
  /// In zh_CN, this message translates to:
  /// **'更新完成'**
  String get updateDone;

  /// No description provided for @updateSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'{a}：更新 {b} 首，跳过 {c} 首，失败 {d} 首'**
  String updateSummary(Object a, Object b, Object c, Object d);

  /// No description provided for @deleteCacheKeepMeta.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除缓存（保留元数据与封面）'**
  String get deleteCacheKeepMeta;

  /// No description provided for @updateTags.
  ///
  /// In zh_CN, this message translates to:
  /// **'更新标签'**
  String get updateTags;

  /// No description provided for @downloadUncachedTracks.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载未缓存曲目'**
  String get downloadUncachedTracks;

  /// No description provided for @libraryTracksEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无曲目'**
  String get libraryTracksEmpty;

  /// No description provided for @sourceUnbound.
  ///
  /// In zh_CN, this message translates to:
  /// **'来源网盘未绑定'**
  String get sourceUnbound;

  /// No description provided for @downloadingPercent.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载中 {p}%'**
  String downloadingPercent(Object p);

  /// No description provided for @libraryEmptyGuide.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无曲目：先在「网络库」下载音乐。'**
  String get libraryEmptyGuide;

  /// No description provided for @tagTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'标题'**
  String get tagTitle;

  /// No description provided for @tagArtist.
  ///
  /// In zh_CN, this message translates to:
  /// **'艺术家'**
  String get tagArtist;

  /// No description provided for @tagAlbumArtist.
  ///
  /// In zh_CN, this message translates to:
  /// **'专辑艺术家'**
  String get tagAlbumArtist;

  /// No description provided for @tagAlbum.
  ///
  /// In zh_CN, this message translates to:
  /// **'专辑'**
  String get tagAlbum;

  /// No description provided for @tagTrack.
  ///
  /// In zh_CN, this message translates to:
  /// **'曲目'**
  String get tagTrack;

  /// No description provided for @tagDisc.
  ///
  /// In zh_CN, this message translates to:
  /// **'碟片'**
  String get tagDisc;

  /// No description provided for @tagYear.
  ///
  /// In zh_CN, this message translates to:
  /// **'年份'**
  String get tagYear;

  /// No description provided for @tagGenre.
  ///
  /// In zh_CN, this message translates to:
  /// **'流派'**
  String get tagGenre;

  /// No description provided for @tagDuration.
  ///
  /// In zh_CN, this message translates to:
  /// **'时长'**
  String get tagDuration;

  /// No description provided for @tagBitrate.
  ///
  /// In zh_CN, this message translates to:
  /// **'比特率'**
  String get tagBitrate;

  /// No description provided for @tagSampleRate.
  ///
  /// In zh_CN, this message translates to:
  /// **'采样率'**
  String get tagSampleRate;

  /// No description provided for @tagLanguage.
  ///
  /// In zh_CN, this message translates to:
  /// **'语言'**
  String get tagLanguage;

  /// No description provided for @tagLyrics.
  ///
  /// In zh_CN, this message translates to:
  /// **'歌词'**
  String get tagLyrics;

  /// No description provided for @errShardKindMismatch.
  ///
  /// In zh_CN, this message translates to:
  /// **'分片类型不一致：文件头 {a}，META kind={b}'**
  String errShardKindMismatch(Object a, Object b);

  /// No description provided for @errNotWdmmFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'不是 Webdav Media Manager 文件（缺少 WDMM 标识）'**
  String get errNotWdmmFile;

  /// No description provided for @errAccountNotConnected.
  ///
  /// In zh_CN, this message translates to:
  /// **'账号未连接：{a}'**
  String errAccountNotConnected(Object a);

  /// No description provided for @errBigintOverflow.
  ///
  /// In zh_CN, this message translates to:
  /// **'大整数超出 {a} 字节'**
  String errBigintOverflow(Object a);

  /// No description provided for @errCloudAccountMissing.
  ///
  /// In zh_CN, this message translates to:
  /// **'云盘账号不存在：{a}'**
  String errCloudAccountMissing(Object a);

  /// No description provided for @errCloudWriteDisabled.
  ///
  /// In zh_CN, this message translates to:
  /// **'云盘账号不支持上传与云端写同步'**
  String get errCloudWriteDisabled;

  /// No description provided for @errContentRangeUnsupported.
  ///
  /// In zh_CN, this message translates to:
  /// **'该驱动不支持区间读取'**
  String get errContentRangeUnsupported;

  /// No description provided for @errContentStreamUnsupported.
  ///
  /// In zh_CN, this message translates to:
  /// **'该驱动不支持内容流读取'**
  String get errContentStreamUnsupported;

  /// No description provided for @errDriverNotReady.
  ///
  /// In zh_CN, this message translates to:
  /// **'云盘驱动尚未接入'**
  String get errDriverNotReady;

  /// No description provided for @errDriverNotReadyInfo.
  ///
  /// In zh_CN, this message translates to:
  /// **'云盘驱动尚未接入：{a}'**
  String errDriverNotReadyInfo(Object a);

  /// No description provided for @errDownloadSizeUnknown.
  ///
  /// In zh_CN, this message translates to:
  /// **'无法确定「{a}」的大小，下载已取消'**
  String errDownloadSizeUnknown(Object a);

  /// No description provided for @errNeteaseRsaKeyLength.
  ///
  /// In zh_CN, this message translates to:
  /// **'网易 raw RSA 的密钥必须是 16 字节'**
  String get errNeteaseRsaKeyLength;

  /// No description provided for @errStreamSizeUnknown.
  ///
  /// In zh_CN, this message translates to:
  /// **'无法确定「{a}」的大小，暂不支持流式播放'**
  String errStreamSizeUnknown(Object a);

  /// No description provided for @errWebdavNotConfigured.
  ///
  /// In zh_CN, this message translates to:
  /// **'未配置 WebDAV'**
  String get errWebdavNotConfigured;

  /// No description provided for @errWebdavSourceNotConnected.
  ///
  /// In zh_CN, this message translates to:
  /// **'WebDAV 未连接，无法取源内容'**
  String get errWebdavSourceNotConnected;

  /// No description provided for @errBaiduDirectLinkFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'获取下载直链失败：{a}'**
  String errBaiduDirectLinkFailed(Object a);

  /// No description provided for @errBaiduRequestFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'百度网盘请求失败：{a}'**
  String errBaiduRequestFailed(Object a);

  /// No description provided for @errBaiduRiskControl.
  ///
  /// In zh_CN, this message translates to:
  /// **'{a} 百度网盘风控（触发安全策略，通常数分钟至数小时后自动解除）。refresh_token 无效或非官方渠道获取也可能触发；请确认通过 https://api.oplist.org/ 获取。'**
  String errBaiduRiskControl(Object a);

  /// No description provided for @errDriver123FileNotFound.
  ///
  /// In zh_CN, this message translates to:
  /// **'123 云盘文件不存在：{a}'**
  String errDriver123FileNotFound(Object a);

  /// No description provided for @errDriver123NetworkFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'[123Open] 网络请求失败：{a}'**
  String errDriver123NetworkFailed(Object a);

  /// No description provided for @errDriver123RequestFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'123 云盘请求失败：{a}'**
  String errDriver123RequestFailed(Object a);

  /// No description provided for @errMissingRefreshToken.
  ///
  /// In zh_CN, this message translates to:
  /// **'123 云盘缺少 refresh_token：请填写 refresh_token（获取方法见 OpenList 官方文档 123_open 驱动页）'**
  String get errMissingRefreshToken;

  /// No description provided for @errMkdirRoot.
  ///
  /// In zh_CN, this message translates to:
  /// **'不能创建根目录'**
  String get errMkdirRoot;

  /// No description provided for @errRefreshOnlineFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'在线 API 刷新失败 (HTTP {a})：{b}。请确认 refresh_token 是通过 https://api.oplist.org/ 获取的有效令牌。'**
  String errRefreshOnlineFailed(Object a, Object b);

  /// No description provided for @errRefreshOnlineFailedNonJson.
  ///
  /// In zh_CN, this message translates to:
  /// **'在线 API 刷新失败 (HTTP {a})：非 JSON 响应。请确认 refresh_token 是通过 https://api.oplist.org/ 获取的有效令牌。'**
  String errRefreshOnlineFailedNonJson(Object a);

  /// No description provided for @errRootOp.
  ///
  /// In zh_CN, this message translates to:
  /// **'不能对根目录执行该操作'**
  String get errRootOp;

  /// No description provided for @errOpen115MissingRefreshToken.
  ///
  /// In zh_CN, this message translates to:
  /// **'115 网盘缺少 refresh_token（必填）'**
  String get errOpen115MissingRefreshToken;

  /// No description provided for @errOpen115RefreshFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'115 网盘 token 刷新失败（{a}）：请确认 refresh_token 有效。'**
  String errOpen115RefreshFailed(Object a);

  /// No description provided for @errOpen115ApiError.
  ///
  /// In zh_CN, this message translates to:
  /// **'115 网盘 API 错误（{a}）'**
  String errOpen115ApiError(Object a);

  /// No description provided for @errOpen115NetworkFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'115 网盘网络请求失败（{a}）'**
  String errOpen115NetworkFailed(Object a);

  /// No description provided for @errOpen115DownurlEmptyData.
  ///
  /// In zh_CN, this message translates to:
  /// **'115 网盘 downurl 未返回直链数据（data 为空）'**
  String get errOpen115DownurlEmptyData;

  /// No description provided for @errOpen115DownurlEmptyUrl.
  ///
  /// In zh_CN, this message translates to:
  /// **'115 网盘 downurl 未返回可用直链（url.url 为空）'**
  String get errOpen115DownurlEmptyUrl;

  /// No description provided for @errOpen115MissingPickCode.
  ///
  /// In zh_CN, this message translates to:
  /// **'115 网盘条目缺少 pick_code，无法获取直链：{a}'**
  String errOpen115MissingPickCode(Object a);

  /// No description provided for @errOpen115TokenVerifyFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'115 网盘 token 验证失败：{a}。请确认 access_token / refresh_token 有效。'**
  String errOpen115TokenVerifyFailed(Object a);

  /// No description provided for @errOpen115NetworkConnectFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'115 网盘网络连接失败（{a}）：proapi.115.com 可能无法从当前部署环境访问（数据中心 IP 可能被 115 拦截），请稍后重试或更换部署环境。'**
  String errOpen115NetworkConnectFailed(Object a);

  /// No description provided for @errOpen115DirectLinkFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'获取 115 网盘直链失败：{a}'**
  String errOpen115DirectLinkFailed(Object a);

  /// No description provided for @errOpen115CopyRenameFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'115 网盘复制完成但未找到副本，无法改名为 {a}'**
  String errOpen115CopyRenameFailed(Object a);

  /// No description provided for @errOpen115FolderNotFound.
  ///
  /// In zh_CN, this message translates to:
  /// **'115 网盘目录不存在：{a}'**
  String errOpen115FolderNotFound(Object a);

  /// No description provided for @errOpen115FileNotFound.
  ///
  /// In zh_CN, this message translates to:
  /// **'115 网盘文件不存在：{a}'**
  String errOpen115FileNotFound(Object a);

  /// No description provided for @errAliyunEntryOrLinkFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'无法获取条目或直链：{a}'**
  String errAliyunEntryOrLinkFailed(Object a);

  /// No description provided for @errAliyunMissingRefreshToken.
  ///
  /// In zh_CN, this message translates to:
  /// **'阿里云盘缺少 refresh_token：请在账号表单填写 refresh_token（获取方法见 OpenList 官方文档 aliyundrive_open 驱动页）。'**
  String get errAliyunMissingRefreshToken;

  /// No description provided for @errAliyunNetworkFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'[AliyundriveOpen] 网络请求失败 {a}'**
  String errAliyunNetworkFailed(Object a);

  /// No description provided for @errAliyunNoDirectLink.
  ///
  /// In zh_CN, this message translates to:
  /// **'[AliyundriveOpen] getDownloadUrl 未返回直链（url / download_url 都为空）'**
  String get errAliyunNoDirectLink;

  /// No description provided for @errAliyunNoDriveId.
  ///
  /// In zh_CN, this message translates to:
  /// **'[AliyundriveOpen] getDriveInfo 未返回任何 drive_id（resource / default / backup 都为空）：请确认账号已开通阿里云盘。'**
  String get errAliyunNoDriveId;

  /// No description provided for @errAliyunNonJson.
  ///
  /// In zh_CN, this message translates to:
  /// **'非 JSON 响应：{a}'**
  String errAliyunNonJson(Object a);

  /// No description provided for @errAliyunRefreshAllFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'[AliyundriveOpen] 刷新令牌的所有策略均失败。请依次检查：1) refresh_token 是否有效且未过期；2) api_url_address 是否可访问；3) 若使用直连 OAuth，client_id / client_secret 是否正确。尝试记录：{a}'**
  String errAliyunRefreshAllFailed(Object a);

  /// No description provided for @errTeraboxRedirectFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'TeraBox 直链重定向失败（{a}）'**
  String errTeraboxRedirectFailed(Object a);

  /// No description provided for @errTeraboxRequestFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'TeraBox 请求失败 {a}'**
  String errTeraboxRequestFailed(Object a);

  /// No description provided for @errTeraboxSignKeyEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'TeraBox 签名失败：sign3 密钥为空（上游 /api/home/info 未返回 sign3）'**
  String get errTeraboxSignKeyEmpty;

  /// No description provided for @errNeteaseApiError.
  ///
  /// In zh_CN, this message translates to:
  /// **'网易云音乐接口报错（{a}）'**
  String errNeteaseApiError(Object a);

  /// No description provided for @errNeteaseCookieRequired.
  ///
  /// In zh_CN, this message translates to:
  /// **'Cookie 必须同时包含 __csrf 与 MUSIC_U：请在网页版 music.163.com 登录后，从开发者工具复制完整 Cookie'**
  String get errNeteaseCookieRequired;

  /// No description provided for @errNeteaseCopyUnsupported.
  ///
  /// In zh_CN, this message translates to:
  /// **'网易云音乐云盘不支持复制（上游驱动未实现该操作）'**
  String get errNeteaseCopyUnsupported;

  /// No description provided for @errNeteaseFileNotFound.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件不存在：{a}'**
  String errNeteaseFileNotFound(Object a);

  /// No description provided for @errNeteaseLoginExpired.
  ///
  /// In zh_CN, this message translates to:
  /// **'网易云音乐登录态已失效（{a}）。Cookie 可能已过期，请重新登录网页版并更新 Cookie'**
  String errNeteaseLoginExpired(Object a);

  /// No description provided for @errNeteaseMkdirUnsupported.
  ///
  /// In zh_CN, this message translates to:
  /// **'网易云音乐云盘不支持新建文件夹（上游驱动未实现该操作）'**
  String get errNeteaseMkdirUnsupported;

  /// No description provided for @errNeteaseMoveUnsupported.
  ///
  /// In zh_CN, this message translates to:
  /// **'网易云音乐云盘不支持移动（上游驱动未实现该操作）'**
  String get errNeteaseMoveUnsupported;

  /// No description provided for @errNeteaseNoSongLink.
  ///
  /// In zh_CN, this message translates to:
  /// **'网易云音乐未返回播放链接（可能是 VIP / 版权受限 / 已下架的歌曲）'**
  String get errNeteaseNoSongLink;

  /// No description provided for @errNeteaseNonJson.
  ///
  /// In zh_CN, this message translates to:
  /// **'网易云音乐返回了非 JSON 响应：{a}'**
  String errNeteaseNonJson(Object a);

  /// No description provided for @errNeteaseRenameUnsupported.
  ///
  /// In zh_CN, this message translates to:
  /// **'网易云音乐云盘不支持重命名（上游驱动未实现该操作）'**
  String get errNeteaseRenameUnsupported;

  /// No description provided for @errNeteaseRequestFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'网易云音乐请求失败：{a}'**
  String errNeteaseRequestFailed(Object a);

  /// No description provided for @errNeteaseRootDelete.
  ///
  /// In zh_CN, this message translates to:
  /// **'网易云音乐不支持删除根目录'**
  String get errNeteaseRootDelete;

  /// No description provided for @errNeteaseUnexpectedStructure.
  ///
  /// In zh_CN, this message translates to:
  /// **'网易云音乐返回了非预期结构：{a}'**
  String errNeteaseUnexpectedStructure(Object a);

  /// No description provided for @errNeteaseUnknownCrypto.
  ///
  /// In zh_CN, this message translates to:
  /// **'未知的加密方式：{a}'**
  String errNeteaseUnknownCrypto(Object a);

  /// No description provided for @errCryptBadCipherLength.
  ///
  /// In zh_CN, this message translates to:
  /// **'crypt 密文长度不合法：{a}'**
  String errCryptBadCipherLength(Object a);

  /// No description provided for @errCryptBlockDecryptFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'crypt 第 {a} 块解密失败（内容损坏或密钥不匹配）'**
  String errCryptBlockDecryptFailed(Object a);

  /// No description provided for @errCryptBlockRangeDecryptFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'crypt 第 {a} 块起解密失败（内容损坏或密钥不匹配）'**
  String errCryptBlockRangeDecryptFailed(Object a);

  /// No description provided for @errCryptDecryptFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'crypt 内容解密失败（内容损坏或密钥不匹配）'**
  String get errCryptDecryptFailed;

  /// No description provided for @errCryptEarlyEof.
  ///
  /// In zh_CN, this message translates to:
  /// **'crypt 内容提前结束（第 {a} 块起，期望 {b} 字节，收到 {c} 字节）'**
  String errCryptEarlyEof(Object a, Object b, Object c);

  /// No description provided for @errCryptInvalidConfig.
  ///
  /// In zh_CN, this message translates to:
  /// **'crypt 配置无效：{a}'**
  String errCryptInvalidConfig(Object a);

  /// No description provided for @errCryptLengthMismatch.
  ///
  /// In zh_CN, this message translates to:
  /// **'crypt 内容长度不符（期望 {a}，收到 {b}）'**
  String errCryptLengthMismatch(Object a, Object b);

  /// No description provided for @errCryptNoDirectLinkAnymore.
  ///
  /// In zh_CN, this message translates to:
  /// **'crypt 源不再提供直链，无法继续解密内容'**
  String get errCryptNoDirectLinkAnymore;

  /// No description provided for @errCryptNoDirectLinkDecrypt.
  ///
  /// In zh_CN, this message translates to:
  /// **'crypt 源不提供直链，无法解密内容'**
  String get errCryptNoDirectLinkDecrypt;

  /// No description provided for @errCryptNoDirectLinkStream.
  ///
  /// In zh_CN, this message translates to:
  /// **'crypt 源不提供直链，无法顺序下载'**
  String get errCryptNoDirectLinkStream;

  /// No description provided for @errCryptNoHeader.
  ///
  /// In zh_CN, this message translates to:
  /// **'crypt 内容不完整（读不到文件头）'**
  String get errCryptNoHeader;

  /// No description provided for @errCryptNoResponseBody.
  ///
  /// In zh_CN, this message translates to:
  /// **'crypt 顺序下载没有响应体'**
  String get errCryptNoResponseBody;

  /// No description provided for @errCryptNoSourceName.
  ///
  /// In zh_CN, this message translates to:
  /// **'crypt 未保存源账号名称；请重新编辑并选择源账号'**
  String get errCryptNoSourceName;

  /// No description provided for @errCryptNotRcloneFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'不是有效的 rclone 加密文件：{a}'**
  String errCryptNotRcloneFile(Object a);

  /// No description provided for @errCryptSizeUnknown.
  ///
  /// In zh_CN, this message translates to:
  /// **'无法确定加密内容的大小（源未提供长度且不支持 Range）'**
  String get errCryptSizeUnknown;

  /// No description provided for @errCryptSourceMissing.
  ///
  /// In zh_CN, this message translates to:
  /// **'crypt 源账号不存在或已删除「{a}」；重新添加同名源账号即可恢复'**
  String errCryptSourceMissing(Object a);

  /// No description provided for @driverNameBaidu.
  ///
  /// In zh_CN, this message translates to:
  /// **'百度网盘'**
  String get driverNameBaidu;

  /// No description provided for @driverName123Open.
  ///
  /// In zh_CN, this message translates to:
  /// **'123 云盘开放平台'**
  String get driverName123Open;

  /// No description provided for @driverName115.
  ///
  /// In zh_CN, this message translates to:
  /// **'115网盘'**
  String get driverName115;

  /// No description provided for @driverNameAliyunOpen.
  ///
  /// In zh_CN, this message translates to:
  /// **'阿里云盘开放平台'**
  String get driverNameAliyunOpen;

  /// No description provided for @driverNameNetease.
  ///
  /// In zh_CN, this message translates to:
  /// **'网易云音乐'**
  String get driverNameNetease;

  /// No description provided for @driverNameCrypt.
  ///
  /// In zh_CN, this message translates to:
  /// **'Crypt 加密目录'**
  String get driverNameCrypt;

  /// No description provided for @errRefreshOnlineNon200.
  ///
  /// In zh_CN, this message translates to:
  /// **'在线 API 返回 HTTP {a}'**
  String errRefreshOnlineNon200(Object a);

  /// No description provided for @formLabelRenewApi.
  ///
  /// In zh_CN, this message translates to:
  /// **'在线续期地址'**
  String get formLabelRenewApi;

  /// No description provided for @formHintRenewApiDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认用 OpenList 维护的公共服务'**
  String get formHintRenewApiDefault;

  /// No description provided for @formHintLocalRefreshDisabled.
  ///
  /// In zh_CN, this message translates to:
  /// **'已开启本地刷新（在线续期停用），关闭开关后可编辑'**
  String get formHintLocalRefreshDisabled;

  /// No description provided for @formLabelLocalRefresh.
  ///
  /// In zh_CN, this message translates to:
  /// **'在本地处理令牌刷新'**
  String get formLabelLocalRefresh;

  /// No description provided for @formSubLocalRefreshBaidu.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭＝在线续期地址刷新；开启＝用自建百度应用刷新（需 Client ID / Secret），在线续期停用'**
  String get formSubLocalRefreshBaidu;

  /// No description provided for @formSubLocalRefresh123.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭＝在线续期；开启＝用自建 123 应用刷新（需 Client ID / Secret），在线续期停用'**
  String get formSubLocalRefresh123;

  /// No description provided for @formSubLocalRefreshAliyun.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭＝用在线续期地址轮询；开启＝用自建阿里云应用直接刷新（需 Client ID / Secret）'**
  String get formSubLocalRefreshAliyun;

  /// No description provided for @formHintOpenListDoc.
  ///
  /// In zh_CN, this message translates to:
  /// **'必填；获取方法见 OpenList 官方文档（{a} 驱动页）'**
  String formHintOpenListDoc(Object a);

  /// No description provided for @formLabelRootId.
  ///
  /// In zh_CN, this message translates to:
  /// **'根目录 ID'**
  String get formLabelRootId;

  /// No description provided for @formHintRootIdOpaque.
  ///
  /// In zh_CN, this message translates to:
  /// **'不透明 id，默认 {a}（网盘根目录）；与账号的远程路径叠加生效'**
  String formHintRootIdOpaque(Object a);

  /// No description provided for @formHint115RefreshToken.
  ///
  /// In zh_CN, this message translates to:
  /// **'必填；获取方法见 OpenList 官方文档（115 Open 驱动页）。115 每次刷新都会轮换它，轮换结果会自动保存'**
  String get formHint115RefreshToken;

  /// No description provided for @formHint115RootId.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认 0（整体根目录）；填非 0 的目录 ID 可把账号挂到该目录下'**
  String get formHint115RootId;

  /// No description provided for @formLabelPageSize.
  ///
  /// In zh_CN, this message translates to:
  /// **'分页大小'**
  String get formLabelPageSize;

  /// No description provided for @formHintPageSize.
  ///
  /// In zh_CN, this message translates to:
  /// **'范围 1~1150，默认 200（超出会被夹到边界；115 单次上限 1150）'**
  String get formHintPageSize;

  /// No description provided for @formLabelRateLimit.
  ///
  /// In zh_CN, this message translates to:
  /// **'限速（次/秒）'**
  String get formLabelRateLimit;

  /// No description provided for @formHintRateLimit.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认 0 = 不限速；填正数则两次 API 请求之间至少间隔 1/该值 秒'**
  String get formHintRateLimit;

  /// No description provided for @formLabelDriveType.
  ///
  /// In zh_CN, this message translates to:
  /// **'网盘类型'**
  String get formLabelDriveType;

  /// No description provided for @formHintDriveType.
  ///
  /// In zh_CN, this message translates to:
  /// **'资源盘 / 默认盘 / 备份盘，对应同一个账号下的不同 drive_id'**
  String get formHintDriveType;

  /// No description provided for @optionDriveResource.
  ///
  /// In zh_CN, this message translates to:
  /// **'资源盘'**
  String get optionDriveResource;

  /// No description provided for @optionDriveDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认盘'**
  String get optionDriveDefault;

  /// No description provided for @optionDriveBackup.
  ///
  /// In zh_CN, this message translates to:
  /// **'备份盘'**
  String get optionDriveBackup;

  /// No description provided for @formLabelDeleteMode.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除方式'**
  String get formLabelDeleteMode;

  /// No description provided for @formHintDeleteMode.
  ///
  /// In zh_CN, this message translates to:
  /// **'移入回收站可在阿里云盘里找回；彻底删除不可恢复'**
  String get formHintDeleteMode;

  /// No description provided for @optionDeleteTrash.
  ///
  /// In zh_CN, this message translates to:
  /// **'移入回收站'**
  String get optionDeleteTrash;

  /// No description provided for @optionDeletePermanent.
  ///
  /// In zh_CN, this message translates to:
  /// **'彻底删除'**
  String get optionDeletePermanent;

  /// No description provided for @formHintTeraboxCookie.
  ///
  /// In zh_CN, this message translates to:
  /// **'必填；从浏览器复制 TeraBox 的 Cookie；过期后需重新粘贴'**
  String get formHintTeraboxCookie;

  /// No description provided for @formLabelRootPath.
  ///
  /// In zh_CN, this message translates to:
  /// **'根目录路径'**
  String get formLabelRootPath;

  /// No description provided for @formHintNeteaseCookie.
  ///
  /// In zh_CN, this message translates to:
  /// **'必填；需含 __csrf 与 MUSIC_U。登录 music.163.com 后从开发者工具复制完整 Cookie（获取方法见 OpenList 官方文档 netease_music 驱动页）'**
  String get formHintNeteaseCookie;

  /// No description provided for @formLabelSongLimit.
  ///
  /// In zh_CN, this message translates to:
  /// **'歌曲数量上限'**
  String get formLabelSongLimit;

  /// No description provided for @formHintSongLimit.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认 {a}；网易云盘接口按此上限一次列取'**
  String formHintSongLimit(Object a);

  /// No description provided for @formLabelSourceAccount.
  ///
  /// In zh_CN, this message translates to:
  /// **'源账号'**
  String get formLabelSourceAccount;

  /// No description provided for @formHintSourceAccount.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择现有 WebDAV 或网盘账号作为加密源'**
  String get formHintSourceAccount;

  /// No description provided for @formLabelSourceDir.
  ///
  /// In zh_CN, this message translates to:
  /// **'源目录'**
  String get formLabelSourceDir;

  /// No description provided for @formHintSourceDir.
  ///
  /// In zh_CN, this message translates to:
  /// **'源账号浏览根下的目录，默认 /（加密文件就存在这里）'**
  String get formHintSourceDir;

  /// No description provided for @formLabelFilenameEncoding.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件名编码'**
  String get formLabelFilenameEncoding;

  /// No description provided for @formHintFilenameEncoding.
  ///
  /// In zh_CN, this message translates to:
  /// **'与 rclone 的 filename_encoding 对应（base32 / base64 / base32768）'**
  String get formHintFilenameEncoding;

  /// No description provided for @formLabelEncryptedSuffix.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件名后缀'**
  String get formLabelEncryptedSuffix;

  /// No description provided for @formHintEncryptedSuffix.
  ///
  /// In zh_CN, this message translates to:
  /// **'仅文件名加密=关闭时生效（OpenList encrypted_suffix）'**
  String get formHintEncryptedSuffix;

  /// No description provided for @formLabelPassword.
  ///
  /// In zh_CN, this message translates to:
  /// **'密码'**
  String get formLabelPassword;

  /// No description provided for @formLabelSalt.
  ///
  /// In zh_CN, this message translates to:
  /// **'盐值（可选）'**
  String get formLabelSalt;

  /// No description provided for @formHintSalt.
  ///
  /// In zh_CN, this message translates to:
  /// **'留空用 rclone 内置默认盐；密码 + 盐相同即可与 rclone / OpenList 互认'**
  String get formHintSalt;

  /// No description provided for @formLabelFilenameEncryption.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件名加密'**
  String get formLabelFilenameEncryption;

  /// No description provided for @optionCryptStandard.
  ///
  /// In zh_CN, this message translates to:
  /// **'标准 (EME)'**
  String get optionCryptStandard;

  /// No description provided for @optionCryptObfuscate.
  ///
  /// In zh_CN, this message translates to:
  /// **'混淆'**
  String get optionCryptObfuscate;

  /// No description provided for @optionCryptOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭'**
  String get optionCryptOff;

  /// No description provided for @formLabelDirNameEncryption.
  ///
  /// In zh_CN, this message translates to:
  /// **'目录名加密'**
  String get formLabelDirNameEncryption;

  /// No description provided for @formSubDirNameEncryption.
  ///
  /// In zh_CN, this message translates to:
  /// **'OpenList 默认关闭；开启后目录名同样加密'**
  String get formSubDirNameEncryption;

  /// No description provided for @svcNoLocalCache.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地无缓存，请先下载'**
  String get svcNoLocalCache;

  /// No description provided for @svcCacheNotInitialized.
  ///
  /// In zh_CN, this message translates to:
  /// **'CacheService 未初始化'**
  String get svcCacheNotInitialized;

  /// No description provided for @svcBackupAccountMissingId.
  ///
  /// In zh_CN, this message translates to:
  /// **'备份账号缺少 id，无法安全恢复'**
  String get svcBackupAccountMissingId;

  /// No description provided for @svcLocalFileUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地文件不可用'**
  String get svcLocalFileUnavailable;

  /// No description provided for @backupTooShort.
  ///
  /// In zh_CN, this message translates to:
  /// **'备份文件过短或损坏'**
  String get backupTooShort;

  /// No description provided for @backupNotEncrypted.
  ///
  /// In zh_CN, this message translates to:
  /// **'不是加密备份（缺少 {magic} 头）'**
  String backupNotEncrypted(Object magic);

  /// No description provided for @backupCiphertextDamaged.
  ///
  /// In zh_CN, this message translates to:
  /// **'备份密文损坏'**
  String get backupCiphertextDamaged;

  /// No description provided for @vaultCiphertextDamaged.
  ///
  /// In zh_CN, this message translates to:
  /// **'凭证密文损坏'**
  String get vaultCiphertextDamaged;

  /// No description provided for @vaultNoteEncrypted.
  ///
  /// In zh_CN, this message translates to:
  /// **'密码类字段（含云盘驱动令牌）加密（AES-256-GCM），其余字段为明文。'**
  String get vaultNoteEncrypted;

  /// No description provided for @vaultNotePlain.
  ///
  /// In zh_CN, this message translates to:
  /// **'密码类字段为明文存储。'**
  String get vaultNotePlain;

  /// No description provided for @mediaArtistWebdav.
  ///
  /// In zh_CN, this message translates to:
  /// **'WebDAV 流媒体'**
  String get mediaArtistWebdav;

  /// No description provided for @ntfProbeHint.
  ///
  /// In zh_CN, this message translates to:
  /// **' | 若仍无通知: 设置→应用→Webdav Media Manager→耗电管理=不限制;通知=允许(含锁屏/悬浮); 通道「{channel}」勿关闭'**
  String ntfProbeHint(Object channel);

  /// No description provided for @ntfProbeRunning.
  ///
  /// In zh_CN, this message translates to:
  /// **'运行'**
  String get ntfProbeRunning;

  /// No description provided for @ntfProbeNone.
  ///
  /// In zh_CN, this message translates to:
  /// **'无'**
  String get ntfProbeNone;

  /// No description provided for @ntfProbeActive.
  ///
  /// In zh_CN, this message translates to:
  /// **'活跃'**
  String get ntfProbeActive;

  /// No description provided for @ntfProbeInactive.
  ///
  /// In zh_CN, this message translates to:
  /// **'否'**
  String get ntfProbeInactive;

  /// No description provided for @ntfProbePosted.
  ///
  /// In zh_CN, this message translates to:
  /// **'已发布'**
  String get ntfProbePosted;

  /// No description provided for @ntfProbeNotPosted.
  ///
  /// In zh_CN, this message translates to:
  /// **'未发布'**
  String get ntfProbeNotPosted;

  /// No description provided for @ntfProbeChanMissing.
  ///
  /// In zh_CN, this message translates to:
  /// **'(未创建)'**
  String get ntfProbeChanMissing;

  /// No description provided for @ntfProbeChanBlocked.
  ///
  /// In zh_CN, this message translates to:
  /// **'(已关闭)'**
  String get ntfProbeChanBlocked;

  /// No description provided for @ntfProbeReport.
  ///
  /// In zh_CN, this message translates to:
  /// **'服务={svc} 会话={session} 通知={posted} 系统通知开关={perm} 通道={channel}{chanState} 重要性={importance} 本包会话数={sessions} 设备={device}{hint}'**
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
  );

  /// No description provided for @ntfProbeReturn.
  ///
  /// In zh_CN, this message translates to:
  /// **'探测返回: {raw}'**
  String ntfProbeReturn(Object raw);

  /// No description provided for @ntfProbeChannelUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'原生探测通道不可用（需完整 APK）'**
  String get ntfProbeChannelUnavailable;

  /// No description provided for @ntfProbeFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'探测失败: {message}'**
  String ntfProbeFailed(Object message);

  /// No description provided for @ntfForceNoAudio.
  ///
  /// In zh_CN, this message translates to:
  /// **'无可用本地音频。请先播放一首歌，再点测试。\n{probe}{error}'**
  String ntfForceNoAudio(Object error, Object probe);

  /// No description provided for @ntfForcePlayed.
  ///
  /// In zh_CN, this message translates to:
  /// **'已强制播放「{title}」 playing={state}\n{probe}{error}\n请查看通知栏 / 媒体控制中心。'**
  String ntfForcePlayed(Object error, Object probe, Object state, Object title);

  /// No description provided for @ntfAsyncError.
  ///
  /// In zh_CN, this message translates to:
  /// **'\n⚠ audio_service 桥接错误: {error}'**
  String ntfAsyncError(Object error);

  /// No description provided for @phArtist.
  ///
  /// In zh_CN, this message translates to:
  /// **'作者'**
  String get phArtist;

  /// No description provided for @phTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'标题'**
  String get phTitle;

  /// No description provided for @phAlbum.
  ///
  /// In zh_CN, this message translates to:
  /// **'专辑'**
  String get phAlbum;

  /// No description provided for @phAlbumArtist.
  ///
  /// In zh_CN, this message translates to:
  /// **'专辑作者'**
  String get phAlbumArtist;

  /// No description provided for @phTrack.
  ///
  /// In zh_CN, this message translates to:
  /// **'音轨号'**
  String get phTrack;

  /// No description provided for @phYear.
  ///
  /// In zh_CN, this message translates to:
  /// **'年份'**
  String get phYear;

  /// No description provided for @phGenre.
  ///
  /// In zh_CN, this message translates to:
  /// **'流派'**
  String get phGenre;

  /// No description provided for @phFileName.
  ///
  /// In zh_CN, this message translates to:
  /// **'原文件名'**
  String get phFileName;

  /// No description provided for @videoStreamingHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频直接流式播放，不下载到本地。'**
  String get videoStreamingHint;

  /// No description provided for @videoHardwareDecoding.
  ///
  /// In zh_CN, this message translates to:
  /// **'硬件解码'**
  String get videoHardwareDecoding;

  /// No description provided for @videoHardwareDecodingHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭后改用软件解码，个别设备更稳定'**
  String get videoHardwareDecodingHint;

  /// No description provided for @videoScanSubdirsHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放列表是否包含子目录里的视频'**
  String get videoScanSubdirsHint;

  /// No description provided for @videoBufferSize.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓冲大小'**
  String get videoBufferSize;

  /// No description provided for @videoBufferInput.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓冲 (MB)'**
  String get videoBufferInput;

  /// No description provided for @videoGestures.
  ///
  /// In zh_CN, this message translates to:
  /// **'手势'**
  String get videoGestures;

  /// No description provided for @videoGestureLeftDoubleTap.
  ///
  /// In zh_CN, this message translates to:
  /// **'左侧双击'**
  String get videoGestureLeftDoubleTap;

  /// No description provided for @videoGestureRightDoubleTap.
  ///
  /// In zh_CN, this message translates to:
  /// **'右侧双击'**
  String get videoGestureRightDoubleTap;

  /// No description provided for @videoGestureLongPress.
  ///
  /// In zh_CN, this message translates to:
  /// **'长按'**
  String get videoGestureLongPress;

  /// No description provided for @videoLongPressRate.
  ///
  /// In zh_CN, this message translates to:
  /// **'长按临时倍速'**
  String get videoLongPressRate;

  /// No description provided for @videoDefaultRate.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认播放倍速'**
  String get videoDefaultRate;

  /// No description provided for @videoSubtitles.
  ///
  /// In zh_CN, this message translates to:
  /// **'字幕'**
  String get videoSubtitles;

  /// No description provided for @videoSubtitleHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'控件显示时画在控件条上方，隐藏时贴窗口底部。'**
  String get videoSubtitleHint;

  /// No description provided for @videoSubtitleSize.
  ///
  /// In zh_CN, this message translates to:
  /// **'字幕大小'**
  String get videoSubtitleSize;

  /// No description provided for @videoPlaybackBehavior.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放行为'**
  String get videoPlaybackBehavior;

  /// No description provided for @videoBackgroundPlayback.
  ///
  /// In zh_CN, this message translates to:
  /// **'后台播放'**
  String get videoBackgroundPlayback;

  /// No description provided for @videoBackgroundPlaybackHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'离开播放器后继续播放声音'**
  String get videoBackgroundPlaybackHint;

  /// No description provided for @videoPip.
  ///
  /// In zh_CN, this message translates to:
  /// **'画中画（小窗）'**
  String get videoPip;

  /// No description provided for @videoPipHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放控件中显示画中画按钮（Android 8+）'**
  String get videoPipHint;

  /// No description provided for @videoBufferSaved.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓冲大小已保存，下次播放生效'**
  String get videoBufferSaved;

  /// No description provided for @videoBufferCurrent.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前 {current} MB（范围 {min}–{max} MB）'**
  String videoBufferCurrent(Object current, Object max, Object min);

  /// No description provided for @videoLongPressCurrent.
  ///
  /// In zh_CN, this message translates to:
  /// **'按住加速到 {rate}×，松手恢复'**
  String videoLongPressCurrent(Object rate);

  /// No description provided for @videoDefaultRateCurrent.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前 {rate}×（范围 {min}×–{max}×）'**
  String videoDefaultRateCurrent(Object max, Object min, Object rate);

  /// No description provided for @videoSubtitleSizeCurrent.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前 {size} sp（范围 {min}–{max} sp）'**
  String videoSubtitleSizeCurrent(Object max, Object min, Object size);

  /// No description provided for @accountsSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'管理多服务器账号'**
  String get accountsSubtitle;

  /// No description provided for @audioStreamingSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'流式传输开关 / 搜索子目录'**
  String get audioStreamingSubtitle;

  /// No description provided for @fileTypesManage.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件后缀管理'**
  String get fileTypesManage;

  /// No description provided for @fileTypesManageSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'音乐 / 视频 / CUE 后缀与默认操作'**
  String get fileTypesManageSubtitle;

  /// No description provided for @coverThumbSize.
  ///
  /// In zh_CN, this message translates to:
  /// **'封面缩略图尺寸'**
  String get coverThumbSize;

  /// No description provided for @coverThumbHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'新封面按此边长生成；已有封面需重新生成。'**
  String get coverThumbHint;

  /// No description provided for @coverSize.
  ///
  /// In zh_CN, this message translates to:
  /// **'边长 (px)'**
  String get coverSize;

  /// No description provided for @cacheCleanup.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存清理'**
  String get cacheCleanup;

  /// No description provided for @cacheCleanupHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'仅清理音频缓存（播放/下载中的保留），标签与封面不受影响。'**
  String get cacheCleanupHint;

  /// No description provided for @currentCacheUsage.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前缓存占用'**
  String get currentCacheUsage;

  /// No description provided for @calculating.
  ///
  /// In zh_CN, this message translates to:
  /// **'计算中…'**
  String get calculating;

  /// No description provided for @unknown.
  ///
  /// In zh_CN, this message translates to:
  /// **'未知'**
  String get unknown;

  /// No description provided for @refresh.
  ///
  /// In zh_CN, this message translates to:
  /// **'刷新'**
  String get refresh;

  /// No description provided for @customRetentionHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义保留时长（至少 1 小时）'**
  String get customRetentionHint;

  /// No description provided for @days.
  ///
  /// In zh_CN, this message translates to:
  /// **'天'**
  String get days;

  /// No description provided for @hours.
  ///
  /// In zh_CN, this message translates to:
  /// **'小时'**
  String get hours;

  /// No description provided for @autoCleanupDisabled.
  ///
  /// In zh_CN, this message translates to:
  /// **'已关闭自动清理，可用下方按钮手动清空。'**
  String get autoCleanupDisabled;

  /// No description provided for @clearAudioCache.
  ///
  /// In zh_CN, this message translates to:
  /// **'手动清空音频缓存'**
  String get clearAudioCache;

  /// No description provided for @shareRenameHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'分享时按标签重命名文件名。'**
  String get shareRenameHint;

  /// No description provided for @shareRenameTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'分享时按标签重命名'**
  String get shareRenameTitle;

  /// No description provided for @shareRenameSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认开启；分享单个文件时仍可再修改文件名'**
  String get shareRenameSubtitle;

  /// No description provided for @renameTemplate.
  ///
  /// In zh_CN, this message translates to:
  /// **'重命名模板'**
  String get renameTemplate;

  /// No description provided for @syncSettings.
  ///
  /// In zh_CN, this message translates to:
  /// **'同步与备份设置'**
  String get syncSettings;

  /// No description provided for @shareRenameTemplate.
  ///
  /// In zh_CN, this message translates to:
  /// **'分享重命名模板'**
  String get shareRenameTemplate;

  /// No description provided for @videoPrevious.
  ///
  /// In zh_CN, this message translates to:
  /// **'上一个视频'**
  String get videoPrevious;

  /// No description provided for @videoNext.
  ///
  /// In zh_CN, this message translates to:
  /// **'下一个视频'**
  String get videoNext;

  /// No description provided for @videoLockScreen.
  ///
  /// In zh_CN, this message translates to:
  /// **'锁定屏幕'**
  String get videoLockScreen;

  /// No description provided for @videoOrientation.
  ///
  /// In zh_CN, this message translates to:
  /// **'切换横竖屏'**
  String get videoOrientation;

  /// No description provided for @videoLockHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'隐藏控件并禁用手势，长按解锁'**
  String get videoLockHint;

  /// No description provided for @videoOrientationLock.
  ///
  /// In zh_CN, this message translates to:
  /// **'锁定旋转方向'**
  String get videoOrientationLock;

  /// No description provided for @videoOrientationLockHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'固定为当前横屏/竖屏'**
  String get videoOrientationLockHint;

  /// No description provided for @videoExitConfirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'退出时二次确认'**
  String get videoExitConfirm;

  /// No description provided for @videoExitConfirmHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'返回时二次确认'**
  String get videoExitConfirmHint;

  /// No description provided for @videoGestureSettingsHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'双击 / 长按动作与长按倍速'**
  String get videoGestureSettingsHint;

  /// No description provided for @cacheCleared.
  ///
  /// In zh_CN, this message translates to:
  /// **'已清理 {count} 个缓存文件（{libraryCount} 首元数据保留）'**
  String cacheCleared(Object count, Object libraryCount);

  /// No description provided for @tagRefreshStarted.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在后台更新本地缓存曲目的标签'**
  String get tagRefreshStarted;

  /// No description provided for @tagRefreshCompleted.
  ///
  /// In zh_CN, this message translates to:
  /// **'标签更新完成：更新 {updated} 首，跳过 {skipped} 首，失败 {failed} 首'**
  String tagRefreshCompleted(Object failed, Object skipped, Object updated);

  /// No description provided for @notificationEnabled.
  ///
  /// In zh_CN, this message translates to:
  /// **'通知权限已开启，播放时会显示媒体通知'**
  String get notificationEnabled;

  /// No description provided for @notificationOpenSettings.
  ///
  /// In zh_CN, this message translates to:
  /// **'请在系统设置中允许通知后返回应用'**
  String get notificationOpenSettings;

  /// No description provided for @notificationOpenSettingsFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'无法打开系统设置，请手动允许通知权限'**
  String get notificationOpenSettingsFailed;

  /// No description provided for @notificationGranted.
  ///
  /// In zh_CN, this message translates to:
  /// **'已授予通知权限'**
  String get notificationGranted;

  /// No description provided for @notificationDenied.
  ///
  /// In zh_CN, this message translates to:
  /// **'未授予通知权限，媒体通知可能无法显示'**
  String get notificationDenied;

  /// No description provided for @retentionDaysHours.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前：保留 {days} 天 {hours} 小时未访问的音频'**
  String retentionDaysHours(Object days, Object hours);

  /// No description provided for @retentionDays.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前：保留 {days} 天未访问的音频'**
  String retentionDays(Object days);

  /// No description provided for @retentionHours.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前：保留 {hours} 小时未访问的音频'**
  String retentionHours(Object hours);

  /// No description provided for @notificationChecking.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在检查…'**
  String get notificationChecking;

  /// No description provided for @notificationStatusAllowed.
  ///
  /// In zh_CN, this message translates to:
  /// **'已允许，播放/暂停时显示媒体通知'**
  String get notificationStatusAllowed;

  /// No description provided for @notificationChannelBlocked.
  ///
  /// In zh_CN, this message translates to:
  /// **'「音乐播放」通道被关闭，点此打开系统设置'**
  String get notificationChannelBlocked;

  /// No description provided for @notificationStatusDenied.
  ///
  /// In zh_CN, this message translates to:
  /// **'已拒绝，点此打开系统设置'**
  String get notificationStatusDenied;

  /// No description provided for @notificationChannelMissing.
  ///
  /// In zh_CN, this message translates to:
  /// **'「音乐播放」通道未创建，播放一次或点「刷新」重试'**
  String get notificationChannelMissing;

  /// No description provided for @notificationNotGranted.
  ///
  /// In zh_CN, this message translates to:
  /// **'未授权，点此请求通知权限'**
  String get notificationNotGranted;

  /// No description provided for @hintsAndNotifications.
  ///
  /// In zh_CN, this message translates to:
  /// **'提示与通知'**
  String get hintsAndNotifications;

  /// No description provided for @hintsSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'屏幕底部提示同时只显示一条，点「知道了」立即关闭。'**
  String get hintsSubtitle;

  /// No description provided for @hintDuration.
  ///
  /// In zh_CN, this message translates to:
  /// **'提示显示时长'**
  String get hintDuration;

  /// No description provided for @downloadNotifications.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载队列系统通知'**
  String get downloadNotifications;

  /// No description provided for @downloadNotificationsHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载进度与完成结果显示在通知栏'**
  String get downloadNotificationsHint;

  /// No description provided for @sendTestNotification.
  ///
  /// In zh_CN, this message translates to:
  /// **'发送测试通知'**
  String get sendTestNotification;

  /// No description provided for @sendTestNotificationHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'立即发一条进度与一条完成通知，用来排查系统是否拦截'**
  String get sendTestNotificationHint;

  /// No description provided for @testNotificationSent.
  ///
  /// In zh_CN, this message translates to:
  /// **'测试通知已发送（进度 + 完成各一条）'**
  String get testNotificationSent;

  /// No description provided for @testNotificationFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'测试通知失败：{error}'**
  String testNotificationFailed(Object error);

  /// No description provided for @confirmCloseVideo.
  ///
  /// In zh_CN, this message translates to:
  /// **'确认关闭视频吗？'**
  String get confirmCloseVideo;

  /// No description provided for @webdavNotConnectedPlay.
  ///
  /// In zh_CN, this message translates to:
  /// **'WebDAV 未连接，无法播放'**
  String get webdavNotConnectedPlay;

  /// No description provided for @videoQueueEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前没有播放列表'**
  String get videoQueueEmpty;

  /// No description provided for @pipUnsupported.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前设备/系统不支持画中画'**
  String get pipUnsupported;

  /// No description provided for @videoPlayFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'无法播放：{error}'**
  String videoPlayFailed(Object error);

  /// No description provided for @scanningFolder.
  ///
  /// In zh_CN, this message translates to:
  /// **'扫描文件夹中…'**
  String get scanningFolder;

  /// No description provided for @buffering.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓冲中…'**
  String get buffering;

  /// No description provided for @opening.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在打开'**
  String get opening;

  /// No description provided for @downloadKeepAlive.
  ///
  /// In zh_CN, this message translates to:
  /// **'后台下载保活'**
  String get downloadKeepAlive;

  /// No description provided for @downloadKeepAliveHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'开启后，下载期间通知栏会常驻一条下载通知（系统要求），关闭下载通知也会显示'**
  String get downloadKeepAliveHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'CN':
            return AppLocalizationsZhCn();
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
