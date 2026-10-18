// Copyright (C) 2026 Webdav Media Manager contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import 'package:webdav_media_manager/models/openlist_connection.dart';
import 'package:webdav_media_manager/services/openlist_media_client.dart';

void main() {
  group('OpenListConnection serialization', () {
    test('toMap/fromMap round-trips all auth modes', () {
      for (final mode in OpenListAuthMode.values) {
        final conn = OpenListConnection(
          label: 'server-${mode.storageKey}',
          baseUrl: 'http://10.0.0.1:5244',
          authMode: mode,
          username: mode == OpenListAuthMode.jwt ? 'alice' : '',
          useHashLogin: mode == OpenListAuthMode.jwt,
          sortOrder: 7,
        );
        final restored = OpenListConnection.fromMap(conn.toMap());
        expect(restored.id, conn.id);
        expect(restored.label, conn.label);
        expect(restored.baseUrl, conn.baseUrl);
        expect(restored.authMode, mode);
        expect(restored.username, conn.username);
        expect(restored.useHashLogin, conn.useHashLogin);
        expect(restored.sortOrder, conn.sortOrder);
      }
    });

    test('auth mode storage keys are stable', () {
      expect(OpenListAuthMode.guest.storageKey, 'guest');
      expect(OpenListAuthMode.jwt.storageKey, 'jwt');
      expect(OpenListAuthMode.siteToken.storageKey, 'site_token');
      // Unknown / null keys fall back to guest.
      expect(OpenListAuthModeX.fromKey(null), OpenListAuthMode.guest);
      expect(OpenListAuthModeX.fromKey('nonsense'), OpenListAuthMode.guest);
      expect(OpenListAuthModeX.fromKey('jwt'), OpenListAuthMode.jwt);
      expect(OpenListAuthModeX.fromKey('site_token'), OpenListAuthMode.siteToken);
    });

    test('copyWith preserves identity', () {
      final conn = OpenListConnection(
        label: 'old',
        baseUrl: 'http://a',
        authMode: OpenListAuthMode.guest,
      );
      final next = conn.copyWith(label: 'new', authMode: OpenListAuthMode.jwt);
      expect(next.id, conn.id);
      expect(next.label, 'new');
      expect(next.authMode, OpenListAuthMode.jwt);
      expect(next.baseUrl, 'http://a');
    });

    test('use_hash_login persists as int 0/1 and back', () {
      final plain = OpenListConnection(
        label: 'p',
        baseUrl: 'http://a',
        useHashLogin: false,
      );
      expect(plain.toMap()['use_hash_login'], 0);
      expect(
        OpenListConnection.fromMap(plain.toMap()).useHashLogin,
        isFalse,
      );
      final hashed = OpenListConnection(
        label: 'h',
        baseUrl: 'http://a',
        useHashLogin: true,
      );
      expect(hashed.toMap()['use_hash_login'], 1);
      expect(
        OpenListConnection.fromMap(hashed.toMap()).useHashLogin,
        isTrue,
      );
    });
  });

  group('OpenListMediaItem parsing', () {
    test('fromJson maps all fields and tolerates missing ones', () {
      final item = OpenListMediaItem.fromJson({
        'id': 42,
        'media_type': 'music',
        'file_name': 'track.flac',
        'scraped_name': '夜曲',
        'cover': 'http://x/cover.jpg',
        'album_name': '十一月的萧邦',
        'album_artist': '周杰伦',
        'duration': 235,
        'rating': 8.5,
        'genre': '流行',
        'release_date': '2005-11-01',
      });
      expect(item.id, 42);
      expect(item.mediaType, 'music');
      expect(item.fileName, 'track.flac');
      expect(item.displayName, '夜曲');
      expect(item.subtitle, '十一月的萧邦');
      expect(item.duration, 235);
      expect(item.rating, 8.5);
    });

    test('displayName falls back to file name without extension', () {
      final item =
          OpenListMediaItem.fromJson({'id': 1, 'file_name': 'movie.mkv'});
      expect(item.displayName, 'movie');
    });

    test('fromJson tolerates an empty payload', () {
      final item = OpenListMediaItem.fromJson({});
      expect(item.id, 0);
      expect(item.fileName, '');
      expect(item.displayName, '');
    });

    test('toJson/fromJson round-trips', () {
      final item = OpenListMediaItem.fromJson({
        'id': 7,
        'media_type': 'video',
        'file_name': 'ep01.mkv',
        'scraped_name': '第一集',
        'video_type': 'tv',
      });
      final back = OpenListMediaItem.fromJson(item.toJson());
      expect(back.id, item.id);
      expect(back.mediaType, item.mediaType);
      expect(back.fileName, item.fileName);
      expect(back.scrapedName, item.scrapedName);
      expect(back.videoType, item.videoType);
    });
  });

  group('OpenListMediaClient helpers', () {
    test('sha256Hex matches a known empty-string digest', () {
      // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb924...
      expect(
        OpenListMediaClient.sha256Hex(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('sha256Hex is stable for a fixed input', () {
      const input = 'hunter2';
      final a = OpenListMediaClient.sha256Hex(input);
      final b = OpenListMediaClient.sha256Hex(input);
      expect(a, b);
      expect(a.length, 64);
      expect(a, isNot(equals(input)));
    });
  });

  group('OpenListApiException', () {
    test('carries message and optional status code', () {
      const e = OpenListApiException('认证失败', statusCode: 401);
      expect(e.message, '认证失败');
      expect(e.statusCode, 401);
      expect(e.toString(), contains('认证失败'));
      expect(e.toString(), contains('401'));
    });

    test('omits status code in toString when null', () {
      const e = OpenListApiException('响应格式错误');
      expect(e.toString(), 'OpenListApiException: 响应格式错误');
    });
  });
}
