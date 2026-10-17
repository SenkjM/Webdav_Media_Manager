import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/file_type_config.dart';
import '../models/webdav_item.dart';
import '../utils/directory_walk.dart';
import 'stream_window.dart';
import 'webdav_service.dart';

/// DLNA 投屏专用播放队列控制器。
///
/// 与 [VideoQueueController] 完全同构但独立——不共享实例，不依赖 media_kit，
/// 不依赖 AudioPlayerService。队列以调用方已知的文件列表为种子，可立即
/// 开始投屏，同时后台扫描同目录渐进式补充队列。
///
/// 支持两种入口：
/// 1. **视频播放器入口**：传入 VideoQueueSeed（含兄弟文件列表），
///    在 [DlnaCastService.startCast] 里构建。
/// 2. **网络库单文件入口**：传入单个 [WebDavItem] + accountId，
///    以该文件为种子，后台扫描同目录其余文件。
///
/// 排序按文件名（不区分大小写），与 [VideoQueueController] 完全一致。
class DlnaQueueController extends ChangeNotifier {
  DlnaQueueController({
    required WebDavService webDav,
    required this.accountId,
    required this.rootPath,
    required List<WebDavItem> seed,
    required String initialRemotePath,
    FileTypeConfig? fileTypes,
    this.category = FileCategory.video,
    this.walkOptions = const WalkOptions(),
  }) : _webDav = webDav,
       _fileTypes = fileTypes ?? FileTypeConfig() {
    _merge(seed);
    _currentRemotePath = _resolveCurrent(initialRemotePath);
  }

  final WebDavService _webDav;

  /// 账号 ID，投屏拉流时需要携带。
  final String accountId;

  /// 后台扫描的根目录路径。
  final String rootPath;

  final FileTypeConfig _fileTypes;

  /// 队列收集的文件类别（默认视频）。
  final FileCategory category;

  /// 后台扫描选项（是否包含子目录、最大深度、最大条目数）。
  final WalkOptions walkOptions;

  final List<WebDavItem> _tracks = [];
  final Set<String> _knownPaths = {};
  final Map<String, List<String>> _namesByDir = {};
  String? _currentRemotePath;
  bool _scanning = false;
  bool _scanComplete = false;
  bool _cancelled = false;
  String? _scanError;
  int _discovered = 0;

  // ── 只读状态 getters ─────────────────────────────────────────────────────────

  /// 当前队列的全部条目（不可变副本）。
  List<WebDavItem> get tracks => List.unmodifiable(_tracks);

  /// 后台扫描是否正在进行。
  bool get scanning => _scanning;

  /// 后台扫描是否已全部完成。
  bool get scanComplete => _scanComplete;

  /// 后台扫描期间遇到的第一个错误（null 表示无错误）。
  String? get scanError => _scanError;

  /// 后台扫描累计新增的条目数。
  int get discovered => _discovered;

  /// 当前投屏文件的远端路径。
  String get currentRemotePath => _currentRemotePath ?? '';

  /// 队列总长度。
  int get length => _tracks.length;

  /// 当前条目在队列中的下标，找不到时为 -1。
  int get index => _tracks.indexWhere((t) => t.path == _currentRemotePath);

  /// 当前投屏的 [WebDavItem]，队列为空或未选中时为 null。
  WebDavItem? get current {
    final i = index;
    return i >= 0 ? _tracks[i] : null;
  }

  /// 是否存在上一条。
  bool get hasPrevious => index > 0;

  /// 是否存在下一条。
  bool get hasNext {
    final i = index;
    return i >= 0 && i + 1 < _tracks.length;
  }

  /// 下一条目，不存在时为 null。
  WebDavItem? get next {
    final i = index;
    if (i < 0 || i + 1 >= _tracks.length) return null;
    return _tracks[i + 1];
  }

  /// 上一条目，不存在时为 null。
  WebDavItem? get previous {
    final i = index;
    if (i <= 0) return null;
    return _tracks[i - 1];
  }

  // ── 队列操作 ─────────────────────────────────────────────────────────────────

  /// 切换到指定下标的条目。超出范围时返回 null，不改变当前选中。
  WebDavItem? selectIndex(int i) {
    if (i < 0 || i >= _tracks.length) return null;
    _currentRemotePath = _tracks[i].path;
    notifyListeners();
    return _tracks[i];
  }

  /// 按远端路径切换。找不到时返回 null。
  WebDavItem? selectRemotePath(String remotePath) =>
      selectIndex(_tracks.indexWhere((t) => t.path == remotePath));

  /// 返回某目录下已知的文件名列表（字幕匹配等场景使用）。
  List<String>? namesFor(String remoteFilePath) =>
      _namesByDir[normDir(directoryOf(remoteFilePath))];

  /// 记录一次目录列举结果（供调用方在扫描外缓存）。
  void noteListing(String dir, List<WebDavItem> items) {
    _namesByDir[normDir(dir)] = [
      for (final item in items)
        if (!item.isDirectory) item.name,
    ];
  }

  /// 启动后台目录扫描。重复调用安全（已在扫描或已完成时直接返回）。
  void startScan() {
    if (_scanning || _scanComplete) return;
    _scanning = true;
    notifyListeners();
    unawaited(_scan());
  }

  /// 取消后台扫描（不抛异常，可在 dispose 前安全调用）。
  void cancel() {
    _cancelled = true;
    _scanning = false;
  }

  // ── 内部实现 ─────────────────────────────────────────────────────────────────

  /// 后台渐进扫描：每个目录列举后立即合并，让队列在扫描过程中持续增长。
  Future<void> _scan() async {
    final walker = DirectoryWalker(rootPath: rootPath, options: walkOptions);
    var failed = 0;
    try {
      while (!_cancelled) {
        final dir = walker.nextDirectory();
        if (dir == null) break;
        try {
          final items = await _webDav.listDirectory(
            accountId,
            dir,
            fileTypes: _fileTypes,
          );
          noteListing(dir, items);
          final media = items.where((e) => e.category == category).toList();
          walker.acceptChildren(
            dir,
            items.where((e) => e.isDirectory).map((e) => e.path),
          );
          if (media.isNotEmpty) _merge(media);
        } catch (e) {
          failed++;
          if (failed == 1) _scanError = e.toString();
        }
      }
    } finally {
      if (!_cancelled) {
        _scanning = false;
        _scanComplete = true;
        notifyListeners();
      }
    }
  }

  /// 将 [items] 按文件名排序合并到队列中，已知路径跳过。
  void _merge(List<WebDavItem> items) {
    var added = 0;
    for (final item in items) {
      if (!_knownPaths.add(item.path)) continue;
      _tracks.add(item);
      added++;
    }
    if (added == 0) return;
    _tracks.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    _discovered += added;
    notifyListeners();
  }

  /// 确保初始文件在队列中可选（即使种子列表里没有它）。
  String _resolveCurrent(String remotePath) {
    if (_knownPaths.contains(remotePath)) return remotePath;
    final name = remotePath.split('/').last;
    final item = WebDavItem(
      name: name,
      path: remotePath,
      isDirectory: false,
      category: FileCategory.video,
    );
    _tracks.add(item);
    _knownPaths.add(remotePath);
    _tracks.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return remotePath;
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}
