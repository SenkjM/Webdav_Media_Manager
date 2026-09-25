/// 网易云音乐云盘驱动（OpenList `netease_music` 移植）。
///
/// 移植自 `localdev/OpenList-Worker/src/backend/drivers/netease_music`
/// （driver.ts + util.ts + crypto.ts，移植底稿）与
/// `localdev/OpenList/drivers/netease_music`（Go 版，语义兜底）。
///
/// **能力面（照 99 §7.3.2 核查表）**：`list | read | delete`。
/// 上游 `MakeDir` / `Rename` / `Move` / `Copy` 都是 `errs.NotSupport` 桩，
/// 因此**不给** mkdir / move / copy 位（禁用即隐藏，99 §7.2.6）；
/// 上传按 99 §7.2.1 全局砍掉（上游的 `putSongStream` 不移植）。
///
/// 与 worker 底稿的三处有意差异：
/// 1. **`weapi` 第二层明文用内层 base64 字符串**（Go 版与
///    NeteaseCloudMusicApi 参考实现一致）；worker 送的是内层原始字节，
///    属该版疏漏，见 `netease_music_crypto.dart` 文件头。
/// 2. **拿不到直链时抛真实原因**：worker 把空 url 写进 `raw_url` 并记
///    `raw_url_error`，客户端里下游必然失败。本实现按 [CloudDriver.get]
///    的契约抛 [CloudDriverException]（与百度驱动同一取舍）。
/// 3. **校验响应 `code`**：worker / Go 都不看响应码，Cookie 失效时表现为
///    「空列表」；本实现在 `code` 存在且非 200 时报错，让保存校验与浏览
///    能给出可读原因。
///
/// **不移植**：Go 版的 `.lrc` 歌词条目（worker 底稿已删，本应用的播放链路
/// 不消费远端歌词；`Link` 的 `parsed` / `RangeReader` 语义依赖 OpenList
/// 自身的 `/p` 代理端点，在对端客户端里无对应物）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/account_capabilities.dart';
import '../cloud_driver.dart';
import 'netease_music_crypto.dart';

/// 驱动配置（对齐上游 Addition；默认值照抄 Go `meta.go`）。
class NeteaseMusicAddition {
  NeteaseMusicAddition({
    required this.cookie,
    this.songLimit = kDefaultSongLimit,
  });

  factory NeteaseMusicAddition.fromJson(Map<String, dynamic> json) =>
      NeteaseMusicAddition(
        cookie: json['cookie'] as String? ?? '',
        songLimit: _parseLimit(json['song_limit']),
      );

  Map<String, dynamic> toJson() => {
        'cookie': cookie,
        'song_limit': songLimit,
      };

  /// 网易云音乐网页版 Cookie（必填）。必须含 `__csrf` 与 `MUSIC_U`。
  String cookie;

  /// 列取的歌曲数上限；上游 Go 默认 200（`song_limit` 的 `default:"200"`）。
  int songLimit;

  /// 解析上限：表单里是文本，需容错（非数字 / 小于 1 一律回默认）。
  static int _parseLimit(Object? raw) {
    final n = raw is int ? raw : int.tryParse('${raw ?? ''}'.trim());
    if (n == null || n < 1) return kDefaultSongLimit;
    return n;
  }
}

/// 列取上限的默认值（照抄上游）。
const int kDefaultSongLimit = 200;

/// 网易云盘歌曲条目（上游 `ListResp.data` 的元素）。
class NeteaseSong {
  NeteaseSong({
    required this.songId,
    required this.fileName,
    required this.fileSize,
    required this.addTime,
    this.picUrl = '',
  });

  static NeteaseSong? fromMap(Map<String, dynamic> m) {
    final name = m['fileName'] as String?;
    final id = (m['songId'] as num?)?.toInt();
    if (name == null || name.isEmpty || id == null) return null;
    final simple = m['simpleSong'];
    String pic = '';
    if (simple is Map) {
      final al = simple['al'];
      if (al is Map) pic = al['picUrl'] as String? ?? '';
    }
    return NeteaseSong(
      songId: id,
      fileName: name,
      fileSize: (m['fileSize'] as num?)?.toInt() ?? 0,
      // addTime 是**毫秒**（Go: time.UnixMilli；worker: new Date(ms)）。
      addTime: (m['addTime'] as num?)?.toInt() ?? 0,
      picUrl: pic,
    );
  }

  final int songId;
  final String fileName;
  final int fileSize;
  final int addTime;
  final String picUrl;

  DateTime? get modified => addTime > 0
      ? DateTime.fromMillisecondsSinceEpoch(addTime)
      : null;
}

