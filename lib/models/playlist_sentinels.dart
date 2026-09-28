/// Stable non-user-facing keys used for generated playlist names.
const kUnnamedPlaylistName = '__wdmm_unnamed_playlist__';
const kLegacyUnnamedPlaylistName = '未命名';

bool isUnnamedPlaylistName(String value) =>
    value == kUnnamedPlaylistName || value == kLegacyUnnamedPlaylistName;
