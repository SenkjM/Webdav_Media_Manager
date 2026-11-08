import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

/// Cross-language contract for library identity.
///
/// The literals below are duplicated **verbatim** in
/// `rust/wdmm-core/crates/wdmm-core/src/track_identity.rs` (module tests). Both
/// sides must change in one commit: a drift here means Rust and Dart would hand
/// out different music ids for the same file, orphaning cached rows and covers.
void main() {
  const goldenPlain = '632274b61f5bebcc7215a15621076969e96b19ed';
  const goldenMessy = 'a14ff280292b3e59249aec8d906503bee71a7e5f';
  const goldenSlice = '9cdbcc6783574188a79c1d7bd8e3732ee68c5a07';
  const goldenCueId = '92db70b74655e4db8ab051f4079e22fa1da1eb75';
  const goldenEmpty = '167d40b282fa3ab3a759bebaa971561c07cf03f4';

  test('music id matches the cross-language golden', () {
    expect(
      musicIdForRemote('Disk A', '/Music/Artist - Song.mp3'),
      goldenPlain,
    );
    expect(
      identityHashStem('Disk A', '/Music/Artist - Song.mp3'),
      goldenPlain.substring(0, 16),
    );
  });

  test('normalization collapses whitespace and slash variants', () {
    expect(
      musicIdForRemote('Disk  B  ', r'\Music//Album/../Track.flac'),
      goldenMessy,
    );
    expect(
      musicIdForRemote('Disk  B  ', r'\Music//Album/../Track.flac'),
      musicIdForRemote('Disk B', '/Music/Album/../Track.flac'),
    );
    expect(normalizeSourceName('  My \t Disk\n'), 'My Disk');
    expect(normalizeSourceName('   '), '');
    expect(normalizeRemotePath(r'Music\A'), '/Music/A');
    expect(normalizeRemotePath('/a//b///c'), '/a/b/c');
    expect(normalizeRemotePath(''), '/');
  });

  test('cue slice and album ids match the cross-language goldens', () {
    expect(
      musicIdForCueSlice('Disk A', '/Music/album.cue', 3),
      goldenSlice,
    );
    expect(cueIdFor('Disk A', '/Music/album.cue'), goldenCueId);
  });

  test('empty paths keep the contract', () {
    expect(musicIdForRemote('', ''), goldenEmpty);
  });
}
