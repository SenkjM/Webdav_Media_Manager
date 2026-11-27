import 'dart:async';
import 'dart:io';

import '../models/webdav_stream.dart';

/// How long the caller may wait for the metadata warm-up before playback
/// proceeds anyway.
///
/// MustProxy drivers resolve the signed link and the encrypted container
/// header on their first ranged read; both are cached per account/path
/// afterwards. Doing that while libmpv boots removes that cold chain from the
/// first frame, but a slow network must never delay playback indefinitely.
const Duration streamPrewarmBudget = Duration(milliseconds: 900);

/// Bytes read from the start of the stream while warming.
const int prewarmHeadBytes = 512 * 1024;

/// Bytes read from the end of the stream while warming (MP4 moov lives there).
const int prewarmTailBytes = 256 * 1024;

/// Best-effort warm-up for a proxied stream.
///
/// Only the local Rust proxy is warmed: a direct upstream URL costs exactly the
/// same single request libmpv is about to make, so prewarming it would only add
/// traffic. Failures and timeouts are swallowed on purpose — a warm-up must
/// never fail a playback attempt.
///
/// The head read is awaited (bounded by [budget]) because the signed link and
/// the container header are exactly what the first real request would pay for;
/// the tail read runs in the background and only helps demuxers that seek to
/// the end before they start reading.
Future<void> prewarmStream(
  WebDavStreamSource source, {
  Duration budget = streamPrewarmBudget,
}) async {
  if (!source.viaProxy || source.uri.isEmpty) return;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  Future<void>? tail;
  try {
    await _warmRange(client, source.uri, 0, prewarmHeadBytes - 1).timeout(budget);
    if (source.size > prewarmHeadBytes * 2) {
      tail = _warmRange(
        client,
        source.uri,
        source.size - prewarmTailBytes,
        source.size - 1,
      ).timeout(budget).catchError((Object _) {});
      unawaited(tail);
    }
  } catch (_) {
    // Best effort only: slow or failed warm-ups are not playback errors.
  } finally {
    if (tail != null) {
      unawaited(tail.whenComplete(() => client.close(force: true)));
    } else {
      client.close(force: true);
    }
  }
}

Future<void> _warmRange(
  HttpClient client,
  String uri,
  int start,
  int end,
) async {
  final request = await client.getUrl(Uri.parse(uri));
  request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
  final response = await request.close();
  await response.drain<void>();
}
