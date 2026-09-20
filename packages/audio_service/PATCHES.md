# Vendored audio_service patches

This tree is audio_service 0.18.19 with local Android fixes:

1. **Android 14+ FGS type** — `internalStartForeground()` uses
   `ServiceCompat.startForeground(..., FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)`
   when `SDK_INT >= 34`. Untyped `startForeground()` throws
   `MissingForegroundServiceTypeException` when the manifest declares
   `foregroundServiceType="mediaPlayback"` and `targetSdk >= 34`, which
   prevents the MediaStyle notification from ever being posted.

2. **Channel importance** — new notification channels use
   `IMPORTANCE_DEFAULT` instead of `IMPORTANCE_LOW` so the shade entry is
   visible on OEM builds that hide LOW media channels.

Upstream: https://pub.dev/packages/audio_service/versions/0.18.19

3. **Notification category** — set `CATEGORY_TRANSPORT` so OEMs treat the notification as media transport.