/// 网易云音乐 API 客户端（上游 `ClientNeteaseMusic` / Go 的 request 封装）。
class NeteaseMusicClient {
  NeteaseMusicClient(this.addition, {Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 60),
                headers: {'User-Agent': apiUA},
                // 非 2xx 也回来读 body：「原样传递报错」需要读到网易的 code。
                validateStatus: (_) => true,
              ),
            );

  /// 普通 API 的 UA（对齐 Go 版 base 客户端的 UserAgentNT）。
  static const String apiUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/142.0.0.0 OpenList/425.6.30';

  /// linuxapi 必需的 UA（上游写死；用 `linux/forward` 端点时必须）。
  static const String linuxApiUA =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.90 Safari/537.36';

  /// linuxapi 的转发端点（上游固定）。
  static const String linuxApiForward = 'https://music.163.com/api/linux/forward';

  static const String referer = 'https://music.163.com';

  /// 云盘列表端点。
  static const String cloudGetUrl = 'https://music.163.com/weapi/v1/cloud/get';

  /// 播放直链端点（走 linuxapi 加密）。
  static const String songUrlApi = 'https://music.163.com/api/song/enhance/player/url';

  /// 删除云盘歌曲端点（**上游两版都是 http**，逐字节保留）。
  static const String cloudDelUrl = 'http://music.163.com/weapi/cloud/del';

  final NeteaseMusicAddition addition;
  final Dio _dio;

  String _csrfToken = '';
  String _musicU = '';

  /// 登录态是否已建立。
  bool get initialized => _csrfToken.isNotEmpty && _musicU.isNotEmpty;

  String get csrfToken => _csrfToken;
  String get musicU => _musicU;

  /// 校验 Cookie 含 `__csrf` 与 `MUSIC_U`（上游 Init 语义）。
  void init() {
    _csrfToken = getCookie('__csrf');
    _musicU = getCookie('MUSIC_U');
    if (_csrfToken.isEmpty || _musicU.isEmpty) {
      throw const CloudDriverException(
        'Cookie 必须同时包含 __csrf 与 MUSIC_U：'
        '请在网页版 music.163.com 登录后，从开发者工具复制完整 Cookie',
      );
    }
  }

  /// 从 Cookie 串里取某项（正则与上游逐字节一致：`name=([^(;|$)]+)`）。
  String getCookie(String name) {
    final re = RegExp('$name=([^(;|\$)]+)');
    final m = re.firstMatch(addition.cookie);
    return m == null ? '' : m.group(1)!;
  }

  /// 统一请求：按 [crypto] 生成表单体、拼 Cookie 与 Referer。
  ///
  /// 对齐上游 `request()`：
  /// - 目标含 `music.163.com` 时带 `Referer`；
  /// - 额外 Cookie（`os=pc` 等）**追加**在配置 Cookie 之后；
  /// - weapi 把 URL 里的 `/<xxx>api/` 段替换为 `/weapi/`；
  /// - linuxapi 把原始 URL 塞进加密载荷，实际打到 `/api/linux/forward`。
  Future<Map<String, dynamic>> request(
    String url, {
    required String crypto,
    Map<String, String>? data,
    Map<String, String>? cookies,
  }) async {
    var target = url;
    final headers = <String, String>{
      'Cookie': _cookieHeader(cookies),
    };
    if (target.contains('music.163.com')) {
      headers['Referer'] = referer;
    }

    final Map<String, String> form;
    if (crypto == 'weapi') {
      form = neteaseWeapi(data ?? const {}).toForm();
      target = _rewriteApiSegment(target, 'weapi');
    } else if (crypto == 'linuxapi') {
      form = neteaseLinuxapi({
        'url': _rewriteApiSegment(target, 'api'),
        'method': 'POST',
        'params': data ?? const <String, String>{},
      });
      headers['User-Agent'] = linuxApiUA;
      target = linuxApiForward;
    } else {
      throw CloudDriverException('未知的加密方式：$crypto');
    }

    final Response<String> res;
    try {
      res = await _dio.post<String>(
        target,
        data: form,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          headers: headers,
        ),
      );
    } on DioException catch (e) {
      throw CloudDriverException('网易云音乐请求失败：${_short(e.message ?? '$e')}');
    }

    final text = res.data ?? '';
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw CloudDriverException(
        '网易云音乐返回了非 JSON 响应（HTTP ${res.statusCode}）：${_short(text)}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw CloudDriverException('网易云音乐返回了非预期结构：${_short(text)}');
    }
    _throwOnApiError(decoded, res.statusCode);
    return decoded;
  }

  /// 响应 `code` 存在且非 200 即报错（本实现相对上游的增量，见文件头）。
  void _throwOnApiError(Map<String, dynamic> body, int? status) {
    final code = (body['code'] as num?)?.toInt();
    if (code == null || code == 200) return;
    final message = (body['message'] as String?)?.trim();
    final detail = (message == null || message.isEmpty)
        ? ''
        : '：$message';
    if (code == 301 || code == 250) {
      throw CloudDriverException(
        '网易云音乐登录态已失效（code $code$detail）。'
        'Cookie 可能已过期，请重新登录网页版并更新 Cookie',
      );
    }
    throw CloudDriverException('网易云音乐接口报错（code $code$detail）');
  }

  /// 把 URL 里的 `/<xxx>api/` 段替换为目标段（上游正则 `/\w*api/`）。
  static String _rewriteApiSegment(String url, String segment) {
    return url.replaceFirstMapped(
      RegExp(r'/\w*api/'),
      (_) => '/$segment/',
    );
  }

  String _cookieHeader(Map<String, String>? extra) {
    final buf = StringBuffer(addition.cookie.trim());
    if (extra != null && extra.isNotEmpty) {
      for (final e in extra.entries) {
        buf.write('; ${e.key}=${e.value}');
      }
    }
    return buf.toString();
  }

  /// 云盘歌曲列表（上游 `getSongObjs`）。
  Future<List<NeteaseSong>> getSongObjs(int limit) async {
    final body = await request(
      cloudGetUrl,
      crypto: 'weapi',
      data: {'limit': '$limit', 'offset': '0'},
      cookies: const {'os': 'pc'},
    );
    final list = body['data'];
    if (list is! List) return const [];
    // 条目缺 fileName / songId 时跳过该条（不整体失败）。
    return [
      for (final e in list)
        if (e is Map<String, dynamic>) ?NeteaseSong.fromMap(e),
    ];
  }

  /// 播放直链（上游 `getSongLink`，走 linuxapi）。
  ///
  /// 返回空串表示上游没给可用链接（VIP / 版权 / 已下架），由驱动层转成
  /// 可读错误。
  Future<String> getSongLink(String id) async {
    final body = await request(
      songUrlApi,
      crypto: 'linuxapi',
      data: {'ids': '[$id]', 'br': '999000'},
      cookies: const {'os': 'pc'},
    );
    final data = body['data'];
    if (data is! List || data.isEmpty) {
      throw const CloudDriverException(
        '网易云音乐未返回播放链接（可能是 VIP / 版权受限 / 已下架的歌曲）',
      );
    }
    final first = data.first;
    final url = first is Map ? first['url'] as String? : null;
    if (url == null || url.isEmpty) {
      throw const CloudDriverException(
        '网易云音乐未返回播放链接（可能是 VIP / 版权受限 / 已下架的歌曲）',
      );
    }
    return url;
  }

  /// 删除云盘歌曲（上游 `removeSong`）。
  Future<void> removeSong(String id) async {
    await request(
      cloudDelUrl,
      crypto: 'weapi',
      data: {'songIds': '[$id]'},
    );
  }

  /// 真连校验：拉一次列表（上限 1）确认 Cookie 真的可用。
  Future<void> verifyLogin() async {
    init();
    await getSongObjs(1);
  }

  static String _short(String s) => s.length > 300 ? '${s.substring(0, 300)}…' : s;
}

