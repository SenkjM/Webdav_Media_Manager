import 'dart:io';

import 'package:dio/dio.dart';

/// 带断点续传的 HTTP 下载（WebDAV 直链与网盘直链共用）。
///
/// 语义要点，别在重构时被「简化」掉：
/// * [resumeFrom] > 0 时发 `Range: bytes=N-`，并以**追加**方式写文件；
/// * 只有响应是 **206 且 `Content-Range` 起点正好等于 N** 才追加——源忽略
///   Range 回了 200、或起点对不上，一律**截断重下**。拼接错位会静默产出损坏
///   文件，比多下一次糟糕得多（尤其视频）；
/// * [onProgress] 报的是**已落盘总量**（含续传那一段），调用方不需要补偿。
Future<void> downloadResumable(
  Dio dio,
  String url,
  Map<String, String> headers,
  File file, {
  int resumeFrom = 0,
  void Function(int received, int total)? onProgress,
  CancelToken? cancelToken,
}) async {
  var start = resumeFrom;
  if (start > 0) {
    final exists = await file.exists();
    if (!exists || await file.length() < start) {
      // 半截文件被系统清理或比记录的短：只能从头来。
      start = 0;
    }
  }
  final response = await dio.get<ResponseBody>(
    url,
    options: Options(
      responseType: ResponseType.stream,
      headers: <String, String>{
        ...headers,
        if (start > 0) 'Range': 'bytes=$start-',
      },
      followRedirects: true,
      // 没网时必须**尽快**报错：默认 connectTimeout 是 null，TCP 会一直挂着，
      // 任务看起来像「暂停」而不是失败（真机反馈的根因之一）。
      connectTimeout: const Duration(seconds: 20),
      // 两次数据之间的间隔上限：断网时 TCP 未必立刻报错，2 分钟太久（看起来像卡死），
      // 45 秒对「正常但慢」的源仍然安全。
      receiveTimeout: const Duration(seconds: 45),
      validateStatus: (code) => code != null && code >= 200 && code < 400,
    ),
    cancelToken: cancelToken,
  );
  final status = response.statusCode ?? 0;
  final contentRange = response.headers.value('content-range');
  var append = false;
  var begin = 0;
  var total = 0;
  if (status == 206) {
    final range = parseContentRange(contentRange);
    if (range != null && start > 0 && range.start == start) {
      append = true;
      begin = start;
      total = range.total;
    }
  }
  if (total <= 0) {
    final length = int.tryParse(response.headers.value('content-length') ?? '');
    total = (length ?? 0) + begin;
  }
  final sink = file.openWrite(mode: append ? FileMode.append : FileMode.write);
  var received = begin;
  try {
    await for (final chunk in response.data!.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total > 0 ? total : received);
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
}

/// `bytes 100-999/1000` 的解析结果。
class ContentRange {
  const ContentRange({required this.start, required this.end, required this.total});

  final int start;
  final int end;
  final int total;
}

/// 解析 `Content-Range`；无法解析（或 `*` 长度）返回 null。
ContentRange? parseContentRange(String? value) {
  if (value == null) return null;
  final spec = value.trim();
  if (!spec.startsWith('bytes ')) return null;
  final slash = spec.indexOf('/');
  if (slash < 0) return null;
  final rangePart = spec.substring(6, slash).trim();
  final totalPart = spec.substring(slash + 1).trim();
  final dash = rangePart.indexOf('-');
  if (dash < 0) return null;
  final start = int.tryParse(rangePart.substring(0, dash).trim());
  final end = int.tryParse(rangePart.substring(dash + 1).trim());
  if (start == null || end == null) return null;
  final total = totalPart == '*' ? -1 : int.tryParse(totalPart);
  if (total == null) return null;
  return ContentRange(start: start, end: end, total: total);
}
