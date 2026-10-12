/// How tapping a music row opens playback (settings default or one-shot).
///
/// [cache]: play from music_cache only; missing file → enqueue and wait, never
/// silent-stream. Neighbors warm via the task queue into music_cache.
///
/// [stream]: use music_cache when present; otherwise stream URL. Do not enqueue
/// music_cache or warm neighbors into it. Temporary prefetch_cache is OK.
enum PlayOpenMode { cache, stream }
