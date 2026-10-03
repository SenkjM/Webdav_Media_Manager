// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Webdav Media Manager';

  @override
  String get settings => '设置';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageSimplifiedChinese => '简体中文';

  @override
  String get languageTraditionalChinese => '繁体中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get webdavServer => 'WebDAV 服务器';

  @override
  String get download => '下载';

  @override
  String get homeAndNavigation => '媒体库主页和导航';

  @override
  String get videoPlayback => '视频播放';

  @override
  String get fileTypes => '文件类型';

  @override
  String get mediaNotifications => '媒体通知';

  @override
  String get languageSettingSubtitle => '选择应用显示语言，重启后仍会保留';

  @override
  String get themeMode => '主题';

  @override
  String get themeModeSubtitle => '浅色、深色，或跟随系统';

  @override
  String get themeModeSystem => '跟随系统';

  @override
  String get themeModeLight => '浅色';

  @override
  String get themeModeDark => '深色';

  @override
  String get themeSeed => '主题色';

  @override
  String get themeSeedSubtitle => '浅色和深色都由这一个颜色生成';

  @override
  String get themeSeedReset => '恢复默认';

  @override
  String get themeSeedHue => '色相';

  @override
  String get themeSeedSaturation => '饱和度';

  @override
  String get themeSeedValue => '明度';

  @override
  String get library => '音乐库';

  @override
  String get playlists => '歌单';

  @override
  String get networkLibrary => '网络库';

  @override
  String get downloadQueue => '下载队列';

  @override
  String get aboutAgpl => '关于 / AGPL';

  @override
  String get exitApp => '退出应用';

  @override
  String get cancel => '取消';

  @override
  String get exit => '退出';

  @override
  String get cacheOneDay => '1 天';

  @override
  String get cacheOneWeek => '1 周';

  @override
  String get cacheCustom => '自定义';

  @override
  String get cacheNever => '永不';

  @override
  String get snackShort => '很短';

  @override
  String get snackNormal => '默认';

  @override
  String get snackLong => '较长';

  @override
  String get snackUntilDismissed => '点击才消失';

  @override
  String get snackOff => '关闭';

  @override
  String get syncOff => '关闭（仅手动）';

  @override
  String get syncEvery15m => '每 15 分钟';

  @override
  String get syncEvery30m => '每 30 分钟';

  @override
  String get syncHourly => '每 1 小时';

  @override
  String get syncEvery6h => '每 6 小时';

  @override
  String get syncDaily => '每 24 小时';

  @override
  String get actionCacheMusic => '缓存音乐';

  @override
  String get actionDownload => '下载';

  @override
  String get actionStream => '流式传输';

  @override
  String get actionReadCue => 'CUE 读取';

  @override
  String get actionStreamMusic => '流式传输（音乐）';

  @override
  String get actionShortCache => '缓存';

  @override
  String get actionShortDownload => '下载';

  @override
  String get actionShortStream => '播放';

  @override
  String get actionShortCue => 'CUE';

  @override
  String get actionShortStreamMusic => '流播';

  @override
  String get targetCache => '应用缓存';

  @override
  String get targetGallery => '系统相册';

  @override
  String get targetDownloads => '系统下载目录';

  @override
  String get musicModeSingle => '单曲循环';

  @override
  String get musicModeSequential => '顺序播放';

  @override
  String get musicModeLoop => '列表循环';

  @override
  String get playbackMode => '播放模式';

  @override
  String unboundSource(Object sourceName) {
    return '未绑定网盘「$sourceName」';
  }

  @override
  String get uncategorized => '未分类';

  @override
  String get unnamedPlaylist => '未命名歌单';

  @override
  String get defaultServer => '默认服务器';

  @override
  String get accountsTitle => '网盘账号管理';

  @override
  String get noAccounts => '尚未添加账号。点击右下角添加。';

  @override
  String get setCurrent => '设为当前';

  @override
  String get edit => '编辑';

  @override
  String get testConnection => '测试连接';

  @override
  String get delete => '删除';

  @override
  String get connectionSuccess => '连接成功';

  @override
  String get connectionFailed => '连接失败';

  @override
  String get deleteServer => '删除服务器';

  @override
  String confirmDeleteServer(Object name) {
    return '确定删除「$name」？其曲目会变成「未绑定网盘」，加回同名即可恢复。';
  }

  @override
  String get audioStreamingTitle => '音频流式';

  @override
  String get streamPlayback => '流式播放';

  @override
  String get streamPlaybackHint => '音乐不下载到本地，直接从网盘边听边传。';

  @override
  String get streamMusic => '流式传输音乐';

  @override
  String get streamMusicHint => '打开后音乐的文件动作里可以选「流式传输（音乐）」。关掉时该动作会被退回默认。';

  @override
  String get scanList => '列表扫描';

  @override
  String get scanListHint => '决定流式播放的「上一首 / 下一首」列表里都有什么。';

  @override
  String get scanSubdirectories => '搜索子目录';

  @override
  String get scanSubdirectoriesHint => '打开：当前目录及其所有子目录里的音频都进列表。关闭：只列当前这一层。';

  @override
  String get downloadPending => '等待中';

  @override
  String get downloadActive => '下载中';

  @override
  String get downloadCompleted => '已完成';

  @override
  String get downloadFailed => '失败';

  @override
  String get downloadCancelled => '已取消';

  @override
  String get downloadAll => '全部下载';

  @override
  String get wakeWaiting => '唤醒等待中任务';

  @override
  String get cancelAll => '全部取消';

  @override
  String get clearCompleted => '清除已完成';

  @override
  String get more => '更多';

  @override
  String get noDownloadTasks => '暂无下载任务';

  @override
  String get queueCleared => '下载队列已清空';

  @override
  String get clearAllQueue => '清除所有队列';

  @override
  String get cueAlbum => 'CUE';

  @override
  String songCount(Object count) {
    return '$count 首';
  }

  @override
  String get inProgress => '进行中';

  @override
  String retrying(Object current, Object max) {
    return '重试中（$current/$max）';
  }

  @override
  String get retry => '重试';

  @override
  String get clearQueueConfirm => '清除队列？';

  @override
  String clearQueueDetails(Object count, Object runningText) {
    return '将移除 $count 条队列记录$runningText；已下载的文件保留。';
  }

  @override
  String runningDownloads(Object count) {
    return '，并取消 $count 个进行中的下载';
  }

  @override
  String get clearAll => '清除全部';

  @override
  String get accountAddServer => '添加服务器';

  @override
  String get accountEditServer => '编辑服务器';

  @override
  String get accountName => '名称';

  @override
  String get accountNameHint => '曲库按此名称绑定，必须唯一；改名等同换盘';

  @override
  String get accountNameTaken => '该名称已被占用，建议换一个';

  @override
  String get accountType => '类型';

  @override
  String get accountRemotePath => '远程路径';

  @override
  String get accountRemotePathHint => '浏览根，默认 /（空置也是 /）';

  @override
  String get accountServerUrl => '服务器 URL';

  @override
  String get accountUsername => '用户名';

  @override
  String get accountPassword => '密码';

  @override
  String get accountPasswordKeep => '密码（留空则不修改）';

  @override
  String get accountPermissions => '权限';

  @override
  String get permissionRead => '读取';

  @override
  String get permissionWrite => '写入';

  @override
  String get permissionCreateFolder => '创建文件夹';

  @override
  String get permissionMove => '移动';

  @override
  String get permissionCopy => '复制';

  @override
  String get permissionDelete => '删除';

  @override
  String get accountFillName => '请填写名称';

  @override
  String accountUnknownProvider(Object providerType) {
    return '未知云盘类型：$providerType';
  }

  @override
  String accountFillField(Object label) {
    return '请填写 $label';
  }

  @override
  String accountSelectField(Object label) {
    return '请选择 $label';
  }

  @override
  String accountValidationFailed(Object error) {
    return '验证失败：$error';
  }

  @override
  String get accountSave => '保存';

  @override
  String accountAdded(Object name) {
    return '成功添加（$name）';
  }

  @override
  String get accountDuplicateTitle => '名称已被占用';

  @override
  String accountDuplicateContent(Object name, Object url) {
    return '已有同名网盘「$name」：\n$url\n\n同名会被当成同一来源。';
  }

  @override
  String get accountChangeName => '改个名字';

  @override
  String get accountKeepName => '仍然使用';

  @override
  String get accountRenameTitle => '改名等同于换盘';

  @override
  String get accountUsernameChangedTitle => '用户名已修改';

  @override
  String accountRenameContent(Object name) {
    return '「$name」的曲目将变为「未绑定网盘」，改回原名即可恢复。\n仅改地址时请保持名称不变。';
  }

  @override
  String get accountUsernameChangedContent => '用户名不参与绑定；新用户名对应别的目录时原路径可能不存在。';

  @override
  String get accountConfirmChange => '确认修改';

  @override
  String get accountBindingHint => '曲目按「名称 + 路径」绑定；改名等同于换盘。';

  @override
  String get manageAccounts => '管理多服务器账号';

  @override
  String get manageAccountsSubtitle => '添加 / 编辑 / 删除 WebDAV 服务器';

  @override
  String get downloadQueueSettings => '下载队列';

  @override
  String get downloadQueueSettingsSubtitle => '断点续传的临时文件保留上限与清理';

  @override
  String get customHome => '自定义主页';

  @override
  String get customHomeSubtitle => '从其他界面返回时回到此主页';

  @override
  String get rememberNetworkPath => '网络库记住上次路径';

  @override
  String get rememberNetworkPathSubtitle => '下次进入网络库时恢复上次浏览的目录';

  @override
  String get videoSettings => '视频播放设置';

  @override
  String get videoSettingsSubtitle => '流式参数 / 手势 / 后台播放 / 画中画';

  @override
  String get audioSettings => '音频流式设置';

  @override
  String get audioSettingsSubtitle => '流式传输开关 / 搜索子目录';

  @override
  String get fileExtensionSettings => '文件后缀管理';

  @override
  String get fileExtensionSettingsSubtitle => '音乐 / 视频 / 图片 / CUE 后缀与默认操作';

  @override
  String get refreshLibraryTags => '手动更新音乐库标签';

  @override
  String get refreshLibraryTagsSubtitle => '异步读取已缓存音乐文件的标签并更新曲库';

  @override
  String get networkNewFolder => '新建文件夹';

  @override
  String get manageServers => '管理服务器';

  @override
  String get currentServer => '当前服务器';

  @override
  String get networkRetry => '重试';

  @override
  String get emptyDirectory => '空目录';

  @override
  String get directory => '目录';

  @override
  String get cueFile => 'CUE 文件';

  @override
  String get playVideo => '播放视频';

  @override
  String get moreActions => '更多操作';

  @override
  String get cancelSelection => '取消全选';

  @override
  String get selectAll => '全选';

  @override
  String get cacheMusic => '缓存音乐';

  @override
  String get copyTo => '复制到';

  @override
  String get moveTo => '移动到';

  @override
  String get downloadAction => '下载';

  @override
  String get fileQueuedOrSaved => '该文件已在下载队列或已下载';

  @override
  String get fileQueuedOrSavedShort => '该文件已在队列或已保存';

  @override
  String get accountRequired => '请先添加 WebDAV 服务器';

  @override
  String get syncTitle => '同步与备份';

  @override
  String get syncIntro => '凭证、歌单与音乐库共用一条远端路径：在下面选网盘、填路径即可。';

  @override
  String get syncAll => '全部同步';

  @override
  String get scheduledSync => '定时同步';

  @override
  String get manualOnly => '已关闭，仅手动同步';

  @override
  String autoSync(Object interval) {
    return '$interval 自动同步';
  }

  @override
  String get remotePath => '远端路径';

  @override
  String get remotePathSubtitle => '凭证、音乐库、歌单与备份都放在这条路径下面';

  @override
  String get selectServer => '① 选择网盘';

  @override
  String get path => '② 路径';

  @override
  String get pathExample => '例如填 /player，音乐库就在 /player/library/';

  @override
  String get apply => '应用';

  @override
  String get encryptionKey => '统一加密密钥（由你指定）';

  @override
  String get encryptionKeyHint => '只保存在本机；留空则以明文存储。';

  @override
  String get keyNotSet => '当前：未设置（凭证与备份里的密码为明文）';

  @override
  String keySet(Object length) {
    return '当前：已设置（长度 $length）';
  }

  @override
  String get saveKey => '保存密钥';

  @override
  String get keySaved => '加密密钥已保存到本机';

  @override
  String operationFailed(Object error) {
    return '操作失败：$error';
  }

  @override
  String get rebuildThreshold => '重建提示阈值';

  @override
  String get cloudFragmentCount => '云端分片数';

  @override
  String get rebuildThresholdHint => '达到这个数量时提示重建（2–500）';

  @override
  String get confirm => '确定';

  @override
  String get exitConfirm => '确定退出？播放将停止。';

  @override
  String get menu => '菜单';

  @override
  String get aboutTitle => '关于';

  @override
  String aboutVersion(Object version) {
    return '版本 $version';
  }

  @override
  String get aboutCiVersion =>
      'CI 预发布写入 versionName（含短 hash）与递增 versionCode，可覆盖安装。';

  @override
  String get aboutDescription => '浏览网盘目录，下载到本地缓存后播放。';

  @override
  String get aboutCredits => '作者与致谢';

  @override
  String get aboutImplementation => '实现：Grok Bot';

  @override
  String get aboutConcept => '创意与需求框架：SenkjM';

  @override
  String get aboutLicense => '许可证';

  @override
  String get aboutLicenseText =>
      '本项目采用 GNU Affero General Public License v3.0（AGPL-3.0）授权。\\n\\n你可以自由使用、修改与分发本软件，但若发布修改版，或通过网络提供基于本软件的服务，必须按 AGPL-3.0 公开对应完整源代码。完整文本见仓库 LICENSE 文件。';

  @override
  String get fileExtSaved => '后缀配置已保存';

  @override
  String get fileExtIntro =>
      '按后缀识别文件类型；多个后缀用空格或逗号分隔。返回网络库刷新后生效。下面每一类的「单击行为」就是网络库点按该文件时的动作，多选工具栏与「更多」菜单遵循同一套判定。';

  @override
  String get fileCatMusic => '音乐文件';

  @override
  String get fileCatVideo => '视频文件';

  @override
  String get fileCatCue => 'CUE 文件';

  @override
  String get fileCatOther => '普通文件';

  @override
  String fileExtDefaultAction(Object action) {
    return '点按默认动作：$action';
  }

  @override
  String fileExtCueNote(Object action) {
    return '点按默认动作：$action（CUE 读取会解析分片并整组下载）';
  }

  @override
  String fileExtOtherNote(Object action) {
    return '点按默认动作：$action（不在上面三张列表里的后缀，下载到系统下载目录）';
  }

  @override
  String get fileExtTapAction => '点按行为';

  @override
  String get fileExtHintExample => '例如：mp3 flac m4a';

  @override
  String get fileExtListLabel => '后缀列表';

  @override
  String get restoreDefault => '恢复默认';

  @override
  String get dlPartFilesTitle => '断点续传的临时文件';

  @override
  String get dlPartFilesIntro =>
      '网络中断重试时会从半截文件接着下。文件留着才续得上，所以这里配的是上限：超过上限的部分会被自动清掉（没有对应下载任务的孤儿文件也会清）。';

  @override
  String get dlRetainDuration => '保留时长';

  @override
  String get unitHours => '小时';

  @override
  String get dlTotalSizeLimit => '总体积上限';

  @override
  String get dlCryptSequential => 'Crypt 顺序流';

  @override
  String get dlCryptSequentialSub => '仅影响下载任务，在线播放和传统续传不变';

  @override
  String get dlCleanNow => '立即清理';

  @override
  String get dlCleanNowSub => '按上面的上限删掉过期的半截文件';

  @override
  String get dlNothingToClean => '没有需要清理的半截文件';

  @override
  String dlCleanedCount(Object count) {
    return '已清理 $count 个半截文件';
  }

  @override
  String dlFieldNotNumber(Object field) {
    return '$field请填数字';
  }

  @override
  String dlFieldClamped(
    Object field,
    Object max,
    Object min,
    Object unit,
    Object value,
  ) {
    return '$field只能在 $min~$max$unit 之间，已按 $value 保存';
  }

  @override
  String dlRangeHint(Object max, Object min, Object unit) {
    return '范围 $min ~ $max $unit，超范围按边界保存';
  }

  @override
  String get playlistQueueEmpty => '当前播放列表为空';

  @override
  String playlistQueueDefaultName(Object day, Object month) {
    return '播放列表 $month/$day';
  }

  @override
  String get playlistCreateFromQueue => '从当前播放列表创建';

  @override
  String playlistCreateFromQueueBody(Object count) {
    return '复制当前队列 $count 首到新歌单。';
  }

  @override
  String get playlistNameLabel => '歌单名称';

  @override
  String get create => '创建';

  @override
  String playlistCreated(Object name) {
    return '已创建歌单「$name」';
  }

  @override
  String get playlistNew => '新建歌单';

  @override
  String get nameLabel => '名称';

  @override
  String get playlistsTitle => '歌单';

  @override
  String get playlistSyncTooltip => '从 WebDAV 同步';

  @override
  String get playlistSynced => '已同步歌单';

  @override
  String playlistSyncFailed(Object error) {
    return '同步失败：$error';
  }

  @override
  String get playlistsEmpty => '暂无歌单：右上角「+」新建，或在音乐库长按曲目添加。';

  @override
  String playlistTrackCount(Object count) {
    return '$count 首';
  }

  @override
  String get playlistRename => '重命名歌单';

  @override
  String get save => '保存';

  @override
  String get playlistDelete => '删除歌单';

  @override
  String playlistDeleteConfirm(Object name) {
    return '确定删除「$name」？本地与 WebDAV 上的对应文件都会删除。';
  }

  @override
  String get rename => '重命名';

  @override
  String get playlistNewEllipsis => '新建歌单…';

  @override
  String get playlistAddTo => '添加到歌单';

  @override
  String get playlistAdded => '已添加到歌单';

  @override
  String playlistAddMany(Object count) {
    return '添加 $count 首到歌单';
  }

  @override
  String playlistAddedMany(Object count) {
    return '已添加 $count 首到歌单';
  }

  @override
  String get playlistNotFound => '歌单不存在';

  @override
  String get playlistAddFromLibrary => '从音乐库添加';

  @override
  String get playlistEmpty => '歌单为空，可从音乐库添加。';

  @override
  String playlistMissingInLibrary(Object name) {
    return '暂无 · $name';
  }

  @override
  String get libraryEmpty => '音乐库中没有曲目';

  @override
  String get notDownloaded => '未下载';

  @override
  String get downloaded => '已下载';

  @override
  String get tapToDownload => '点按加入下载';

  @override
  String get streamNotConnected => 'WebDAV 未连接，无法流式播放';

  @override
  String get playlistSheetTitle => '播放列表';

  @override
  String get searchList => '搜索列表';

  @override
  String get noMatchingTracks => '没有匹配的曲目';

  @override
  String get streamUrlFailed => '无法建立流式地址，请检查账户配置';

  @override
  String get loading => '加载中…';

  @override
  String get back => '返回';

  @override
  String get streamingNotCached => '流式传输 · 未缓存';

  @override
  String seekSeconds(Object seconds) {
    return '$seconds 秒';
  }

  @override
  String get previousTrack => '上一首';

  @override
  String get pause => '暂停';

  @override
  String get play => '播放';

  @override
  String get nextTrack => '下一首';

  @override
  String playbackFailed(Object error) {
    return '播放失败：$error';
  }

  @override
  String get newFolder => '新建文件夹';

  @override
  String get close => '关闭';

  @override
  String get parentFolder => '上一级';

  @override
  String get pickThisFolder => '到此文件夹';

  @override
  String get noSubfolders => '这个目录里没有子文件夹';

  @override
  String movedItems(Object count) {
    return '已移动 $count 项';
  }

  @override
  String copiedItems(Object count) {
    return '已复制 $count 项';
  }

  @override
  String failedWith(Object reason) {
    return '失败：$reason';
  }

  @override
  String movePartialResult(Object done, Object failed, Object reason) {
    return '成功 $done 项，失败 $failed 项：$reason';
  }

  @override
  String get nowPlayingQueueTitle => '当前播放列表';

  @override
  String nowPlayingQueueCount(Object count) {
    return '当前播放列表（$count）';
  }

  @override
  String get nowPlayingQueueEmpty => '当前没有播放队列。\n从音乐库或网络库开始播放后会出现在此。';

  @override
  String playerChipAlbumArtist(Object artist) {
    return '专辑艺人 · $artist';
  }

  @override
  String playerChipTrackNumber(Object n, Object total) {
    return '曲目 $n/$total';
  }

  @override
  String playerChipTrackNoTotal(Object n) {
    return '曲目 $n';
  }

  @override
  String playerChipDiscNumber(Object n, Object total) {
    return '碟 $n/$total';
  }

  @override
  String playerChipDiscNoTotal(Object n) {
    return '碟 $n';
  }

  @override
  String get playerRowAccount => '账号';

  @override
  String get playerRowServer => '服务器';

  @override
  String get playerRowRemotePath => '远程路径';

  @override
  String get playerRowFileName => '文件名';

  @override
  String get playerRowType => '类型';

  @override
  String get playerRowCueNoteKey => '说明';

  @override
  String get playerRowCueNote => '来自 CUE 分片，播放与缓存共用源音频。';

  @override
  String get playerRowCueFile => 'CUE 文件';

  @override
  String get playerRowSourceAudio => '源音频';

  @override
  String get playerRowCueTrackIndex => 'CUE 曲序';

  @override
  String get playerClipEnd => '结尾';

  @override
  String get playerRowClipRange => '分片区间';

  @override
  String get playerRowLocalCache => '本地缓存';

  @override
  String get playerNotDownloaded => '未下载';

  @override
  String get playerRowFileSize => '文件大小';

  @override
  String get playerFileDetails => '文件详情';

  @override
  String get copyAll => '复制全部';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String copiedKey(Object key) {
    return '已复制：$key';
  }

  @override
  String get tagsUpdatedFromLocal => '已从本地文件更新标签';

  @override
  String get tagsNeedDownloadFirst => '该曲目尚未缓存，请先下载后再更新标签';

  @override
  String get updateThisTrackTags => '更新此曲标签';

  @override
  String get nowPlaying => '正在播放';

  @override
  String get noTrackSelected => '未选择曲目';

  @override
  String get dlSavedToGallery => '已存入系统相册';

  @override
  String get dlTargetGallery => '目标：系统相册';

  @override
  String get dlSavedToDownloads => '已存入下载目录';

  @override
  String get dlTargetDownloads => '目标：下载目录';

  @override
  String get rebuildHintThreshold => '重建提示阈值';

  @override
  String get cloudFragmentCountLabel => '云端分片数';

  @override
  String get cloudFragmentCountHelper => '达到这个数量时提示重建（2–500）';

  @override
  String get unifiedEncryptionKey => '统一加密密钥（由你指定）';

  @override
  String get unifiedEncryptionKeyHint => '只保存在本机；留空则以明文存储。';

  @override
  String get keyNotSetLong => '当前：未设置（凭证与备份里的密码为明文）';

  @override
  String keySetLong(Object length) {
    return '当前：已设置（长度 $length）';
  }

  @override
  String get keySavedNotice => '加密密钥已保存到本机';

  @override
  String get overwriteLibraryTitle => '从云端覆写音乐库';

  @override
  String get overwriteLibraryBody => '会从云端下载音乐库数据库并覆写本地。';

  @override
  String get overwriteLibraryNote =>
      '本地索引、标签与尚未同步的改动会被云端那份替换；已下载的音频、封面与缓存不会删除。';

  @override
  String get overwriteLibraryAction => '覆写';

  @override
  String get overwriteLibraryPhrase => '如果确认覆写请输入 YES';

  @override
  String get destroyLibraryTitle => '销毁音乐库';

  @override
  String get destroyLibraryBody => '会逐条销毁本地音乐库：每一首的缓存音频、封面与库记录都会被删除，并各留一条墓碑。';

  @override
  String get destroyLibraryNote =>
      '删除记录会在下次同步时上传到云端，云端重建也恢复不了这次销毁的内容。此操作后会关闭自动同步。';

  @override
  String get destroyLibraryAction => '销毁';

  @override
  String get destroyLibraryPhrase => '如果确认销毁请输入 YES';

  @override
  String destroyLibraryDone(Object count) {
    return '已销毁 $count 首；下次同步上传删除记录，定时同步已关闭';
  }

  @override
  String readCloudLibraryFailed(Object error) {
    return '读取云端库失败：$error';
  }

  @override
  String get tidyCloudLibraryTitle => '整理云端音乐库';

  @override
  String get missingFragments => '有分片缺失，只能重建。';

  @override
  String missingFragmentName(Object name) {
    return '• 缺 $name';
  }

  @override
  String get orphanFiles => '孤儿文件：清单没引用，可删除。';

  @override
  String get auditHealthy => '一切一致，无需处理。';

  @override
  String get deleteOrphans => '删除孤儿文件';

  @override
  String get rebuildFromLocal => '以本机为准重建';

  @override
  String orphansDeleted(Object count) {
    return '已删除 $count 个孤儿文件';
  }

  @override
  String get restoreConfirmTitle => '确认恢复';

  @override
  String get restoreConfirmBody => '将用备份覆盖本机账号凭证、音乐库与歌单，不可撤销。';

  @override
  String get restore => '恢复';

  @override
  String exportedTo(Object fileName, Object location) {
    return '已导出到$location：$fileName';
  }

  @override
  String exportFailed(Object error) {
    return '导出失败：$error';
  }

  @override
  String pickFileFailed(Object error) {
    return '选择文件失败：$error';
  }

  @override
  String get pasteBase64First => '请先粘贴备份内容（Base64）';

  @override
  String remoteRootUpdated(Object path) {
    return '远端路径已更新：$path';
  }

  @override
  String get derivedPathCredentials => '账号凭证';

  @override
  String get derivedPathPlaylists => '歌单';

  @override
  String get derivedPathLibrary => '音乐库';

  @override
  String get derivedPathBackups => '全部备份';

  @override
  String get syncAndBackup => '备份与同步';

  @override
  String get syncIntroLong => '凭证、歌单与音乐库共用一条远端路径：在下面选网盘、填路径即可。';

  @override
  String get scheduledSyncOff => '已关闭，仅手动同步';

  @override
  String scheduledSyncAuto(Object interval) {
    return '$interval 自动同步';
  }

  @override
  String get remotePathSubtitleLong => '凭证、歌单、音乐库与备份都放在这条路径下面';

  @override
  String get needWebdavServer => '请先添加 WebDAV 服务器。';

  @override
  String get selectCloudDrive => '① 选择网盘';

  @override
  String get pathStep => '② 路径';

  @override
  String get pathExampleLong => '例如填 /player，音乐库就在 /player/library/';

  @override
  String get credentialsSection => '账号凭证';

  @override
  String credentialsSectionDesc(Object path) {
    return '云端 $path：全部网盘账号；密码类字段加密，不支持类型的账号恢复时自动跳过。';
  }

  @override
  String get encryptPasswordField => '加密密码类字段';

  @override
  String get encryptPasswordOn => '口令不匹配时密码留空';

  @override
  String get encryptPasswordOff => '明文保存密码';

  @override
  String lastAutoScan(Object time) {
    return '上次自动扫描：$time';
  }

  @override
  String get uploadCredentials => '上传凭证';

  @override
  String get downloadCredentials => '下载凭证';

  @override
  String get playlistsSection => '歌单';

  @override
  String playlistsSectionDesc(Object path) {
    return '双向同步。整份歌单按最后写入合并；每个歌单另有一份删除记录，避免其它设备把已删歌单或曲目重新传上来：$path';
  }

  @override
  String get syncPlaylistsNow => '立即同步歌单';

  @override
  String get compactPlaylistDeletions => '清理删除记录';

  @override
  String get compactPlaylistDeletionsHint => '以当前歌单为快照，删掉各歌单的删除记录包。没有定时提醒。';

  @override
  String get librarySection => '音乐库';

  @override
  String librarySectionDesc(Object path) {
    return '${path}index.json 清单 + lib/seg/del 分片；只传变化，删除在重建时落实。';
  }

  @override
  String cloudFragmentsLine(Object count, Object hint, Object size) {
    return '云端分片：$count 个（约 $size）$hint';
  }

  @override
  String get cloudFragmentsHint => ' · 建议重建';

  @override
  String get syncAction => '同步';

  @override
  String get rebuildAction => '重建';

  @override
  String get tidyAction => '整理';

  @override
  String rebuildHintNow(Object count, Object target) {
    return '当前云端分片 $count 个，达到 $target 个时提示重建';
  }

  @override
  String rebuildHintTarget(Object target) {
    return '云端分片达到 $target 个时提示重建';
  }

  @override
  String get customThreshold => '自定义…';

  @override
  String customThresholdValue(Object count) {
    return '自定义（$count）';
  }

  @override
  String get allBackupsSection => '全部备份';

  @override
  String allBackupsSectionDesc(Object path) {
    return '把凭证 + 音乐库 + 歌单写成一个归档到 $path。';
  }

  @override
  String get startBackup => '开始备份';

  @override
  String get readBackupsUnderPath => '读取该路径下的备份';

  @override
  String get backupToRestore => '要恢复的备份';

  @override
  String get restoreFromSelectedBackup => '从所选备份恢复';

  @override
  String get localImportExportSection => '本地导入导出';

  @override
  String get localImportExportDesc => '导出、导入同样使用上面那把密钥。';

  @override
  String get exportToDownloads => '导出到系统下载目录';

  @override
  String get exportReadableJson => '导出可读 JSON（排障，不含封面）';

  @override
  String get importFromLocalFile => '从本地文件导入…';

  @override
  String get pasteBase64Label => '或粘贴备份内容（Base64）';

  @override
  String get importFromPaste => '从粘贴内容导入';

  @override
  String get processing => '处理中…';

  @override
  String get rebuildCloudLibraryTitle => '重建云端音乐库';

  @override
  String get rebuildCloudLibraryDesc => '以本机为准重写全部分片，并落实删除。';

  @override
  String get tracksPerShard => '每个分片包含歌曲数';

  @override
  String get embedCoversInShards => '把封面缩略图写进分片';

  @override
  String get embedCoversInShardsDesc => '每首歌独立存一份，不去重；关闭则云端不含封面';

  @override
  String get estimating => '正在估算…';

  @override
  String get estimateUnavailable => '估算不可用';

  @override
  String get fileExtTapBehavior => '点按行为';

  @override
  String readBackupsListFailed(Object error) {
    return '读取备份列表失败：$error';
  }

  @override
  String get trackStateQueued => '排队';

  @override
  String get trackStateDownloading => '下载中';

  @override
  String get trackStateReady => '就绪';

  @override
  String get trackStatePlaying => '播放中';

  @override
  String get trackStateError => '错误';

  @override
  String get playQueueTitle => '播放列表';

  @override
  String get webdavErrorPerm => '权限错误';

  @override
  String get webdavErrorGeneric => '操作失败';

  @override
  String get dialogOk => '确定';

  @override
  String get destroyInProgress => '正在销毁';

  @override
  String processedOfTotal(Object processed, Object total) {
    return '已处理 $processed / $total 首';
  }

  @override
  String get destroyStopHint => '「终止」或直接返回都会停在当前这首之后；已经销毁的不会恢复。';

  @override
  String get actionStop => '终止';

  @override
  String get tagRefreshInProgress => '正在更新标签';

  @override
  String get tagRefreshStopHint => '只读取本地缓存；终止后保留已更新的曲目。';

  @override
  String get tagRefreshPreparing => '准备中';

  @override
  String get recoveryTitle => '需要恢复本地数据';

  @override
  String get recoveryHeading => '数据库初始化失败';

  @override
  String get recoveryBody => '请先导出全部本地数据库，再清除并重新进入应用。';

  @override
  String get recoveryNothingToExport => '未找到可导出的本地数据库';

  @override
  String recoveryExportedCount(Object count, Object ok) {
    return '已导出 $ok / $count 个数据库文件到下载目录';
  }

  @override
  String recoveryExportFailed(Object error) {
    return '导出失败：$error';
  }

  @override
  String get recoveryClearTitle => '清除本地数据库？';

  @override
  String get recoveryClearContent => '建议先导出数据库。清除后请重新打开应用，网盘账号和本地索引需要重新配置。';

  @override
  String recoveryClearedCount(Object count) {
    return '已清除 $count 个数据库文件，请重新打开应用';
  }

  @override
  String get recoveryExportAll => '导出全部本地数据库';

  @override
  String get recoveryClearAndExit => '清除并退出';

  @override
  String get recoveryClearAndReenter => '清除数据并重新进入';

  @override
  String get dialogCancel => '取消';

  @override
  String get fileActionIsFolder => '这是文件夹，不能按文件动作处理';

  @override
  String fileActionNotApplicable(Object action, Object category) {
    return '「$action」不适用于$category';
  }

  @override
  String get fileActionNotApplicableGeneric => '该动作不适用于这个文件';

  @override
  String get catMusicFile => '音乐文件';

  @override
  String get catVideoFile => '视频文件';

  @override
  String get catCueFile => 'CUE 文件';

  @override
  String get catOtherFile => '普通文件';

  @override
  String get videoGestureNone => '无操作';

  @override
  String get videoGestureBack10s => '后退 10 秒';

  @override
  String get videoGestureForward10s => '前进 10 秒';

  @override
  String get videoGestureBack30s => '后退 30 秒';

  @override
  String get videoGestureForward30s => '前进 30 秒';

  @override
  String get videoGestureHoldSpeedUp => '长按临时加速（松手恢复）';

  @override
  String get videoGesturePlayPause => '播放 / 暂停';

  @override
  String get videoSubtitleVisible => '显示字幕';

  @override
  String get videoSubtitleHidden => '不显示';

  @override
  String get videoTapOpen => '打开视频';

  @override
  String get videoTapDownload => '下载';

  @override
  String get musicTapDownload => '下载音乐';

  @override
  String get musicTapPlayCached => '播放（已缓存则播放，否则下载）';

  @override
  String get libSortByName => '按名称';

  @override
  String get libSortByAlbumTrack => '按曲序';

  @override
  String get cueMultiSliceLabel => '多歌曲合并分片';

  @override
  String get artistUnknown => '未知艺术家';

  @override
  String get albumUnknown => '未知专辑';

  @override
  String get snackGotIt => '知道了';

  @override
  String get rootFolder => '根目录';

  @override
  String folderPickerTitle(Object folder, Object purpose) {
    return '$purpose：$folder';
  }

  @override
  String get webdavErrorPermDetail => '权限不足或未授权（401/403）';

  @override
  String itemWithMessage(Object message, Object name) {
    return '$name：$message';
  }

  @override
  String accountWithName(Object name, Object user) {
    return '$name（$user）';
  }

  @override
  String labelValuePair(Object label, Object value) {
    return '$label：$value';
  }

  @override
  String syncOperationFailed(Object error) {
    return '操作失败：$error';
  }

  @override
  String get syncUnknownError => '未知错误';

  @override
  String get syncNoChanges => '无变更';

  @override
  String get syncListSep => '；';

  @override
  String get syncNotePrefix => '注意：';

  @override
  String get nameJoiner => '、';

  @override
  String get progressPreparing => '准备中…';

  @override
  String get progressDone => '完成';

  @override
  String get progressScanningCloudCredentials => '扫描云端凭证…';

  @override
  String get progressScanningPlaylists => '扫描歌单…';

  @override
  String get progressUploadingCredentials => '上传凭证…';

  @override
  String get progressDownloadingCredentials => '下载凭证…';

  @override
  String get progressMergingPlaylists => '合并歌单…';

  @override
  String get progressCompactingPlaylistDeletions => '清理歌单删除记录…';

  @override
  String get progressReadingCloudIndex => '读取云端曲库索引…';

  @override
  String progressAdoptingCloudTracks(Object count) {
    return '采纳云端 $count 首…';
  }

  @override
  String progressUploadingTombstones(Object count) {
    return '上传 $count 条删除记录…';
  }

  @override
  String progressAppendingSegments(Object count) {
    return '追加 $count 首到云端增量分片…';
  }

  @override
  String get progressUploadingFullShards => '上传完整曲库分片…';

  @override
  String get progressPackingBackup => '打包凭证 / 音乐库 / 歌单…';

  @override
  String get progressDownloadingRestore => '下载并恢复…';

  @override
  String get progressGeneratingBackup => '生成备份…';

  @override
  String get progressWritingDownloads => '写入下载目录…';

  @override
  String get progressUnpackingRestore => '解包并恢复…';

  @override
  String get warnCredentialsSkippedNoKey => '凭证同步已跳过（未设置统一加密密钥）';

  @override
  String warnCredentialScanSkipped(Object e) {
    return '凭证扫描跳过：$e';
  }

  @override
  String warnLeftoverTombstones(Object count) {
    return '重建后仍残留 $count 条墓碑（有活行与墓碑同时存在），建议检查数据';
  }

  @override
  String stepPlaylistsMerged(Object count) {
    return '歌单已合并（$count 个）';
  }

  @override
  String stepCredentialsUploaded(Object count) {
    return '凭证已同步到云端（$count 个服务器）';
  }

  @override
  String get stepCloudNoCredentials => '云端暂无凭证文件';

  @override
  String stepPlaylistsSynced(Object count) {
    return '歌单已同步（$count 个）';
  }

  @override
  String get stepPlaylistDeletionsCompacted => '歌单删除记录已清理';

  @override
  String get stepIncrementalNoChange => '增量同步：无变化（未上传任何内容）';

  @override
  String stepIncrementalUploaded(
    Object adopted,
    Object tombs,
    Object uploaded,
  ) {
    return '增量同步：上传 $uploaded 首，采纳 $adopted 首，删除 $tombs 条';
  }

  @override
  String stepClearedDeadTombstones(Object count) {
    return '清理了 $count 条已失效的墓碑';
  }

  @override
  String stepRebuildDone(Object localCount, Object rev, Object shards) {
    return '重建完成：$shards 个分片，base 覆盖到 rev $rev（本机 $localCount 首）';
  }

  @override
  String get stepBackupDone => '备份完成';

  @override
  String get stepRestoreDone => '恢复完成';

  @override
  String get stepLocalBackupImported => '本地备份已导入';

  @override
  String get errNoWebdavAccount => '请先添加 WebDAV 账号';

  @override
  String vaultSummaryAccounts(Object imported, Object updated) {
    return '账号：新增 $imported，更新 $updated；';
  }

  @override
  String vaultSummaryPasswords(
    Object passwordsMissing,
    Object passwordsRestored,
  ) {
    return '密码恢复 $passwordsRestored，留空 $passwordsMissing';
  }

  @override
  String get vaultSummaryMissingNote => '（缺少统一解密密钥，可稍后手动填写）';

  @override
  String vaultSummarySkipped(Object count) {
    return '；跳过 $count 个不支持的网盘类型';
  }

  @override
  String get vaultSyncedEncrypted => '账号凭证已同步到云端（密码已加密）';

  @override
  String get vaultSyncedPlaintext => '账号凭证已同步到云端（明文密码）';

  @override
  String vaultCloudNoFile(Object remotePath) {
    return '云端暂无凭证文件（$remotePath），已跳过';
  }

  @override
  String vaultRestoredFromCloud(Object summary) {
    return '已从云端恢复账号凭证：$summary';
  }

  @override
  String get errVaultDestNotConfigured => '凭证同步目的地网盘未配置';

  @override
  String get errBackupDestNotConfigured => '备份目的地网盘未配置';

  @override
  String backupDoneLatest(Object remote, Object size) {
    return '已备份到 $remote（$size；并更新 latest）';
  }

  @override
  String get errBackupEncryptedNeedPassphrase => '此备份已加密，请输入口令';

  @override
  String get errBackupUnrecognizedContent => '无法识别的备份内容';

  @override
  String backupRestoredFull(Object count) {
    return '备份已恢复：$count 个服务器、音乐库与歌单已写回';
  }

  @override
  String backupRestoredMissingPasswords(Object missing) {
    return '备份已恢复，但以下服务器的密码无法解密并已留空：$missing。请在账号管理中补填。';
  }

  @override
  String errNotBackupArchive(Object kind) {
    return '这是 $kind 类文件，不是备份归档';
  }

  @override
  String errPlaylistKindMismatch(Object expected, Object kind) {
    return '这是 $kind 类文件，不是歌单文档（期望 $expected）';
  }

  @override
  String get errPlaylistMissingId => '歌单文档缺少 playlistId，无法识别';

  @override
  String errPlaylistDeletionKindMismatch(Object expected, Object kind) {
    return '这是 $kind 类文件，不是歌单删除记录（期望 $expected）';
  }

  @override
  String get errPlaylistDeletionMissingId => '歌单删除记录缺少 playlistId，无法识别';

  @override
  String errVaultKindMismatch(Object expected, Object kind) {
    return '这是 $kind 类文件，不是凭证库（期望 $expected）';
  }

  @override
  String estimateLabelWithCovers(Object shards, Object sizeLabel) {
    return '预计 $shards 个分片 · 含封面约 $sizeLabel';
  }

  @override
  String estimateLabelNoCovers(Object shards, Object sizeLabel) {
    return '预计 $shards 个分片 · 不含封面约 $sizeLabel';
  }

  @override
  String auditBaseShards(Object count) {
    return '基础分片 $count 个';
  }

  @override
  String auditSegments(Object count) {
    return '增量 $count 个';
  }

  @override
  String auditTombstones(Object count) {
    return '墓碑 $count 个';
  }

  @override
  String auditTotalBytes(Object size) {
    return '合计 $size';
  }

  @override
  String auditOrphans(Object count) {
    return '孤儿文件 $count 个';
  }

  @override
  String auditMissing(Object count) {
    return '缺失文件 $count 个';
  }

  @override
  String get exportErrUnsupportedPlatform => '当前平台不支持写入系统相册/下载目录';

  @override
  String exportErrSourceMissing(Object detail) {
    return '源文件不存在：$detail';
  }

  @override
  String exportErrBadNativeResponse(Object detail) {
    return '导出失败：原生返回 $detail';
  }

  @override
  String get exportErrFailed => '导出失败';

  @override
  String exportErrFailedWith(Object detail) {
    return '导出失败：$detail';
  }

  @override
  String get exportErrChannelUnavailable => '原生导出通道不可用（需完整 APK）';

  @override
  String get pickerErrUnsupportedPlatform => '当前平台不支持系统文件选择器';

  @override
  String get pickerErrBadResponse => '文件选择返回异常';

  @override
  String get pickerErrFailed => '文件选择失败';

  @override
  String get pickerErrChannelUnavailable => '原生文件选择器不可用（需完整 APK）';

  @override
  String get locationSystemGallery => '系统相册';

  @override
  String get locationDownloads => '下载目录';

  @override
  String locationDownloadsSubdir(Object dir) {
    return '下载目录/$dir';
  }

  @override
  String get dlChannelProgressName => '下载进度';

  @override
  String get dlChannelProgressDesc => '下载队列进行中的进度';

  @override
  String get dlChannelDoneName => '下载完成';

  @override
  String get dlChannelDoneDesc => '全部下载完成后的结果汇总';

  @override
  String dlDoneCancelledCount(Object count) {
    return '取消 $count';
  }

  @override
  String dlDoneFailedCount(Object count) {
    return '失败 $count';
  }

  @override
  String dlDoneOkCount(Object count) {
    return '成功 $count';
  }

  @override
  String get dlDoneSep => ' · ';

  @override
  String dlDoneTitle(Object parts) {
    return '下载完成：$parts';
  }

  @override
  String get dlErrCueMalformed => '无法解析的 CUE：需要标准 FILE + TRACK/INDEX';

  @override
  String get dlErrOffline => '网络不可用';

  @override
  String get dlErrQueueCleared => '队列已清空';

  @override
  String dlErrQueueSchemaDrift(Object raw) {
    return '下载队列数据库结构过旧（$raw）。请重启应用以升级数据库。';
  }

  @override
  String dlErrSourceUnbound(Object source) {
    return '来源网盘未绑定（$source）';
  }

  @override
  String get dlErrWritePublicFailed => '写入公共目录失败';

  @override
  String dlNetworkInterruptedRetry(Object attempts, Object max) {
    return '网络中断，正在重试 ($attempts/$max)';
  }

  @override
  String dlOfflineRetryWait(Object attempts, Object max, Object seconds) {
    return '网络不可用，$seconds 秒后重试 ($attempts/$max)';
  }

  @override
  String dlRetryExhausted(Object max, Object reason) {
    return '重试 $max 次仍失败：$reason';
  }

  @override
  String netLoadGiveUpFailed(Object err, Object failures) {
    return '$err\n\n已自动重试 $failures 次仍失败，等待手动重试。';
  }

  @override
  String netEnqueueFailed(Object err) {
    return '加入下载失败：$err';
  }

  @override
  String get netStreamingExperimental => '音乐流式传输未打开，请先在设置里打开';

  @override
  String get netParsingCue => '正在解析 CUE…';

  @override
  String netCueReadFailed(Object e) {
    return '读取 CUE 失败：$e';
  }

  @override
  String netCueGroupTitle(Object tracks) {
    return '$tracks 曲';
  }

  @override
  String netCueGroupTitleMulti(Object files, Object tracks) {
    return '$tracks 曲 · $files';
  }

  @override
  String get netCueGroupSubtitle => '将整张专辑按分片导入音乐库。';

  @override
  String netCueDownloadFailed(Object e) {
    return 'CUE 下载失败：$e';
  }

  @override
  String netItemSubtitle(Object action, Object category) {
    return '$category · 点按＝$action';
  }

  @override
  String get netCacheFolderAudio => '缓存文件夹中的音频';

  @override
  String get netCacheFolderAudioDesc => '递归扫描，音频进缓存并进音乐库';

  @override
  String get netDownloadWholeFolder => '下载整个文件夹';

  @override
  String get netDownloadWholeFolderDesc => '递归下载目录树，不挑文件类型';

  @override
  String get netDefaultActionFromSettings => '设置里的默认动作';

  @override
  String get netExperimentalNoDownload => '不下载、不进音乐库';

  @override
  String get netDownloadToGallery => '下载到系统相册';

  @override
  String get netDownloadToGalleryDesc => '保存到 Movies/WebdavMediaManager';

  @override
  String get netCopyTo => '复制到…';

  @override
  String get netMoveTo => '移动到…';

  @override
  String get netNewName => '新名称';

  @override
  String get netTapDownload => '点按下载';

  @override
  String netSelectedCount(Object n) {
    return '已选 $n 项';
  }

  @override
  String get netCachingMusic => '正在缓存音乐…';

  @override
  String get netNoNewAudio => '这里没有新的音频';

  @override
  String get netEnqueueing => '正在加入下载队列…';

  @override
  String get netNothingDownloadable => '所选内容里没有可下载的文件';

  @override
  String netEnqueuedCount(Object n) {
    return '已加入 $n 项';
  }

  @override
  String netEnqueueFailedFolders(Object n) {
    return '失败 $n 个文件夹';
  }

  @override
  String get netJoinSep => '，';

  @override
  String get netFolder => '文件夹';

  @override
  String get netVideo => '视频';

  @override
  String get netAudio => '音频';

  @override
  String get netFile => '文件';

  @override
  String get netConfirmDeleteTitle => '确认删除';

  @override
  String netConfirmDeleteMsg(Object name) {
    return '确定删除「$name」？此操作不可撤销。';
  }

  @override
  String get ntfAllDone => '全部下载完成';

  @override
  String ntfDoneCount(Object done, Object total) {
    return '已完成 $done / $total';
  }

  @override
  String ntfDoneCountPercent(Object done, Object percent, Object total) {
    return '总进度 $percent% · 已完成 $done / $total';
  }

  @override
  String get ntfDoneWithFailures => '下载结束（有失败）';

  @override
  String ntfDownloadingTitle(Object index, Object total) {
    return '正在下载（第 $index / $total 个）';
  }

  @override
  String get ntfImportanceOff => '已关闭';

  @override
  String get ntfImportanceMin => '最低';

  @override
  String get ntfImportanceLow => '低';

  @override
  String get ntfImportanceDefault => '默认';

  @override
  String get ntfImportanceHigh => '高';

  @override
  String get ntfImportanceMax => '最高';

  @override
  String get ntfMediaChannelName => '音乐播放';

  @override
  String get ntfMediaChannelDesc => '正在播放的音乐控制';

  @override
  String get ntfStatusBlocked => '已关闭（请在系统通知设置中重新开启）';

  @override
  String get ntfStatusChecking => '正在检查…';

  @override
  String get ntfStatusCreated => '已创建';

  @override
  String ntfStatusCreatedImportance(Object importance) {
    return '已创建 · 重要性 $importance';
  }

  @override
  String get ntfStatusNoChannels => '当前平台无通知通道';

  @override
  String get ntfStatusNotCreated => '未创建';

  @override
  String ntfSummaryCancelled(Object count) {
    return '取消：$count 个';
  }

  @override
  String ntfSummaryFailed(Object count) {
    return '失败：$count 个';
  }

  @override
  String ntfSummaryOk(Object count) {
    return '成功：$count 个';
  }

  @override
  String get ntfSelfTestAndroidOnly => '仅 Android 支持';

  @override
  String get ntfSelfTestBlocked => '系统已关闭本应用的通知';

  @override
  String get ntfSelfTestBody => '测试通知 · 50% · 已完成 0 / 1';

  @override
  String get ntfSelfTestSummary => '成功：1 个（测试）';

  @override
  String libQueuedCount(Object count) {
    return '已加入 $count 项下载';
  }

  @override
  String libQueuedUnavailable(Object count) {
    return '$count 项来源不可用';
  }

  @override
  String get libQueuedAdded => '已加入下载';

  @override
  String get cueGroupDeleteTitle => '删除整个 CUE 缓存组？';

  @override
  String get cueGroupDeleteTitleMulti => '删除多个 CUE 缓存组？';

  @override
  String get cueGroupDeleteBodyIntro => '将删除整组：';

  @override
  String cueGroupDeleteBodyIntroCount(Object count) {
    return '将删除 $count 个 CUE 组：';
  }

  @override
  String moreFilesCount(Object count) {
    return '…共 $count 个文件';
  }

  @override
  String get cueGroupDeleteWhole => '删除整组';

  @override
  String cueGroupDeleted(Object count) {
    return '已删除 CUE 缓存组（$count 个文件）';
  }

  @override
  String get cacheDeleteTitle => '删除本地音频缓存？';

  @override
  String cacheDeleteBodyOne(Object name) {
    return '将删除「$name」的音频缓存，标签与封面保留。';
  }

  @override
  String cacheDeleteBodyMany(Object count) {
    return '将删除 $count 个缓存文件，标签与封面保留。';
  }

  @override
  String cacheDeletedCount(Object count) {
    return '已删除 $count 个本地音频缓存';
  }

  @override
  String get destroyTracksTitle => '销毁所选曲目？';

  @override
  String destroyTracksBody(Object count) {
    return '将删除 $count 首曲目（缓存、库记录、元数据与封面），不可恢复。';
  }

  @override
  String get destroyTracksCueNote => '（CUE 分片整组删除）';

  @override
  String get destroyAction => '销毁';

  @override
  String destroyedTracksCount(Object count) {
    return '已销毁 $count 首曲目';
  }

  @override
  String get shareCueUnsupported => 'CUE 音轨不支持分享';

  @override
  String get shareCueUnsupportedAndNotLocal => 'CUE 音轨不支持分享；其余曲目尚未下载到本地';

  @override
  String get shareNotLocalOne => '该曲目尚未下载到本地，无法分享';

  @override
  String get shareNotLocalAll => '所选曲目均未下载到本地，无法分享';

  @override
  String shareCueSkipped(Object count) {
    return '已跳过 $count 首 CUE 音轨（不支持分享）';
  }

  @override
  String shareNotLocalSkipped(Object count) {
    return '已跳过 $count 首未下载曲目';
  }

  @override
  String get shareNothingToShare => '没有可分享的文件';

  @override
  String shareDoneCount(Object count) {
    return '已分享 $count 个文件';
  }

  @override
  String shareFailed(Object reason) {
    return '分享失败：$reason';
  }

  @override
  String get shareNameTitle => '分享文件名';

  @override
  String get shareRenameTemplateHint => '留空字段自动去掉多余分隔符，扩展名始终保留。';

  @override
  String get fileNameLabel => '文件名';

  @override
  String shareExtFixed(Object ext) {
    return '扩展名固定为 $ext';
  }

  @override
  String shareOriginalFile(Object name) {
    return '原文件：$name';
  }

  @override
  String get shareUseOriginalName => '用原文件名';

  @override
  String get shareAction => '分享';

  @override
  String get searchPlaceholder => '搜索标题 / 艺术家 / 专辑';

  @override
  String get searchAction => '搜索';

  @override
  String get closeSearch => '关闭搜索';

  @override
  String get sortTooltip => '排序';

  @override
  String get tabAlbums => '专辑';

  @override
  String get tabArtists => '作者';

  @override
  String get tabTitles => '音乐名';

  @override
  String get tabGenres => '流派';

  @override
  String get libraryNoMatch => '无匹配曲目';

  @override
  String get genreEmpty => '暂无流派：下载带流派元数据的曲目后出现。';

  @override
  String get noMatchResult => '无匹配结果';

  @override
  String get updateCancelled => '已终止';

  @override
  String get updateDone => '更新完成';

  @override
  String updateSummary(Object a, Object b, Object c, Object d) {
    return '$a：更新 $b 首，跳过 $c 首，失败 $d 首';
  }

  @override
  String get deleteCacheKeepMeta => '删除缓存（保留元数据与封面）';

  @override
  String get updateTags => '更新标签';

  @override
  String get downloadUncachedTracks => '下载未缓存曲目';

  @override
  String get libraryTracksEmpty => '暂无曲目';

  @override
  String get sourceUnbound => '来源网盘未绑定';

  @override
  String downloadingPercent(Object p) {
    return '下载中 $p%';
  }

  @override
  String get libraryEmptyGuide => '暂无曲目：先在「网络库」下载音乐。';

  @override
  String get tagTitle => '标题';

  @override
  String get tagArtist => '艺术家';

  @override
  String get tagAlbumArtist => '专辑艺术家';

  @override
  String get tagAlbum => '专辑';

  @override
  String get tagTrack => '曲目';

  @override
  String get tagDisc => '碟片';

  @override
  String get tagYear => '年份';

  @override
  String get tagGenre => '流派';

  @override
  String get tagDuration => '时长';

  @override
  String get tagBitrate => '比特率';

  @override
  String get tagSampleRate => '采样率';

  @override
  String get tagLanguage => '语言';

  @override
  String get tagLyrics => '歌词';

  @override
  String errShardKindMismatch(Object a, Object b) {
    return '分片类型不一致：文件头 $a，META kind=$b';
  }

  @override
  String get errNotWdmmFile => '不是 Webdav Media Manager 文件（缺少 WDMM 标识）';

  @override
  String errAccountNotConnected(Object a) {
    return '账号未连接：$a';
  }

  @override
  String errBigintOverflow(Object a) {
    return '大整数超出 $a 字节';
  }

  @override
  String errCloudAccountMissing(Object a) {
    return '云盘账号不存在：$a';
  }

  @override
  String get errCloudWriteDisabled => '云盘账号不支持上传与云端写同步';

  @override
  String get errContentRangeUnsupported => '该驱动不支持区间读取';

  @override
  String get errContentStreamUnsupported => '该驱动不支持内容流读取';

  @override
  String get errDriverNotReady => '云盘驱动尚未接入';

  @override
  String errDriverNotReadyInfo(Object a) {
    return '云盘驱动尚未接入：$a';
  }

  @override
  String errDownloadSizeUnknown(Object a) {
    return '无法确定「$a」的大小，下载已取消';
  }

  @override
  String get errNeteaseRsaKeyLength => '网易 raw RSA 的密钥必须是 16 字节';

  @override
  String errStreamSizeUnknown(Object a) {
    return '无法确定「$a」的大小，暂不支持流式播放';
  }

  @override
  String get errWebdavNotConfigured => '未配置 WebDAV';

  @override
  String get errWebdavSourceNotConnected => 'WebDAV 未连接，无法取源内容';

  @override
  String errBaiduDirectLinkFailed(Object a) {
    return '获取下载直链失败：$a';
  }

  @override
  String errBaiduRequestFailed(Object a) {
    return '百度网盘请求失败：$a';
  }

  @override
  String errBaiduRiskControl(Object a) {
    return '$a 百度网盘风控（触发安全策略，通常数分钟至数小时后自动解除）。refresh_token 无效或非官方渠道获取也可能触发；请确认通过 https://api.oplist.org/ 获取。';
  }

  @override
  String errDriver123FileNotFound(Object a) {
    return '123 云盘文件不存在：$a';
  }

  @override
  String errDriver123NetworkFailed(Object a) {
    return '[123Open] 网络请求失败：$a';
  }

  @override
  String errDriver123RequestFailed(Object a) {
    return '123 云盘请求失败：$a';
  }

  @override
  String get errMissingRefreshToken =>
      '123 云盘缺少 refresh_token：请填写 refresh_token（获取方法见 OpenList 官方文档 123_open 驱动页）';

  @override
  String get errMkdirRoot => '不能创建根目录';

  @override
  String errRefreshOnlineFailed(Object a, Object b) {
    return '在线 API 刷新失败 (HTTP $a)：$b。请确认 refresh_token 是通过 https://api.oplist.org/ 获取的有效令牌。';
  }

  @override
  String errRefreshOnlineFailedNonJson(Object a) {
    return '在线 API 刷新失败 (HTTP $a)：非 JSON 响应。请确认 refresh_token 是通过 https://api.oplist.org/ 获取的有效令牌。';
  }

  @override
  String get errRootOp => '不能对根目录执行该操作';

  @override
  String get errOpen115MissingRefreshToken => '115 网盘缺少 refresh_token（必填）';

  @override
  String errOpen115RefreshFailed(Object a) {
    return '115 网盘 token 刷新失败（$a）：请确认 refresh_token 有效。';
  }

  @override
  String errOpen115ApiError(Object a) {
    return '115 网盘 API 错误（$a）';
  }

  @override
  String errOpen115NetworkFailed(Object a) {
    return '115 网盘网络请求失败（$a）';
  }

  @override
  String get errOpen115DownurlEmptyData => '115 网盘 downurl 未返回直链数据（data 为空）';

  @override
  String get errOpen115DownurlEmptyUrl => '115 网盘 downurl 未返回可用直链（url.url 为空）';

  @override
  String errOpen115MissingPickCode(Object a) {
    return '115 网盘条目缺少 pick_code，无法获取直链：$a';
  }

  @override
  String errOpen115TokenVerifyFailed(Object a) {
    return '115 网盘 token 验证失败：$a。请确认 access_token / refresh_token 有效。';
  }

  @override
  String errOpen115NetworkConnectFailed(Object a) {
    return '115 网盘网络连接失败（$a）：proapi.115.com 可能无法从当前部署环境访问（数据中心 IP 可能被 115 拦截），请稍后重试或更换部署环境。';
  }

  @override
  String errOpen115DirectLinkFailed(Object a) {
    return '获取 115 网盘直链失败：$a';
  }

  @override
  String errOpen115CopyRenameFailed(Object a) {
    return '115 网盘复制完成但未找到副本，无法改名为 $a';
  }

  @override
  String errOpen115FolderNotFound(Object a) {
    return '115 网盘目录不存在：$a';
  }

  @override
  String errOpen115FileNotFound(Object a) {
    return '115 网盘文件不存在：$a';
  }

  @override
  String errAliyunEntryOrLinkFailed(Object a) {
    return '无法获取条目或直链：$a';
  }

  @override
  String get errAliyunMissingRefreshToken =>
      '阿里云盘缺少 refresh_token：请在账号表单填写 refresh_token（获取方法见 OpenList 官方文档 aliyundrive_open 驱动页）。';

  @override
  String errAliyunNetworkFailed(Object a) {
    return '[AliyundriveOpen] 网络请求失败 $a';
  }

  @override
  String get errAliyunNoDirectLink =>
      '[AliyundriveOpen] getDownloadUrl 未返回直链（url / download_url 都为空）';

  @override
  String get errAliyunNoDriveId =>
      '[AliyundriveOpen] getDriveInfo 未返回任何 drive_id（resource / default / backup 都为空）：请确认账号已开通阿里云盘。';

  @override
  String errAliyunNonJson(Object a) {
    return '非 JSON 响应：$a';
  }

  @override
  String errAliyunRefreshAllFailed(Object a) {
    return '[AliyundriveOpen] 刷新令牌的所有策略均失败。请依次检查：1) refresh_token 是否有效且未过期；2) api_url_address 是否可访问；3) 若使用直连 OAuth，client_id / client_secret 是否正确。尝试记录：$a';
  }

  @override
  String errTeraboxRedirectFailed(Object a) {
    return 'TeraBox 直链重定向失败（$a）';
  }

  @override
  String errTeraboxRequestFailed(Object a) {
    return 'TeraBox 请求失败 $a';
  }

  @override
  String get errTeraboxSignKeyEmpty =>
      'TeraBox 签名失败：sign3 密钥为空（上游 /api/home/info 未返回 sign3）';

  @override
  String errNeteaseApiError(Object a) {
    return '网易云音乐接口报错（$a）';
  }

  @override
  String get errNeteaseCookieRequired =>
      'Cookie 必须同时包含 __csrf 与 MUSIC_U：请在网页版 music.163.com 登录后，从开发者工具复制完整 Cookie';

  @override
  String get errNeteaseCopyUnsupported => '网易云音乐云盘不支持复制（上游驱动未实现该操作）';

  @override
  String errNeteaseFileNotFound(Object a) {
    return '文件不存在：$a';
  }

  @override
  String errNeteaseLoginExpired(Object a) {
    return '网易云音乐登录态已失效（$a）。Cookie 可能已过期，请重新登录网页版并更新 Cookie';
  }

  @override
  String get errNeteaseMkdirUnsupported => '网易云音乐云盘不支持新建文件夹（上游驱动未实现该操作）';

  @override
  String get errNeteaseMoveUnsupported => '网易云音乐云盘不支持移动（上游驱动未实现该操作）';

  @override
  String get errNeteaseNoSongLink => '网易云音乐未返回播放链接（可能是 VIP / 版权受限 / 已下架的歌曲）';

  @override
  String errNeteaseNonJson(Object a) {
    return '网易云音乐返回了非 JSON 响应：$a';
  }

  @override
  String get errNeteaseRenameUnsupported => '网易云音乐云盘不支持重命名（上游驱动未实现该操作）';

  @override
  String errNeteaseRequestFailed(Object a) {
    return '网易云音乐请求失败：$a';
  }

  @override
  String get errNeteaseRootDelete => '网易云音乐不支持删除根目录';

  @override
  String errNeteaseUnexpectedStructure(Object a) {
    return '网易云音乐返回了非预期结构：$a';
  }

  @override
  String errNeteaseUnknownCrypto(Object a) {
    return '未知的加密方式：$a';
  }

  @override
  String errCryptBadCipherLength(Object a) {
    return 'crypt 密文长度不合法：$a';
  }

  @override
  String errCryptBlockDecryptFailed(Object a) {
    return 'crypt 第 $a 块解密失败（内容损坏或密钥不匹配）';
  }

  @override
  String errCryptBlockRangeDecryptFailed(Object a) {
    return 'crypt 第 $a 块起解密失败（内容损坏或密钥不匹配）';
  }

  @override
  String get errCryptDecryptFailed => 'crypt 内容解密失败（内容损坏或密钥不匹配）';

  @override
  String errCryptEarlyEof(Object a, Object b, Object c) {
    return 'crypt 内容提前结束（第 $a 块起，期望 $b 字节，收到 $c 字节）';
  }

  @override
  String errCryptInvalidConfig(Object a) {
    return 'crypt 配置无效：$a';
  }

  @override
  String errCryptLengthMismatch(Object a, Object b) {
    return 'crypt 内容长度不符（期望 $a，收到 $b）';
  }

  @override
  String get errCryptNoDirectLinkAnymore => 'crypt 源不再提供直链，无法继续解密内容';

  @override
  String get errCryptNoDirectLinkDecrypt => 'crypt 源不提供直链，无法解密内容';

  @override
  String get errCryptNoDirectLinkStream => 'crypt 源不提供直链，无法顺序下载';

  @override
  String get errCryptNoHeader => 'crypt 内容不完整（读不到文件头）';

  @override
  String get errCryptNoResponseBody => 'crypt 顺序下载没有响应体';

  @override
  String get errCryptNoSourceName => 'crypt 未保存源账号名称；请重新编辑并选择源账号';

  @override
  String errCryptNotRcloneFile(Object a) {
    return '不是有效的 rclone 加密文件：$a';
  }

  @override
  String get errCryptSizeUnknown => '无法确定加密内容的大小（源未提供长度且不支持 Range）';

  @override
  String errCryptSourceMissing(Object a) {
    return 'crypt 源账号不存在或已删除「$a」；重新添加同名源账号即可恢复';
  }

  @override
  String get driverNameBaidu => '百度网盘';

  @override
  String get driverName123Open => '123 云盘开放平台';

  @override
  String get driverName115 => '115网盘';

  @override
  String get driverNameAliyunOpen => '阿里云盘开放平台';

  @override
  String get driverNameNetease => '网易云音乐';

  @override
  String get driverNameCrypt => 'Crypt 加密目录';

  @override
  String errRefreshOnlineNon200(Object a) {
    return '在线 API 返回 HTTP $a';
  }

  @override
  String get formLabelRenewApi => '在线续期地址';

  @override
  String get formHintRenewApiDefault => '默认用 OpenList 维护的公共服务';

  @override
  String get formHintLocalRefreshDisabled => '已开启本地刷新（在线续期停用），关闭开关后可编辑';

  @override
  String get formLabelLocalRefresh => '在本地处理令牌刷新';

  @override
  String get formSubLocalRefreshBaidu =>
      '关闭＝在线续期地址刷新；开启＝用自建百度应用刷新（需 Client ID / Secret），在线续期停用';

  @override
  String get formSubLocalRefresh123 =>
      '关闭＝在线续期；开启＝用自建 123 应用刷新（需 Client ID / Secret），在线续期停用';

  @override
  String get formSubLocalRefreshAliyun =>
      '关闭＝用在线续期地址轮询；开启＝用自建阿里云应用直接刷新（需 Client ID / Secret）';

  @override
  String formHintOpenListDoc(Object a) {
    return '必填；获取方法见 OpenList 官方文档（$a 驱动页）';
  }

  @override
  String get formLabelRootId => '根目录 ID';

  @override
  String formHintRootIdOpaque(Object a) {
    return '不透明 id，默认 $a（网盘根目录）；与账号的远程路径叠加生效';
  }

  @override
  String get formHint115RefreshToken =>
      '必填；获取方法见 OpenList 官方文档（115 Open 驱动页）。115 每次刷新都会轮换它，轮换结果会自动保存';

  @override
  String get formHint115RootId => '默认 0（整体根目录）；填非 0 的目录 ID 可把账号挂到该目录下';

  @override
  String get formLabelPageSize => '分页大小';

  @override
  String get formHintPageSize => '范围 1~1150，默认 200（超出会被夹到边界；115 单次上限 1150）';

  @override
  String get formLabelRateLimit => '限速（次/秒）';

  @override
  String get formHintRateLimit => '默认 0 = 不限速；填正数则两次 API 请求之间至少间隔 1/该值 秒';

  @override
  String get formLabelDriveType => '网盘类型';

  @override
  String get formHintDriveType => '资源盘 / 默认盘 / 备份盘，对应同一个账号下的不同 drive_id';

  @override
  String get optionDriveResource => '资源盘';

  @override
  String get optionDriveDefault => '默认盘';

  @override
  String get optionDriveBackup => '备份盘';

  @override
  String get formLabelDeleteMode => '删除方式';

  @override
  String get formHintDeleteMode => '移入回收站可在阿里云盘里找回；彻底删除不可恢复';

  @override
  String get optionDeleteTrash => '移入回收站';

  @override
  String get optionDeletePermanent => '彻底删除';

  @override
  String get formHintTeraboxCookie => '必填；从浏览器复制 TeraBox 的 Cookie；过期后需重新粘贴';

  @override
  String get formLabelRootPath => '根目录路径';

  @override
  String get formHintNeteaseCookie =>
      '必填；需含 __csrf 与 MUSIC_U。登录 music.163.com 后从开发者工具复制完整 Cookie（获取方法见 OpenList 官方文档 netease_music 驱动页）';

  @override
  String get formLabelSongLimit => '歌曲数量上限';

  @override
  String formHintSongLimit(Object a) {
    return '默认 $a；网易云盘接口按此上限一次列取';
  }

  @override
  String get formLabelSourceAccount => '源账号';

  @override
  String get formHintSourceAccount => '选择现有 WebDAV 或网盘账号作为加密源';

  @override
  String get formLabelSourceDir => '源目录';

  @override
  String get formHintSourceDir => '源账号浏览根下的目录，默认 /（加密文件就存在这里）';

  @override
  String get formLabelFilenameEncoding => '文件名编码';

  @override
  String get formHintFilenameEncoding =>
      '与 rclone 的 filename_encoding 对应（base32 / base64 / base32768）';

  @override
  String get formLabelEncryptedSuffix => '文件名后缀';

  @override
  String get formHintEncryptedSuffix =>
      '仅文件名加密=关闭时生效（OpenList encrypted_suffix）';

  @override
  String get formLabelPassword => '密码';

  @override
  String get formLabelSalt => '盐值（可选）';

  @override
  String get formHintSalt =>
      '留空用 rclone 内置默认盐；密码 + 盐相同即可与 rclone / OpenList 互认';

  @override
  String get formLabelFilenameEncryption => '文件名加密';

  @override
  String get optionCryptStandard => '标准 (EME)';

  @override
  String get optionCryptObfuscate => '混淆';

  @override
  String get optionCryptOff => '关闭';

  @override
  String get formLabelDirNameEncryption => '目录名加密';

  @override
  String get formSubDirNameEncryption => 'OpenList 默认关闭；开启后目录名同样加密';

  @override
  String get svcNoLocalCache => '本地无缓存，请先下载';

  @override
  String get svcCacheNotInitialized => 'CacheService 未初始化';

  @override
  String get svcBackupAccountMissingId => '备份账号缺少 id，无法安全恢复';

  @override
  String get svcLocalFileUnavailable => '本地文件不可用';

  @override
  String get backupTooShort => '备份文件过短或损坏';

  @override
  String backupNotEncrypted(Object magic) {
    return '不是加密备份（缺少 $magic 头）';
  }

  @override
  String get backupCiphertextDamaged => '备份密文损坏';

  @override
  String get vaultCiphertextDamaged => '凭证密文损坏';

  @override
  String get vaultNoteEncrypted => '密码类字段（含云盘驱动令牌）加密（AES-256-GCM），其余字段为明文。';

  @override
  String get vaultNotePlain => '密码类字段为明文存储。';

  @override
  String get mediaArtistWebdav => 'WebDAV 流媒体';

  @override
  String ntfProbeHint(Object channel) {
    return ' | 若仍无通知: 设置→应用→Webdav Media Manager→耗电管理=不限制;通知=允许(含锁屏/悬浮); 通道「$channel」勿关闭';
  }

  @override
  String get ntfProbeRunning => '运行';

  @override
  String get ntfProbeNone => '无';

  @override
  String get ntfProbeActive => '活跃';

  @override
  String get ntfProbeInactive => '否';

  @override
  String get ntfProbePosted => '已发布';

  @override
  String get ntfProbeNotPosted => '未发布';

  @override
  String get ntfProbeChanMissing => '(未创建)';

  @override
  String get ntfProbeChanBlocked => '(已关闭)';

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
    return '服务=$svc 会话=$session 通知=$posted 系统通知开关=$perm 通道=$channel$chanState 重要性=$importance 本包会话数=$sessions 设备=$device$hint';
  }

  @override
  String ntfProbeReturn(Object raw) {
    return '探测返回: $raw';
  }

  @override
  String get ntfProbeChannelUnavailable => '原生探测通道不可用（需完整 APK）';

  @override
  String ntfProbeFailed(Object message) {
    return '探测失败: $message';
  }

  @override
  String ntfForceNoAudio(Object error, Object probe) {
    return '无可用本地音频。请先播放一首歌，再点测试。\n$probe$error';
  }

  @override
  String ntfForcePlayed(
    Object error,
    Object probe,
    Object state,
    Object title,
  ) {
    return '已强制播放「$title」 playing=$state\n$probe$error\n请查看通知栏 / 媒体控制中心。';
  }

  @override
  String ntfAsyncError(Object error) {
    return '\n⚠ audio_service 桥接错误: $error';
  }

  @override
  String get phArtist => '作者';

  @override
  String get phTitle => '标题';

  @override
  String get phAlbum => '专辑';

  @override
  String get phAlbumArtist => '专辑作者';

  @override
  String get phTrack => '音轨号';

  @override
  String get phYear => '年份';

  @override
  String get phGenre => '流派';

  @override
  String get phFileName => '原文件名';

  @override
  String get videoStreamingHint => '视频直接流式播放，不下载到本地。';

  @override
  String get videoHardwareDecoding => '硬件解码';

  @override
  String get videoHardwareDecodingHint => '关闭后改用软件解码，个别设备更稳定';

  @override
  String get videoScanSubdirsHint => '播放列表是否包含子目录里的视频';

  @override
  String get videoBufferSize => '缓冲大小';

  @override
  String get videoBufferInput => '缓冲 (MB)';

  @override
  String get videoGestures => '手势';

  @override
  String get videoGestureLeftDoubleTap => '左侧双击';

  @override
  String get videoGestureRightDoubleTap => '右侧双击';

  @override
  String get videoGestureLongPress => '长按';

  @override
  String get videoLongPressRate => '长按临时倍速';

  @override
  String get videoDefaultRate => '默认播放倍速';

  @override
  String get videoSubtitles => '字幕';

  @override
  String get videoSubtitleHint => '控件显示时画在控件条上方，隐藏时贴窗口底部。';

  @override
  String get videoSubtitleSize => '字幕大小';

  @override
  String get videoPlaybackBehavior => '播放行为';

  @override
  String get videoBackgroundPlayback => '后台播放';

  @override
  String get videoBackgroundPlaybackHint => '离开播放器后继续播放声音';

  @override
  String get videoPip => '画中画（小窗）';

  @override
  String get videoPipHint => '播放控件中显示画中画按钮（Android 8+）';

  @override
  String get videoBufferSaved => '缓冲大小已保存，下次播放生效';

  @override
  String videoBufferCurrent(Object current, Object max, Object min) {
    return '当前 $current MB（范围 $min–$max MB）';
  }

  @override
  String videoLongPressCurrent(Object rate) {
    return '按住加速到 $rate×，松手恢复';
  }

  @override
  String videoDefaultRateCurrent(Object max, Object min, Object rate) {
    return '当前 $rate×（范围 $min×–$max×）';
  }

  @override
  String videoSubtitleSizeCurrent(Object max, Object min, Object size) {
    return '当前 $size sp（范围 $min–$max sp）';
  }

  @override
  String get accountsSubtitle => '管理多服务器账号';

  @override
  String get audioStreamingSubtitle => '流式传输开关 / 搜索子目录';

  @override
  String get fileTypesManage => '文件后缀管理';

  @override
  String get fileTypesManageSubtitle => '音乐 / 视频 / 图片 / CUE 后缀与默认操作';

  @override
  String get coverThumbSize => '封面缩略图尺寸';

  @override
  String get coverThumbHint => '新封面按此边长生成；已有封面需重新生成。';

  @override
  String get coverSize => '边长 (px)';

  @override
  String get cacheCleanup => '缓存清理';

  @override
  String get cacheCleanupHint => '仅清理音频缓存（播放/下载中的保留），标签与封面不受影响。';

  @override
  String get currentCacheUsage => '当前缓存占用';

  @override
  String get calculating => '计算中…';

  @override
  String get unknown => '未知';

  @override
  String get refresh => '刷新';

  @override
  String get customRetentionHint => '自定义保留时长（至少 1 小时）';

  @override
  String get days => '天';

  @override
  String get hours => '小时';

  @override
  String get autoCleanupDisabled => '已关闭自动清理，可用下方按钮手动清空。';

  @override
  String get clearAudioCache => '手动清空音频缓存';

  @override
  String get shareRenameHint => '分享时按标签重命名文件名。';

  @override
  String get shareRenameTitle => '分享时按标签重命名';

  @override
  String get shareRenameSubtitle => '默认开启；分享单个文件时仍可再修改文件名';

  @override
  String get renameTemplate => '重命名模板';

  @override
  String get syncSettings => '同步与备份设置';

  @override
  String get shareRenameTemplate => '分享重命名模板';

  @override
  String get videoPrevious => '上一个视频';

  @override
  String get videoNext => '下一个视频';

  @override
  String get videoLockScreen => '锁定屏幕';

  @override
  String get videoOrientation => '切换横竖屏';

  @override
  String get videoLockHint => '隐藏控件并禁用手势，长按解锁';

  @override
  String get videoOrientationLock => '锁定旋转方向';

  @override
  String get videoOrientationLockHint => '固定为当前横屏/竖屏';

  @override
  String get videoExitConfirm => '退出时二次确认';

  @override
  String get videoExitConfirmHint => '返回时二次确认';

  @override
  String get videoGestureSettingsHint => '双击 / 长按动作与长按倍速';

  @override
  String cacheCleared(Object count, Object libraryCount) {
    return '已清理 $count 个缓存文件（$libraryCount 首元数据保留）';
  }

  @override
  String get tagRefreshStarted => '正在后台更新本地缓存曲目的标签';

  @override
  String tagRefreshCompleted(Object failed, Object skipped, Object updated) {
    return '标签更新完成：更新 $updated 首，跳过 $skipped 首，失败 $failed 首';
  }

  @override
  String get notificationEnabled => '通知权限已开启，播放时会显示媒体通知';

  @override
  String get notificationOpenSettings => '请在系统设置中允许通知后返回应用';

  @override
  String get notificationOpenSettingsFailed => '无法打开系统设置，请手动允许通知权限';

  @override
  String get notificationGranted => '已授予通知权限';

  @override
  String get notificationDenied => '未授予通知权限，媒体通知可能无法显示';

  @override
  String retentionDaysHours(Object days, Object hours) {
    return '当前：保留 $days 天 $hours 小时未访问的音频';
  }

  @override
  String retentionDays(Object days) {
    return '当前：保留 $days 天未访问的音频';
  }

  @override
  String retentionHours(Object hours) {
    return '当前：保留 $hours 小时未访问的音频';
  }

  @override
  String get notificationChecking => '正在检查…';

  @override
  String get notificationStatusAllowed => '已允许，播放/暂停时显示媒体通知';

  @override
  String get notificationChannelBlocked => '「音乐播放」通道被关闭，点此打开系统设置';

  @override
  String get notificationStatusDenied => '已拒绝，点此打开系统设置';

  @override
  String get notificationChannelMissing => '「音乐播放」通道未创建，播放一次或点「刷新」重试';

  @override
  String get notificationNotGranted => '未授权，点此请求通知权限';

  @override
  String get hintsAndNotifications => '提示与通知';

  @override
  String get hintsSubtitle => '屏幕底部提示同时只显示一条，点「知道了」立即关闭。';

  @override
  String get hintDuration => '提示显示时长';

  @override
  String get downloadNotifications => '下载队列系统通知';

  @override
  String get downloadNotificationsHint => '下载进度与完成结果显示在通知栏';

  @override
  String get sendTestNotification => '发送测试通知';

  @override
  String get sendTestNotificationHint => '立即发一条进度与一条完成通知，用来排查系统是否拦截';

  @override
  String get testNotificationSent => '测试通知已发送（进度 + 完成各一条）';

  @override
  String testNotificationFailed(Object error) {
    return '测试通知失败：$error';
  }

  @override
  String get confirmCloseVideo => '确认关闭视频吗？';

  @override
  String get webdavNotConnectedPlay => 'WebDAV 未连接，无法播放';

  @override
  String get videoQueueEmpty => '当前没有播放列表';

  @override
  String get pipUnsupported => '当前设备/系统不支持画中画';

  @override
  String videoPlayFailed(Object error) {
    return '无法播放：$error';
  }

  @override
  String get scanningFolder => '扫描文件夹中…';

  @override
  String get buffering => '缓冲中…';

  @override
  String get opening => '正在打开';

  @override
  String get downloadKeepAlive => '后台下载保活';

  @override
  String get downloadKeepAliveHint => '开启后，下载期间通知栏会常驻一条下载通知（系统要求），关闭下载通知也会显示';

  @override
  String get streamingSection => '流式传输';

  @override
  String get imageViewer => '图片查看';

  @override
  String get imageViewerSubtitle => '幻灯片、适应方式、预取数量';

  @override
  String get imageSlideshow => '幻灯片播放';

  @override
  String get imageSlideshowHint => '按间隔自动切换到下一张。手动翻页会重新计时，不会关闭这个开关。';

  @override
  String get imageSlideshowInterval => '间隔';

  @override
  String imageSlideshowSeconds(Object seconds) {
    return '$seconds 秒';
  }

  @override
  String get imageSlideshowLoop => '循环';

  @override
  String get imageSlideshowLoopHint => '播到最后一张后回到第一张';

  @override
  String get imageFit => '适应方式';

  @override
  String get imageFitContain => '完整显示';

  @override
  String get imageFitCover => '铺满';

  @override
  String get imagePrefetchCount => '预取数量';

  @override
  String get imagePrefetchHint => '向前、向后各预取这么多张（1–5），不会一次载入整本相册。默认每侧 1 张。';

  @override
  String get imageScanSubdirs => '搜索子目录';

  @override
  String get imageScanSubdirsHint => '默认关闭。打开后相册会包含子目录中的图片，扫描可能较慢。';

  @override
  String get actionViewImage => '查看图片';

  @override
  String get actionShortViewImage => '查看';

  @override
  String get fileCatImage => '图片文件';

  @override
  String get catImageFile => '图片文件';

  @override
  String get netImage => '图片';

  @override
  String get imageViewerEmpty => '这个目录里没有可查看的图片';

  @override
  String imageLoadFailed(Object error) {
    return '无法加载这张图片：$error';
  }

  @override
  String get imageViewerRetry => '重试';

  @override
  String get imageViewerGestureHint => '轻点左侧上一张，右侧下一张，中间打开设置';

  @override
  String imageViewerCount(Object index, Object total) {
    return '$index / $total';
  }

  @override
  String get imageViewerPrevious => '上一张';

  @override
  String get imageViewerNext => '下一张';

  @override
  String get imageViewerOpenSettings => '图片设置';

  @override
  String get imageScanningSubdirs => '正在搜索子目录…';

  @override
  String get settingsMisc => '杂项';

  @override
  String get settingsThumbnails => '缩略图';

  @override
  String get settingsThumbnailsSubtitle => '封面缩略图边长，只影响之后新写入的图';

  @override
  String get settingsShareSubtitle => '分享时按标签重命名';

  @override
  String get downloadNomedia => '排除媒体扫描';

  @override
  String get downloadNomediaSubtitle =>
      '打开后在下载目录写入 .nomedia，系统扫描会跳过该文件夹；关闭后删除该文件';

  @override
  String get downloadNomediaAlreadyPresent => '下载目录里已经有 .nomedia，已按外部操作完成';

  @override
  String get downloadNomediaAlreadyAbsent => '下载目录里已经没有 .nomedia，已按外部操作完成';

  @override
  String get actionShortGallery => '相册';

  @override
  String get netDownloadToGalleryPictures => '保存到 Pictures/WebdavMediaManager';

  @override
  String get videoAutoSidecar => '自动加载同目录外挂字幕';

  @override
  String get videoAutoSidecarHint => '播放时在视频自己的目录里匹配同名字幕。这一集的手动导入优先。';

  @override
  String get videoSubtitleSubdir => '同时搜索指定子目录';

  @override
  String get videoSubtitleSubdirHint => '开启后，额外只列视频所在目录下这一层子目录。默认关闭。';

  @override
  String get videoSubtitleSubdirEmpty => '留空等于不搜索。只填一个文件夹名，例如 sub。';

  @override
  String get videoSubtitleSubdirName => '子目录名';

  @override
  String get videoSubtitleSubdirInvalid => '子目录只能是一层文件夹名';

  @override
  String get videoSubtitlePick => '选择字幕';

  @override
  String get videoSubtitleOff => '关闭字幕';

  @override
  String get videoSubtitleNone => '没有可用字幕';

  @override
  String get videoSubtitleExternal => '外挂字幕';

  @override
  String get videoSubtitleEncoding => '字幕编码';

  @override
  String get videoSubtitleEncodingHint => '手动指定编码只影响这一次播放的外挂和导入字幕，用来兜底。';

  @override
  String get videoSubtitleEncodingAuto => '自动检测';

  @override
  String get videoSubtitleImportRemote => '从当前网盘导入';

  @override
  String get videoSubtitleImportLocal => '从本地文件导入';

  @override
  String get videoSubtitleBinarySkipped => '这个字幕不是文本，已跳过';

  @override
  String get videoSubtitleUnsupported => '只支持 srt、ass、ssa、vtt、sub';

  @override
  String get videoSubtitleLoadFailed => '字幕加载失败';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get appTitle => 'Webdav Media Manager';

  @override
  String get settings => '設定';

  @override
  String get language => '語言';

  @override
  String get languageSystem => '跟隨系統';

  @override
  String get languageSimplifiedChinese => '簡體中文';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get webdavServer => 'WebDAV 伺服器';

  @override
  String get download => '下載';

  @override
  String get homeAndNavigation => '媒體庫首頁和導覽';

  @override
  String get videoPlayback => '影片播放';

  @override
  String get fileTypes => '檔案類型';

  @override
  String get mediaNotifications => '媒體通知';

  @override
  String get languageSettingSubtitle => '選擇應用程式顯示語言，重新啟動後仍會保留';

  @override
  String get themeMode => '主題';

  @override
  String get themeModeSubtitle => '淺色、深色，或跟隨系統';

  @override
  String get themeModeSystem => '跟隨系統';

  @override
  String get themeModeLight => '淺色';

  @override
  String get themeModeDark => '深色';

  @override
  String get themeSeed => '主題色';

  @override
  String get themeSeedSubtitle => '淺色和深色都由這一個顏色生成';

  @override
  String get themeSeedReset => '恢復預設';

  @override
  String get themeSeedHue => '色相';

  @override
  String get themeSeedSaturation => '飽和度';

  @override
  String get themeSeedValue => '明度';

  @override
  String get library => '音樂庫';

  @override
  String get playlists => '歌單';

  @override
  String get networkLibrary => '網路庫';

  @override
  String get downloadQueue => '下載佇列';

  @override
  String get aboutAgpl => '關於 / AGPL';

  @override
  String get exitApp => '退出應用程式';

  @override
  String get cancel => '取消';

  @override
  String get exit => '退出';

  @override
  String get cacheOneDay => '1 天';

  @override
  String get cacheOneWeek => '1 週';

  @override
  String get cacheCustom => '自訂';

  @override
  String get cacheNever => '永不';

  @override
  String get snackShort => '很短';

  @override
  String get snackNormal => '預設';

  @override
  String get snackLong => '較長';

  @override
  String get snackUntilDismissed => '點擊後消失';

  @override
  String get snackOff => '關閉';

  @override
  String get syncOff => '關閉（僅手動）';

  @override
  String get syncEvery15m => '每 15 分鐘';

  @override
  String get syncEvery30m => '每 30 分鐘';

  @override
  String get syncHourly => '每 1 小時';

  @override
  String get syncEvery6h => '每 6 小時';

  @override
  String get syncDaily => '每 24 小時';

  @override
  String get actionCacheMusic => '快取音樂';

  @override
  String get actionDownload => '下載';

  @override
  String get actionStream => '串流傳輸';

  @override
  String get actionReadCue => 'CUE 讀取';

  @override
  String get actionStreamMusic => '串流傳輸（音樂）';

  @override
  String get actionShortCache => '快取';

  @override
  String get actionShortDownload => '下載';

  @override
  String get actionShortStream => '播放';

  @override
  String get actionShortCue => 'CUE';

  @override
  String get actionShortStreamMusic => '串流播放';

  @override
  String get targetCache => '應用程式快取';

  @override
  String get targetGallery => '系統相簿';

  @override
  String get targetDownloads => '系統下載目錄';

  @override
  String get musicModeSingle => '單曲循環';

  @override
  String get musicModeSequential => '順序播放';

  @override
  String get musicModeLoop => '清單循環';

  @override
  String get playbackMode => '播放模式';

  @override
  String unboundSource(Object sourceName) {
    return '未綁定網路磁碟「$sourceName」';
  }

  @override
  String get uncategorized => '未分類';

  @override
  String get unnamedPlaylist => '未命名歌單';

  @override
  String get defaultServer => '預設伺服器';

  @override
  String get accountsTitle => '網盤帳號管理';

  @override
  String get noAccounts => '尚未新增帳號。點擊右下角新增。';

  @override
  String get setCurrent => '設為目前';

  @override
  String get edit => '編輯';

  @override
  String get testConnection => '測試連線';

  @override
  String get delete => '刪除';

  @override
  String get connectionSuccess => '連線成功';

  @override
  String get connectionFailed => '連線失敗';

  @override
  String get deleteServer => '刪除伺服器';

  @override
  String confirmDeleteServer(Object name) {
    return '確定刪除「$name」？其曲目會變成「未綁定網路磁碟」，加回同名即可恢復。';
  }

  @override
  String get audioStreamingTitle => '音訊串流';

  @override
  String get streamPlayback => '串流播放';

  @override
  String get streamPlaybackHint => '音樂不下載到本機，直接從網路磁碟邊聽邊傳。';

  @override
  String get streamMusic => '串流傳輸音樂';

  @override
  String get streamMusicHint => '開啟後音樂的檔案動作可選「串流傳輸（音樂）」。關閉時該動作會退回預設。';

  @override
  String get scanList => '清單掃描';

  @override
  String get scanListHint => '決定串流播放的「上一首／下一首」清單內容。';

  @override
  String get scanSubdirectories => '搜尋子目錄';

  @override
  String get scanSubdirectoriesHint => '開啟：目前目錄及所有子目錄的音訊都加入清單。關閉：只列出目前這一層。';

  @override
  String get downloadPending => '等待中';

  @override
  String get downloadActive => '下載中';

  @override
  String get downloadCompleted => '已完成';

  @override
  String get downloadFailed => '失敗';

  @override
  String get downloadCancelled => '已取消';

  @override
  String get downloadAll => '全部下載';

  @override
  String get wakeWaiting => '喚醒等待中的工作';

  @override
  String get cancelAll => '全部取消';

  @override
  String get clearCompleted => '清除已完成';

  @override
  String get more => '更多';

  @override
  String get noDownloadTasks => '目前沒有下載工作';

  @override
  String get queueCleared => '下載佇列已清空';

  @override
  String get clearAllQueue => '清除所有佇列';

  @override
  String get cueAlbum => 'CUE';

  @override
  String songCount(Object count) {
    return '$count 首';
  }

  @override
  String get inProgress => '進行中';

  @override
  String retrying(Object current, Object max) {
    return '重試中（$current/$max）';
  }

  @override
  String get retry => '重試';

  @override
  String get clearQueueConfirm => '清除佇列？';

  @override
  String clearQueueDetails(Object count, Object runningText) {
    return '將移除 $count 筆佇列記錄$runningText；已下載的檔案會保留。';
  }

  @override
  String runningDownloads(Object count) {
    return '，並取消 $count 個進行中的下載';
  }

  @override
  String get clearAll => '全部清除';

  @override
  String get accountAddServer => '新增伺服器';

  @override
  String get accountEditServer => '編輯伺服器';

  @override
  String get accountName => '名稱';

  @override
  String get accountNameHint => '音樂庫按此名稱綁定，必須唯一；改名等同換磁碟';

  @override
  String get accountNameTaken => '此名稱已被使用，建議換一個';

  @override
  String get accountType => '類型';

  @override
  String get accountRemotePath => '遠端路徑';

  @override
  String get accountRemotePathHint => '瀏覽根目錄，預設 /（留空也是 /）';

  @override
  String get accountServerUrl => '伺服器 URL';

  @override
  String get accountUsername => '使用者名稱';

  @override
  String get accountPassword => '密碼';

  @override
  String get accountPasswordKeep => '密碼（留空則不修改）';

  @override
  String get accountPermissions => '權限';

  @override
  String get permissionRead => '讀取';

  @override
  String get permissionWrite => '寫入';

  @override
  String get permissionCreateFolder => '建立資料夾';

  @override
  String get permissionMove => '移動';

  @override
  String get permissionCopy => '複製';

  @override
  String get permissionDelete => '刪除';

  @override
  String get accountFillName => '請填寫名稱';

  @override
  String accountUnknownProvider(Object providerType) {
    return '未知網路磁碟類型：$providerType';
  }

  @override
  String accountFillField(Object label) {
    return '請填寫 $label';
  }

  @override
  String accountSelectField(Object label) {
    return '請選擇 $label';
  }

  @override
  String accountValidationFailed(Object error) {
    return '驗證失敗：$error';
  }

  @override
  String get accountSave => '儲存';

  @override
  String accountAdded(Object name) {
    return '已新增（$name）';
  }

  @override
  String get accountDuplicateTitle => '名稱已被使用';

  @override
  String accountDuplicateContent(Object name, Object url) {
    return '已有同名網路磁碟「$name」：\n$url\n\n同名會被視為同一來源。';
  }

  @override
  String get accountChangeName => '換個名稱';

  @override
  String get accountKeepName => '仍然使用';

  @override
  String get accountRenameTitle => '改名等同換磁碟';

  @override
  String get accountUsernameChangedTitle => '使用者名稱已修改';

  @override
  String accountRenameContent(Object name) {
    return '「$name」的曲目將變為「未綁定網路磁碟」，改回原名即可恢復。\n僅修改位址時請保持名稱不變。';
  }

  @override
  String get accountUsernameChangedContent =>
      '使用者名稱不參與綁定；新使用者名稱對應其他目錄時原路徑可能不存在。';

  @override
  String get accountConfirmChange => '確認修改';

  @override
  String get accountBindingHint => '曲目按「名稱 + 路徑」綁定；改名等同換磁碟。';

  @override
  String get manageAccounts => '管理多伺服器帳號';

  @override
  String get manageAccountsSubtitle => '新增／編輯／刪除 WebDAV 伺服器';

  @override
  String get downloadQueueSettings => '下載佇列';

  @override
  String get downloadQueueSettingsSubtitle => '續傳暫存檔保留上限與清理';

  @override
  String get customHome => '自訂首頁';

  @override
  String get customHomeSubtitle => '從其他介面返回時回到此首頁';

  @override
  String get rememberNetworkPath => '網路庫記住上次路徑';

  @override
  String get rememberNetworkPathSubtitle => '下次進入網路庫時恢復上次瀏覽的目錄';

  @override
  String get videoSettings => '影片播放設定';

  @override
  String get videoSettingsSubtitle => '串流參數／手勢／背景播放／子母畫面';

  @override
  String get audioSettings => '音訊串流設定';

  @override
  String get audioSettingsSubtitle => '串流傳輸開關／搜尋子目錄';

  @override
  String get fileExtensionSettings => '檔案副檔名管理';

  @override
  String get fileExtensionSettingsSubtitle => '音樂／影片／圖片／CUE 副檔名與預設動作';

  @override
  String get refreshLibraryTags => '手動更新音樂庫標籤';

  @override
  String get refreshLibraryTagsSubtitle => '非同步讀取已快取音樂檔案的標籤並更新曲庫';

  @override
  String get networkNewFolder => '新增資料夾';

  @override
  String get manageServers => '管理伺服器';

  @override
  String get currentServer => '目前伺服器';

  @override
  String get networkRetry => '重試';

  @override
  String get emptyDirectory => '空目錄';

  @override
  String get directory => '目錄';

  @override
  String get cueFile => 'CUE 檔案';

  @override
  String get playVideo => '播放影片';

  @override
  String get moreActions => '更多操作';

  @override
  String get cancelSelection => '取消全選';

  @override
  String get selectAll => '全選';

  @override
  String get cacheMusic => '快取音樂';

  @override
  String get copyTo => '複製到';

  @override
  String get moveTo => '移動到';

  @override
  String get downloadAction => '下載';

  @override
  String get fileQueuedOrSaved => '檔案已在下載佇列或已下載';

  @override
  String get fileQueuedOrSavedShort => '檔案已在佇列或已儲存';

  @override
  String get accountRequired => '請先新增網路磁碟帳號';

  @override
  String get syncTitle => '同步與備份';

  @override
  String get syncIntro => '憑證、歌單與音樂庫共用一條遠端路徑：在下面選網路磁碟、填寫路徑即可。';

  @override
  String get syncAll => '全部同步';

  @override
  String get scheduledSync => '定時同步';

  @override
  String get manualOnly => '已關閉，僅手動同步';

  @override
  String autoSync(Object interval) {
    return '$interval 自動同步';
  }

  @override
  String get remotePath => '遠端路徑';

  @override
  String get remotePathSubtitle => '憑證、音樂庫、歌單與備份都放在這條路徑下方';

  @override
  String get selectServer => '① 選擇網路磁碟';

  @override
  String get path => '② 路徑';

  @override
  String get pathExample => '例如填寫 /player，音樂庫就在 /player/library/';

  @override
  String get apply => '套用';

  @override
  String get encryptionKey => '統一加密金鑰（由你指定）';

  @override
  String get encryptionKeyHint => '只儲存在本機；留空則以明文儲存。';

  @override
  String get keyNotSet => '目前：未設定（憑證與備份中的密碼為明文）';

  @override
  String keySet(Object length) {
    return '目前：已設定（長度 $length）';
  }

  @override
  String get saveKey => '儲存金鑰';

  @override
  String get keySaved => '加密金鑰已儲存到本機';

  @override
  String operationFailed(Object error) {
    return '操作失敗：$error';
  }

  @override
  String get rebuildThreshold => '重建提示閾值';

  @override
  String get cloudFragmentCount => '雲端分片數';

  @override
  String get rebuildThresholdHint => '達到此數量時提示重建（2–500）';

  @override
  String get confirm => '確定';

  @override
  String get exitConfirm => '確定退出？播放將停止。';

  @override
  String get menu => '選單';

  @override
  String get aboutTitle => '關於';

  @override
  String aboutVersion(Object version) {
    return '版本 $version';
  }

  @override
  String get aboutCiVersion =>
      'CI 預發布會寫入 versionName（含短 hash）與遞增 versionCode，可覆蓋安裝。';

  @override
  String get aboutDescription => '瀏覽網路磁碟目錄，下載到本機快取後播放。';

  @override
  String get aboutCredits => '作者與致謝';

  @override
  String get aboutImplementation => '實作：Grok Bot';

  @override
  String get aboutConcept => '創意與需求框架：SenkjM';

  @override
  String get aboutLicense => '授權條款';

  @override
  String get aboutLicenseText =>
      '本專案採用 GNU Affero General Public License v3.0（AGPL-3.0）授權。\\n\\n你可以自由使用、修改與散布本軟體，但若發布修改版，或透過網路提供基於本軟體的服務，必須依 AGPL-3.0 公開對應完整原始碼。完整文字請見儲存庫 LICENSE 檔案。';

  @override
  String get fileExtSaved => '副檔名設定已儲存';

  @override
  String get fileExtIntro =>
      '依副檔名辨識檔案類型；多個副檔名以空格或逗號分隔。返回網路庫重新整理後生效。下面每一類的「點按行為」就是網路庫點按該檔案時的動作，多選工具列與「更多」選單遵循同一套判定。';

  @override
  String get fileCatMusic => '音樂檔案';

  @override
  String get fileCatVideo => '影片檔案';

  @override
  String get fileCatCue => 'CUE 檔案';

  @override
  String get fileCatOther => '一般檔案';

  @override
  String fileExtDefaultAction(Object action) {
    return '點按預設動作：$action';
  }

  @override
  String fileExtCueNote(Object action) {
    return '點按預設動作：$action（CUE 讀取會解析分片並整組下載）';
  }

  @override
  String fileExtOtherNote(Object action) {
    return '點按預設動作：$action（不在上面三張清單裡的副檔名，下載到系統下載目錄）';
  }

  @override
  String get fileExtTapAction => '點按行為';

  @override
  String get fileExtHintExample => '例如：mp3 flac m4a';

  @override
  String get fileExtListLabel => '副檔名清單';

  @override
  String get restoreDefault => '還原預設';

  @override
  String get dlPartFilesTitle => '斷點續傳的暫存檔';

  @override
  String get dlPartFilesIntro =>
      '網路中斷重試時會從半截檔案接著下。檔案留著才續得上，所以這裡配置的是上限：超過上限的部分會被自動清除（沒有對應下載任務的孤兒檔案也會清除）。';

  @override
  String get dlRetainDuration => '保留時長';

  @override
  String get unitHours => '小時';

  @override
  String get dlTotalSizeLimit => '總容量上限';

  @override
  String get dlCryptSequential => 'Crypt 順序流';

  @override
  String get dlCryptSequentialSub => '僅影響下載任務，線上播放與傳統續傳不變';

  @override
  String get dlCleanNow => '立即清理';

  @override
  String get dlCleanNowSub => '依上面的上限刪除過期的半截檔案';

  @override
  String get dlNothingToClean => '沒有需要清理的半截檔案';

  @override
  String dlCleanedCount(Object count) {
    return '已清理 $count 個半截檔案';
  }

  @override
  String dlFieldNotNumber(Object field) {
    return '$field請填寫數字';
  }

  @override
  String dlFieldClamped(
    Object field,
    Object max,
    Object min,
    Object unit,
    Object value,
  ) {
    return '$field只能在 $min~$max$unit 之間，已按 $value 儲存';
  }

  @override
  String dlRangeHint(Object max, Object min, Object unit) {
    return '範圍 $min ~ $max $unit，超範圍依邊界儲存';
  }

  @override
  String get playlistQueueEmpty => '目前播放清單為空';

  @override
  String playlistQueueDefaultName(Object day, Object month) {
    return '播放清單 $month/$day';
  }

  @override
  String get playlistCreateFromQueue => '從目前播放清單建立';

  @override
  String playlistCreateFromQueueBody(Object count) {
    return '複製目前佇列 $count 首到新歌單。';
  }

  @override
  String get playlistNameLabel => '歌單名稱';

  @override
  String get create => '建立';

  @override
  String playlistCreated(Object name) {
    return '已建立歌單「$name」';
  }

  @override
  String get playlistNew => '新增歌單';

  @override
  String get nameLabel => '名稱';

  @override
  String get playlistsTitle => '歌單';

  @override
  String get playlistSyncTooltip => '從 WebDAV 同步';

  @override
  String get playlistSynced => '已同步歌單';

  @override
  String playlistSyncFailed(Object error) {
    return '同步失敗：$error';
  }

  @override
  String get playlistsEmpty => '尚無歌單：右上角「+」新增，或在音樂庫長按曲目加入。';

  @override
  String playlistTrackCount(Object count) {
    return '$count 首';
  }

  @override
  String get playlistRename => '重新命名歌單';

  @override
  String get save => '儲存';

  @override
  String get playlistDelete => '刪除歌單';

  @override
  String playlistDeleteConfirm(Object name) {
    return '確定刪除「$name」？本機與 WebDAV 上的對應檔案都會刪除。';
  }

  @override
  String get rename => '重新命名';

  @override
  String get playlistNewEllipsis => '新增歌單…';

  @override
  String get playlistAddTo => '加入歌單';

  @override
  String get playlistAdded => '已加入歌單';

  @override
  String playlistAddMany(Object count) {
    return '加入 $count 首到歌單';
  }

  @override
  String playlistAddedMany(Object count) {
    return '已加入 $count 首到歌單';
  }

  @override
  String get playlistNotFound => '歌單不存在';

  @override
  String get playlistAddFromLibrary => '從音樂庫加入';

  @override
  String get playlistEmpty => '歌單為空，可從音樂庫加入。';

  @override
  String playlistMissingInLibrary(Object name) {
    return '暫無 · $name';
  }

  @override
  String get libraryEmpty => '音樂庫中沒有曲目';

  @override
  String get notDownloaded => '未下載';

  @override
  String get downloaded => '已下載';

  @override
  String get tapToDownload => '點按加入下載';

  @override
  String get streamNotConnected => 'WebDAV 未連線，無法串流播放';

  @override
  String get playlistSheetTitle => '播放清單';

  @override
  String get searchList => '搜尋清單';

  @override
  String get noMatchingTracks => '沒有符合的曲目';

  @override
  String get streamUrlFailed => '無法建立串流位址，請檢查帳號設定';

  @override
  String get loading => '載入中…';

  @override
  String get back => '返回';

  @override
  String get streamingNotCached => '串流傳輸 · 未快取';

  @override
  String seekSeconds(Object seconds) {
    return '$seconds 秒';
  }

  @override
  String get previousTrack => '上一首';

  @override
  String get pause => '暫停';

  @override
  String get play => '播放';

  @override
  String get nextTrack => '下一首';

  @override
  String playbackFailed(Object error) {
    return '播放失敗：$error';
  }

  @override
  String get newFolder => '新增資料夾';

  @override
  String get close => '關閉';

  @override
  String get parentFolder => '上一層';

  @override
  String get pickThisFolder => '到此資料夾';

  @override
  String get noSubfolders => '這個目錄裡沒有子資料夾';

  @override
  String movedItems(Object count) {
    return '已移動 $count 項';
  }

  @override
  String copiedItems(Object count) {
    return '已複製 $count 項';
  }

  @override
  String failedWith(Object reason) {
    return '失敗：$reason';
  }

  @override
  String movePartialResult(Object done, Object failed, Object reason) {
    return '成功 $done 項，失敗 $failed 項：$reason';
  }

  @override
  String get nowPlayingQueueTitle => '目前播放清單';

  @override
  String nowPlayingQueueCount(Object count) {
    return '目前播放清單（$count）';
  }

  @override
  String get nowPlayingQueueEmpty => '目前沒有播放佇列。\n從音樂庫或網路庫開始播放後會出現在此。';

  @override
  String playerChipAlbumArtist(Object artist) {
    return '專輯藝人 · $artist';
  }

  @override
  String playerChipTrackNumber(Object n, Object total) {
    return '曲目 $n/$total';
  }

  @override
  String playerChipTrackNoTotal(Object n) {
    return '曲目 $n';
  }

  @override
  String playerChipDiscNumber(Object n, Object total) {
    return '碟 $n/$total';
  }

  @override
  String playerChipDiscNoTotal(Object n) {
    return '碟 $n';
  }

  @override
  String get playerRowAccount => '帳號';

  @override
  String get playerRowServer => '伺服器';

  @override
  String get playerRowRemotePath => '遠端路徑';

  @override
  String get playerRowFileName => '檔名';

  @override
  String get playerRowType => '類型';

  @override
  String get playerRowCueNoteKey => '說明';

  @override
  String get playerRowCueNote => '來自 CUE 分片，播放與快取共用來源音訊。';

  @override
  String get playerRowCueFile => 'CUE 檔案';

  @override
  String get playerRowSourceAudio => '來源音訊';

  @override
  String get playerRowCueTrackIndex => 'CUE 曲序';

  @override
  String get playerClipEnd => '結尾';

  @override
  String get playerRowClipRange => '分片區間';

  @override
  String get playerRowLocalCache => '本機快取';

  @override
  String get playerNotDownloaded => '未下載';

  @override
  String get playerRowFileSize => '檔案大小';

  @override
  String get playerFileDetails => '檔案詳情';

  @override
  String get copyAll => '複製全部';

  @override
  String get copiedToClipboard => '已複製到剪貼簿';

  @override
  String copiedKey(Object key) {
    return '已複製：$key';
  }

  @override
  String get tagsUpdatedFromLocal => '已從本機檔案更新標籤';

  @override
  String get tagsNeedDownloadFirst => '該曲目尚未快取，請先下載後再更新標籤';

  @override
  String get updateThisTrackTags => '更新此曲標籤';

  @override
  String get nowPlaying => '正在播放';

  @override
  String get noTrackSelected => '未選擇曲目';

  @override
  String get dlSavedToGallery => '已存入系統相簿';

  @override
  String get dlTargetGallery => '目標：系統相簿';

  @override
  String get dlSavedToDownloads => '已存入下載目錄';

  @override
  String get dlTargetDownloads => '目標：下載目錄';

  @override
  String get rebuildHintThreshold => '重建提示閾值';

  @override
  String get cloudFragmentCountLabel => '雲端分片數';

  @override
  String get cloudFragmentCountHelper => '達到這個數量時提示重建（2–500）';

  @override
  String get unifiedEncryptionKey => '統一加密金鑰（由你指定）';

  @override
  String get unifiedEncryptionKeyHint => '只保存在本機；留空則以明文儲存。';

  @override
  String get keyNotSetLong => '目前：未設定（憑證與備份裡的密碼為明文）';

  @override
  String keySetLong(Object length) {
    return '目前：已設定（長度 $length）';
  }

  @override
  String get keySavedNotice => '加密金鑰已儲存到本機';

  @override
  String get overwriteLibraryTitle => '從雲端覆寫音樂庫';

  @override
  String get overwriteLibraryBody => '會從雲端下載音樂庫資料庫並覆寫本機。';

  @override
  String get overwriteLibraryNote =>
      '本機索引、標籤與尚未同步的改動會被雲端那份替換；已下載的音訊、封面與快取不會刪除。';

  @override
  String get overwriteLibraryAction => '覆寫';

  @override
  String get overwriteLibraryPhrase => '如果確認覆寫請輸入 YES';

  @override
  String get destroyLibraryTitle => '銷毀音樂庫';

  @override
  String get destroyLibraryBody => '會逐條銷毀本機音樂庫：每一首的快取音訊、封面與庫記錄都會被刪除，並各留一條墓碑。';

  @override
  String get destroyLibraryNote =>
      '刪除記錄會在下次同步時上傳到雲端，雲端重建也恢復不了這次銷毀的內容。此操作後會關閉自動同步。';

  @override
  String get destroyLibraryAction => '銷毀';

  @override
  String get destroyLibraryPhrase => '如果確認銷毀請輸入 YES';

  @override
  String destroyLibraryDone(Object count) {
    return '已銷毀 $count 首；下次同步上傳刪除記錄，定時同步已關閉';
  }

  @override
  String readCloudLibraryFailed(Object error) {
    return '讀取雲端庫失敗：$error';
  }

  @override
  String get tidyCloudLibraryTitle => '整理雲端音樂庫';

  @override
  String get missingFragments => '有分片缺失，只能重建。';

  @override
  String missingFragmentName(Object name) {
    return '• 缺 $name';
  }

  @override
  String get orphanFiles => '孤兒檔案：清單沒引用，可刪除。';

  @override
  String get auditHealthy => '一切一致，無需處理。';

  @override
  String get deleteOrphans => '刪除孤兒檔案';

  @override
  String get rebuildFromLocal => '以本機為準重建';

  @override
  String orphansDeleted(Object count) {
    return '已刪除 $count 個孤兒檔案';
  }

  @override
  String get restoreConfirmTitle => '確認恢復';

  @override
  String get restoreConfirmBody => '將用備份覆蓋本機帳號憑證、音樂庫與歌單，不可撤銷。';

  @override
  String get restore => '恢復';

  @override
  String exportedTo(Object fileName, Object location) {
    return '已匯出到$location：$fileName';
  }

  @override
  String exportFailed(Object error) {
    return '匯出失敗：$error';
  }

  @override
  String pickFileFailed(Object error) {
    return '選擇檔案失敗：$error';
  }

  @override
  String get pasteBase64First => '請先貼上備份內容（Base64）';

  @override
  String remoteRootUpdated(Object path) {
    return '遠端路徑已更新：$path';
  }

  @override
  String get derivedPathCredentials => '帳號憑證';

  @override
  String get derivedPathPlaylists => '歌單';

  @override
  String get derivedPathLibrary => '音樂庫';

  @override
  String get derivedPathBackups => '全部備份';

  @override
  String get syncAndBackup => '備份與同步';

  @override
  String get syncIntroLong => '憑證、歌單與音樂庫共用一條遠端路徑：在下面選網盤、填路徑即可。';

  @override
  String get scheduledSyncOff => '已關閉，僅手動同步';

  @override
  String scheduledSyncAuto(Object interval) {
    return '$interval 自動同步';
  }

  @override
  String get remotePathSubtitleLong => '憑證、歌單、音樂庫與備份都放在這條路徑下面';

  @override
  String get needWebdavServer => '請先新增 WebDAV 伺服器。';

  @override
  String get selectCloudDrive => '① 選擇網盤';

  @override
  String get pathStep => '② 路徑';

  @override
  String get pathExampleLong => '例如填 /player，音樂庫就在 /player/library/';

  @override
  String get credentialsSection => '帳號憑證';

  @override
  String credentialsSectionDesc(Object path) {
    return '雲端 $path：全部網盤帳號；密碼類欄位加密，不支援類型的帳號恢復時自動跳過。';
  }

  @override
  String get encryptPasswordField => '加密密碼類欄位';

  @override
  String get encryptPasswordOn => '口令不符時密碼留空';

  @override
  String get encryptPasswordOff => '明文儲存密碼';

  @override
  String lastAutoScan(Object time) {
    return '上次自動掃描：$time';
  }

  @override
  String get uploadCredentials => '上傳憑證';

  @override
  String get downloadCredentials => '下載憑證';

  @override
  String get playlistsSection => '歌單';

  @override
  String playlistsSectionDesc(Object path) {
    return '雙向同步。整份歌單按最後寫入合併；每個歌單另有一份刪除記錄，避免其它裝置把已刪歌單或曲目重新傳上來：$path';
  }

  @override
  String get syncPlaylistsNow => '立即同步歌單';

  @override
  String get compactPlaylistDeletions => '清理刪除記錄';

  @override
  String get compactPlaylistDeletionsHint => '以目前歌單為快照，刪掉各歌單的刪除記錄包。沒有定時提醒。';

  @override
  String get librarySection => '音樂庫';

  @override
  String librarySectionDesc(Object path) {
    return '${path}index.json 清單 + lib/seg/del 分片；只傳變化，刪除在重建時落實。';
  }

  @override
  String cloudFragmentsLine(Object count, Object hint, Object size) {
    return '雲端分片：$count 個（約 $size）$hint';
  }

  @override
  String get cloudFragmentsHint => ' · 建議重建';

  @override
  String get syncAction => '同步';

  @override
  String get rebuildAction => '重建';

  @override
  String get tidyAction => '整理';

  @override
  String rebuildHintNow(Object count, Object target) {
    return '目前雲端分片 $count 個，達到 $target 個時提示重建';
  }

  @override
  String rebuildHintTarget(Object target) {
    return '雲端分片達到 $target 個時提示重建';
  }

  @override
  String get customThreshold => '自訂…';

  @override
  String customThresholdValue(Object count) {
    return '自訂（$count）';
  }

  @override
  String get allBackupsSection => '全部備份';

  @override
  String allBackupsSectionDesc(Object path) {
    return '把憑證 + 音樂庫 + 歌單寫成一個封存到 $path。';
  }

  @override
  String get startBackup => '開始備份';

  @override
  String get readBackupsUnderPath => '讀取該路徑下的備份';

  @override
  String get backupToRestore => '要恢復的備份';

  @override
  String get restoreFromSelectedBackup => '從所選備份恢復';

  @override
  String get localImportExportSection => '本機匯入匯出';

  @override
  String get localImportExportDesc => '匯出、匯入同樣使用上面那把金鑰。';

  @override
  String get exportToDownloads => '匯出到系統下載目錄';

  @override
  String get exportReadableJson => '匯出可讀 JSON（排障，不含封面）';

  @override
  String get importFromLocalFile => '從本機檔案匯入…';

  @override
  String get pasteBase64Label => '或貼上備份內容（Base64）';

  @override
  String get importFromPaste => '從貼上內容匯入';

  @override
  String get processing => '處理中…';

  @override
  String get rebuildCloudLibraryTitle => '重建雲端音樂庫';

  @override
  String get rebuildCloudLibraryDesc => '以本機為準重寫全部分片，並落實刪除。';

  @override
  String get tracksPerShard => '每個分片包含歌曲數';

  @override
  String get embedCoversInShards => '把封面縮圖寫進分片';

  @override
  String get embedCoversInShardsDesc => '每首歌獨立存一份，不去重；關閉則雲端不含封面';

  @override
  String get estimating => '正在估算…';

  @override
  String get estimateUnavailable => '估算不可用';

  @override
  String get fileExtTapBehavior => '點按行為';

  @override
  String readBackupsListFailed(Object error) {
    return '讀取備份清單失敗：$error';
  }

  @override
  String get trackStateQueued => '排隊';

  @override
  String get trackStateDownloading => '下載中';

  @override
  String get trackStateReady => '就緒';

  @override
  String get trackStatePlaying => '播放中';

  @override
  String get trackStateError => '錯誤';

  @override
  String get playQueueTitle => '播放佇列';

  @override
  String get webdavErrorPerm => '權限錯誤';

  @override
  String get webdavErrorGeneric => '操作失敗';

  @override
  String get dialogOk => '確定';

  @override
  String get destroyInProgress => '正在銷毀';

  @override
  String processedOfTotal(Object processed, Object total) {
    return '已處理 $processed / $total 首';
  }

  @override
  String get destroyStopHint => '「終止」或直接返回都會停在當前這首之後；已經銷毀的不會恢復。';

  @override
  String get actionStop => '終止';

  @override
  String get tagRefreshInProgress => '正在更新標籤';

  @override
  String get tagRefreshStopHint => '只讀取本機快取；終止後保留已更新的曲目。';

  @override
  String get tagRefreshPreparing => '準備中';

  @override
  String get recoveryTitle => '需要恢復本機資料';

  @override
  String get recoveryHeading => '資料庫初始化失敗';

  @override
  String get recoveryBody => '請先匯出全部本機資料庫，再清除並重新進入應用。';

  @override
  String get recoveryNothingToExport => '未找到可匯出的本機資料庫';

  @override
  String recoveryExportedCount(Object count, Object ok) {
    return '已匯出 $ok / $count 個資料庫檔案到下載目錄';
  }

  @override
  String recoveryExportFailed(Object error) {
    return '匯出失敗：$error';
  }

  @override
  String get recoveryClearTitle => '清除本機資料庫？';

  @override
  String get recoveryClearContent => '建議先匯出資料庫。清除後請重新開啟應用，網盤帳號和本機索引需要重新設定。';

  @override
  String recoveryClearedCount(Object count) {
    return '已清除 $count 個資料庫檔案，請重新開啟應用';
  }

  @override
  String get recoveryExportAll => '匯出全部本機資料庫';

  @override
  String get recoveryClearAndExit => '清除並退出';

  @override
  String get recoveryClearAndReenter => '清除資料並重新進入';

  @override
  String get dialogCancel => '取消';

  @override
  String get fileActionIsFolder => '這是資料夾，不能按檔案動作處理';

  @override
  String fileActionNotApplicable(Object action, Object category) {
    return '「$action」不適用於$category';
  }

  @override
  String get fileActionNotApplicableGeneric => '該動作不適用於這個檔案';

  @override
  String get catMusicFile => '音樂檔案';

  @override
  String get catVideoFile => '影片檔案';

  @override
  String get catCueFile => 'CUE 檔案';

  @override
  String get catOtherFile => '一般檔案';

  @override
  String get videoGestureNone => '無操作';

  @override
  String get videoGestureBack10s => '後退 10 秒';

  @override
  String get videoGestureForward10s => '前進 10 秒';

  @override
  String get videoGestureBack30s => '後退 30 秒';

  @override
  String get videoGestureForward30s => '後退 30 秒';

  @override
  String get videoGestureHoldSpeedUp => '長按暫時加速（鬆手恢復）';

  @override
  String get videoGesturePlayPause => '播放 / 暫停';

  @override
  String get videoSubtitleVisible => '顯示字幕';

  @override
  String get videoSubtitleHidden => '不顯示';

  @override
  String get videoTapOpen => '開啟影片';

  @override
  String get videoTapDownload => '下載';

  @override
  String get musicTapDownload => '下載音樂';

  @override
  String get musicTapPlayCached => '播放（已快取則播放，否則下載）';

  @override
  String get libSortByName => '按名稱';

  @override
  String get libSortByAlbumTrack => '按曲序';

  @override
  String get cueMultiSliceLabel => '多歌曲合併分片';

  @override
  String get artistUnknown => '未知藝術家';

  @override
  String get albumUnknown => '未知專輯';

  @override
  String get snackGotIt => '知道了';

  @override
  String get rootFolder => '根目錄';

  @override
  String folderPickerTitle(Object folder, Object purpose) {
    return '$purpose：$folder';
  }

  @override
  String get webdavErrorPermDetail => '權限不足或未授權（401/403）';

  @override
  String itemWithMessage(Object message, Object name) {
    return '$name：$message';
  }

  @override
  String accountWithName(Object name, Object user) {
    return '$name（$user）';
  }

  @override
  String labelValuePair(Object label, Object value) {
    return '$label：$value';
  }

  @override
  String syncOperationFailed(Object error) {
    return '操作失敗：$error';
  }

  @override
  String get syncUnknownError => '未知錯誤';

  @override
  String get syncNoChanges => '無變更';

  @override
  String get syncListSep => '；';

  @override
  String get syncNotePrefix => '注意：';

  @override
  String get nameJoiner => '、';

  @override
  String get progressPreparing => '準備中…';

  @override
  String get progressDone => '完成';

  @override
  String get progressScanningCloudCredentials => '掃描雲端憑證…';

  @override
  String get progressScanningPlaylists => '掃描歌單…';

  @override
  String get progressUploadingCredentials => '上傳憑證…';

  @override
  String get progressDownloadingCredentials => '下載憑證…';

  @override
  String get progressMergingPlaylists => '合併歌單…';

  @override
  String get progressCompactingPlaylistDeletions => '清理歌單刪除記錄…';

  @override
  String get progressReadingCloudIndex => '讀取雲端曲庫索引…';

  @override
  String progressAdoptingCloudTracks(Object count) {
    return '採納雲端 $count 首…';
  }

  @override
  String progressUploadingTombstones(Object count) {
    return '上傳 $count 條刪除記錄…';
  }

  @override
  String progressAppendingSegments(Object count) {
    return '追加 $count 首到雲端增量分片…';
  }

  @override
  String get progressUploadingFullShards => '上傳完整曲庫分片…';

  @override
  String get progressPackingBackup => '打包憑證 / 音樂庫 / 歌單…';

  @override
  String get progressDownloadingRestore => '下載並還原…';

  @override
  String get progressGeneratingBackup => '產生備份…';

  @override
  String get progressWritingDownloads => '寫入下載目錄…';

  @override
  String get progressUnpackingRestore => '解包並還原…';

  @override
  String get warnCredentialsSkippedNoKey => '憑證同步已跳過（未設定統一加密金鑰）';

  @override
  String warnCredentialScanSkipped(Object e) {
    return '憑證掃描跳過：$e';
  }

  @override
  String warnLeftoverTombstones(Object count) {
    return '重建後仍殘留 $count 條墓碑（有活行與墓碑同時存在），建議檢查資料';
  }

  @override
  String stepPlaylistsMerged(Object count) {
    return '歌單已合併（$count 個）';
  }

  @override
  String stepCredentialsUploaded(Object count) {
    return '憑證已同步到雲端（$count 個伺服器）';
  }

  @override
  String get stepCloudNoCredentials => '雲端暫無憑證檔案';

  @override
  String stepPlaylistsSynced(Object count) {
    return '歌單已同步（$count 個）';
  }

  @override
  String get stepPlaylistDeletionsCompacted => '歌單刪除記錄已清理';

  @override
  String get stepIncrementalNoChange => '增量同步：無變更（未上傳任何內容）';

  @override
  String stepIncrementalUploaded(
    Object adopted,
    Object tombs,
    Object uploaded,
  ) {
    return '增量同步：上傳 $uploaded 首，採納 $adopted 首，刪除 $tombs 條';
  }

  @override
  String stepClearedDeadTombstones(Object count) {
    return '清理了 $count 條已失效的墓碑';
  }

  @override
  String stepRebuildDone(Object localCount, Object rev, Object shards) {
    return '重建完成：$shards 個分片，base 覆蓋到 rev $rev（本機 $localCount 首）';
  }

  @override
  String get stepBackupDone => '備份完成';

  @override
  String get stepRestoreDone => '還原完成';

  @override
  String get stepLocalBackupImported => '本機備份已匯入';

  @override
  String get errNoWebdavAccount => '請先新增 WebDAV 帳號';

  @override
  String vaultSummaryAccounts(Object imported, Object updated) {
    return '帳號：新增 $imported，更新 $updated；';
  }

  @override
  String vaultSummaryPasswords(
    Object passwordsMissing,
    Object passwordsRestored,
  ) {
    return '密碼還原 $passwordsRestored，留空 $passwordsMissing';
  }

  @override
  String get vaultSummaryMissingNote => '（缺少統一解密金鑰，可稍後手動填寫）';

  @override
  String vaultSummarySkipped(Object count) {
    return '；跳過 $count 個不支援的網路磁碟類型';
  }

  @override
  String get vaultSyncedEncrypted => '帳號憑證已同步到雲端（密碼已加密）';

  @override
  String get vaultSyncedPlaintext => '帳號憑證已同步到雲端（明文密碼）';

  @override
  String vaultCloudNoFile(Object remotePath) {
    return '雲端暫無憑證檔案（$remotePath），已跳過';
  }

  @override
  String vaultRestoredFromCloud(Object summary) {
    return '已從雲端還原帳號憑證：$summary';
  }

  @override
  String get errVaultDestNotConfigured => '憑證同步目的地網路磁碟未設定';

  @override
  String get errBackupDestNotConfigured => '備份目的地網路磁碟未設定';

  @override
  String backupDoneLatest(Object remote, Object size) {
    return '已備份到 $remote（$size；並更新 latest）';
  }

  @override
  String get errBackupEncryptedNeedPassphrase => '此備份已加密，請輸入口令';

  @override
  String get errBackupUnrecognizedContent => '無法識別的備份內容';

  @override
  String backupRestoredFull(Object count) {
    return '備份已還原：$count 個伺服器、音樂庫與歌單已寫回';
  }

  @override
  String backupRestoredMissingPasswords(Object missing) {
    return '備份已還原，但以下伺服器的密碼無法解密並已留空：$missing。請在帳號管理中補填。';
  }

  @override
  String errNotBackupArchive(Object kind) {
    return '這是 $kind 類檔案，不是備份封存';
  }

  @override
  String errPlaylistKindMismatch(Object expected, Object kind) {
    return '這是 $kind 類檔案，不是歌單文件（期望 $expected）';
  }

  @override
  String get errPlaylistMissingId => '歌單文件缺少 playlistId，無法辨識';

  @override
  String errPlaylistDeletionKindMismatch(Object expected, Object kind) {
    return '這是 $kind 類檔案，不是歌單刪除記錄（期望 $expected）';
  }

  @override
  String get errPlaylistDeletionMissingId => '歌單刪除記錄缺少 playlistId，無法辨識';

  @override
  String errVaultKindMismatch(Object expected, Object kind) {
    return '這是 $kind 類檔案，不是憑證庫（期望 $expected）';
  }

  @override
  String estimateLabelWithCovers(Object shards, Object sizeLabel) {
    return '預計 $shards 個分片 · 含封面約 $sizeLabel';
  }

  @override
  String estimateLabelNoCovers(Object shards, Object sizeLabel) {
    return '預計 $shards 個分片 · 不含封面約 $sizeLabel';
  }

  @override
  String auditBaseShards(Object count) {
    return '基礎分片 $count 個';
  }

  @override
  String auditSegments(Object count) {
    return '增量 $count 個';
  }

  @override
  String auditTombstones(Object count) {
    return '墓碑 $count 個';
  }

  @override
  String auditTotalBytes(Object size) {
    return '合計 $size';
  }

  @override
  String auditOrphans(Object count) {
    return '孤兒檔案 $count 個';
  }

  @override
  String auditMissing(Object count) {
    return '遺失檔案 $count 個';
  }

  @override
  String get exportErrUnsupportedPlatform => '目前平台不支援寫入系統相簿/下載目錄';

  @override
  String exportErrSourceMissing(Object detail) {
    return '來源檔案不存在：$detail';
  }

  @override
  String exportErrBadNativeResponse(Object detail) {
    return '匯出失敗：原生回傳 $detail';
  }

  @override
  String get exportErrFailed => '匯出失敗';

  @override
  String exportErrFailedWith(Object detail) {
    return '匯出失敗：$detail';
  }

  @override
  String get exportErrChannelUnavailable => '原生匯出通道不可用（需完整 APK）';

  @override
  String get pickerErrUnsupportedPlatform => '目前平台不支援系統檔案選擇器';

  @override
  String get pickerErrBadResponse => '檔案選擇回傳異常';

  @override
  String get pickerErrFailed => '檔案選擇失敗';

  @override
  String get pickerErrChannelUnavailable => '原生檔案選擇器不可用（需完整 APK）';

  @override
  String get locationSystemGallery => '系統相簿';

  @override
  String get locationDownloads => '下載目錄';

  @override
  String locationDownloadsSubdir(Object dir) {
    return '下載目錄/$dir';
  }

  @override
  String get dlChannelProgressName => '下載進度';

  @override
  String get dlChannelProgressDesc => '下載佇列進行中的進度';

  @override
  String get dlChannelDoneName => '下載完成';

  @override
  String get dlChannelDoneDesc => '全部下載完成後的結果彙總';

  @override
  String dlDoneCancelledCount(Object count) {
    return '取消 $count';
  }

  @override
  String dlDoneFailedCount(Object count) {
    return '失敗 $count';
  }

  @override
  String dlDoneOkCount(Object count) {
    return '成功 $count';
  }

  @override
  String get dlDoneSep => ' · ';

  @override
  String dlDoneTitle(Object parts) {
    return '下載完成：$parts';
  }

  @override
  String get dlErrCueMalformed => '無法解析的 CUE：需要標準 FILE + TRACK/INDEX';

  @override
  String get dlErrOffline => '網路不可用';

  @override
  String get dlErrQueueCleared => '佇列已清空';

  @override
  String dlErrQueueSchemaDrift(Object raw) {
    return '下載佇列資料庫結構過舊（$raw）。請重新啟動應用程式以升級資料庫。';
  }

  @override
  String dlErrSourceUnbound(Object source) {
    return '來源網路磁碟未綁定（$source）';
  }

  @override
  String get dlErrWritePublicFailed => '寫入公共目錄失敗';

  @override
  String dlNetworkInterruptedRetry(Object attempts, Object max) {
    return '網路中斷，正在重試 ($attempts/$max)';
  }

  @override
  String dlOfflineRetryWait(Object attempts, Object max, Object seconds) {
    return '網路不可用，$seconds 秒後重試 ($attempts/$max)';
  }

  @override
  String dlRetryExhausted(Object max, Object reason) {
    return '重試 $max 次仍失敗：$reason';
  }

  @override
  String netLoadGiveUpFailed(Object err, Object failures) {
    return '$err\n\n已自動重試 $failures 次仍失敗，等待手動重試。';
  }

  @override
  String netEnqueueFailed(Object err) {
    return '加入下載失敗：$err';
  }

  @override
  String get netStreamingExperimental => '音樂串流未開啟，請先在設定裡開啟';

  @override
  String get netParsingCue => '正在解析 CUE…';

  @override
  String netCueReadFailed(Object e) {
    return '讀取 CUE 失敗：$e';
  }

  @override
  String netCueGroupTitle(Object tracks) {
    return '$tracks 曲';
  }

  @override
  String netCueGroupTitleMulti(Object files, Object tracks) {
    return '$tracks 曲 · $files';
  }

  @override
  String get netCueGroupSubtitle => '將整張專輯按分片匯入音樂庫。';

  @override
  String netCueDownloadFailed(Object e) {
    return 'CUE 下載失敗：$e';
  }

  @override
  String netItemSubtitle(Object action, Object category) {
    return '$category · 點按＝$action';
  }

  @override
  String get netCacheFolderAudio => '快取資料夾中的音訊';

  @override
  String get netCacheFolderAudioDesc => '遞迴掃描，音訊進快取並進音樂庫';

  @override
  String get netDownloadWholeFolder => '下載整個資料夾';

  @override
  String get netDownloadWholeFolderDesc => '遞迴下載目錄樹，不挑檔案類型';

  @override
  String get netDefaultActionFromSettings => '設定裡的預設動作';

  @override
  String get netExperimentalNoDownload => '不下載、不進音樂庫';

  @override
  String get netDownloadToGallery => '下載到系統相簿';

  @override
  String get netDownloadToGalleryDesc => '儲存到 Movies/WebdavMediaManager';

  @override
  String get netCopyTo => '複製到…';

  @override
  String get netMoveTo => '移動到…';

  @override
  String get netNewName => '新名稱';

  @override
  String get netTapDownload => '點按下載';

  @override
  String netSelectedCount(Object n) {
    return '已選 $n 項';
  }

  @override
  String get netCachingMusic => '正在快取音樂…';

  @override
  String get netNoNewAudio => '這裡沒有新的音訊';

  @override
  String get netEnqueueing => '正在加入下載佇列…';

  @override
  String get netNothingDownloadable => '所選內容裡沒有可下載的檔案';

  @override
  String netEnqueuedCount(Object n) {
    return '已加入 $n 項';
  }

  @override
  String netEnqueueFailedFolders(Object n) {
    return '失敗 $n 個資料夾';
  }

  @override
  String get netJoinSep => '，';

  @override
  String get netFolder => '資料夾';

  @override
  String get netVideo => '影片';

  @override
  String get netAudio => '音訊';

  @override
  String get netFile => '檔案';

  @override
  String get netConfirmDeleteTitle => '確認刪除';

  @override
  String netConfirmDeleteMsg(Object name) {
    return '確定刪除「$name」？此操作不可復原。';
  }

  @override
  String get ntfAllDone => '全部下載完成';

  @override
  String ntfDoneCount(Object done, Object total) {
    return '已完成 $done / $total';
  }

  @override
  String ntfDoneCountPercent(Object done, Object percent, Object total) {
    return '總進度 $percent% · 已完成 $done / $total';
  }

  @override
  String get ntfDoneWithFailures => '下載結束（有失敗）';

  @override
  String ntfDownloadingTitle(Object index, Object total) {
    return '正在下載（第 $index / $total 個）';
  }

  @override
  String get ntfImportanceOff => '已關閉';

  @override
  String get ntfImportanceMin => '最低';

  @override
  String get ntfImportanceLow => '低';

  @override
  String get ntfImportanceDefault => '預設';

  @override
  String get ntfImportanceHigh => '高';

  @override
  String get ntfImportanceMax => '最高';

  @override
  String get ntfMediaChannelName => '音樂播放';

  @override
  String get ntfMediaChannelDesc => '正在播放的音樂控制';

  @override
  String get ntfStatusBlocked => '已關閉（請在系統通知設定中重新開啟）';

  @override
  String get ntfStatusChecking => '正在檢查…';

  @override
  String get ntfStatusCreated => '已建立';

  @override
  String ntfStatusCreatedImportance(Object importance) {
    return '已建立 · 重要性 $importance';
  }

  @override
  String get ntfStatusNoChannels => '目前平台無通知通道';

  @override
  String get ntfStatusNotCreated => '未建立';

  @override
  String ntfSummaryCancelled(Object count) {
    return '取消：$count 個';
  }

  @override
  String ntfSummaryFailed(Object count) {
    return '失敗：$count 個';
  }

  @override
  String ntfSummaryOk(Object count) {
    return '成功：$count 個';
  }

  @override
  String get ntfSelfTestAndroidOnly => '僅 Android 支援';

  @override
  String get ntfSelfTestBlocked => '系統已關閉本應用程式的通知';

  @override
  String get ntfSelfTestBody => '測試通知 · 50% · 已完成 0 / 1';

  @override
  String get ntfSelfTestSummary => '成功：1 個（測試）';

  @override
  String libQueuedCount(Object count) {
    return '已加入 $count 項下載';
  }

  @override
  String libQueuedUnavailable(Object count) {
    return '$count 項來源不可用';
  }

  @override
  String get libQueuedAdded => '已加入下載';

  @override
  String get cueGroupDeleteTitle => '刪除整個 CUE 快取組？';

  @override
  String get cueGroupDeleteTitleMulti => '刪除多個 CUE 快取組？';

  @override
  String get cueGroupDeleteBodyIntro => '將刪除整組：';

  @override
  String cueGroupDeleteBodyIntroCount(Object count) {
    return '將刪除 $count 個 CUE 組：';
  }

  @override
  String moreFilesCount(Object count) {
    return '…共 $count 個檔案';
  }

  @override
  String get cueGroupDeleteWhole => '刪除整組';

  @override
  String cueGroupDeleted(Object count) {
    return '已刪除 CUE 快取組（$count 個檔案）';
  }

  @override
  String get cacheDeleteTitle => '刪除本地音訊快取？';

  @override
  String cacheDeleteBodyOne(Object name) {
    return '將刪除「$name」的音訊快取，標籤與封面保留。';
  }

  @override
  String cacheDeleteBodyMany(Object count) {
    return '將刪除 $count 個快取檔案，標籤與封面保留。';
  }

  @override
  String cacheDeletedCount(Object count) {
    return '已刪除 $count 個本地音訊快取';
  }

  @override
  String get destroyTracksTitle => '銷毀所選曲目？';

  @override
  String destroyTracksBody(Object count) {
    return '將刪除 $count 首曲目（快取、庫記錄、詮釋資料與封面），不可復原。';
  }

  @override
  String get destroyTracksCueNote => '（CUE 分片整組刪除）';

  @override
  String get destroyAction => '銷毀';

  @override
  String destroyedTracksCount(Object count) {
    return '已銷毀 $count 首曲目';
  }

  @override
  String get shareCueUnsupported => 'CUE 音軌不支援分享';

  @override
  String get shareCueUnsupportedAndNotLocal => 'CUE 音軌不支援分享；其餘曲目尚未下載到本地';

  @override
  String get shareNotLocalOne => '該曲目尚未下載到本地，無法分享';

  @override
  String get shareNotLocalAll => '所選曲目均未下載到本地，無法分享';

  @override
  String shareCueSkipped(Object count) {
    return '已跳過 $count 首 CUE 音軌（不支援分享）';
  }

  @override
  String shareNotLocalSkipped(Object count) {
    return '已跳過 $count 首未下載曲目';
  }

  @override
  String get shareNothingToShare => '沒有可分享的檔案';

  @override
  String shareDoneCount(Object count) {
    return '已分享 $count 個檔案';
  }

  @override
  String shareFailed(Object reason) {
    return '分享失敗：$reason';
  }

  @override
  String get shareNameTitle => '分享檔名';

  @override
  String get shareRenameTemplateHint => '留空欄位會自動移除多餘分隔符，副檔名始終保留。';

  @override
  String get fileNameLabel => '檔名';

  @override
  String shareExtFixed(Object ext) {
    return '副檔名固定為 $ext';
  }

  @override
  String shareOriginalFile(Object name) {
    return '原始檔案：$name';
  }

  @override
  String get shareUseOriginalName => '使用原始檔名';

  @override
  String get shareAction => '分享';

  @override
  String get searchPlaceholder => '搜尋標題 / 藝術家 / 專輯';

  @override
  String get searchAction => '搜尋';

  @override
  String get closeSearch => '關閉搜尋';

  @override
  String get sortTooltip => '排序';

  @override
  String get tabAlbums => '專輯';

  @override
  String get tabArtists => '作者';

  @override
  String get tabTitles => '音樂名';

  @override
  String get tabGenres => '流派';

  @override
  String get libraryNoMatch => '無匹配曲目';

  @override
  String get genreEmpty => '暫無流派：下載帶流派詮釋資料的曲目後出現。';

  @override
  String get noMatchResult => '無匹配結果';

  @override
  String get updateCancelled => '已終止';

  @override
  String get updateDone => '更新完成';

  @override
  String updateSummary(Object a, Object b, Object c, Object d) {
    return '$a：更新 $b 首，跳過 $c 首，失敗 $d 首';
  }

  @override
  String get deleteCacheKeepMeta => '刪除快取（保留詮釋資料與封面）';

  @override
  String get updateTags => '更新標籤';

  @override
  String get downloadUncachedTracks => '下載未快取曲目';

  @override
  String get libraryTracksEmpty => '暫無曲目';

  @override
  String get sourceUnbound => '來源網路磁碟未綁定';

  @override
  String downloadingPercent(Object p) {
    return '下載中 $p%';
  }

  @override
  String get libraryEmptyGuide => '暫無曲目：先在「網路磁碟」下載音樂。';

  @override
  String get tagTitle => '標題';

  @override
  String get tagArtist => '藝術家';

  @override
  String get tagAlbumArtist => '專輯藝術家';

  @override
  String get tagAlbum => '專輯';

  @override
  String get tagTrack => '曲目';

  @override
  String get tagDisc => '碟片';

  @override
  String get tagYear => '年份';

  @override
  String get tagGenre => '流派';

  @override
  String get tagDuration => '時長';

  @override
  String get tagBitrate => '位元率';

  @override
  String get tagSampleRate => '取樣率';

  @override
  String get tagLanguage => '語言';

  @override
  String get tagLyrics => '歌詞';

  @override
  String errShardKindMismatch(Object a, Object b) {
    return '分片類型不一致：檔案頭 $a，META kind=$b';
  }

  @override
  String get errNotWdmmFile => '不是 Webdav Media Manager 檔案（缺少 WDMM 標識）';

  @override
  String errAccountNotConnected(Object a) {
    return '帳號未連線：$a';
  }

  @override
  String errBigintOverflow(Object a) {
    return '大整數超出 $a 位元組';
  }

  @override
  String errCloudAccountMissing(Object a) {
    return '網盤帳號不存在：$a';
  }

  @override
  String get errCloudWriteDisabled => '網盤帳號不支援上傳與雲端寫入同步';

  @override
  String get errContentRangeUnsupported => '此驅動不支援區間讀取';

  @override
  String get errContentStreamUnsupported => '此驅動不支援內容串流讀取';

  @override
  String get errDriverNotReady => '網盤驅動尚未接入';

  @override
  String errDriverNotReadyInfo(Object a) {
    return '網盤驅動尚未接入：$a';
  }

  @override
  String errDownloadSizeUnknown(Object a) {
    return '無法確定「$a」的大小，下載已取消';
  }

  @override
  String get errNeteaseRsaKeyLength => '網易 raw RSA 的金鑰必須是 16 位元組';

  @override
  String errStreamSizeUnknown(Object a) {
    return '無法確定「$a」的大小，暫不支援串流播放';
  }

  @override
  String get errWebdavNotConfigured => '未設定 WebDAV';

  @override
  String get errWebdavSourceNotConnected => 'WebDAV 未連線，無法取得來源內容';

  @override
  String errBaiduDirectLinkFailed(Object a) {
    return '取得下載直鏈失敗：$a';
  }

  @override
  String errBaiduRequestFailed(Object a) {
    return '百度網盤請求失敗：$a';
  }

  @override
  String errBaiduRiskControl(Object a) {
    return '$a 百度網盤風控（觸發安全策略，通常數分鐘至數小時後自動解除）。refresh_token 無效或非官方管道取得也可能觸發；請確認透過 https://api.oplist.org/ 取得。';
  }

  @override
  String errDriver123FileNotFound(Object a) {
    return '123 雲盤檔案不存在：$a';
  }

  @override
  String errDriver123NetworkFailed(Object a) {
    return '[123Open] 網路請求失敗：$a';
  }

  @override
  String errDriver123RequestFailed(Object a) {
    return '123 雲盤請求失敗：$a';
  }

  @override
  String get errMissingRefreshToken =>
      '123 雲盤缺少 refresh_token：請填寫 refresh_token（取得方法見 OpenList 官方文件 123_open 驅動頁）';

  @override
  String get errMkdirRoot => '不能建立根目錄';

  @override
  String errRefreshOnlineFailed(Object a, Object b) {
    return '線上 API 重新整理失敗 (HTTP $a)：$b。請確認 refresh_token 是透過 https://api.oplist.org/ 取得的有效權杖。';
  }

  @override
  String errRefreshOnlineFailedNonJson(Object a) {
    return '線上 API 重新整理失敗 (HTTP $a)：非 JSON 回應。請確認 refresh_token 是透過 https://api.oplist.org/ 取得的有效權杖。';
  }

  @override
  String get errRootOp => '不能對根目錄執行該操作';

  @override
  String get errOpen115MissingRefreshToken => '115 網盤缺少 refresh_token（必填）';

  @override
  String errOpen115RefreshFailed(Object a) {
    return '115 網盤 token 刷新失敗（$a）：請確認 refresh_token 有效。';
  }

  @override
  String errOpen115ApiError(Object a) {
    return '115 網盤 API 錯誤（$a）';
  }

  @override
  String errOpen115NetworkFailed(Object a) {
    return '115 網盤網路請求失敗（$a）';
  }

  @override
  String get errOpen115DownurlEmptyData => '115 網盤 downurl 未回傳直鏈資料（data 為空）';

  @override
  String get errOpen115DownurlEmptyUrl => '115 網盤 downurl 未回傳可用直鏈（url.url 為空）';

  @override
  String errOpen115MissingPickCode(Object a) {
    return '115 網盤條目缺少 pick_code，無法取得直鏈：$a';
  }

  @override
  String errOpen115TokenVerifyFailed(Object a) {
    return '115 網盤 token 驗證失敗：$a。請確認 access_token / refresh_token 有效。';
  }

  @override
  String errOpen115NetworkConnectFailed(Object a) {
    return '115 網盤網路連線失敗（$a）：proapi.115.com 可能無法從目前部署環境存取（資料中心 IP 可能被 115 攔截），請稍後重試或更換部署環境。';
  }

  @override
  String errOpen115DirectLinkFailed(Object a) {
    return '取得 115 網盤直鏈失敗：$a';
  }

  @override
  String errOpen115CopyRenameFailed(Object a) {
    return '115 網盤複製完成但未找到副本，無法改名為 $a';
  }

  @override
  String errOpen115FolderNotFound(Object a) {
    return '115 網盤目錄不存在：$a';
  }

  @override
  String errOpen115FileNotFound(Object a) {
    return '115 網盤檔案不存在：$a';
  }

  @override
  String errAliyunEntryOrLinkFailed(Object a) {
    return '無法取得條目或直鏈：$a';
  }

  @override
  String get errAliyunMissingRefreshToken =>
      '阿里雲盤缺少 refresh_token：請在帳號表單填寫 refresh_token（取得方法見 OpenList 官方文件 aliyundrive_open 驅動頁）。';

  @override
  String errAliyunNetworkFailed(Object a) {
    return '[AliyundriveOpen] 網路請求失敗 $a';
  }

  @override
  String get errAliyunNoDirectLink =>
      '[AliyundriveOpen] getDownloadUrl 未回傳直鏈（url / download_url 都為空）';

  @override
  String get errAliyunNoDriveId =>
      '[AliyundriveOpen] getDriveInfo 未回傳任何 drive_id（resource / default / backup 都為空）：請確認帳號已開通阿里雲盤。';

  @override
  String errAliyunNonJson(Object a) {
    return '非 JSON 回應：$a';
  }

  @override
  String errAliyunRefreshAllFailed(Object a) {
    return '[AliyundriveOpen] 刷新權杖的所有策略均失敗。請依次檢查：1) refresh_token 是否有效且未過期；2) api_url_address 是否可存取；3) 若使用直連 OAuth，client_id / client_secret 是否正確。嘗試記錄：$a';
  }

  @override
  String errTeraboxRedirectFailed(Object a) {
    return 'TeraBox 直鏈重新導向失敗（$a）';
  }

  @override
  String errTeraboxRequestFailed(Object a) {
    return 'TeraBox 請求失敗 $a';
  }

  @override
  String get errTeraboxSignKeyEmpty =>
      'TeraBox 簽章失敗：sign3 金鑰為空（上游 /api/home/info 未回傳 sign3）';

  @override
  String errNeteaseApiError(Object a) {
    return '網易雲音樂介面報錯（$a）';
  }

  @override
  String get errNeteaseCookieRequired =>
      'Cookie 必須同時包含 __csrf 與 MUSIC_U：請在網頁版 music.163.com 登入後，從開發者工具複製完整 Cookie';

  @override
  String get errNeteaseCopyUnsupported => '網易雲音樂雲盤不支援複製（上游驅動未實作該操作）';

  @override
  String errNeteaseFileNotFound(Object a) {
    return '檔案不存在：$a';
  }

  @override
  String errNeteaseLoginExpired(Object a) {
    return '網易雲音樂登入態已失效（$a）。Cookie 可能已過期，請重新登入網頁版並更新 Cookie';
  }

  @override
  String get errNeteaseMkdirUnsupported => '網易雲音樂雲盤不支援新增資料夾（上游驅動未實作該操作）';

  @override
  String get errNeteaseMoveUnsupported => '網易雲音樂雲盤不支援移動（上游驅動未實作該操作）';

  @override
  String get errNeteaseNoSongLink => '網易雲音樂未回傳播放連結（可能是 VIP / 版權受限 / 已下架的歌曲）';

  @override
  String errNeteaseNonJson(Object a) {
    return '網易雲音樂回傳了非 JSON 回應：$a';
  }

  @override
  String get errNeteaseRenameUnsupported => '網易雲音樂雲盤不支援重新命名（上游驅動未實作該操作）';

  @override
  String errNeteaseRequestFailed(Object a) {
    return '網易雲音樂請求失敗：$a';
  }

  @override
  String get errNeteaseRootDelete => '網易雲音樂不支援刪除根目錄';

  @override
  String errNeteaseUnexpectedStructure(Object a) {
    return '網易雲音樂回傳了非預期結構：$a';
  }

  @override
  String errNeteaseUnknownCrypto(Object a) {
    return '未知的加密方式：$a';
  }

  @override
  String errCryptBadCipherLength(Object a) {
    return 'crypt 密文長度不合法：$a';
  }

  @override
  String errCryptBlockDecryptFailed(Object a) {
    return 'crypt 第 $a 塊解密失敗（內容損壞或金鑰不匹配）';
  }

  @override
  String errCryptBlockRangeDecryptFailed(Object a) {
    return 'crypt 第 $a 塊起解密失敗（內容損壞或金鑰不匹配）';
  }

  @override
  String get errCryptDecryptFailed => 'crypt 內容解密失敗（內容損壞或金鑰不匹配）';

  @override
  String errCryptEarlyEof(Object a, Object b, Object c) {
    return 'crypt 內容提前結束（第 $a 塊起，期望 $b 位元組，收到 $c 位元組）';
  }

  @override
  String errCryptInvalidConfig(Object a) {
    return 'crypt 配置無效：$a';
  }

  @override
  String errCryptLengthMismatch(Object a, Object b) {
    return 'crypt 內容長度不符（期望 $a，收到 $b）';
  }

  @override
  String get errCryptNoDirectLinkAnymore => 'crypt 來源不再提供直鏈，無法繼續解密內容';

  @override
  String get errCryptNoDirectLinkDecrypt => 'crypt 來源不提供直鏈，無法解密內容';

  @override
  String get errCryptNoDirectLinkStream => 'crypt 來源不提供直鏈，無法順序下載';

  @override
  String get errCryptNoHeader => 'crypt 內容不完整（讀不到檔案頭）';

  @override
  String get errCryptNoResponseBody => 'crypt 順序下載沒有回應體';

  @override
  String get errCryptNoSourceName => 'crypt 未儲存來源帳號名稱；請重新編輯並選擇來源帳號';

  @override
  String errCryptNotRcloneFile(Object a) {
    return '不是有效的 rclone 加密檔案：$a';
  }

  @override
  String get errCryptSizeUnknown => '無法確定加密內容的大小（來源未提供長度且不支援 Range）';

  @override
  String errCryptSourceMissing(Object a) {
    return 'crypt 來源帳號不存在或已刪除「$a」；重新新增同名來源帳號即可還原';
  }

  @override
  String get driverNameBaidu => '百度網盤';

  @override
  String get driverName123Open => '123 雲盤開放平台';

  @override
  String get driverName115 => '115網盤';

  @override
  String get driverNameAliyunOpen => '阿里雲盤開放平台';

  @override
  String get driverNameNetease => '網易雲音樂';

  @override
  String get driverNameCrypt => 'Crypt 加密目錄';

  @override
  String errRefreshOnlineNon200(Object a) {
    return '線上 API 傳回 HTTP $a';
  }

  @override
  String get formLabelRenewApi => '線上續期地址';

  @override
  String get formHintRenewApiDefault => '預設使用 OpenList 維護的公共服務';

  @override
  String get formHintLocalRefreshDisabled => '已開啟本機重新整理（線上續期停用），關閉開關後可編輯';

  @override
  String get formLabelLocalRefresh => '在本機處理權杖重新整理';

  @override
  String get formSubLocalRefreshBaidu =>
      '關閉＝線上續期地址重新整理；開啟＝用自建百度應用重新整理（需 Client ID / Secret），線上續期停用';

  @override
  String get formSubLocalRefresh123 =>
      '關閉＝線上續期；開啟＝用自建 123 應用重新整理（需 Client ID / Secret），線上續期停用';

  @override
  String get formSubLocalRefreshAliyun =>
      '關閉＝用線上續期地址輪詢；開啟＝用自建阿里雲應用直接重新整理（需 Client ID / Secret）';

  @override
  String formHintOpenListDoc(Object a) {
    return '必填；取得方法請見 OpenList 官方文件（$a 驅動頁）';
  }

  @override
  String get formLabelRootId => '根目錄 ID';

  @override
  String formHintRootIdOpaque(Object a) {
    return '不透明 id，預設 $a（網盤根目錄）；與帳號的遠端路徑疊加生效';
  }

  @override
  String get formHint115RefreshToken =>
      '必填；取得方法請見 OpenList 官方文件（115 Open 驅動頁）。115 每次重新整理都會輪換它，輪換結果會自動儲存';

  @override
  String get formHint115RootId => '預設 0（整體根目錄）；填非 0 的目錄 ID 可把帳號掛到該目錄下';

  @override
  String get formLabelPageSize => '分頁大小';

  @override
  String get formHintPageSize => '範圍 1~1150，預設 200（超出會被夾到邊界；115 單次上限 1150）';

  @override
  String get formLabelRateLimit => '限速（次/秒）';

  @override
  String get formHintRateLimit => '預設 0 = 不限速；填正數則兩次 API 請求之間至少間隔 1/該值 秒';

  @override
  String get formLabelDriveType => '網盤類型';

  @override
  String get formHintDriveType => '資源盤 / 預設盤 / 備份盤，對應同一個帳號下的不同 drive_id';

  @override
  String get optionDriveResource => '資源盤';

  @override
  String get optionDriveDefault => '預設盤';

  @override
  String get optionDriveBackup => '備份盤';

  @override
  String get formLabelDeleteMode => '刪除方式';

  @override
  String get formHintDeleteMode => '移入回收站可在阿里雲盤裡找回；徹底刪除不可還原';

  @override
  String get optionDeleteTrash => '移入回收站';

  @override
  String get optionDeletePermanent => '徹底刪除';

  @override
  String get formHintTeraboxCookie => '必填；從瀏覽器複製 TeraBox 的 Cookie；過期後需重新貼上';

  @override
  String get formLabelRootPath => '根目錄路徑';

  @override
  String get formHintNeteaseCookie =>
      '必填；需含 __csrf 與 MUSIC_U。登入 music.163.com 後從開發者工具複製完整 Cookie（取得方法請見 OpenList 官方文件 netease_music 驅動頁）';

  @override
  String get formLabelSongLimit => '歌曲數量上限';

  @override
  String formHintSongLimit(Object a) {
    return '預設 $a；網易雲盤介面按此上限一次列取';
  }

  @override
  String get formLabelSourceAccount => '來源帳號';

  @override
  String get formHintSourceAccount => '選擇現有 WebDAV 或網盤帳號作為加密來源';

  @override
  String get formLabelSourceDir => '來源目錄';

  @override
  String get formHintSourceDir => '來源帳號瀏覽根下的目錄，預設 /（加密檔案就存在這裡）';

  @override
  String get formLabelFilenameEncoding => '檔名編碼';

  @override
  String get formHintFilenameEncoding =>
      '與 rclone 的 filename_encoding 對應（base32 / base64 / base32768）';

  @override
  String get formLabelEncryptedSuffix => '檔名後綴';

  @override
  String get formHintEncryptedSuffix =>
      '僅檔名加密=關閉時生效（OpenList encrypted_suffix）';

  @override
  String get formLabelPassword => '密碼';

  @override
  String get formLabelSalt => '鹽值（可選）';

  @override
  String get formHintSalt =>
      '留空用 rclone 內建預設鹽；密碼 + 鹽相同即可與 rclone / OpenList 互認';

  @override
  String get formLabelFilenameEncryption => '檔名加密';

  @override
  String get optionCryptStandard => '標準 (EME)';

  @override
  String get optionCryptObfuscate => '混淆';

  @override
  String get optionCryptOff => '關閉';

  @override
  String get formLabelDirNameEncryption => '目錄名加密';

  @override
  String get formSubDirNameEncryption => 'OpenList 預設關閉；開啟後目錄名同樣加密';

  @override
  String get svcNoLocalCache => '本機無快取，請先下載';

  @override
  String get svcCacheNotInitialized => 'CacheService 未初始化';

  @override
  String get svcBackupAccountMissingId => '備份帳號缺少 id，無法安全復原';

  @override
  String get svcLocalFileUnavailable => '本機檔案不可用';

  @override
  String get backupTooShort => '備份檔案過短或損毀';

  @override
  String backupNotEncrypted(Object magic) {
    return '不是加密備份（缺少 $magic 標頭）';
  }

  @override
  String get backupCiphertextDamaged => '備份密文損毀';

  @override
  String get vaultCiphertextDamaged => '憑證密文損毀';

  @override
  String get vaultNoteEncrypted => '密碼類欄位（含雲端磁碟權杖）已加密（AES-256-GCM），其餘欄位為明文。';

  @override
  String get vaultNotePlain => '密碼類欄位為明文儲存。';

  @override
  String get mediaArtistWebdav => 'WebDAV 串流媒體';

  @override
  String ntfProbeHint(Object channel) {
    return ' | 若仍無通知: 設定→應用程式→Webdav Media Manager→電池最佳化=不限制;通知=允許(含鎖定畫面/懸浮); 頻道「$channel」請勿關閉';
  }

  @override
  String get ntfProbeRunning => '執行';

  @override
  String get ntfProbeNone => '無';

  @override
  String get ntfProbeActive => '活躍';

  @override
  String get ntfProbeInactive => '否';

  @override
  String get ntfProbePosted => '已發布';

  @override
  String get ntfProbeNotPosted => '未發布';

  @override
  String get ntfProbeChanMissing => '(未建立)';

  @override
  String get ntfProbeChanBlocked => '(已關閉)';

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
    return '服務=$svc 會話=$session 通知=$posted 系統通知開關=$perm 頻道=$channel$chanState 重要性=$importance 本套件會話數=$sessions 裝置=$device$hint';
  }

  @override
  String ntfProbeReturn(Object raw) {
    return '探測返回: $raw';
  }

  @override
  String get ntfProbeChannelUnavailable => '原生探測通道不可用（需完整 APK）';

  @override
  String ntfProbeFailed(Object message) {
    return '探測失敗: $message';
  }

  @override
  String ntfForceNoAudio(Object error, Object probe) {
    return '沒有可用的本機音訊。請先播放一首歌，再點測試。\n$probe$error';
  }

  @override
  String ntfForcePlayed(
    Object error,
    Object probe,
    Object state,
    Object title,
  ) {
    return '已強制播放「$title」 playing=$state\n$probe$error\n請查看通知列 / 媒體控制中心。';
  }

  @override
  String ntfAsyncError(Object error) {
    return '\n⚠ audio_service 橋接錯誤: $error';
  }

  @override
  String get phArtist => '作者';

  @override
  String get phTitle => '標題';

  @override
  String get phAlbum => '專輯';

  @override
  String get phAlbumArtist => '專輯作者';

  @override
  String get phTrack => '音軌號';

  @override
  String get phYear => '年份';

  @override
  String get phGenre => '流派';

  @override
  String get phFileName => '原始檔名';

  @override
  String get videoStreamingHint => '影片直接串流播放，不下載到本機。';

  @override
  String get videoHardwareDecoding => '硬體解碼';

  @override
  String get videoHardwareDecodingHint => '關閉後改用軟體解碼，部分裝置更穩定';

  @override
  String get videoScanSubdirsHint => '播放清單是否包含子目錄中的影片';

  @override
  String get videoBufferSize => '緩衝大小';

  @override
  String get videoBufferInput => '緩衝 (MB)';

  @override
  String get videoGestures => '手勢';

  @override
  String get videoGestureLeftDoubleTap => '左側雙擊';

  @override
  String get videoGestureRightDoubleTap => '右側雙擊';

  @override
  String get videoGestureLongPress => '長按';

  @override
  String get videoLongPressRate => '長按臨時倍速';

  @override
  String get videoDefaultRate => '預設播放倍速';

  @override
  String get videoSubtitles => '字幕';

  @override
  String get videoSubtitleHint => '顯示控件時位於控制列上方，隱藏時貼近視窗底部。';

  @override
  String get videoSubtitleSize => '字幕大小';

  @override
  String get videoPlaybackBehavior => '播放行為';

  @override
  String get videoBackgroundPlayback => '背景播放';

  @override
  String get videoBackgroundPlaybackHint => '離開播放器後繼續播放聲音';

  @override
  String get videoPip => '子母畫面（小窗）';

  @override
  String get videoPipHint => '播放控件中顯示子母畫面按鈕（Android 8+）';

  @override
  String get videoBufferSaved => '緩衝大小已儲存，下次播放生效';

  @override
  String videoBufferCurrent(Object current, Object max, Object min) {
    return '目前 $current MB（範圍 $min–$max MB）';
  }

  @override
  String videoLongPressCurrent(Object rate) {
    return '按住加速至 $rate×，放手恢復';
  }

  @override
  String videoDefaultRateCurrent(Object max, Object min, Object rate) {
    return '目前 $rate×（範圍 $min×–$max×）';
  }

  @override
  String videoSubtitleSizeCurrent(Object max, Object min, Object size) {
    return '目前 $size sp（範圍 $min–$max sp）';
  }

  @override
  String get accountsSubtitle => '管理多伺服器帳號';

  @override
  String get audioStreamingSubtitle => '串流傳輸開關 / 搜尋子目錄';

  @override
  String get fileTypesManage => '檔案副檔名管理';

  @override
  String get fileTypesManageSubtitle => '音樂 / 影片 / 圖片 / CUE 副檔名與預設動作';

  @override
  String get coverThumbSize => '封面縮圖尺寸';

  @override
  String get coverThumbHint => '新封面按此邊長生成；已有封面需重新生成。';

  @override
  String get coverSize => '邊長 (px)';

  @override
  String get cacheCleanup => '快取清理';

  @override
  String get cacheCleanupHint => '僅清理音訊快取（播放/下載中的保留），標籤與封面不受影響。';

  @override
  String get currentCacheUsage => '目前快取用量';

  @override
  String get calculating => '計算中…';

  @override
  String get unknown => '未知';

  @override
  String get refresh => '重新整理';

  @override
  String get customRetentionHint => '自訂保留時間（至少 1 小時）';

  @override
  String get days => '天';

  @override
  String get hours => '小時';

  @override
  String get autoCleanupDisabled => '已關閉自動清理，可使用下方按鈕手動清空。';

  @override
  String get clearAudioCache => '手動清空音訊快取';

  @override
  String get shareRenameHint => '分享時按標籤重新命名檔案名稱。';

  @override
  String get shareRenameTitle => '分享時按標籤重新命名';

  @override
  String get shareRenameSubtitle => '預設開啟；分享單一檔案時仍可修改檔名';

  @override
  String get renameTemplate => '重新命名範本';

  @override
  String get syncSettings => '同步與備份設定';

  @override
  String get shareRenameTemplate => '分享重新命名範本';

  @override
  String get videoPrevious => '上一部影片';

  @override
  String get videoNext => '下一部影片';

  @override
  String get videoLockScreen => '鎖定螢幕';

  @override
  String get videoOrientation => '切換橫豎屏';

  @override
  String get videoLockHint => '隱藏控制項並停用手勢，長按解鎖';

  @override
  String get videoOrientationLock => '鎖定旋轉方向';

  @override
  String get videoOrientationLockHint => '固定為目前橫屏/豎屏';

  @override
  String get videoExitConfirm => '退出時二次確認';

  @override
  String get videoExitConfirmHint => '返回時二次確認';

  @override
  String get videoGestureSettingsHint => '雙擊 / 長按動作與長按倍速';

  @override
  String cacheCleared(Object count, Object libraryCount) {
    return '已清理 $count 個快取檔案（保留 $libraryCount 首元資料）';
  }

  @override
  String get tagRefreshStarted => '正在背景更新本地快取曲目的標籤';

  @override
  String tagRefreshCompleted(Object failed, Object skipped, Object updated) {
    return '標籤更新完成：更新 $updated 首，略過 $skipped 首，失敗 $failed 首';
  }

  @override
  String get notificationEnabled => '通知權限已開啟，播放時會顯示媒體通知';

  @override
  String get notificationOpenSettings => '請在系統設定中允許通知後返回應用程式';

  @override
  String get notificationOpenSettingsFailed => '無法開啟系統設定，請手動允許通知權限';

  @override
  String get notificationGranted => '已授予通知權限';

  @override
  String get notificationDenied => '未授予通知權限，媒體通知可能無法顯示';

  @override
  String retentionDaysHours(Object days, Object hours) {
    return '目前：保留 $days 天 $hours 小時未存取的音訊';
  }

  @override
  String retentionDays(Object days) {
    return '目前：保留 $days 天未存取的音訊';
  }

  @override
  String retentionHours(Object hours) {
    return '目前：保留 $hours 小時未存取的音訊';
  }

  @override
  String get notificationChecking => '正在檢查…';

  @override
  String get notificationStatusAllowed => '已允許，播放/暫停時顯示媒體通知';

  @override
  String get notificationChannelBlocked => '「音樂播放」頻道已關閉，點此開啟系統設定';

  @override
  String get notificationStatusDenied => '已拒絕，點此開啟系統設定';

  @override
  String get notificationChannelMissing => '「音樂播放」頻道未建立，播放一次或點「重新整理」重試';

  @override
  String get notificationNotGranted => '未授權，點此要求通知權限';

  @override
  String get hintsAndNotifications => '提示與通知';

  @override
  String get hintsSubtitle => '螢幕底部提示同時只顯示一則，點「知道了」立即關閉。';

  @override
  String get hintDuration => '提示顯示時長';

  @override
  String get downloadNotifications => '下載佇列系統通知';

  @override
  String get downloadNotificationsHint => '下載進度與完成結果顯示在通知列';

  @override
  String get sendTestNotification => '傳送測試通知';

  @override
  String get sendTestNotificationHint => '立即傳送一則進度與一則完成通知，用於排查系統是否攔截';

  @override
  String get testNotificationSent => '測試通知已傳送（進度 + 完成各一則）';

  @override
  String testNotificationFailed(Object error) {
    return '測試通知失敗：$error';
  }

  @override
  String get confirmCloseVideo => '確認關閉影片嗎？';

  @override
  String get webdavNotConnectedPlay => 'WebDAV 未連線，無法播放';

  @override
  String get videoQueueEmpty => '目前沒有播放佇列';

  @override
  String get pipUnsupported => '目前裝置/系統不支援子母畫面';

  @override
  String videoPlayFailed(Object error) {
    return '無法播放：$error';
  }

  @override
  String get scanningFolder => '正在掃描資料夾…';

  @override
  String get buffering => '緩衝中…';

  @override
  String get opening => '正在開啟';

  @override
  String get downloadKeepAlive => '後台下載保活';

  @override
  String get downloadKeepAliveHint => '開啟後，下載期間通知列會常駐一則下載通知（系統要求），關閉下載通知也會顯示';

  @override
  String get streamingSection => '串流傳輸';

  @override
  String get imageViewer => '圖片檢視';

  @override
  String get imageViewerSubtitle => '幻燈片、適應方式、預取數量';

  @override
  String get imageSlideshow => '幻燈片播放';

  @override
  String get imageSlideshowHint => '按間隔自動切到下一張。手動翻頁會重新計時，不會關閉這個開關。';

  @override
  String get imageSlideshowInterval => '間隔';

  @override
  String imageSlideshowSeconds(Object seconds) {
    return '$seconds 秒';
  }

  @override
  String get imageSlideshowLoop => '循環';

  @override
  String get imageSlideshowLoopHint => '放到最後一張後回到第一張';

  @override
  String get imageFit => '適應方式';

  @override
  String get imageFitContain => '完整顯示';

  @override
  String get imageFitCover => '鋪滿';

  @override
  String get imagePrefetchCount => '預取數量';

  @override
  String get imagePrefetchHint => '向前、向後各預取這麼多張（1–5），不會一次載入整本相簿。預設每側 1 張。';

  @override
  String get imageScanSubdirs => '搜尋子目錄';

  @override
  String get imageScanSubdirsHint => '預設關閉。開啟後相簿會包含子目錄中的圖片，掃描可能較慢。';

  @override
  String get actionViewImage => '檢視圖片';

  @override
  String get actionShortViewImage => '檢視';

  @override
  String get fileCatImage => '圖片檔案';

  @override
  String get catImageFile => '圖片檔案';

  @override
  String get netImage => '圖片';

  @override
  String get imageViewerEmpty => '這個目錄裡沒有可檢視的圖片';

  @override
  String imageLoadFailed(Object error) {
    return '無法載入這張圖片：$error';
  }

  @override
  String get imageViewerRetry => '重試';

  @override
  String get imageViewerGestureHint => '輕點左側上一張，右側下一張，中間開啟設定';

  @override
  String imageViewerCount(Object index, Object total) {
    return '$index / $total';
  }

  @override
  String get imageViewerPrevious => '上一張';

  @override
  String get imageViewerNext => '下一張';

  @override
  String get imageViewerOpenSettings => '圖片設定';

  @override
  String get imageScanningSubdirs => '正在搜尋子目錄…';

  @override
  String get settingsMisc => '雜項';

  @override
  String get settingsThumbnails => '縮圖';

  @override
  String get settingsThumbnailsSubtitle => '封面縮圖邊長，只影響之後新寫入的圖';

  @override
  String get settingsShareSubtitle => '分享時依標籤重新命名';

  @override
  String get downloadNomedia => '排除媒體掃描';

  @override
  String get downloadNomediaSubtitle =>
      '開啟後在下載目錄寫入 .nomedia，系統掃描會略過該資料夾；關閉後刪除該檔案';

  @override
  String get downloadNomediaAlreadyPresent => '下載目錄裡已經有 .nomedia，已按外部操作完成';

  @override
  String get downloadNomediaAlreadyAbsent => '下載目錄裡已經沒有 .nomedia，已按外部操作完成';

  @override
  String get actionShortGallery => '相簿';

  @override
  String get netDownloadToGalleryPictures => '儲存到 Pictures/WebdavMediaManager';

  @override
  String get videoAutoSidecar => '自動載入同目錄外掛字幕';

  @override
  String get videoAutoSidecarHint => '播放時在影片自己的目錄裡比對同名字幕。這一集的手動匯入優先。';

  @override
  String get videoSubtitleSubdir => '同時搜尋指定子目錄';

  @override
  String get videoSubtitleSubdirHint => '開啟後，額外只列出影片所在目錄下這一層子目錄。預設關閉。';

  @override
  String get videoSubtitleSubdirEmpty => '留空等於不搜尋。只填一個資料夾名稱，例如 sub。';

  @override
  String get videoSubtitleSubdirName => '子目錄名稱';

  @override
  String get videoSubtitleSubdirInvalid => '子目錄只能是一層資料夾名稱';

  @override
  String get videoSubtitlePick => '選擇字幕';

  @override
  String get videoSubtitleOff => '關閉字幕';

  @override
  String get videoSubtitleNone => '沒有可用字幕';

  @override
  String get videoSubtitleExternal => '外掛字幕';

  @override
  String get videoSubtitleEncoding => '字幕編碼';

  @override
  String get videoSubtitleEncodingHint => '手動指定編碼只影響這一次播放的外掛和匯入字幕，用來兜底。';

  @override
  String get videoSubtitleEncodingAuto => '自動偵測';

  @override
  String get videoSubtitleImportRemote => '從目前網盤匯入';

  @override
  String get videoSubtitleImportLocal => '從本機檔案匯入';

  @override
  String get videoSubtitleBinarySkipped => '這個字幕不是文字，已略過';

  @override
  String get videoSubtitleUnsupported => '只支援 srt、ass、ssa、vtt、sub';

  @override
  String get videoSubtitleLoadFailed => '字幕載入失敗';
}
