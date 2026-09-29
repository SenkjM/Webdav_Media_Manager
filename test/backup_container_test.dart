import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/library_track.dart';
import 'package:webdav_media_manager/models/playlist.dart';
import 'package:webdav_media_manager/services/credential_vault_codec.dart';
import 'package:webdav_media_manager/services/library_shard_codec.dart';
import 'package:webdav_media_manager/services/playlist_codec.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';
import 'package:webdav_media_manager/utils/wmp_container.dart';

/// The backup archive is a container: META + TRACKS (every row, CUE slices
/// included) + raw COVERS (one own copy per row) + SETTINGS/CUE_ALBUMS as JSON
/// + **embedded container bytes** for CREDENTIALS (a whole `WDMMCV01` document)
/// and PLAYLISTS (one record per playlist, `blob` = that playlist's whole
/// `WDMMPL01` document). This mirrors `BackupService.buildArchiveBytes` without
/// touching the filesystem, so the *format* is pinned even though the service
/// itself needs path_provider.
LibraryTrack _track(
  String path, {
  String source = '123pan',
  int rev = 7,
  String? cueRemotePath,
  int? cueIndex,
}) => LibraryTrack(
  sourceName: source,
  remotePath: path,
  fileName: path.split('/').last,
  title: '标题',
  artist: 'Ado',
  album: '心臓',
  cueRemotePath: cueRemotePath,
  cueTrackIndex: cueIndex,
  rev: rev,
);

Uint8List _blob(int length, int seed) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i + seed) & 0xFF));

/// A one-playlist `WDMMPL01` document, built the way the service builds it.
Uint8List _playlistBytes({String id = 'pl-1', String name = '最爱'}) =>
    PlaylistCodec.encode(
      Playlist(
        id: id,
        name: name,
        updatedAt: DateTime.utc(2026, 9, 20),
        entries: [
          PlaylistEntry(
            sourceName: '123pan',
            remotePath: '/m/a.flac',
            musicId: musicIdForRemote('123pan', '/m/a.flac'),
            title: 'a.flac',
            durationMs: 215000,
          ),
        ],
      ),
      deviceId: 'dev-1',
    );

/// A one-entry `WDMMCV01` document, built the way the service builds it.
Uint8List _vaultBytes() => CredentialVaultCodec.encode(
  const [
    VaultRecord(
      id: 'acc-1',
      name: '123pan',
      providerType: 'webdav',
      url: 'https://nas.example.com',
      username: 'alice',
      password: 'AESGCMv1:x',
      passwordEncrypted: true,
      remotePath: '/',
    ),
  ],
  formatVersion: 2,
  deviceId: 'dev-1',
);

