/// How a comic container is opened by default.
///
/// [stream] reads pages over HTTP Range as the reader walks through the
/// archive, so nothing is downloaded up front. [cache] downloads the whole
/// file first: slower to start and it costs the archive's size on disk, but
/// it is the only way in for a driver that cannot answer Range requests.
enum MangaReadMode { stream, cache }

extension MangaReadModeX on MangaReadMode {
  String get storageKey => name;

  static MangaReadMode fromStorageKey(String? key) {
    for (final mode in MangaReadMode.values) {
      if (mode.storageKey == key) return mode;
    }
    return MangaReadMode.stream;
  }
}
