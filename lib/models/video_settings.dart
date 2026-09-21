/// Actions bindable to a video-player gesture (left/right double-tap or
/// long-press). Values are persisted by their [storageKey].
enum VideoGestureAction {
  none,
  back10s,
  forward10s,
  back30s,
  forward30s,
  toggleRate2x,
  playPause,
}

extension VideoGestureActionX on VideoGestureAction {
  String get storageKey => switch (this) {
        VideoGestureAction.none => 'none',
        VideoGestureAction.back10s => 'back10s',
        VideoGestureAction.forward10s => 'forward10s',
        VideoGestureAction.back30s => 'back30s',
        VideoGestureAction.forward30s => 'forward30s',
        VideoGestureAction.toggleRate2x => 'toggle2x',
        VideoGestureAction.playPause => 'play_pause',
      };

  String get labelZh => switch (this) {
        VideoGestureAction.none => '无操作',
        VideoGestureAction.back10s => '后退 10 秒',
        VideoGestureAction.forward10s => '前进 10 秒',
        VideoGestureAction.back30s => '后退 30 秒',
        VideoGestureAction.forward30s => '前进 30 秒',
        // Long-press only: hold to speed up, release to restore.
        VideoGestureAction.toggleRate2x => '长按临时加速（松手恢复）',
        VideoGestureAction.playPause => '播放 / 暂停',
      };

  static VideoGestureAction fromStorageKey(String? key) {
    switch (key) {
      case 'back10s':
        return VideoGestureAction.back10s;
      case 'forward10s':
        return VideoGestureAction.forward10s;
      case 'back30s':
        return VideoGestureAction.back30s;
      case 'forward30s':
        return VideoGestureAction.forward30s;
      case 'toggle2x':
        return VideoGestureAction.toggleRate2x;
      case 'play_pause':
        return VideoGestureAction.playPause;
      case 'none':
      default:
        return VideoGestureAction.none;
    }
  }
}

/// Whether subtitles are drawn.
///
/// There is deliberately no "inside the picture" mode any more: the player's
/// control bars hug the picture's edges, so the only predictable place that
/// never fights with them is **just above the bottom control bar** (and at the
/// bottom of the window when the controls are hidden). Size is configurable in
/// 视频播放设置.
enum VideoSubtitlePosition {
  /// Drawn above the bottom control bar (or at the window bottom when hidden).
  visible,

  /// Hidden entirely.
  hidden,
}

extension VideoSubtitlePositionX on VideoSubtitlePosition {
  String get storageKey => switch (this) {
        VideoSubtitlePosition.visible => 'visible',
        VideoSubtitlePosition.hidden => 'hidden',
      };

  String get labelZh => switch (this) {
        VideoSubtitlePosition.visible => '显示字幕',
        VideoSubtitlePosition.hidden => '不显示',
      };

  static VideoSubtitlePosition fromStorageKey(String? key) =>
      key == 'hidden'
          ? VideoSubtitlePosition.hidden
          : VideoSubtitlePosition.visible;
}

/// Default primary (tap) action for a video file in the network library.
enum VideoTapAction {
  /// Stream the video from WebDAV and open the player.
  open,

  /// Enqueue the file for download instead of playing.
  download,
}

extension VideoTapActionX on VideoTapAction {
  String get storageKey => switch (this) {
        VideoTapAction.open => 'open',
        VideoTapAction.download => 'download',
      };

  String get labelZh => switch (this) {
        VideoTapAction.open => '打开视频',
        VideoTapAction.download => '下载',
      };

  static VideoTapAction fromStorageKey(String? key) =>
      key == 'download' ? VideoTapAction.download : VideoTapAction.open;
}

/// Default primary (tap) action for a music file in the network library.
enum MusicTapAction {
  /// Enqueue the file for download.
  download,

  /// Play from cache when available; otherwise fall back to download.
  play,
}

extension MusicTapActionX on MusicTapAction {
  String get storageKey => switch (this) {
        MusicTapAction.download => 'download',
        MusicTapAction.play => 'play',
      };

  String get labelZh => switch (this) {
        MusicTapAction.download => '下载音乐',
        MusicTapAction.play => '播放（已缓存则播放，否则下载）',
      };

  static MusicTapAction fromStorageKey(String? key) =>
      key == 'play' ? MusicTapAction.play : MusicTapAction.download;
}
