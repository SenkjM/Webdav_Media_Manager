import 'dart:ui' show Locale;

import 'package:charset/charset.dart' as charset;
import 'package:enough_convert/enough_convert.dart' as extra;
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_media_manager/models/file_type_config.dart';
import 'package:webdav_media_manager/models/webdav_item.dart';
import 'package:webdav_media_manager/services/settings_service.dart';
import 'package:webdav_media_manager/utils/subtitle_encoding.dart';
import 'package:webdav_media_manager/utils/subtitle_sidecar.dart';

WebDavItem file(
  String name, {
  String? path,
  bool directory = false,
  int? size,
}) {
  return WebDavItem(
    name: name,
    path: path ?? '/show/$name',
    isDirectory: directory,
    size: size,
  );
}

late AppLocalizations l10n;

void main() {
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  final videos = FileTypeConfig.defaultVideoExtensions.toSet();

  group('字幕文件名匹配', () {
    test('去掉最后一个视频后缀，精确同名优先于语言后缀', () {
      expect(videoStem('Show.S01E01.mkv', videos), 'Show.S01E01');
      expect(videoStem('Movie.MP4', videos), 'Movie');
      final exact = matchSubtitleFileName(
        videoFileName: 'Show.S01E01.mkv',
        subtitleFileName: 'Show.S01E01.SRT',
        videoExtensions: videos,
      );
      expect(exact, isNotNull);
      expect(exact!.exact, isTrue);
      expect(exact.language, '默认');
      expect(exact.languageKey, isEmpty);
      expect(exact.format, 'srt');

      final zh = matchSubtitleFileName(
        videoFileName: 'video.mkv',
        subtitleFileName: 'video.zh-CN.ass',
        videoExtensions: videos,
      );
      expect(zh!.language, 'zh-CN');
      expect(zh.languageKey, 'zh');
      expect(zh.format, 'ass');
      expect(zh.exact, isFalse);
      expect(
        matchSubtitleFileName(
          videoFileName: 'video.mkv',
          subtitleFileName: 'video.chs.srt',
          videoExtensions: videos,
        )!.languageKey,
        'zh',
      );
      expect(
        matchSubtitleFileName(
          videoFileName: 'video.mkv',
          subtitleFileName: 'video.chi.srt',
          videoExtensions: videos,
        )!.languageKey,
        'zh',
      );
      expect(
        matchSubtitleFileName(
          videoFileName: 'video.mkv',
          subtitleFileName: 'video.zh-Hans.srt',
          videoExtensions: videos,
        )!.languageKey,
        'zh',
      );
      final eng = matchSubtitleFileName(
        videoFileName: 'video.mkv',
        subtitleFileName: 'video.eng.vtt',
        videoExtensions: videos,
      )!;
      expect(eng.language, 'eng');
      expect(eng.languageKey, 'en');
    });

    test('中间段不限语言代码，多点仍是一条，精确同名是默认', () {
      const stem =
          '[Nekomoe kissaten&VCB-Studio] Cyberpunk Edgerunners [01][Ma10p_1080p][x265_flac]';
      final jpsc = matchSubtitleFileName(
        videoFileName: '$stem.mkv',
        subtitleFileName: '$stem.JPSC.ass',
        videoExtensions: videos,
      )!;
      expect(jpsc.language, 'JPSC');
      expect(jpsc.languageKey, 'jpsc');
      expect(jpsc.format, 'ass');
      expect(jpsc.exact, isFalse);
      final jpscLabel = labelSameDirectorySidecar(
        language: jpsc.language,
        format: jpsc.format,
        l10n: l10n,
      );
      expect(jpscLabel.title, 'JPSC');
      expect(jpscLabel.formatTag, 'ass');

      final dotted = matchSubtitleFileName(
        videoFileName: 'video.mkv',
        subtitleFileName: 'video.a.b.ass',
        videoExtensions: videos,
      )!;
      expect(dotted.language, 'a.b');
      expect(dotted.format, 'ass');
      expect(dotted.exact, isFalse);
      final dottedHits = collectSidecars(
        videoFileName: 'video.mkv',
        sameDirectory: [file('video.a.b.ass')],
        videoExtensions: videos,
      );
      expect(dottedHits, hasLength(1));
      expect(dottedHits.single.labelFor(l10n).title, 'a.b');
      expect(dottedHits.single.labelFor(l10n).formatTag, 'ass');

      final forced = matchSubtitleFileName(
        videoFileName: 'video.mkv',
        subtitleFileName: 'video.zh.forced.srt',
        videoExtensions: videos,
      )!;
      expect(forced.language, 'zh.forced');
      expect(
        matchSubtitleFileName(
          videoFileName: 'Movie.mkv',
          subtitleFileName: 'Movie.Chinese.srt',
          videoExtensions: videos,
        )!.language,
        'Chinese',
      );

      final plain = matchSubtitleFileName(
        videoFileName: '电影.mkv',
        subtitleFileName: '电影.ass',
        videoExtensions: videos,
      )!;
      expect(plain.exact, isTrue);
      expect(plain.language, '默认');
      expect(plain.language, isNot('auto'));
      final plainLabel = labelSameDirectorySidecar(
        language: plain.language,
        format: plain.format,
        l10n: l10n,
      );
      expect(plainLabel.title, '默认');
      expect(plainLabel.formatTag, 'ass');
    });

    test('不匹配别的文件，也不匹配目录', () {
      final hits = collectSidecars(
        videoFileName: 'video.mkv',
        sameDirectory: [
          file('video.srt'),
          file('video.zh.srt'),
          file('subs', directory: true, path: '/show/subs/'),
          file('other.srt'),
        ],
        videoExtensions: videos,
      );
      expect(hits.map((h) => h.name), ['video.srt', 'video.zh.srt']);
    });

    test('子目录视频用自己的父目录，而不是正在浏览的文件夹', () {
      const nested = '/shows/season1/ep.mkv';
      expect(videoParentDirectory(nested), '/shows/season1');
      expect(sameDirectory(nested, '/shows'), isFalse);
      expect(sameDirectory(nested, '/shows/season1/'), isTrue);
    });

    test('外挂：精确文件名先于界面语言，再按文件名', () {
      final hits = collectSidecars(
        videoFileName: 'video.mkv',
        sameDirectory: [
          file('video.en.srt'),
          file('video.zh.ass'),
          file('video.srt'),
        ],
        subdirectory: [file('video.ja.srt', path: '/show/sub/video.ja.srt')],
        subdirectoryName: 'sub',
        videoExtensions: videos,
      );
      expect(pickSidecar(hits, 'zh')!.name, 'video.srt');
      final noExact = hits.where((h) => h.name != 'video.srt').toList();
      expect(pickSidecar(noExact, 'zh')!.name, 'video.zh.ass');
      final rest = noExact.where((h) => h.languageKey != 'zh').toList();
      expect(pickSidecar(rest, 'zh')!.name, 'video.en.srt');
    });
  });

  group('字幕列表标签', () {
    test('同目录只显示语言和格式标签，子目录带前缀，内嵌没有格式', () {
      final same = labelSameDirectorySidecar(language: 'zh', format: 'ASS', l10n: l10n);
      expect(same.title, 'zh');
      expect(same.formatTag, 'ass');

      final empty = labelSameDirectorySidecar(language: '', format: 'srt', l10n: l10n);
      expect(empty.title, '默认');
      expect(empty.formatTag, 'srt');

      final sub = labelSubdirectorySidecar(
        subdirectory: 'sub',
        language: 'zh',
        format: 'srt',
      );
      expect(sub.title, '/sub/zh');
      expect(sub.formatTag, 'srt');

      final embedded = labelEmbeddedSubtitle('zh', l10n);
      expect(embedded.title, '[内嵌] zh');
      expect(embedded.formatTag, isNull);
      final embeddedDefault = labelEmbeddedSubtitle('', l10n);
      expect(embeddedDefault.title, '[内嵌] 默认');
      expect(embeddedDefault.formatTag, isNull);
      expect(
        embeddedCueFromTrack(id: '8', language: null)!.labelFor(l10n).title,
        '[内嵌] 默认',
      );
      expect(
        embeddedCueFromTrack(id: '8', language: '')!.labelFor(l10n).formatTag,
        isNull,
      );
      expect(embeddedCueFromTrack(id: '9', language: 'auto'), isNull);
      expect(embeddedCueFromTrack(id: 'auto', language: 'zh'), isNull);
      expect(embeddedCueFromTrack(id: 'no', language: 'en'), isNull);

      final manual = labelManualSubtitle(fileName: 'extra.ssa', format: 'ssa');
      expect(manual.title, 'extra.ssa');
      expect(manual.formatTag, 'ssa');
    });

    test('位图内嵌轨道不进列表，文本内嵌优先界面语言', () {
      expect(
        embeddedCueFromTrack(
          id: '1',
          codec: 'hdmv_pgs_subtitle',
          language: 'zh',
        ),
        isNull,
      );
      expect(
        embeddedCueFromTrack(id: '2', codec: 'dvd_subtitle', language: 'en'),
        isNull,
      );
      final zh = embeddedCueFromTrack(
        id: '3',
        codec: 'subrip',
        language: 'chi',
      )!;
      final en = embeddedCueFromTrack(id: '4', codec: 'ass', language: 'eng')!;
      expect(zh.labelFor(l10n).title, '[内嵌] zh');
      expect(zh.labelFor(l10n).formatTag, isNull);
      expect(pickEmbedded([en, zh], 'zh')!.id, '3');
      expect(
        selectSubtitle(
          manualId: 'manual',
          embedded: [zh],
          sidecars: collectSidecars(
            videoFileName: 'video.mkv',
            sameDirectory: [file('video.srt')],
            videoExtensions: videos,
          ),
          uiLanguageKey: 'zh',
        ).kind,
        SubtitleAutoKind.manual,
      );
      expect(
        selectSubtitle(
          embedded: [zh],
          sidecars: collectSidecars(
            videoFileName: 'video.mkv',
            sameDirectory: [file('video.srt')],
            videoExtensions: videos,
          ),
          uiLanguageKey: 'en',
        ).kind,
        SubtitleAutoKind.embedded,
      );
      expect(
        selectSubtitle(
          embedded: const [],
          sidecars: collectSidecars(
            videoFileName: 'video.mkv',
            sameDirectory: [file('video.srt')],
            videoExtensions: videos,
          ),
          uiLanguageKey: 'zh',
        ).kind,
        SubtitleAutoKind.sidecar,
      );
    });

    test('打开后新出现的轨和合成 auto 语言不算内嵌', () {
      expect(
        embeddedSubtitleIds(
          ids: const ['auto', 'no', '1', '2'],
          languages: const [null, null, 'zh', null],
          capturedIds: const {'1', '2'},
        ),
        ['1', '2'],
      );
      expect(
        embeddedSubtitleIds(
          ids: const ['1', '3', '4'],
          languages: const [null, 'auto', 'auto'],
          capturedIds: const {'1'},
        ),
        ['1'],
      );
      expect(
        embeddedSubtitleIds(
          ids: const ['5', '6'],
          languages: const ['auto', 'AUTO'],
          capturedIds: const <String>{},
        ),
        isEmpty,
      );
      expect(
        embeddedSubtitleIds(
          ids: const ['7'],
          languages: const ['jpsc'],
          capturedIds: const {'1'},
        ),
        isEmpty,
      );
      expect(
        embeddedSubtitleIds(
          ids: const ['1', '8'],
          languages: const ['zh', 'en'],
        ),
        ['1', '8'],
      );
    });
  });

  group('字幕编码', () {
    test('UTF-8、GBK、Big5 和 UTF-16 能被认出来', () {
      const text = '1\n中文\n';
      final utf8Bytes = utf8SubtitleBytes(text);
      expect(decodeSubtitleBytes(utf8Bytes)!.text, text);
      expect(decodeSubtitleBytes(utf8Bytes)!.name, 'utf-8');

      final gbkBytes = charset.gbk.encode(text);
      final gbkDecoded = decodeSubtitleBytes(gbkBytes)!;
      expect(gbkDecoded.text, text);
      expect(gbkDecoded.name, 'gbk');

      final big5Bytes = extra.Big5Codec().encode('字幕');
      final big5Decoded = decodeSubtitleBytes(big5Bytes)!;
      expect(big5Decoded.text, '字幕');
      expect(big5Decoded.name, 'big5');

      final utf16 = <int>[0xFF, 0xFE, 0x2D, 0x4E, 0x87, 0x65, 0x0A, 0x00];
      final utf16Decoded = decodeSubtitleBytes(utf16)!;
      expect(utf16Decoded.name, 'utf-16le');
      expect(utf16Decoded.text.contains('中'), isTrue);

      expect(
        decodeSubtitleBytes(
          gbkBytes,
          override: SubtitleEncodingChoice.gbk,
        )!.text,
        text,
      );
      expect(
        looksLikeBinarySubtitle(const [0x00, 0x00, 0x01, 0xBA, 0x00]),
        isTrue,
      );
      expect(
        subtitlePayloadIsText(const [0x00, 0x00, 0x01, 0xBA], 'sub'),
        isFalse,
      );
      expect(
        subtitlePayloadIsText(utf8SubtitleBytes('1\nhello'), 'srt'),
        isTrue,
      );
    });
  });

  test('同目录外挂默认开，子目录增强默认关，而且不是视频扫描子目录那个键', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsService();
    await settings.init();
    expect(settings.videoAutoSubtitle, isTrue);
    expect(settings.videoSubtitleSubdirEnabled, isFalse);
    expect(settings.videoSubtitleSubdir, 'sub');
    expect(settings.videoScanSubdirs, isFalse);
    expect(settings.exportForBackup()['video_auto_subtitle'], isTrue);
    expect(
      settings.exportForBackup()['video_subtitle_subdir_enabled'],
      isFalse,
    );
    expect(sanitizeSubtitleSubdir('/sub'), 'sub');
    expect(sanitizeSubtitleSubdir('a/b'), isNull);
    expect(await settings.setVideoSubtitleSubdir('a/b'), isFalse);
    expect(await settings.setVideoSubtitleSubdir('subs'), isTrue);
    final again = SettingsService();
    await again.init();
    expect(again.videoSubtitleSubdir, 'subs');
  });
}
