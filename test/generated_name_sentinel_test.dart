import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/account_sentinels.dart';
import 'package:webdav_media_manager/models/playlist_sentinels.dart';

void main() {
  test(
    'generated account and playlist names have stable sentinel compatibility',
    () {
      expect(isDefaultServerName(kDefaultServerName), isTrue);
      expect(isDefaultServerName(kLegacyDefaultServerName), isTrue);
      expect(isDefaultServerName('My server'), isFalse);
      expect(isUnnamedPlaylistName(kUnnamedPlaylistName), isTrue);
      expect(isUnnamedPlaylistName(kLegacyUnnamedPlaylistName), isTrue);
      expect(isUnnamedPlaylistName('Favorites'), isFalse);
    },
  );
}
