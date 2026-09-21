package com.webdav.webdav_music_player

import android.app.NotificationManager
import android.content.Context
import android.media.session.MediaSessionManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts a small MethodChannel so Flutter can:
 * - send the task to the background (same as Home) without finishing the Activity
 * - probe whether the media notification / MediaSession are alive
 *
 * Do not reference [com.ryanheise.audioservice.AudioService] here: that pulls
 * MediaBrowserServiceCompat into the app compile classpath and breaks release
 * Kotlin builds unless androidx.media is forced onto :app.
 *
 * Must extend [AudioServiceFragmentActivity] (not the plain [AudioServiceActivity]):
 * the plain variant only overrides `provideFlutterEngine()` and leaves
 * `getCachedEngineId()` / `shouldDestroyEngineWithHost()` at their Flutter
 * defaults, so `shouldDestroyEngineWithHost()` resolves to true. Every time
 * this Activity is destroyed (OS reclaiming the backgrounded task, swiping
 * it from Recents, etc.) Flutter then destroys the *shared* FlutterEngine
 * that also hosts MusicAudioHandler — killing the MediaSession and the
 * notification and resetting all in-app playback state. The Fragment
 * variant overrides all three lifecycle hooks so the shared engine survives
 * Activity destruction; only the audio_service FGS/handler controls its
 * lifecycle (see `onTaskRemoved` in MusicAudioHandler).
 */
class MainActivity : AudioServiceFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "moveTaskToBack" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }
                "mediaNotificationDiagnostics" -> {
                    result.success(mediaNotificationDiagnostics())
                }
                "enterPictureInPicture" -> {
                    result.success(enterPictureInPictureModeCompat())
                }
                "isInPictureInPicture" -> {
                    result.success(isInPictureInPictureModeCompat())
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Enter picture-in-picture, guarding for API levels that lack the API. */
    private fun enterPictureInPictureModeCompat(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                enterPictureInPictureMode(
                    android.app.PictureInPictureParams.Builder().build(),
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                @Suppress("DEPRECATION")
                enterPictureInPictureMode()
            } else {
                return false
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun isInPictureInPictureModeCompat(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                @Suppress("DEPRECATION")
                isInPictureInPictureMode
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun mediaNotificationDiagnostics(): Map<String, Any?> {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "com.webdav.webdav_music_player.audio.v4"
        var channelImportance: Int? = null
        var channelExists = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = nm.getNotificationChannel(channelId)
            channelExists = ch != null
            channelImportance = ch?.importance
        }
        val posted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            nm.activeNotifications.any { it.id == AUDIO_SERVICE_NOTIFICATION_ID }
        } else {
            false
        }
        var ourActiveSessionCount = 0
        var mediaSessionActive = false
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val msm = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
                val controllers = msm.getActiveSessions(null)
                for (c in controllers) {
                    if (c.packageName == packageName) {
                        ourActiveSessionCount++
                        val st = c.playbackState
                        if (st != null && st.state != android.media.session.PlaybackState.STATE_NONE) {
                            mediaSessionActive = true
                        }
                    }
                }
            }
        } catch (_: SecurityException) {
            // MEDIA_CONTENT_CONTROL not granted — session count stays 0.
        } catch (_: Exception) {
            // ignore
        }
        val notificationsEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            nm.areNotificationsEnabled()
        } else {
            true
        }
        var channelBlocked = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = nm.getNotificationChannel(channelId)
            channelBlocked = ch != null && ch.importance == NotificationManager.IMPORTANCE_NONE
        }
        return mapOf(
            "audioServiceRunning" to posted,
            "servicePlaying" to mediaSessionActive,
            "mediaSessionActive" to mediaSessionActive,
            "notificationPosted" to posted,
            "notificationsEnabled" to notificationsEnabled,
            "channelId" to channelId,
            "channelExists" to channelExists,
            "channelImportance" to channelImportance,
            "channelBlocked" to channelBlocked,
            "ourActiveSessionCount" to ourActiveSessionCount,
            "sdk" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "servicePresentHint" to posted,
        )
    }

    companion object {
        private const val CHANNEL = "com.webdav.webdav_music_player/app"
        /** Must match AudioService.NOTIFICATION_ID */
        private const val AUDIO_SERVICE_NOTIFICATION_ID = 1124
    }
}
