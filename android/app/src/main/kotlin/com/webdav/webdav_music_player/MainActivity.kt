package com.webdav.webdav_music_player

import android.app.NotificationManager
import android.content.Context
import android.media.session.MediaSessionManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
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
 */
class MainActivity : AudioServiceActivity() {
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
                else -> result.notImplemented()
            }
        }
    }

    private fun mediaNotificationDiagnostics(): Map<String, Any?> {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "com.webdav.webdav_music_player.audio.v3"
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
        return mapOf(
            "audioServiceRunning" to posted,
            "servicePlaying" to mediaSessionActive,
            "mediaSessionActive" to mediaSessionActive,
            "notificationPosted" to posted,
            "notificationsEnabled" to notificationsEnabled,
            "channelId" to channelId,
            "channelExists" to channelExists,
            "channelImportance" to channelImportance,
            "ourActiveSessionCount" to ourActiveSessionCount,
            "sdk" to Build.VERSION.SDK_INT,
            "servicePresentHint" to posted,
        )
    }

    companion object {
        private const val CHANNEL = "com.webdav.webdav_music_player/app"
        /** Must match AudioService.NOTIFICATION_ID */
        private const val AUDIO_SERVICE_NOTIFICATION_ID = 1124
    }
}
