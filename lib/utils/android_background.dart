import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _kAppChannel = MethodChannel('com.webdav.webdav_music_player/app');

/// Moves the Android task to the background (like pressing Home).
///
/// Does **not** finish the Activity, so Flutter [AppState] / the player stay
/// alive and `audio_service` can keep playing with its media FGS.
///
/// On non-Android platforms this is a no-op (returns without finishing).
Future<void> moveAppToBackground() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    await _kAppChannel.invokeMethod<void>('moveTaskToBack');
  } on MissingPluginException {
    // Hot-reload / tests without the native plugin — leave UI as-is.
  } on PlatformException {
    // Ignore; caller already chose not to finish the app.
  }
}
