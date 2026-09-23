/// What a stream is being used for.
///
/// Video and music share one remote-stream pipeline (same `media_kit` player,
/// same media session), so this only changes the session's wording and whether
/// the queue is exposed. It exists because "video mode" used to be the only
/// remote-stream mode, and music must not be told "视频" in the notification.
enum StreamKind { video, music }

/// A WebDAV resource prepared for media_kit streaming playback.
///
/// Carries the fully-qualified URL plus the HTTP headers (Basic auth) that
/// libmpv needs, so the caller never touches credentials directly.
class WebDavStreamSource {
  const WebDavStreamSource({
    required this.uri,
    required this.headers,
    required this.name,
    required this.remotePath,
    required this.accountId,
    this.kind = StreamKind.video,
  });

  final String uri;
  final Map<String, String> headers;
  final String name;
  final String remotePath;
  final String accountId;

  /// 这条流是视频还是音乐（实验性流式播放）。只影响媒体会话的文案与队列语义。
  final StreamKind kind;
}
