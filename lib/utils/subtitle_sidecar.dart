import '../models/file_type_config.dart';
import '../models/webdav_item.dart';

/// Extensions treated as text sidecars. `.idx` is not one of them.
const Set<String> subtitleSidecarExtensions = {
  'srt',
  'ass',
  'ssa',
  'vtt',
  'sub',
};

/// One language segment: `zh`, `en`, `chi`, `zh-CN`, `zh-Hans`. Not `Chinese`.
final RegExp _languageSegment = RegExp(
  r'^[a-z]{2,3}(?:[_-][a-z]{2,4})?$',
  caseSensitive: false,
);

/// Filename without its last video extension, compared case-insensitively.
String videoStem(String fileName, Set<String> videoExtensions) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0) return fileName;
  final ext = fileName.substring(dot + 1).toLowerCase();
  if (!videoExtensions.contains(ext)) return fileName;
  return fileName.substring(0, dot);
}

/// Parent directory of a remote file. `/a/b/c.mkv` → `/a/b`.
String videoParentDirectory(String remotePath) {
  final canonical = canonicalDirectory(remotePath);
  final slash = canonical.lastIndexOf('/');
  if (slash <= 0) return '/';
  return canonical.substring(0, slash);
}

/// Drop a trailing slash so `/a/b` and `/a/b/` compare equal.
String canonicalDirectory(String path) {
  if (path.isEmpty) return '/';
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

bool sameDirectory(String filePath, String folderPath) =>
    videoParentDirectory(filePath) == canonicalDirectory(folderPath);

/// One folder segment. `/sub` → `sub`. Empty means the enhancement is off.
/// `null` means the value is not a single path segment (`..`, `a/b`).
String? sanitizeSubtitleSubdir(String raw) {
  var text = raw.trim().replaceAll('\\', '/');
  while (text.startsWith('/')) {
    text = text.substring(1);
  }
  while (text.endsWith('/')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.isEmpty) return '';
  if (text.contains('/') || text == '.' || text == '..') return null;
  return text;
}

/// How a sidecar name relates to a video name. Null when it does not match.
class SubtitleNameMatch {
  const SubtitleNameMatch({
    required this.language,
    required this.languageKey,
    required this.format,
    required this.exact,
  });

  /// Display language. Empty when the file has no language segment.
  /// Known aliases become `zh` / `en`; anything else keeps the segment.
  final String language;

  /// Lowercase key used for UI-language comparison. Empty if [language] is.
  final String languageKey;

  /// Lowercase extension without the dot.
  final String format;

  /// `{stem}.ext` with no language segment.
  final bool exact;
}

SubtitleNameMatch? matchSubtitleFileName({
  required String videoFileName,
  required String subtitleFileName,
  Set<String>? videoExtensions,
}) {
  final exts = videoExtensions ?? FileTypeConfig.defaultVideoExtensions.toSet();
  final stem = videoStem(videoFileName, exts);
  if (stem.isEmpty) return null;
  final format = _extensionOf(subtitleFileName);
  if (format == null) return null;
  final lowerName = subtitleFileName.toLowerCase();
  final lowerStem = stem.toLowerCase();
  final dotExt = '.$format';
  if (!lowerName.endsWith(dotExt)) return null;
  if (lowerName == '$lowerStem$dotExt') {
    return SubtitleNameMatch(
      language: '',
      languageKey: '',
      format: format,
      exact: true,
    );
  }
  if (!lowerName.startsWith('$lowerStem.')) return null;
  final middle = lowerName.substring(
    lowerStem.length + 1,
    lowerName.length - dotExt.length,
  );
  if (middle.isEmpty || middle.contains('.')) return null;
  if (!_languageSegment.hasMatch(middle)) return null;
  final rawMiddle = subtitleFileName.substring(
    lowerStem.length + 1,
    subtitleFileName.length - dotExt.length,
  );
  final language = displaySubtitleLanguage(rawMiddle);
  return SubtitleNameMatch(
    language: language,
    languageKey: language.toLowerCase(),
    format: format,
    exact: false,
  );
}

String? _extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return null;
  final ext = fileName.substring(dot + 1).toLowerCase();
  if (!subtitleSidecarExtensions.contains(ext)) return null;
  return ext;
}

