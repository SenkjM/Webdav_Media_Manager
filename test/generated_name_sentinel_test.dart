import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/account_sentinels.dart';
import 'package:webdav_media_manager/models/playlist_sentinels.dart';

void main() {
  test(
    'generated account and playlist names have stable sentinel compatibility',
    () {
      expect(isDefaultServerName(kDefaultServerName), isTrue);
      expect(isDefaultServerName('默认服务器'), isFalse);
      expect(isDefaultServerName('My server'), isFalse);
      expect(isUnnamedPlaylistName(kUnnamedPlaylistName), isTrue);
      expect(isUnnamedPlaylistName('未命名'), isFalse);
      expect(isUnnamedPlaylistName('Favorites'), isFalse);
    },
  );
}
