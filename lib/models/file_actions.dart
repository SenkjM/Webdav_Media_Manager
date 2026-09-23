import 'file_type_config.dart';
import 'download_task.dart';

/// 网络库对文件能做的事。
///
/// 这是「文件动作模型」的动作半边：**类型决定候选动作，设置决定默认动作，
/// 每个入口（单击 / 多选工具栏 / 更多菜单）都问同一个函数**。三个入口各写
/// 一份 if-else 是这次要消掉的东西——它们已经开始互相打架了（更多菜单里
/// 音乐写「播放（仅本地缓存）」，多选里视频被跳过，普通文件多选直接被丢）。
enum FileAction {
  /// 音乐：下载到应用音频缓存，随后 ingest 进音乐库。
  cacheMusic,

  /// 任何文件：下载到系统下载目录（不缓存、不进音乐库、不流式）。
  download,

  /// 视频：远端流式播放，不落盘。
  stream,

  /// CUE：读取并解析，整组下载。
  readCue,

  /// 音乐：远端流式播放（实验性，见 docs/99 的可行性分析）。
  streamMusic,
}

extension FileActionX on FileAction {
  String get storageKey => switch (this) {
    FileAction.cacheMusic => 'cache_music',
    FileAction.download => 'download',
    FileAction.stream => 'stream',
    FileAction.readCue => 'read_cue',
    FileAction.streamMusic => 'stream_music',
  };

  String get labelZh => switch (this) {
    FileAction.cacheMusic => '缓存音乐',
    FileAction.download => '下载',
    FileAction.stream => '流式传输',
    FileAction.readCue => 'cue 读取',
    FileAction.streamMusic => '流式传输（音乐）',
  };

  /// 短标签，给多选工具栏这类空间紧张的地方用。
  String get shortLabelZh => switch (this) {
    FileAction.cacheMusic => '缓存',
    FileAction.download => '下载',
    FileAction.stream => '播放',
    FileAction.readCue => 'CUE',
    FileAction.streamMusic => '流播',
  };

  /// 该动作落盘到哪里。流式播放不落盘，返回 null。
  DownloadTarget? get downloadTarget => switch (this) {
    FileAction.cacheMusic => DownloadTarget.cache,
    FileAction.download => DownloadTarget.downloads,
    FileAction.readCue => DownloadTarget.cache,
    FileAction.stream || FileAction.streamMusic => null,
  };

  static FileAction fromStorageKey(String? key, FileAction fallback) =>
      FileAction.values.firstWhere(
        (a) => a.storageKey == key,
        orElse: () => fallback,
      );
}

/// 每类文件各自允许的动作，顺序即设置页下拉框的顺序，第一项是默认。
class FileActionCatalog {
  const FileActionCatalog._();

  static const List<FileAction> music = [
    FileAction.cacheMusic,
    FileAction.streamMusic,
    FileAction.download,
  ];

  static const List<FileAction> video = [
    FileAction.stream,
    FileAction.download,
  ];

  static const List<FileAction> cue = [FileAction.readCue, FileAction.download];

  static const List<FileAction> other = [FileAction.download];

  /// [FileCategory] → 允许的动作列表。
  static List<FileAction> forCategory(FileCategory category) =>
      switch (category) {
        FileCategory.music => music,
        FileCategory.video => video,
        FileCategory.cue => cue,
        FileCategory.other => other,
      };

  /// 类别在那个「永远允许」的动作之外，还允许哪些动作。
  ///
  /// 「任何文件都可以采用下载」是硬性要求，所以 [FileAction.download] 不在
  /// 各个列表里重复出现，而是由这里统一追加。音乐列表里那份是刻意的：它要
  /// 在设置下拉框里排第三位，不代表默认。
  static bool isAllowed(FileCategory category, FileAction action) {
    if (action == FileAction.download) return true;
    return forCategory(category).contains(action);
  }

  /// 该类别的出厂默认动作。
  static FileAction defaultFor(FileCategory category) => switch (category) {
    FileCategory.music => FileAction.cacheMusic,
    FileCategory.cue => FileAction.readCue,
    FileCategory.video => FileAction.stream,
    FileCategory.other => FileAction.download,
  };
}

/// 解析后的「单击行为」设置：一个类别一个动作，且一定合法。
///
/// 解析过程就是**拦截不合法行为**的地方：把音乐设成 `stream`（视频那个
/// 流式）或者把普通文件设成 `cacheMusic` 都会被退回到该类别默认值，而不是
/// 等到用户点下去才在界面里失败。
class FileActionConfig {
  FileActionConfig({
    Map<FileCategory, FileAction>? actions,
    this.allowMusicStreaming = false,
  }) : actions = {
         for (final c in FileCategory.values)
           c: _sanitize(
             c,
             actions?[c] ?? FileActionCatalog.defaultFor(c),
             allowMusicStreaming: allowMusicStreaming,
           ),
       };

  final Map<FileCategory, FileAction> actions;

  /// 音乐能否选中「流式传输（音乐）」。**不是**持久化字段：值从
  /// 音频流式设置页的开关来，由 [FileActionConfig] 的构造方传进来。
  final bool allowMusicStreaming;

