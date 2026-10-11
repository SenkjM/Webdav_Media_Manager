import 'package:media_kit/media_kit.dart';

/// What the music player opens: a local file, or a remote URL with headers.
///
/// Stream vs cache differs only by whether [localPath] is set. Same bottom
/// controls and media session either way.
class PlayableMedia {
  const PlayableMedia._({this.localPath, this.uri, this.headers});

  factory PlayableMedia.file(String path) => PlayableMedia._(localPath: path);

  factory PlayableMedia.stream({
    required String uri,
    required Map<String, String> headers,
  }) => PlayableMedia._(uri: uri, headers: headers);

  final String? localPath;
  final String? uri;
  final Map<String, String>? headers;

  bool get isLocal => localPath != null && localPath!.isNotEmpty;

  Media toMedia({Duration? start, Duration? end}) {
    if (isLocal) {
      return Media(localPath!, start: start, end: end);
    }
    return Media(
      uri!,
      httpHeaders: headers ?? const {},
      start: start,
      end: end,
    );
  }
}
