import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/playable_media.dart';

void main() {
  test('PlayableMedia.file marks local', () {
    final p = PlayableMedia.file('/tmp/a.mp3');
    expect(p.isLocal, isTrue);
    expect(p.localPath, '/tmp/a.mp3');
    final m = p.toMedia();
    expect(m.uri, contains('a.mp3'));
  });

  test('PlayableMedia.stream carries headers', () {
    final p = PlayableMedia.stream(
      uri: 'https://example/a.mp3',
      headers: {'Authorization': 'Basic x'},
    );
    expect(p.isLocal, isFalse);
    final m = p.toMedia();
    expect(m.uri, 'https://example/a.mp3');
    expect(m.httpHeaders?['Authorization'], 'Basic x');
  });
}
