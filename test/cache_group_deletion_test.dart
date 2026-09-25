import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/utils/cache_group_codec.dart';
import 'package:webdav_media_manager/utils/track_identity.dart';

/// Legacy key builders, mirroring the pre-v8 prefs layout exactly:
/// `cache_group_<identity.hashCode>`, `cache_group_members_<groupId.hashCode>`
/// and `cache_access_<identity.hashCode>`.
String legacyGroupKey(String identity) =>
    'cache_group_${identity.hashCode}';

String legacyGroupMembersKey(String groupId) =>
    'cache_group_members_${groupId.hashCode}';

String legacyAccessKey(String identity) => 'cache_access_${identity.hashCode}';

void main() {
  group('cache group member codec', () {
    test('encode / decode round-trips identities', () {
      final ids = [
        trackIdentityKey('acc', '/a.cue'),
        trackIdentityKey('acc', '/a.flac'),
      ];
      final raw = encodeCacheGroupMembers(ids);
      expect(decodeCacheGroupMembers(raw), ids);
    });

    test('decode tolerates null and corrupt values', () {
      expect(decodeCacheGroupMembers(null), isEmpty);
      expect(decodeCacheGroupMembers(''), isEmpty);
      expect(decodeCacheGroupMembers('not-json'), isEmpty);
      expect(decodeCacheGroupMembers('[1,2]'), ['1', '2']); // coerced to string
    });

    test('splitCacheIdentity splits source from remote path', () {
      final id = trackIdentityKey('acc', '/a.flac');
      final parts = splitCacheIdentity(id);
      expect(parts, isNotNull);
      final split = parts!;
      expect(split.sourceName, 'acc');
      expect(split.remotePath, '/a.flac');
    });

    test('legacy key builders match the documented prefixes', () {
      final id = trackIdentityKey('acc', '/a.cue');
      expect(legacyGroupKey(id), startsWith(legacyCacheGroupKeyPrefix));
      expect(
        legacyGroupMembersKey('g'),
        startsWith(legacyCacheGroupMembersKeyPrefix),
      );
      expect(legacyAccessKey(id), startsWith(legacyCacheAccessKeyPrefix));
    });
  });

  group('legacy prefs migration parser', () {
    test('recovers group id via hashCode-suffixed members key', () {
      final groupId = cueCacheGroupId('acc', '/a.cue');
      final ids = [
        trackIdentityKey('acc', '/a.cue'),
        trackIdentityKey('acc', '/a.flac'),
      ];
      final entries = <String, String>{
        legacyGroupKey(ids[0]): groupId,
        legacyGroupKey(ids[1]): groupId,
        legacyGroupMembersKey(groupId): jsonEncode(ids),
        // unrelated access key must not affect group parsing
        legacyAccessKey(ids[0]): '2026-01-01T00:00:00.000',
      };
      final groups = parseLegacyCacheGroups(entries);
      expect(groups, hasLength(1));
      expect(groups.single.groupId, groupId);
      expect(groups.single.members, ids);
    });

    test('skips members with no recoverable group id', () {
      final ids = [
        trackIdentityKey('acc', '/a.cue'),
        trackIdentityKey('acc', '/a.flac'),
      ];
      // No `cache_group_*` path→id entries at all.
      final entries = <String, String>{
        'cache_group_members_12345': jsonEncode(ids),
      };
      expect(parseLegacyCacheGroups(entries), isEmpty);
    });

    test('skips corrupt member lists', () {
      final entries = <String, String>{
        'cache_group_members_12345': 'not-json',
      };
      expect(parseLegacyCacheGroups(entries), isEmpty);
    });

    test('ignores non-legacy keys', () {
      final entries = <String, String>{
        'settings_something': 'v',
        'cache_group_members_12345': 'not-json',
      };
      expect(parseLegacyCacheGroups(entries), isEmpty);
    });

    test('dedupes groups that resolve more than once', () {
      final groupId = cueCacheGroupId('acc', '/a.cue');
      final ids = [
        trackIdentityKey('acc', '/a.cue'),
        trackIdentityKey('acc', '/a.flac'),
      ];
      final entries = <String, String>{
        legacyGroupKey(ids[0]): groupId,
        legacyGroupMembersKey(groupId): jsonEncode(ids),
      };
      final groups = parseLegacyCacheGroups(entries);
      expect(groups, hasLength(1));
    });
  });
}
