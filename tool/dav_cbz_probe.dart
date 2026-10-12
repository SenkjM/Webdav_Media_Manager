// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Diagnostic: does this WebDAV server actually serve a CBZ over HTTP Range?
//
// The reader asks for four shapes of `Range` before it shows a page. A server
// that answers 200 instead of 206 for any of them makes the app fall back to
// "cache the whole archive" — this prints which one, instead of leaving you to
// guess from the dialog.
//
//   dart run tool/dav_cbz_probe.dart \
//     --url https://webdav.example.com/dav \
//     --user U --pass P \
//     --path '/Manga/vol01.cbz' \
//     [--all-pages]
//
// `--all-pages` also measures the full page walk, which is what the reader used
// to do up front (and no longer does — pages are fetched on demand now).
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:webdav_media_manager/models/webdav_stream.dart';
import 'package:webdav_media_manager/utils/cbz_range_zip.dart';

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}

Future<void> _probeShape(
  Uri uri,
  String auth,
  String label,
  String? range,
) async {
  final dio = Dio();
  final headers = <String, String>{
    'Authorization': auth,
    'User-Agent': 'WebdavMediaManager/1.0',
  };
  if (range != null) headers['Range'] = range;
  try {
    final res = await dio.getUri<List<int>>(
      uri,
      options: Options(
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
        headers: headers,
      ),
    );
    final data = res.data ?? const <int>[];
    final cr = res.headers.value('content-range');
    final ok = res.statusCode == 206;
    print(
      '${ok ? "ok  " : "FAIL"} ${label.padRight(22)} '
      'status=${res.statusCode} bytes=${data.length} '
      'content-range=${cr ?? "-"}',
    );
  } on DioException catch (e) {
    print('FAIL ${label.padRight(22)} ${e.type} ${e.message}');
  }
}

Future<void> main(List<String> args) async {
  final baseUrl = _arg(args, '--url');
  final remotePath = _arg(args, '--path');
  final user = _arg(args, '--user') ?? '';
  final pass = _arg(args, '--pass') ?? '';
  if (baseUrl == null || remotePath == null) {
    print('need --url and --path (see the header of this file)');
    exit(2);
  }

  final base = Uri.parse(baseUrl);
  final uri = base.replace(
    pathSegments: [
      ...base.pathSegments.where((s) => s.isNotEmpty),
      ...remotePath.split('/').where((s) => s.isNotEmpty),
    ],
  );
  final auth = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
  print('uri = $uri\n');

  print('-- Range shapes the reader needs --');
  await _probeShape(uri, auth, 'no range (baseline)', null);
  await _probeShape(uri, auth, 'bytes=0-0 (probe)', 'bytes=0-0');
  await _probeShape(uri, auth, 'bytes=0- (open)', 'bytes=0-');
  await _probeShape(uri, auth, 'bytes=-65536 (tail)', 'bytes=-65536');
  await _probeShape(uri, auth, 'bytes=100-199 (mid)', 'bytes=100-199');

  print('\n-- CbzRangeZip (what the reader actually runs) --');
  final src = WebDavStreamSource(
    uri: uri.toString(),
    headers: {'User-Agent': 'WebdavMediaManager/1.0', 'Authorization': auth},
    name: remotePath.split('/').last,
    remotePath: remotePath,
    accountId: 'probe',
  );
  final zip = CbzRangeZip(source: src);
  final sw = Stopwatch()..start();
  try {
    await zip.open();
    print(
      'open ok: ${zip.imageEntries.length} pages, '
      'totalSize=${zip.totalSize} (${sw.elapsedMilliseconds} ms)',
    );
  } on CbzRangeUnsupportedException catch (e) {
    print('open FAILED (range unsupported): ${e.detail ?? e}');
    exit(1);
  } catch (e) {
    print('open FAILED: ${e.runtimeType}: $e');
    exit(1);
  }

  final first = zip.imageEntries.first;
  final t0 = sw.elapsedMilliseconds;
  final page = await zip.extractEntry(first);
  print(
    'first page "${first.name}": ${page.length} bytes '
    '(+${sw.elapsedMilliseconds - t0} ms) — this is the time to first pixel',
  );

  final info = zip.findComicInfo();
  if (info == null) {
    print('ComicInfo.xml: absent');
  } else {
    final meta = ComicInfoMeta.parse(await zip.extractEntry(info));
    print('ComicInfo.xml: title=${meta?.title} series=${meta?.series}');
  }

  if (!args.contains('--all-pages')) {
    print('\n(add --all-pages to time the full page walk)');
    exit(0);
  }

  print('\n-- full page walk --');
  var bytes = 0;
  var failed = 0;
  for (final e in zip.imageEntries) {
    try {
      bytes += (await zip.extractEntry(e)).length;
    } catch (_) {
      failed++;
    }
  }
  print(
    '${zip.imageEntries.length} pages, $bytes bytes, $failed failed, '
    '${sw.elapsedMilliseconds} ms total',
  );
  exit(0);
}