/// `zh-CN` / `chs` / `chi` / `zh-Hans` → `zh`. `en` / `eng` → `en`.
/// Empty, `und`, and missing tags stay empty. Other segments stay as written.
String displaySubtitleLanguage(String? raw) {
  if (raw == null) return '';
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final key = trimmed.toLowerCase().replaceAll('_', '-');
  if (key == 'und' || key == 'undetermined' || key == 'unknown') return '';
  const zh = {
    'zh',
    'zho',
    'chi',
    'chs',
    'cht',
    'zh-cn',
    'zh-sg',
    'zh-hans',
    'zh-tw',
    'zh-hk',
    'zh-mo',
    'zh-hant',
    'cn',
    'sc',
    'tc',
  };
  if (zh.contains(key)) return 'zh';
  if (key == 'en' || key == 'eng' || key.startsWith('en-')) return 'en';
  if (key.startsWith('zh-')) return 'zh';
  return trimmed;
}

/// UI language key (`zh` / `en` / other ISO code) from a locale language code.
String uiSubtitleLanguageKey(String languageCode) {
  if (languageCode.trim().isEmpty) return '';
  return displaySubtitleLanguage(languageCode).toLowerCase();
}

/// Picker title plus an optional format tag. Embedded rows never have a tag.
class SubtitleRowLabel {
  const SubtitleRowLabel({required this.title, this.formatTag});

  final String title;
  final String? formatTag;
}

SubtitleRowLabel labelSameDirectorySidecar({
  required String language,
  required String format,
}) => SubtitleRowLabel(title: language, formatTag: format.toLowerCase());

SubtitleRowLabel labelSubdirectorySidecar({
  required String subdirectory,
  required String language,
  required String format,
}) {
  final folder = subdirectory.replaceAll('\\', '/');
  final title = language.isEmpty ? '/$folder' : '/$folder/$language';
  return SubtitleRowLabel(title: title, formatTag: format.toLowerCase());
}

SubtitleRowLabel labelEmbeddedSubtitle(String language) => SubtitleRowLabel(
  title: language.isEmpty ? '[内嵌]' : '[内嵌] $language',
);

SubtitleRowLabel labelManualSubtitle({
  required String fileName,
  required String format,
}) => SubtitleRowLabel(title: fileName, formatTag: format.toLowerCase());

/// A sidecar file that matched the video name.
class SidecarHit {
  const SidecarHit({
    required this.name,
    required this.path,
    required this.language,
    required this.languageKey,
    required this.format,
    required this.exact,
    this.subdirectory,
    this.size,
  });

  final String name;
  final String path;
  final String language;
  final String languageKey;
  final String format;
  final bool exact;

  /// Null for a same-directory file. Otherwise the single folder name.
  final String? subdirectory;

  /// Remote size when the listing provided one. Used to skip huge `.sub` files.
  final int? size;

  SubtitleRowLabel get label => subdirectory == null
      ? labelSameDirectorySidecar(language: language, format: format)
      : labelSubdirectorySidecar(
          subdirectory: subdirectory!,
          language: language,
          format: format,
        );
}

/// Text embedded track we are willing to select. Bitmap codecs are omitted.
class EmbeddedSubtitleCue {
  const EmbeddedSubtitleCue({
    required this.id,
    required this.language,
    required this.languageKey,
    this.title,
    this.isDefault = false,
  });

  final String id;
  final String language;
  final String languageKey;
  final String? title;
  final bool isDefault;

  SubtitleRowLabel get label => labelEmbeddedSubtitle(language);
}

const Set<String> _bitmapSubtitleCodecs = {
  'hdmv_pgs_subtitle',
  'hdmv_pgs',
  'pgssub',
  'pgs',
  'dvd_subtitle',
  'dvdsub',
  'vobsub',
  'vob_subtitle',
  'dvb_subtitle',
  'xsub',
};

bool isBitmapSubtitleCodec(String? codec) {
  if (codec == null || codec.trim().isEmpty) return false;
  final key = codec.trim().toLowerCase();
  if (_bitmapSubtitleCodecs.contains(key)) return true;
  return key.contains('pgs') ||
      key.contains('vobsub') ||
      key.contains('dvd_sub') ||
      key.contains('dvdsub');
}

