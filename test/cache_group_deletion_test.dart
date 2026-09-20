import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_music_player/utils/track_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cue cache group members clear together in prefs scheme', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final groupId = cueCacheGroupId('acc', '/a.cue');
    final membersKey = 'cache_group_members_${groupId.hashCode}';
    final ids = [
      trackIdentityKey('acc', '/a.cue'),
      trackIdentityKey('acc', '/a.flac'),
    ];
    await prefs.setString(membersKey, jsonEncode(ids));
    expect(jsonDecode(prefs.getString(membersKey)!) as List, hasLength(2));
    await prefs.remove(membersKey);
    expect(prefs.getString(membersKey), isNull);
  });
}
