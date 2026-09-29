import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_media_manager/models/download_task.dart';
import 'package:webdav_media_manager/models/file_actions.dart';
import 'package:webdav_media_manager/models/file_type_config.dart';
import 'package:webdav_media_manager/services/settings_service.dart';

/// T1 回归：类型 → 动作的判定只有一份实现。
///
/// 改动之前三处各写一套 if-else（单击、多选、更多菜单），音乐与视频的
/// 语义已经开始分叉。这些测试锁住「哪个动作对哪种类型合法」和「默认动作
/// 是什么」，界面只是它的投影。
void main() {
  final types = FileTypeConfig();

  group('按后缀判类型', () {
    test('音乐 / 视频 / cue / 图片 / 普通', () {
      expect(types.categoryFor('song.flac'), FileCategory.music);
      expect(types.categoryFor('movie.mkv'), FileCategory.video);
      expect(types.categoryFor('album.cue'), FileCategory.cue);
      expect(types.categoryFor('cover.JPG'), FileCategory.image);
      expect(types.categoryFor('a.jpeg'), FileCategory.image);
      expect(types.categoryFor('a.png'), FileCategory.image);
      expect(types.categoryFor('a.webp'), FileCategory.image);
      expect(types.categoryFor('a.gif'), FileCategory.image);
      expect(types.categoryFor('readme.pdf'), FileCategory.other);
    });

    test('旧配置没有 image 键时用默认图片后缀，不冲掉音乐', () {
      final old = FileTypeConfig.fromJson({
        'music': ['mp3', 'flac'],
        'video': ['mp4'],
        'cue': ['cue'],
      });
      expect(old.musicExtensions, ['mp3', 'flac']);
      expect(old.videoExtensions, ['mp4']);
      expect(old.imageExtensions, FileTypeConfig.defaultImageExtensions);
      expect(old.categoryFor('song.flac'), FileCategory.music);
      expect(old.categoryFor('cover.jpg'), FileCategory.image);
      final cleared = FileTypeConfig.fromJson({
        'music': ['mp3'],
        'video': ['mp4'],
        'cue': ['cue'],
        'image': [],
      });
      expect(cleared.imageExtensions, isEmpty);
      expect(cleared.categoryFor('a.jpg'), FileCategory.other);
      expect(cleared.categoryFor('a.mp3'), FileCategory.music);
    });

    test('默认动作：音乐缓存、cue 读取、视频流式、图片查看、普通下载', () {
      expect(
        FileActionCatalog.defaultFor(FileCategory.music),
        FileAction.cacheMusic,
      );
      expect(
        FileActionCatalog.defaultFor(FileCategory.image),
        FileAction.viewImage,
      );
      expect(
        FileActionCatalog.defaultFor(FileCategory.cue),
        FileAction.readCue,
      );
      expect(
        FileActionCatalog.defaultFor(FileCategory.video),
        FileAction.stream,
      );
      expect(
        FileActionCatalog.defaultFor(FileCategory.other),
        FileAction.download,
      );
    });
  });

  group('拦截不合法行为', () {
    test('任何文件都允许下载', () {
      for (final c in FileCategory.values) {
        expect(
          FileActionCatalog.isAllowed(c, FileAction.download),
          isTrue,
          reason: '$c 也应该能下载',
        );
      }
    });

    test('缓存音乐只对音乐合法', () {
      expect(
        FileActionCatalog.isAllowed(FileCategory.music, FileAction.cacheMusic),
        isTrue,
      );
      expect(
        FileActionCatalog.isAllowed(FileCategory.video, FileAction.cacheMusic),
        isFalse,
      );
      expect(
        FileActionCatalog.isAllowed(FileCategory.other, FileAction.cacheMusic),
        isFalse,
      );
    });

    test('视频那个流式传输不适用于音乐（音乐要用 streamMusic）', () {
      expect(
        judgeAction(
          action: FileAction.stream,
          category: FileCategory.music,
          isDirectory: false,
        ).allowed,
        isFalse,
      );
      expect(
        judgeAction(
          action: FileAction.streamMusic,
          category: FileCategory.music,
          isDirectory: false,
        ).allowed,
        isTrue,
      );
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

    test('拒绝时给出结构化原因（动作与类别）', () {
      final d = judgeAction(
        action: FileAction.cacheMusic,
        category: FileCategory.video,
        isDirectory: false,
      );
      expect(d.allowed, isFalse);
      final reason = d.reason;
      expect(reason, isA<FileActionDenyNotApplicable>());
      final n = reason as FileActionDenyNotApplicable;
      expect(n.action, FileAction.cacheMusic);
      expect(n.category, FileCategory.video);
    });
  });

  group('落盘目标', () {
    test('缓存音乐落在缓存，下载落在下载目录，流式不落盘', () {
      expect(FileAction.cacheMusic.downloadTarget, DownloadTarget.cache);
      expect(FileAction.download.downloadTarget, DownloadTarget.downloads);
      expect(FileAction.readCue.downloadTarget, DownloadTarget.cache);
      expect(FileAction.stream.downloadTarget, isNull);
      expect(FileAction.streamMusic.downloadTarget, isNull);
      expect(FileAction.viewImage.downloadTarget, isNull);
      expect(FileAction.downloadToGallery.downloadTarget, DownloadTarget.gallery);
      expect(
        FileActionCatalog.isAllowed(FileCategory.image, FileAction.downloadToGallery),
        isTrue,
      );
      expect(
        FileActionCatalog.isAllowed(FileCategory.video, FileAction.downloadToGallery),
        isFalse,
      );
      expect(
        FileActionCatalog.forCategory(FileCategory.image),
        contains(FileAction.downloadToGallery),
      );
    });
  });

  group('设置解析与迁移', () {
    test('非法动作在解析时退回默认值', () {
      final cfg = FileActionConfig(
        actions: {
          FileCategory.video: FileAction.cacheMusic,
          FileCategory.other: FileAction.readCue,
        },
      );
      expect(cfg.video, FileAction.stream);
      expect(cfg.other, FileAction.download);
    });

    test('流式开关关掉时音乐流式退回缓存', () {
      final cfg = FileActionConfig(
        allowMusicStreaming: false,
        actions: {FileCategory.music: FileAction.streamMusic},
      );
      expect(cfg.music, FileAction.cacheMusic);
      expect(
        cfg.choicesFor(FileCategory.music),
        isNot(contains(FileAction.streamMusic)),
      );
    });

    test('打开流式开关后音乐流式可选，单击默认仍是缓存', () {
      final cfg = FileActionConfig(allowMusicStreaming: true);
      expect(cfg.music, FileAction.cacheMusic);
      expect(
        cfg.choicesFor(FileCategory.music),
        contains(FileAction.streamMusic),
      );
      expect(
        cfg.choicesFor(FileCategory.video),
        isNot(contains(FileAction.streamMusic)),
      );
    });

    test('JSON 往返保持动作', () {
      final cfg = FileActionConfig(
        allowMusicStreaming: true,
        actions: {
          FileCategory.music: FileAction.streamMusic,
          FileCategory.video: FileAction.download,
        },
      );
      // 开关不再随 JSON 走：它由调用方从设置里传进来（见 SettingsService）。
      final back = FileActionConfig.fromJson(
        cfg.toJson(),
        allowMusicStreaming: true,
      )!;
      expect(back.music, FileAction.streamMusic);
      expect(back.video, FileAction.download);
      expect(back.cue, FileAction.readCue);
      expect(back.image, FileAction.viewImage);
      expect(back.other, FileAction.download);
      expect(back.toJson()['image'], 'view_image');
      expect(back.allowMusicStreaming, isTrue);
    });

    test('旧动作 JSON 缺 image 键时回退到查看图片', () {
      final back = FileActionConfig.fromJson({
        'music': 'cache_music',
        'video': 'stream',
        'cue': 'read_cue',
        'other': 'download',
      }, allowMusicStreaming: true)!;
      expect(back.music, FileAction.cacheMusic);
      expect(back.image, FileAction.viewImage);
    });

    test('forFileName 先判类型再取动作', () {
      final cfg = FileActionConfig(
        actions: {FileCategory.video: FileAction.download},
      );
      expect(cfg.forFileName('a.mkv', types), FileAction.download);
      // 开关关着时，就算动作写成 streamMusic 也会退回缓存。
      expect(cfg.forFileName('a.flac', types), FileAction.cacheMusic);
      expect(cfg.forFileName('a.cue', types), FileAction.readCue);
      expect(cfg.forFileName('a.jpg', types), FileAction.viewImage);
      expect(cfg.forFileName('a.zip', types), FileAction.download);
      // 开关开着也不把单击出厂默认改成流式；要流式得显式选。
      final streaming = FileActionConfig(allowMusicStreaming: true);
      expect(streaming.forFileName('a.flac', types), FileAction.cacheMusic);
      final chosen = FileActionConfig(
        allowMusicStreaming: true,
        actions: {FileCategory.music: FileAction.streamMusic},
      );
      expect(chosen.forFileName('a.flac', types), FileAction.streamMusic);
    });
  });

  group('多选工具栏的那个下载动作', () {
    test('全是音乐时叫「缓存音乐」', () {
      expect(
        bulkDownloadAction([FileCategory.music, FileCategory.music]),
        FileAction.cacheMusic,
      );
    });

    test('混进视频或普通文件就退化成「下载」', () {
      expect(
        bulkDownloadAction([FileCategory.music, FileCategory.video]),
        FileAction.download,
      );
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
      expect(
        s.fileActions.music,
        FileAction.cacheMusic,
        reason: '旧音乐语义（play / download）都是先缓存再播',
      );
      expect(s.fileActions.cue, FileAction.readCue);
      expect(s.fileActions.other, FileAction.download);
      expect(s.audioStreamingEnabled, isFalse);
    });

    test('旧配置里的 experimental_music_streaming 迁到新开关', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'file_action_config_json':
            '{"music":"stream_music","experimental_music_streaming":true}',
      });
      final s = SettingsService();
      await s.init();
      expect(s.audioStreamingEnabled, isTrue, reason: '点过一次的开关不该再点第二次');
      expect(s.fileActions.music, FileAction.streamMusic);
    });

    test('写回后再读，走的是新配置', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final s = SettingsService();
      await s.init();
      await s.setFileAction(FileCategory.video, FileAction.download);
      final again = SettingsService();
      await again.init();
      expect(again.fileActions.video, FileAction.download);
      expect(again.audioStreamingEnabled, isTrue);
      expect(again.fileActions.music, FileAction.cacheMusic);
    });

    test('新安装音乐流式开关默认开，单击仍是缓存', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final s = SettingsService();
      await s.init();
      expect(s.audioStreamingEnabled, isTrue);
      expect(s.fileActions.music, FileAction.cacheMusic);
      expect(s.fileActions.video, FileAction.stream);
      expect(s.fileActions.image, FileAction.viewImage);
      expect(s.downloadNomediaEnabled, isFalse);
      expect(s.exportForBackup()['download_nomedia'], isFalse);
      await s.setDownloadNomediaEnabled(true);
      final againNomedia = SettingsService();
      await againNomedia.init();
      expect(againNomedia.downloadNomediaEnabled, isTrue);
      expect(againNomedia.exportForBackup()['download_nomedia'], isTrue);
    });

    test('已保存的音乐动作不会被新默认覆盖', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'file_action_config_json': '{"music":"cache_music","video":"stream","cue":"read_cue","other":"download"}',
      });
      final s = SettingsService();
      await s.init();
      expect(s.audioStreamingEnabled, isFalse);
      expect(s.fileActions.music, FileAction.cacheMusic);
      expect(s.fileActions.image, FileAction.viewImage);
      await s.setAudioStreamingEnabled(true);
      expect(s.fileActions.music, FileAction.cacheMusic);
    });

    test('已保存的流式开关不会被新安装默认盖掉', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'audio_streaming_enabled': false,
        'file_action_config_json':
            '{"music":"download","video":"stream","cue":"read_cue","other":"download"}',
      });
      final s = SettingsService();
      await s.init();
      expect(s.audioStreamingEnabled, isFalse);
      expect(s.fileActions.music, FileAction.download);
    });

    test('关掉音乐流式时已选的流式退回缓存', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final s = SettingsService();
      await s.init();
      expect(s.fileActions.music, FileAction.cacheMusic);
      await s.setFileAction(FileCategory.music, FileAction.streamMusic);
      expect(s.fileActions.music, FileAction.streamMusic);
      await s.setAudioStreamingEnabled(false);
      expect(s.fileActions.music, FileAction.cacheMusic);
      final again = SettingsService();
      await again.init();
      expect(again.audioStreamingEnabled, isFalse);
      expect(again.fileActions.music, FileAction.cacheMusic);
    });
  });

  group('图片查看设置', () {
    test('默认关幻灯片、每侧预取 1、子目录扫描关，并进备份', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final s = SettingsService();
      await s.init();
      expect(s.imageSlideshowEnabled, isFalse);
      expect(s.imageSlideshowIntervalSeconds, 3);
      expect(s.imageSlideshowLoop, isTrue);
      expect(s.imageFit, SettingsService.imageFitContain);
      expect(s.imagePrefetchCount, 1);
      expect(s.imageScanSubdirs, isFalse);
      await s.setImagePrefetchCount(9);
      await s.setImageSlideshowIntervalSeconds(0);
      await s.setImageFit('cover');
      await s.setImageScanSubdirs(true);
      expect(s.imagePrefetchCount, 5);
      expect(s.imageSlideshowIntervalSeconds, 1);
      expect(s.imageFit, SettingsService.imageFitCover);
      final again = SettingsService();
      await again.init();
      expect(again.imagePrefetchCount, 5);
      expect(again.imageScanSubdirs, isTrue);
      expect(again.imageFit, SettingsService.imageFitCover);
      final backup = again.exportForBackup();
      expect(backup['image_scan_subdirs'], isTrue);
      expect(backup['image_prefetch_count'], 5);
      expect(backup['image_slideshow_enabled'], isFalse);
      expect(backup['file_action_config'], isA<Map>());
      expect((backup['file_action_config'] as Map)['image'], 'view_image');
      final gallery = FileActionConfig(
        actions: {FileCategory.image: FileAction.downloadToGallery},
      );
      expect(gallery.image, FileAction.downloadToGallery);
      expect(gallery.toJson()['image'], 'download_to_gallery');
      final backGallery = FileActionConfig.fromJson(gallery.toJson());
      expect(backGallery!.image, FileAction.downloadToGallery);
      expect((backup['file_action_config'] as Map)['music'], 'cache_music');
    });
  });
}
