import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _kAppChannel = MethodChannel(
  'com.webdav.webdav_music_player/app',
);

/// Requests Android Picture-in-Picture for the running activity.
///
/// The video surface (media_kit texture) keeps rendering while the activity is
/// paused, so playback continues in the small window. Returns whether the
/// request was accepted.
Future<bool> enterPictureInPicture() async {
  if (kIsWeb || !Platform.isAndroid) return false;
  try {
    return await _kAppChannel.invokeMethod<bool>('enterPictureInPicture') ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}

/// Whether the activity is currently in Picture-in-Picture mode.
Future<bool> isInPictureInPicture() async {
  if (kIsWeb || !Platform.isAndroid) return false;
  try {
    return await _kAppChannel.invokeMethod<bool>('isInPictureInPicture') ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