void main() {
  group('backup container', () {
    test('round-trips rows, per-track covers and the embedded container sections', () {
      final tracks = [
        _track('/m/a.flac'),
        _track(
          '/m/disc.cue#cue:2',
          rev: 8,
          cueRemotePath: '/m/disc.cue',
          cueIndex: 2,
        ),
        _track('/m/b.flac', source: 'aliyun', rev: 9),
      ];
      final coverA = _blob(32, 1);
      final coverC = _blob(48, 3);
      final blobs = <Uint8List?>[coverA, null, coverC];

      final records = <Map<int, Object?>>[];
      var coverIndex = 0;
      for (var i = 0; i < tracks.length; i++) {
        final has = blobs[i] != null;
        records.add(
          LibraryShardCodec.trackToRecord(
            tracks[i],
            coverIndex: has ? coverIndex++ : null,
          ),
        );
      }

      final vaultBytes = _vaultBytes();
      final playlistBytes = _playlistBytes();

      final container = WmpContainer.encode(
        {
          WmpSections.meta: encodeRecords([
            {
              WmpMeta.kind: WmpKind.backup,
              WmpMeta.count: tracks.length,
              WmpMeta.deviceId: 'dev-1',
              WmpMeta.note: jsonEncode({
                'format': 'webdav_media_manager_backup',
                'formatVersion': 5,
                'activeAccountId': 'acc-1',
                'passwordEncryption': 'aes-256-gcm',
              }),
            },
          ]),
          WmpSections.tracks: encodeRecords(records),
          WmpSections.covers: buildCoverSection([
            (bytes: coverA, kind: WmpImageKind.jpeg),
            (bytes: coverC, kind: WmpImageKind.webp),
          ]),
          WmpSections.credentials: vaultBytes,
          // 段 id 是单字节（全表 256 个），所以一个歌单一条 record，
          // 不是「一个歌单一个段」。
          WmpSections.playlists: encodeRecords([
            {WmpBackupPlaylist.blob: playlistBytes},
          ]),
          WmpSections.settings: Uint8List.fromList(
            utf8.encode(jsonEncode({'cache_retention': 'one_week'})),
          ),
          WmpSections.cueAlbums: Uint8List.fromList(
            utf8.encode(
              jsonEncode([
                {'cue_id': 'c1', 'title': '专辑'},
              ]),
            ),
          ),
        },
        kind: WmpFileKind.backup,
        rawIds: {
          WmpSections.covers,
          WmpSections.credentials,
          WmpSections.playlists,
        },
      );

      // Sanity: it really is a container, not JSON.
      expect(WmpContainer.looksLikeContainer(container), isTrue);
      expect(WmpContainer.kindOf(container), WmpFileKind.backup);

      final parsed = WmpContainer.fromBytes(container);
      final meta = decodeRecords(
        parsed.readSection(WmpSections.meta)!,
        intTags: kMetaIntTags,
      ).single;
      expect(meta[WmpMeta.kind], WmpKind.backup);
      expect(meta[WmpMeta.count], 3);
      final header = jsonDecode(meta[WmpMeta.note] as String) as Map;
      expect(header['activeAccountId'], 'acc-1');
      expect(header['passwordEncryption'], 'aes-256-gcm');

      final rows = decodeRecords(
        parsed.readSection(WmpSections.tracks)!,
        intTags: kTrackIntTags,
      );
      expect(rows, hasLength(3));
      final coversRaw = parsed.readSection(WmpSections.covers)!;
      final coverTable = parseCoverSection(coversRaw);
      expect(coverTable, hasLength(2));

      final restored = <LibraryTrack>[];
      for (final row in rows) {
        restored.add(LibraryShardCodec.recordToTrack(row));
      }
      expect(restored[0].sourceName, '123pan');
      expect(restored[1].isCueVirtual, isTrue);
      expect(restored[2].sourceName, 'aliyun');
      // Cover indexes point at this row's own blob.
      expect(rows[0][WmpTrack.coverIndex], 0);
      expect(rows[1].containsKey(WmpTrack.coverIndex), isFalse);
      expect(rows[2][WmpTrack.coverIndex], 1);
      expect(coverTable[0].bytesIn(coversRaw), coverA);
      expect(coverTable[1].bytesIn(coversRaw), coverC);
      expect(coverTable[0].kind, WmpImageKind.jpeg);
      expect(coverTable[1].kind, WmpImageKind.webp);

      // CREDENTIALS 段整段就是远端那份 CV 文档，恢复侧直接喂 codec。
      final credsRaw = parsed.readSection(WmpSections.credentials)!;
      expect(credsRaw, vaultBytes);
      expect(WmpContainer.kindOf(credsRaw), WmpFileKind.vault);
      final vault = CredentialVaultCodec.decode(credsRaw);
      expect(vault.entryCount, 1);
      expect(vault.entries.single.name, '123pan');
      expect(vault.entries.single.password, 'AESGCMv1:x');

      // PLAYLISTS 段：每歌单一条 record，blob 是完整 .wdmp 字节。
      final playlistRaw = parsed.readSection(WmpSections.playlists)!;
      final playlistRecords = decodeRecords(
        playlistRaw,
        intTags: const {},
        bytesTags: const {WmpBackupPlaylist.blob},
      );
      expect(playlistRecords, hasLength(1));
      final blob = playlistRecords.single[WmpBackupPlaylist.blob];
      expect(blob, isA<Uint8List>());
      expect(blob! as Uint8List, playlistBytes);
      // 与远端拉取共用同一个解码函数。
      final playlist = PlaylistCodec.decode(blob as Uint8List);
      expect(playlist.playlist.id, 'pl-1');
      expect(playlist.playlist.name, '最爱');
      expect(playlist.entryCount, 1);

      // SETTINGS / CUE_ALBUMS 保持 JSON 不变。
      expect(
        jsonDecode(utf8.decode(parsed.readSection(WmpSections.settings)!))[
            'cache_retention'],
        'one_week',
      );
      expect(
        jsonDecode(utf8.decode(parsed.readSection(WmpSections.cueAlbums)!))[0][
            'title'],
        '专辑',
      );
    });

    test('rawIds：内嵌容器段原样落盘，不二次 deflate', () {
      final vaultBytes = _vaultBytes();
      final playlistBytes = _playlistBytes();

      final sections = {
        WmpSections.credentials: vaultBytes,
        WmpSections.playlists: encodeRecords([
          {WmpBackupPlaylist.blob: playlistBytes},
        ]),
      };

      final raw = WmpContainer.fromBytes(
        WmpContainer.encode(
          sections,
          kind: WmpFileKind.backup,
          rawIds: {WmpSections.credentials, WmpSections.playlists},
        ),
      );
      // raw：段字节原样落盘，连编解码标记都是 raw。
      expect(raw.info(WmpSections.credentials)!.codec, WmpCodec.raw);
      expect(raw.storedBytes(WmpSections.credentials), vaultBytes);
      expect(raw.info(WmpSections.playlists)!.codec, WmpCodec.raw);
      expect(
        raw.storedBytes(WmpSections.playlists),
        sections[WmpSections.playlists],
      );
      expect(raw.readSection(WmpSections.credentials), vaultBytes);

      // 不在 rawIds 里就真的再压一次：内嵌容器本身已经是压缩过的字节，deflate
      // 只能退化成 stored block——字节变了、体积反而更大（每个块多 5 字节头）。
      // 这正是 backup_service 必须把这两段列进 rawIds 的原因。
      final deflated = WmpContainer.fromBytes(
        WmpContainer.encode(sections, kind: WmpFileKind.backup),
      );
      expect(deflated.info(WmpSections.credentials)!.codec, WmpCodec.deflate);
      expect(deflated.storedBytes(WmpSections.credentials), isNot(vaultBytes));
      expect(
        deflated.storedBytes(WmpSections.credentials).length,
        greaterThanOrEqualTo(vaultBytes.length),
        reason: '对已压缩数据再 deflate 至少不会变小（实测为 stored block，更胖）',
      );
      // 但无论压没压，读回来必须逐字节一致。
      expect(deflated.readSection(WmpSections.credentials), vaultBytes);
      expect(
        deflated.readSection(WmpSections.playlists),
        sections[WmpSections.playlists],
      );
    });

    test('a readable JSON export is not mistaken for a container', () {
      final json = utf8.encode(
        jsonEncode({
          'format': 'webdav_media_manager_backup',
          'formatVersion': 5,
          'library': {'tracks': <dynamic>[]},
        }),
      );
      expect(
        WmpContainer.looksLikeContainer(Uint8List.fromList(json)),
        isFalse,
      );
    });

    test('a container body survives the deflate round-trip byte for byte', () {
      final container = WmpContainer.encode({
        WmpSections.settings: Uint8List.fromList(
          utf8.encode(jsonEncode({'a': 1, 'b': '中文'})),
        ),
      }, kind: WmpFileKind.backup);
      final parsed = WmpContainer.fromBytes(container);
      expect(
        jsonDecode(utf8.decode(parsed.readSection(WmpSections.settings)!)),
        {'a': 1, 'b': '中文'},
      );
    });
  });
}