  FileAction get music => actions[FileCategory.music]!;
  FileAction get video => actions[FileCategory.video]!;
  FileAction get cue => actions[FileCategory.cue]!;
  FileAction get other => actions[FileCategory.other]!;

  FileAction forCategory(FileCategory category) => actions[category]!;

  /// 一个文件名在这份设置下的默认动作：先用 [FileTypeConfig] 判类别，再取该类别的动作。
  FileAction forFileName(String name, FileTypeConfig types) =>
      forCategory(types.categoryFor(name));

  /// 该类别在设置里可以选的动作。
  ///
  /// 关掉音乐流式开关时，这里也要**不出现**「流式传输（音乐）」：
  /// 构造期虽然已经把它退回默认值，但下拉框若还列着这一项，用户选完
  /// 会被静静退回，看不出为什么没生效。
  List<FileAction> choicesFor(FileCategory category) {
    final base = FileActionCatalog.forCategory(category);
    if (category != FileCategory.music || allowMusicStreaming) return base;
    return base.where((a) => a != FileAction.streamMusic).toList();
  }

  FileActionConfig copyWith({Map<FileCategory, FileAction>? actions}) =>
      FileActionConfig(
        actions: actions ?? this.actions,
        allowMusicStreaming: allowMusicStreaming,
      );

  FileActionConfig withAction(FileCategory category, FileAction action) =>
      copyWith(actions: {...actions, category: action});

  Map<String, dynamic> toJson() => {
    'music': music.storageKey,
    'video': video.storageKey,
    'cue': cue.storageKey,
    'other': other.storageKey,
  };

  /// [allowMusicStreaming] 由调用方从设置里取（`SettingsService.audioStreamingEnabled`）。
  static FileActionConfig? fromJson(
    Map<String, dynamic>? json, {
    bool allowMusicStreaming = false,
  }) {
    if (json == null) return null;
    return FileActionConfig(
      allowMusicStreaming: allowMusicStreaming,
      actions: {
        FileCategory.music: FileActionX.fromStorageKey(
          json['music'] as String?,
          FileActionCatalog.defaultFor(FileCategory.music),
        ),
        FileCategory.video: FileActionX.fromStorageKey(
          json['video'] as String?,
          FileActionCatalog.defaultFor(FileCategory.video),
        ),
        FileCategory.cue: FileActionX.fromStorageKey(
          json['cue'] as String?,
          FileActionCatalog.defaultFor(FileCategory.cue),
        ),
        FileCategory.other: FileActionX.fromStorageKey(
          json['other'] as String?,
          FileActionCatalog.defaultFor(FileCategory.other),
        ),
      },
    );
  }

  static FileAction _sanitize(
    FileCategory category,
    FileAction action, {
    required bool allowMusicStreaming,
  }) {
    if (action == FileAction.streamMusic && !allowMusicStreaming) {
      return FileActionCatalog.defaultFor(category);
    }
    if (!FileActionCatalog.isAllowed(category, action)) {
      return FileActionCatalog.defaultFor(category);
    }
    return action;
  }
}

/// 动作在具体条目上的判定结果：能不能做、为什么不能。
///
/// 三个入口都拿这个结构决定按钮是否可用 / 点下去要说什么，而不是各自
/// 复制一遍 `item.isAudio && !item.isDirectory`。
class FileActionDecision {
  const FileActionDecision({
    required this.action,
    required this.allowed,
    this.reason,
  });

  final FileAction action;
  final bool allowed;

  /// 不允许时给用户看的原因（中文）。
  final String? reason;

  static FileActionDecision allow(FileAction action) =>
      FileActionDecision(action: action, allowed: true);

  static FileActionDecision deny(FileAction action, String reason) =>
      FileActionDecision(action: action, allowed: false, reason: reason);
}

/// 判断某个动作能不能作用在这个条目上。
///
/// 这里的判据是**条目自身的性质**，不是设置：设置只决定「默认动作是哪个」，
/// 一个动作是否可用与该类别的允许列表一致。所以音乐行永远不该出现「流式
/// 传输」（那是视频的），普通文件永远不该出现「缓存音乐」。
FileActionDecision judgeAction({
  required FileAction action,
  required FileCategory category,
  required bool isDirectory,
}) {
  if (isDirectory) {
    return FileActionDecision.deny(action, '这是文件夹，不能按文件动作处理');
  }
  if (!FileActionCatalog.isAllowed(category, action)) {
    return FileActionDecision.deny(
      action,
      '「${action.labelZh}」不适用于${categoryLabelZh(category)}',
    );
  }
  return FileActionDecision.allow(action);
}

String categoryLabelZh(FileCategory category) => switch (category) {
  FileCategory.music => '音乐文件',
  FileCategory.video => '视频文件',
  FileCategory.cue => 'CUE 文件',
  FileCategory.other => '普通文件',
};

/// 多选工具栏要显示的那一个「按类型分发」的下载动作。
///
/// 混合选择时按「能不能缓存」收敛：全是音乐才叫「缓存音乐」，否则叫「下载」
/// ——因为视频与普通文件都只能走下载目录。
FileAction bulkDownloadAction(Iterable<FileCategory> categories) {
  final list = categories.toList();
  if (list.isNotEmpty && list.every((c) => c == FileCategory.music)) {
    return FileAction.cacheMusic;
  }
  return FileAction.download;
}
