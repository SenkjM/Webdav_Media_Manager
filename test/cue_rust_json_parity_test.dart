import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/services/rust_library_service.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

/// Pure-Dart parity: Android CUE JSON helpers must match Core CueAlbum/CueSlice
/// snake_case shapes documented in crates/wdmm-ffi/docs/API.md and exercised by
/// Core `tests::cue_json_roundtrip_schema`. No FFI / device required.
void main() {
  final now = DateTime.utc(2024, 1, 2, 3, 4, 5);

  test('cueAlbumJson emits Core CueAlbum keys', () {
    final json = RustLibraryService.cueAlbumJson(
      cueId: 'cue-test',
      sourceName: 'test-source',
      cueRemotePath: '/path/album.cue',
      title: 'Test Album',
      performer: 'Test Artist',
      cacheGroupId: 'cache-grp-001',
      createdAt: now,
    );
    expect(json, isNotNull);
    expect(json!.keys.toSet(), {
      'cue_id',
      'source_name',
      'cue_remote_path',
      'title',
      'performer',
      'cache_group_id',
      'created_at',
    });
    expect(json['cue_id'], 'cue-test');
    expect(json['created_at'], now.toUtc().toIso8601String());
  });

  test('cueSliceJson emits Core CueSlice keys and types', () {
    final cuePath = '/path/album.cue';
    final source = 'test-source';
    final track = LibraryTrack(
      musicId: musicIdForCueSlice(source, cuePath, 1),
      sourceName: source,
      remotePath: '/path/track01.virtual',
      fileName: 'track01.mp3',
      title: 'Track 1',
      artist: 'Track Artist',
      albumArtist: 'Album Artist',
      album: 'Test Album',
      durationMs: 240000,
      trackNumber: 1,
      trackTotal: 10,
      discNumber: 1,
      discTotal: 1,
      year: 2024,
      genre: 'Rock',
      bitrate: 320,
      sampleRate: 44100,
      coverPath: '/path/thumb.jpg',
      cueId: cueIdFor(source, cuePath),
      cueRemotePath: cuePath,
      cueTrackIndex: 1,
      audioMusicId: 'audio-test-001',
      audioRemotePath: '/path/album.flac',
      clipStartMs: 0,
      clipEndMs: 240000,
      cacheGroupId: 'cache-grp-001',
      rev: 12345,
      remoteMissing: false,
      lastDownloadedAt: now,
      lastTagReadAt: now,
    );

    expect(track.isCueVirtual, isTrue);
    final json = RustLibraryService.cueSliceJson(track);
    expect(json, isNotNull);

    const required = {
      'music_id',
      'cue_id',
      'audio_music_id',
      'source_name',
      'remote_path',
      'file_name',
      'track_index',
      'title',
      'artist',
      'album_artist',
      'album',
      'duration_ms',
      'track_number',
      'track_total',
      'disc_number',
      'disc_total',
      'year',
      'genre',
      'bitrate',
      'sample_rate',
      'cover_path',
      'audio_remote_path',
      'clip_start_ms',
      'clip_end_ms',
      'cache_group_id',
      'rev',
      'last_downloaded_at',
      'last_tag_read_at',
      'remote_missing',
    };
    expect(json!.keys.toSet(), required);
    expect(json['track_index'], isA<int>());
    expect(json['track_index'], 1);
    expect(json['audio_music_id'], 'audio-test-001');
    expect(json['remote_missing'], 0);
    expect(json['last_downloaded_at'], now.toUtc().toIso8601String());
  });

  test('cueSliceJson rejects non-CUE tracks', () {
    final track = LibraryTrack(
      sourceName: 's',
      remotePath: '/a.mp3',
      fileName: 'a.mp3',
    );
    expect(RustLibraryService.cueSliceJson(track), isNull);
  });
}