/// Null when the track is `auto` / `no` or a bitmap codec the text painter
/// cannot show. A missing codec stays selectable.
EmbeddedSubtitleCue? embeddedCueFromTrack({
  required String id,
  String? language,
  String? title,
  String? codec,
  bool isDefault = false,
  bool external = false,
}) {
  if (external) return null;
  if (id == 'auto' || id == 'no' || id.isEmpty) return null;
  if (isBitmapSubtitleCodec(codec)) return null;
  final display = displaySubtitleLanguage(language);
  return EmbeddedSubtitleCue(
    id: id,
    language: display,
    languageKey: display.toLowerCase(),
    title: title,
    isDefault: isDefault,
  );
}

List<SidecarHit> collectSidecars({
  required String videoFileName,
  required Iterable<WebDavItem> sameDirectory,
  Iterable<WebDavItem> subdirectory = const [],
  String? subdirectoryName,
  Set<String>? videoExtensions,
}) {
  final hits = <SidecarHit>[];
  void take(Iterable<WebDavItem> items, String? folder) {
    for (final item in items) {
      if (item.isDirectory) continue;
      final match = matchSubtitleFileName(
        videoFileName: videoFileName,
        subtitleFileName: item.name,
        videoExtensions: videoExtensions,
      );
      if (match == null) continue;
      hits.add(
        SidecarHit(
          name: item.name,
          path: item.path,
          language: match.language,
          languageKey: match.languageKey,
          format: match.format,
          exact: match.exact,
          subdirectory: folder,
          size: item.size,
        ),
      );
    }
  }

  take(sameDirectory, null);
  final folder = subdirectoryName;
  if (folder != null && folder.isNotEmpty) {
    take(subdirectory, folder);
  }
  return hits;
}

/// Exact basename, then UI language, then file name.
SidecarHit? pickSidecar(List<SidecarHit> hits, String uiLanguageKey) {
  if (hits.isEmpty) return null;
  final ui = uiLanguageKey.toLowerCase();
  final sorted = [...hits]..sort((a, b) {
    final rank = _sidecarRank(a, ui).compareTo(_sidecarRank(b, ui));
    if (rank != 0) return rank;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return sorted.first;
}

int _sidecarRank(SidecarHit hit, String ui) {
  if (hit.exact) return 0;
  if (ui.isNotEmpty && hit.languageKey == ui) return 1;
  return 2;
}

/// Prefer the UI language. If none match, keep a deterministic text track so
/// an embedded subtitle still outranks sidecars.
EmbeddedSubtitleCue? pickEmbedded(
  List<EmbeddedSubtitleCue> cues,
  String uiLanguageKey,
) {
  if (cues.isEmpty) return null;
  final ui = uiLanguageKey.toLowerCase();
  final matched = ui.isEmpty
      ? cues
      : cues.where((c) => c.languageKey == ui).toList();
  final pool = matched.isNotEmpty ? matched : cues;
  final sorted = [...pool]..sort((a, b) {
    final pref = (b.isDefault ? 1 : 0).compareTo(a.isDefault ? 1 : 0);
    if (pref != 0) return pref;
    final an = (a.title ?? a.language).toLowerCase();
    final bn = (b.title ?? b.language).toLowerCase();
    final byName = an.compareTo(bn);
    if (byName != 0) return byName;
    return a.id.compareTo(b.id);
  });
  return sorted.first;
}

enum SubtitleAutoKind { none, manual, embedded, sidecar }

class SubtitleAutoSelection {
  const SubtitleAutoSelection(this.kind, {this.id});

  final SubtitleAutoKind kind;

  /// Manual token, embedded track id, or sidecar path.
  final String? id;
}

/// Manual (this episode) > embedded text > external sidecar > nothing.
SubtitleAutoSelection selectSubtitle({
  String? manualId,
  required List<EmbeddedSubtitleCue> embedded,
  required List<SidecarHit> sidecars,
  required String uiLanguageKey,
}) {
  if (manualId != null && manualId.isNotEmpty) {
    return SubtitleAutoSelection(SubtitleAutoKind.manual, id: manualId);
  }
  final emb = pickEmbedded(embedded, uiLanguageKey);
  if (emb != null) {
    return SubtitleAutoSelection(SubtitleAutoKind.embedded, id: emb.id);
  }
  final side = pickSidecar(sidecars, uiLanguageKey);
  if (side != null) {
    return SubtitleAutoSelection(SubtitleAutoKind.sidecar, id: side.path);
  }
  return const SubtitleAutoSelection(SubtitleAutoKind.none);
}
