import '../l10n/generated/app_localizations.dart';

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

  String label(AppLocalizations l10n) => switch (this) {
    VideoGestureAction.none => l10n.videoGestureNone,
    VideoGestureAction.back10s => l10n.videoGestureBack10s,
    VideoGestureAction.forward10s => l10n.videoGestureForward10s,
    VideoGestureAction.back30s => l10n.videoGestureBack30s,
    VideoGestureAction.forward30s => l10n.videoGestureForward30s,
    // Long-press only: hold to speed up, release to restore.
    VideoGestureAction.toggleRate2x => l10n.videoGestureHoldSpeedUp,
    VideoGestureAction.playPause => l10n.videoGesturePlayPause,
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

  String label(AppLocalizations l10n) => switch (this) {
    VideoSubtitlePosition.visible => l10n.videoSubtitleVisible,
    VideoSubtitlePosition.hidden => l10n.videoSubtitleHidden,
  };

  static VideoSubtitlePosition fromStorageKey(String? key) => key == 'hidden'
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

  String label(AppLocalizations l10n) => switch (this) {
    VideoTapAction.open => l10n.videoTapOpen,
    VideoTapAction.download => l10n.videoTapDownload,
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

  String label(AppLocalizations l10n) => switch (this) {
    MusicTapAction.download => l10n.musicTapDownload,
    MusicTapAction.play => l10n.musicTapPlayCached,
  };

  static MusicTapAction fromStorageKey(String? key) =>
      key == 'play' ? MusicTapAction.play : MusicTapAction.download;
}
