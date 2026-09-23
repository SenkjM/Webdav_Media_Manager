import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/file_type_config.dart';
import 'package:webdav_media_manager/models/webdav_stream.dart';

/// 远端流管线只有一条（视频的），音乐流式只是换了个用途标记。
///
/// 判定按网络库那套后缀配置来，所以这一组测试锁的是**方向的默认值**：
/// 认不出来的东西一律视频，绝不能因为不认识就变成音乐用法——那会让视频
/// 打不开，而这是回归里最难查的一类。
void main() {
  final types = FileTypeConfig();

  StreamKind kindFor(String name) =>
      types.categoryFor(name) == FileCategory.music
          ? StreamKind.music
          : StreamKind.video;

  test('音乐后缀走音乐用途', () {
    for (final n in ['a.mp3', 'a.FLAC', 'a.m4a', 'a.opus']) {
      expect(kindFor(n), StreamKind.music, reason: n);
    }
  });

  test('视频后缀走视频用途', () {
    for (final n in ['a.mp4', 'a.MKV', 'a.ts', 'a.webm']) {
      expect(kindFor(n), StreamKind.video, reason: n);
    }
  });

  test('认不出来的后缀退化为视频，而不是音乐', () {
    for (final n in ['a.rmvb', 'a.pdf', 'a.zip', 'noextension']) {
      expect(kindFor(n), StreamKind.video, reason: n);
    }
  });

  test('用户新加的音乐后缀立刻生效（信任配置）', () {
    final custom = FileTypeConfig(musicExtensions: ['mp3', 'dsf']);
    expect(custom.categoryFor('a.dsf'), FileCategory.music);
  });

  test('audio 后缀同时出现在两个表里时，音乐优先', () {
    final both = FileTypeConfig(
      musicExtensions: ['mp3', 'xyz'],
      videoExtensions: ['mp4', 'xyz'],
    );
    expect(both.categoryFor('a.xyz'), FileCategory.music);
  });
}
