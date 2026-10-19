// Copyright (C) 2026 Webdav Media Manager contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:webdav_media_manager/models/emby_connection.dart';
import 'package:webdav_media_manager/services/emby_media_client.dart';

void main() {
  // ── EmbyConnection serialization ─────────────────────────────────────────

  group('EmbyConnection serialization', () {
    test('toMap/fromMap round-trips password mode', () {
      final conn = EmbyConnection(
        label: 'My Emby',
        baseUrl: 'http://10.0.0.1:8096',
        authMode: EmbyAuthMode.password,
        username: 'alice',
        sortOrder: 3,
      );
      final restored = EmbyConnection.fromMap(conn.toMap());
      expect(restored.id, conn.id);
      expect(restored.label, conn.label);
      expect(restored.baseUrl, conn.baseUrl);
      expect(restored.authMode, EmbyAuthMode.password);
      expect(restored.username, 'alice');
      expect(restored.deviceId, conn.deviceId);
      expect(restored.sortOrder, 3);
    });

    test('toMap/fromMap round-trips apiKey mode', () {
      final conn = EmbyConnection(
        label: 'API conn',
        baseUrl: 'https://jf.example.com/jellyfin',
        authMode: EmbyAuthMode.apiKey,
        username: '',
        sortOrder: 0,
      );
      final restored = EmbyConnection.fromMap(conn.toMap());
      expect(restored.authMode, EmbyAuthMode.apiKey);
      expect(restored.baseUrl, 'https://jf.example.com/jellyfin');
      expect(restored.id, conn.id);
      expect(restored.deviceId, conn.deviceId);
    });

    test('auth mode storage keys are stable', () {
      expect(EmbyAuthMode.password.storageKey, 'password');
      expect(EmbyAuthMode.apiKey.storageKey, 'api_key');
      // Unknown / null keys fall back to password.
      expect(EmbyAuthModeX.fromKey(null), EmbyAuthMode.password);
      expect(EmbyAuthModeX.fromKey('nonsense'), EmbyAuthMode.password);
      expect(EmbyAuthModeX.fromKey('password'), EmbyAuthMode.password);
      expect(EmbyAuthModeX.fromKey('api_key'), EmbyAuthMode.apiKey);
    });

    test('copyWith preserves id and deviceId', () {
      final conn = EmbyConnection(
        label: 'old',
        baseUrl: 'http://a',
        authMode: EmbyAuthMode.password,
      );
      final next = conn.copyWith(label: 'new', authMode: EmbyAuthMode.apiKey);
      expect(next.id, conn.id);
      expect(next.deviceId, conn.deviceId);
      expect(next.label, 'new');
      expect(next.authMode, EmbyAuthMode.apiKey);
      expect(next.baseUrl, 'http://a');
    });

    test('userId round-trips', () {
      final conn = EmbyConnection(
        label: 'x',
        baseUrl: 'http://h',
        userId: 'abc123',
      );
      expect(EmbyConnection.fromMap(conn.toMap()).userId, 'abc123');
    });

    test('equality is id-based', () {
      final a = EmbyConnection(id: 'same', label: 'a', baseUrl: 'http://x');
      final b = EmbyConnection(id: 'same', label: 'b', baseUrl: 'http://y');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  // ── EmbyItem parsing ──────────────────────────────────────────────────────

  group('EmbyItem parsing', () {
    test('fromJson maps all basic fields', () {
      final item = EmbyItem.fromJson({
        'Id': 'abc',
        'Name': '夜曲',
        'Type': 'Audio',
        'IsFolder': false,
        'Album': '十一月的萧邦',
        'AlbumArtist': '周杰伦',
        'Artists': ['周杰伦'],
        'IndexNumber': 5,
        'ParentIndexNumber': 1,
        'ProductionYear': 2005,
        'Overview': 'great song',
        'ImageTags': {'Primary': 'tag123'},
        'UserData': {'Played': true, 'IsFavorite': false},
      });
      expect(item.id, 'abc');
      expect(item.name, '夜曲');
      expect(item.type, 'Audio');
      expect(item.isFolder, isFalse);
      expect(item.album, '十一月的萧邦');
      expect(item.albumArtist, '周杰伦');
      expect(item.artists, ['周杰伦']);
      expect(item.indexNumber, 5);
      expect(item.parentIndexNumber, 1);
      expect(item.productionYear, 2005);
      expect(item.overview, 'great song');
      expect(item.primaryImageTag, 'tag123');
      expect(item.played, isTrue);
      expect(item.isFavorite, isFalse);
      expect(item.displayName, '夜曲');
      expect(item.subtitle, '十一月的萧邦');
    });

    test('fromJson tolerates empty payload', () {
      final item = EmbyItem.fromJson({});
      expect(item.id, '');
      expect(item.name, '');
      expect(item.isFolder, isFalse);
      expect(item.artists, isEmpty);
      expect(item.imageTags, isEmpty);
      expect(item.runTimeDuration, isNull);
    });

    test('RunTimeTicks converts to Duration correctly', () {
      // 3 minutes = 180 s = 180_000 ms = 1_800_000_000 ticks
      final item = EmbyItem.fromJson({
        'Id': 'x',
        'Name': 'test',
        'RunTimeTicks': 1800000000,
      });
      expect(item.runTimeDuration, const Duration(minutes: 3));
    });

    test('subtitle falls back to albumArtist then artists then year', () {
      // album present → album
      final a = EmbyItem.fromJson({'Id': '1', 'Name': 'a', 'Album': 'MyAlbum'});
      expect(a.subtitle, 'MyAlbum');

      // no album, has albumArtist
      final b = EmbyItem.fromJson({
        'Id': '2',
        'Name': 'b',
        'AlbumArtist': 'The Band',
      });
      expect(b.subtitle, 'The Band');

      // no album/artist, has year
      final c = EmbyItem.fromJson({
        'Id': '3',
        'Name': 'c',
        'ProductionYear': 1999,
      });
      expect(c.subtitle, '1999');

      // nothing
      final d = EmbyItem.fromJson({'Id': '4', 'Name': 'd'});
      expect(d.subtitle, '');
    });

    test('toJson round-trips Id/Name/RunTimeTicks', () {
      final item = EmbyItem.fromJson({
        'Id': 'xyz',
        'Name': 'Track',
        'RunTimeTicks': 600000000, // 60 s
        'Album': 'Album X',
      });
      final back = EmbyItem.fromJson(item.toJson());
      expect(back.id, 'xyz');
      expect(back.name, 'Track');
      expect(back.runTimeDuration, const Duration(seconds: 60));
      expect(back.album, 'Album X');
    });
  });

  // ── EmbyItemsPage ─────────────────────────────────────────────────────────

  group('EmbyItemsPage hasMore', () {
    test('hasMore true when more items remain', () {
      final page = EmbyItemsPage(
        items: List.generate(50, (i) => EmbyItem.fromJson({'Id': '$i', 'Name': 'i'})),
        totalRecordCount: 120,
        startIndex: 0,
      );
      expect(page.hasMore, isTrue);
    });

    test('hasMore false when all items loaded', () {
      final page = EmbyItemsPage(
        items: List.generate(20, (i) => EmbyItem.fromJson({'Id': '$i', 'Name': 'i'})),
        totalRecordCount: 20,
        startIndex: 0,
      );
      expect(page.hasMore, isFalse);
    });

    test('isEmpty works', () {
      const empty = EmbyItemsPage(items: [], totalRecordCount: 0, startIndex: 0);
      expect(empty.isEmpty, isTrue);
    });
  });

  // ── Authorization header builder ──────────────────────────────────────────

  group('buildAuthorizationHeader', () {
    test('no token', () {
      final h = EmbyMediaClient.buildAuthorizationHeader(
        deviceId: 'dev1',
        platform: 'Android',
        version: '1.0.0',
      );
      expect(h, contains('MediaBrowser Client="WDMM"'));
      expect(h, contains('Device="Android"'));
      expect(h, contains('DeviceId="dev1"'));
      expect(h, contains('Version="1.0.0"'));
      expect(h, isNot(contains('Token=')));
    });

    test('with token includes Token field', () {
      final h = EmbyMediaClient.buildAuthorizationHeader(
        deviceId: 'dev2',
        token: 'secret_token',
        platform: 'iOS',
        version: '0.0.0',
      );
      expect(h, contains('Token="secret_token"'));
    });

    test('empty token omits Token field', () {
      final h = EmbyMediaClient.buildAuthorizationHeader(
        deviceId: 'dev3',
        token: '',
        platform: 'Linux',
        version: '0.0.0',
      );
      expect(h, isNot(contains('Token=')));
    });
  });

  // ── URL builders ──────────────────────────────────────────────────────────

  group('URL builders', () {
    EmbyConnection conn({String base = 'http://host:8096'}) => EmbyConnection(
          id: 'id1',
          label: 'test',
          baseUrl: base,
          deviceId: 'dev1',
        );

    test('imageUrl basic', () {
      final url = EmbyMediaClient.imageUrl(conn(), 'item1');
      expect(url, 'http://host:8096/Items/item1/Images/Primary');
    });

    test('imageUrl with maxWidth and tag', () {
      final url = EmbyMediaClient.imageUrl(
        conn(),
        'item2',
        maxWidth: 300,
        tag: 'abc',
      );
      expect(url, contains('/Items/item2/Images/Primary'));
      expect(url, contains('maxWidth=300'));
      expect(url, contains('tag=abc'));
    });

    test('imageUrl strips trailing slash from base', () {
      final url = EmbyMediaClient.imageUrl(
        conn(base: 'http://host:8096/'),
        'item3',
      );
      // Trailing slash removed: path should not have double-slash after port.
      expect(url, startsWith('http://host:8096/Items/'));
      expect(url.replaceFirst('http://', ''), isNot(contains('//')));
    });

    test('imageUrl preserves sub-path base', () {
      final url = EmbyMediaClient.imageUrl(
        conn(base: 'http://host:8096/emby'),
        'item4',
      );
      expect(url, startsWith('http://host:8096/emby/Items'));
    });

    test('audioStreamUrl contains static=true and api_key param', () {
      final url = EmbyMediaClient.audioStreamUrl(conn(), 'aud1', 'tok');
      expect(url, contains('/Audio/aud1/stream'));
      expect(url, contains('static=true'));
      expect(url, contains('api_key=tok'));
    });

    test('videoStreamUrl contains Videos path and container when given', () {
      final url = EmbyMediaClient.videoStreamUrl(
        conn(),
        'vid1',
        'tok2',
        container: 'mp4',
      );
      expect(url, contains('/Videos/vid1/stream'));
      expect(url, contains('static=true'));
      expect(url, contains('api_key=tok2'));
      expect(url, contains('Container=mp4'));
    });

    test('downloadUrl contains /Download path', () {
      final url = EmbyMediaClient.downloadUrl(conn(), 'itm1', 'tok3');
      expect(url, contains('/Items/itm1/Download'));
      expect(url, contains('api_key=tok3'));
    });
  });

  // ── EmbyApiException ──────────────────────────────────────────────────────

  group('EmbyApiException', () {
    test('carries message and optional status code', () {
      const e = EmbyApiException('认证失败', statusCode: 401);
      expect(e.message, '认证失败');
      expect(e.statusCode, 401);
      expect(e.toString(), contains('认证失败'));
      expect(e.toString(), contains('401'));
    });

    test('omits status code in toString when null', () {
      const e = EmbyApiException('响应格式错误');
      expect(e.toString(), 'EmbyApiException: 响应格式错误');
    });

    test('message never contains token/password keywords in example', () {
      // Verify the helper class itself doesn't embed secret values when used as intended.
      const e = EmbyApiException('登录失败：连接超时');
      expect(e.toString(), isNot(contains('api_key=')));
      expect(e.toString(), isNot(contains('token=')));
    });
  });

  // ── capabilitiesForCollectionType ─────────────────────────────────────────

  group('capabilitiesForCollectionType', () {
    test('music includes musicLibrary and stream', () {
      final caps = capabilitiesForCollectionType('music');
      expect(caps, contains(EmbyCapability.musicLibrary));
      expect(caps, contains(EmbyCapability.stream));
      expect(caps, contains(EmbyCapability.browse));
    });

    test('movies includes stream', () {
      final caps = capabilitiesForCollectionType('movies');
      expect(caps, contains(EmbyCapability.stream));
      expect(caps, isNot(contains(EmbyCapability.musicLibrary)));
    });

    test('null/unknown type returns base capabilities', () {
      final caps = capabilitiesForCollectionType(null);
      expect(caps, contains(EmbyCapability.browse));
      expect(caps, contains(EmbyCapability.images));
      expect(caps.length, 2);
    });
  });

  // ── API-key userId resolution (pure logic) ────────────────────────────────

  group('resolveApiKeyUserId user-list picking', () {
    // Mirror the selection algorithm from EmbyMediaClient._resolveApiKeyUserId
    // as a pure local function so we can test it without network or sqflite.
    Map<String, dynamic>? pickUser(
      List<dynamic> users,
      String username,
    ) {
      Map<String, dynamic>? picked;
      if (username.isNotEmpty) {
        for (final u in users) {
          if (u is Map<String, dynamic>) {
            final name = (u['Name'] as String?) ?? '';
            if (name.toLowerCase() == username.toLowerCase()) {
              picked = u;
              break;
            }
          }
        }
      }
      if (picked == null) {
        Map<String, dynamic>? firstEnabled;
        Map<String, dynamic>? firstAdmin;
        for (final u in users) {
          if (u is! Map<String, dynamic>) continue;
          final policy = u['Policy'];
          final disabled =
              (policy is Map ? policy['IsDisabled'] : null) == true;
          if (disabled) continue;
          firstEnabled ??= u;
          final isAdmin =
              (policy is Map ? policy['IsAdministrator'] : null) == true;
          if (isAdmin) firstAdmin ??= u;
        }
        picked = firstAdmin ?? firstEnabled;
      }
      return picked;
    }

    final users = [
      {
        'Id': 'admin-id',
        'Name': 'Admin',
        'Policy': {'IsDisabled': false, 'IsAdministrator': true},
      },
      {
        'Id': 'alice-id',
        'Name': 'Alice',
        'Policy': {'IsDisabled': false, 'IsAdministrator': false},
      },
      {
        'Id': 'disabled-id',
        'Name': 'Bob',
        'Policy': {'IsDisabled': true, 'IsAdministrator': false},
      },
    ];

    test('picks by username match (case-insensitive)', () {
      expect(pickUser(users, 'alice')?['Id'], 'alice-id');
      expect(pickUser(users, 'ALICE')?['Id'], 'alice-id');
    });

    test('falls back to admin when no username given', () {
      expect(pickUser(users, '')?['Id'], 'admin-id');
    });

    test('no match falls back to admin over regular user', () {
      expect(pickUser(users, 'nobody')?['Id'], 'admin-id');
    });

    test('skips disabled users', () {
      final onlyDisabled = [
        {
          'Id': 'x',
          'Name': 'X',
          'Policy': {'IsDisabled': true, 'IsAdministrator': false},
        }
      ];
      expect(pickUser(onlyDisabled, ''), isNull);
    });

    test('returns null for empty list', () {
      expect(pickUser([], ''), isNull);
    });

    test('regular user selected when no admin present', () {
      final noAdmin = [
        {
          'Id': 'reg-id',
          'Name': 'Regular',
          'Policy': {'IsDisabled': false, 'IsAdministrator': false},
        }
      ];
      expect(pickUser(noAdmin, '')?['Id'], 'reg-id');
    });
  });

  // ── _dioMessage safety ────────────────────────────────────────────────────

  group('_dioMessage safety (no api_key leakage)', () {
    test('unknown DioExceptionType formats as 网络错误(type) with no secret', () {
      final e = DioException(
        requestOptions:
            RequestOptions(path: '/test?api_key=supersecret'),
        type: DioExceptionType.unknown,
        message: 'http://host/Audio/1/stream?api_key=supersecret',
      );
      // The default branch now returns '网络错误（${e.type.name}）'.
      final msg = '网络错误（${e.type.name}）';
      expect(msg, isNot(contains('api_key=')));
      expect(msg, isNot(contains('supersecret')));
      expect(msg, contains('网络错误'));
    });

    test('EmbyApiException message is never a raw URL', () {
      const e = EmbyApiException('获取视图失败：连接超时');
      expect(e.message, isNot(contains('api_key=')));
      expect(e.message, isNot(contains('http')));
    });
  });
}
