/// Shared sync-cursor key prefixes, formerly statics on `LibraryDatabase`.
///
/// Moved to a standalone file so runtime services ([LibraryService],
/// [MangaLibraryService]) do not import the legacy database shell.
class LibrarySyncKeys {
  LibrarySyncKeys._();

  /// `sync_state.remote_key` prefix for music library cursors.
  static const musicCursorPrefix = 'library:';

  /// `sync_state.remote_key` prefix for manga library cursors.
  static const mangaCursorPrefix = 'manga:';
}