/// 网易云音乐云盘驱动。
///
/// 上游是**单层平铺**的云盘（只有歌曲文件，没有目录树），因此：
/// - [list] 忽略路径，永远返回全部歌曲（同 worker 的 `list()`）；
/// - [get] / [remove] 按**文件名**在列表里定位（同 worker）。
/// 账号的「远程路径」对它是**纯虚拟前缀**：条目路径由上层拼接，驱动只认
/// 文件名，所以改远程路径不会让条目失联。
class NeteaseMusicDriver extends CloudDriver {
  NeteaseMusicDriver({
    required NeteaseMusicAddition addition,
    Dio? dio,
  }) : _client = NeteaseMusicClient(addition, dio: dio);

  final NeteaseMusicClient _client;

  NeteaseMusicAddition get addition => _client.addition;

  /// 测试用：直接拿客户端。
  NeteaseMusicClient get client => _client;

  @override
  Future<void> init() async {
    _client.init();
  }

  @override
  Future<List<CloudFileItem>> list(String path) async {
    final songs = await _client.getSongObjs(addition.songLimit);
    return [for (final s in songs) _toItem(s)];
  }

  @override
  Future<CloudFileItem> get(String path) async {
    final name = cloudBasename(path);
    if (name.isEmpty || path == '/' || path.isEmpty) {
      // 浏览根：云盘本身没有目录条目，返回一个目录占位（同 worker 的
      // 「name: root, is_dir: true」分支）。
      return const CloudFileItem(name: '/', isDir: true);
    }
    final song = await _findByName(name);
    if (song == null) {
      throw CloudDriverException('文件不存在：$name');
    }
    final item = _toItem(song);
    final url = await _client.getSongLink('${song.songId}');
    return CloudFileItem(
      name: item.name,
      isDir: false,
      size: item.size,
      modified: item.modified,
      rawUrl: url,
      // 直链由网易 CDN 直接提供，上游未声明必需请求头（Go / worker 同）。
      rawHeaders: const {'User-Agent': NeteaseMusicClient.apiUA},
    );
  }

