/// A WebDAV resource prepared for media_kit streaming playback.
///
/// Carries the fully-qualified URL plus the HTTP headers (Basic auth) that
/// libmpv needs, so the video player never touches credentials directly.
class WebDavStreamSource {
  const WebDavStreamSource({
    required this.uri,
    required this.headers,
    required this.name,
    required this.remotePath,
    required this.accountId,
  });

  final String uri;
  final Map<String, String> headers;
  final String name;
  final String remotePath;
  final String accountId;
}
