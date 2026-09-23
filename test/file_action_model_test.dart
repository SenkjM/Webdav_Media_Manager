import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_media_manager/models/download_task.dart';
import 'package:webdav_media_manager/models/file_actions.dart';
import 'package:webdav_media_manager/models/file_type_config.dart';
import 'package:webdav_media_manager/services/settings_service.dart';
import 'package:webdav_media_manager/utils/audio_extensions.dart';

/// T1 回归：类型 → 动作的判定只有一份实现。
///
/// 改动之前三处各写一套 if-else（单击、多选、更多菜单），音乐与视频的
/// 语义已经开始分叉。这些测试锁住「哪个动作对哪种类型合法」和「默认动作
/// 是什么」，界面只是它的投影。
void main() {
  final types = FileTypeConfig();

  group('按后缀判类型', () {
    test('音乐 / 视频 / cue / 普通', () {
      expect(types.categoryFor('song.flac'), FileCategory.music);
      expect(types.categoryFor('movie.mkv'), FileCategory.video);
      expect(types.categoryFor('album.cue'), FileCategory.cue);
      expect(types.categoryFor('readme.pdf'), FileCategory.other);
    });

    test('默认动作：音乐缓存、cue 读取、视频流式、普通下载', () {
      expect(FileActionCatalog.defaultFor(FileCategory.music),
          FileAction.cacheMusic);
      expect(FileActionCatalog.defaultFor(FileCategory.cue),
          FileAction.readCue);
      expect(FileActionCatalog.defaultFor(FileCategory.video),
          FileAction.stream);
      expect(FileActionCatalog.defaultFor(FileCategory.other),
          FileAction.download);
    });
  });

  group('拦截不合法行为', () {
    test('任何文件都允许下载', () {
      for (final c in FileCategory.values) {
        expect(FileActionCatalog.isAllowed(c, FileAction.download), isTrue,
            reason: '$c 也应该能下载');
      }
    });

    test('缓存音乐只对音乐合法', () {
      expect(FileActionCatalog.isAllowed(FileCategory.music, FileAction.cacheMusic),
          isTrue);
      expect(FileActionCatalog.isAllowed(FileCategory.video, FileAction.cacheMusic),
          isFalse);
      expect(FileActionCatalog.isAllowed(FileCategory.other, FileAction.cacheMusic),
          isFalse);
    });

    test('视频那个流式传输不适用于音乐（音乐要用实验性的 streamMusic）', () {
      expect(judgeAction(
        action: FileAction.stream,
        category: FileCategory.music,
        isDirectory: false,
      ).allowed, isFalse);
      expect(judgeAction(
        action: FileAction.streamMusic,
        category: FileCategory.music,
        isDirectory: false,
      ).allowed, isTrue);
    });

    test('文件夹不能按文件动作处理', () {
      final d = judgeAction(
        action: FileAction.download,
        category: FileCategory.other,
        isDirectory: true,
      );
      expect(d.allowed, isFalse);
      expect(d.reason, isNotNull);
    });

    test('拒绝时给出中文原因', () {
      final d = judgeAction(
        action: FileAction.cacheMusic,
        category: FileCategory.video,
        isDirectory: false,
      );
      expect(d.allowed, isFalse);
      expect(d.reason, contains('缓存音乐'));
      expect(d.reason, contains('视频'));
    });
  });

  group('落盘目标', () {
    test('缓存音乐落在缓存，下载落在下载目录，流式不落盘', () {
      expect(FileAction.cacheMusic.downloadTarget, DownloadTarget.cache);
      expect(FileAction.download.downloadTarget, DownloadTarget.downloads);
      expect(FileAction.readCue.downloadTarget, DownloadTarget.cache);
      expect(FileAction.stream.downloadTarget, isNull);
      expect(FileAction.streamMusic.downloadTarget, isNull);
    });
  });

  group('设置解析与迁移', () {
    test('非法动作在解析时退回默认值', () {
      final cfg = FileActionConfig(actions: {
        FileCategory.video: FileAction.cacheMusic,
        FileCategory.other: FileAction.readCue,
      });
      expect(cfg.video, FileAction.stream);
      expect(cfg.other, FileAction.download);
    });

    test('实验开关关掉时音乐流式退回缓存', () {
      final cfg = FileActionConfig(
        experimentalMusicStreaming: false,
        actions: {FileCategory.music: FileAction.streamMusic},
      );
      expect(cfg.music, FileAction.cacheMusic);
      expect(cfg.choicesFor(FileCategory.music), isNot(contains(FileAction.streamMusic)));
    });

    test('打开实验开关后音乐流式可选', () {
      final cfg = FileActionConfig(experimentalMusicStreaming: true);
      expect(cfg.choicesFor(FileCategory.music), contains(FileAction.streamMusic));
      expect(cfg.choicesFor(FileCategory.video),
          isNot(contains(FileAction.streamMusic)));
    });

    test('JSON 往返保持动作与开关', () {
      final cfg = FileActionConfig(
        experimentalMusicStreaming: true,
        actions: {
          FileCategory.music: FileAction.streamMusic,
          FileCategory.video: FileAction.download,
        },
      );
      final back = FileActionConfig.fromJson(cfg.toJson())!;
      expect(back.music, FileAction.streamMusic);
      expect(back.video, FileAction.download);
      expect(back.cue, FileAction.readCue);
      expect(back.other, FileAction.download);
      expect(back.experimentalMusicStreaming, isTrue);
    });

    test('forFileName 先判类型再取动作', () {
      final cfg = FileActionConfig(actions: {
        FileCategory.video: FileAction.download,
      });
      expect(cfg.forFileName('a.mkv', types), FileAction.download);
      expect(cfg.forFileName('a.flac', types), FileAction.cacheMusic);
      expect(cfg.forFileName('a.cue', types), FileAction.readCue);
      expect(cfg.forFileName('a.zip', types), FileAction.download);
    });
  });

  group('多选工具栏的那个下载动作', () {
    test('全是音乐时叫「缓存音乐」', () {
      expect(bulkDownloadAction([FileCategory.music, FileCategory.music]),
          FileAction.cacheMusic);
    });

    test('混进视频或普通文件就退化成「下载」', () {
      expect(bulkDownloadAction([FileCategory.music, FileCategory.video]),
          FileAction.download);
      expect(bulkDownloadAction([FileCategory.other]), FileAction.download);
    });
  });

  group('旧设置的迁移', () {
    test('视频旧值 download → 下载；open → 流式传输', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'video_tap_action': 'download',
        'music_tap_action': 'play',
      });
      final s = SettingsService();
      await s.init();
      expect(s.fileActions.video, FileAction.download);
      expect(s.fileActions.music, FileAction.cacheMusic,
          reason: '旧音乐语义（play / download）都是先缓存再播');
      expect(s.fileActions.cue, FileAction.readCue);
      expect(s.fileActions.other, FileAction.download);
      expect(s.fileActions.experimentalMusicStreaming, isFalse);
    });

    test('写回后再读，走的是新配置', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final s = SettingsService();
      await s.init();
      await s.setFileAction(FileCategory.video, FileAction.download);
      final again = SettingsService();
      await again.init();
      expect(again.fileActions.video, FileAction.download);
    });
  });
}