  /// 删除：按文件名定位后按歌曲 id 删除（上游 `removeSongObj`）。
  @override
  Future<void> remove(String path) async {
    final name = cloudBasename(path);
    if (name.isEmpty) {
      throw const CloudDriverException('网易云音乐不支持删除根目录');
    }
    final song = await _findByName(name);
    if (song == null) {
      throw CloudDriverException('文件不存在：$name');
    }
    await _client.removeSong('${song.songId}');
  }

  /// 上游 `MakeDir` 是 `errs.NotSupport` 桩（99 §7.3.2 核查表）。
  ///
  /// 注意：返回**失败的 Future** 而不是同步 throw——`async` 之外的同步
  /// 抛出会绕过 `await` / `expectLater` 的错误通道，调用方拿不到可读原因。
  @override
  Future<void> mkdir(String path) async => throw _unsupported('新建文件夹');

  /// 上游 `Rename` 是 `errs.NotSupport` 桩。
  @override
  Future<void> rename(String path, String newPath) async =>
      throw _unsupported('重命名');

  /// 上游 `Move` 是 `errs.NotSupport` 桩。
  @override
  Future<void> move(String srcPath, String dstDir, String newName) async =>
      throw _unsupported('移动');

  /// 上游 `Copy` 是 `errs.NotSupport` 桩。
  @override
  Future<void> copy(String srcPath, String dstDir, String newName) async =>
      throw _unsupported('复制');

  CloudDriverException _unsupported(String what) =>
      CloudDriverException('网易云音乐云盘不支持$what（上游驱动未实现该操作）');

  Future<NeteaseSong?> _findByName(String name) async {
    final songs = await _client.getSongObjs(addition.songLimit);
    for (final s in songs) {
      if (s.fileName == name) return s;
    }
    return null;
  }

  CloudFileItem _toItem(NeteaseSong s) => CloudFileItem(
        name: s.fileName,
        isDir: false,
        size: s.fileSize,
        modified: s.modified,
      );
}

/// 驱动自描述（99 §7.2.10）：类型、显示名、能力遮罩、表单参数、构造
/// 全部收在本文件；`driver_registry.dart` 加一行即接入账号表单。
class NeteaseMusicSpec extends CloudDriverSpec {
  const NeteaseMusicSpec();

  @override
  String get typeId => 'netease_music';

  @override
  String get displayName => '网易云音乐';

  /// 列出 / 读取 / 删除。**没有** mkdir / move / copy：
  /// 上游四个写方法中除 Remove 外全是 `errs.NotSupport` 桩（99 §7.3.2）。
  @override
  int get capabilities =>
      AccountCaps.list | AccountCaps.read | AccountCaps.delete;

  @override
  List<CloudDriverFormItem> get form => const [
        CloudDriverField(
          key: 'cookie',
          label: 'Cookie',
          hint: '必填；需含 __csrf 与 MUSIC_U。'
              '登录 music.163.com 后从开发者工具复制完整 Cookie'
              '（获取方法见 OpenList 官方文档 netease_music 驱动页）',
          required: true,
          obscure: true,
        ),
        CloudDriverField(
          key: 'song_limit',
          label: '歌曲数量上限',
          hint: '默认 $kDefaultSongLimit；网易云盘接口按此上限一次列取',
          defaultValue: '$kDefaultSongLimit',
        ),
      ];

  @override
  CloudDriver create(
    Map<String, dynamic> config, {
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
    CloudDriverEnv? env,
  }) {
    // Cookie 是唯一凭证，网易不轮换它，因此没有 onTokenUpdate 通道。
    return NeteaseMusicDriver(addition: NeteaseMusicAddition.fromJson(config));
  }

  /// 保存前**真连**一次：Cookie 必须在服务端可用，而不只是格式对
  /// （对齐百度「能获取到 access_token 才保存」的语义，99 §4.3.1）。
  @override
  Future<void> verify(
    Map<String, dynamic> config, {
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
    CloudDriverEnv? env,
  }) async {
    final driver = create(config,
        onTokenUpdate: onTokenUpdate, env: env) as NeteaseMusicDriver;
    await driver.client.verifyLogin();
  }
}
