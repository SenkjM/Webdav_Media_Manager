package com.senkjm.media_manager

import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.MethodChannel

/**
 * dataSync foreground service that keeps a download queue alive after the app
 * leaves the foreground.
 *
 * The foreground notification is the existing download progress notification
 * (id 2001, channel `downloads.v1`). This service posts a minimal ongoing
 * notification once via [startForeground] and then never updates it; Dart's
 * next `flutter_local_notifications` show(2001) replaces the content while the
 * FGS flag stays. The native-owned progress fallback (Kotlin updates 2001 for
 * the whole transfer) is intentionally not implemented — it remains the S4
 * device-test fallback if ColorOS rejects this path.
 *
 * A partial wakelock is held with a timeout and renewed while the service is
 * alive. Android 15+ calls [onTimeout] when the dataSync quota (about 6 h in
 * 24 h) is exhausted; we stop the FGS and tell Dart instead of crashing.
 */
class DownloadKeepAliveService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var foreground = false
    private var timedOut = false
    private var lastStartId = 0
    private val handler = Handler(Looper.getMainLooper())
    private val renewWakeLock = Runnable { refreshWakeLock() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        if (intent?.action == ACTION_STOP) {
            stopGracefully()
            return START_NOT_STICKY
        }
        // Already in the foreground: do not rebuild the notification. Dart owns
        // later updates of this id.
        if (foreground) return START_NOT_STICKY
        val title = intent?.getStringExtra(EXTRA_TITLE)?.takeIf { it.isNotBlank() }
            ?: DEFAULT_TITLE
        val channelId = intent?.getStringExtra(EXTRA_CHANNEL_ID)?.takeIf { it.isNotBlank() }
            ?: DEFAULT_CHANNEL_ID
        val notificationId = intent?.getIntExtra(EXTRA_NOTIFICATION_ID, DEFAULT_NOTIFICATION_ID)
            ?: DEFAULT_NOTIFICATION_ID
        try {
            ensureChannel(channelId)
            val notification = minimalNotification(channelId, title)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    notificationId,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(notificationId, notification)
            }
            foreground = true
            running = true
            acquireWakeLock()
        } catch (e: Exception) {
            foreground = false
            running = false
            releaseWakeLock()
            notifyStartFailed(e)
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    /**
     * API 34+ entry. API 35's `onTimeout(startId, fgsType)` delegates here by
     * default, which is how the dataSync 6 h / 24 h quota reaches us.
     */
    override fun onTimeout(startId: Int) {
        if (timedOut) return
        timedOut = true
        foreground = false
        running = false
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
            // Already left the foreground.
        }
        releaseWakeLock()
        try {
            flutterChannel?.invokeMethod("onTimeout", null)
        } catch (_: Exception) {
            // Engine is gone; stopping the service is still the right outcome.
        }
        stopSelf(startId)
    }

    fun stopGracefully() {
        val id = lastStartId
        foreground = false
        running = false
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
            // Not in the foreground, or already stopped.
        }
        releaseWakeLock()
        stopSelf(id)
    }

    override fun onDestroy() {
        foreground = false
        running = false
        releaseWakeLock()
        if (instance === this) instance = null
        super.onDestroy()
    }

    private fun ensureChannel(channelId: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(channelId) != null) return
        val channel = NotificationChannel(
            channelId,
            "下载进度",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.setSound(null, null)
        channel.enableVibration(false)
        channel.setShowBadge(false)
        channel.description = "下载进度"
        nm.createNotificationChannel(channel)
    }

    private fun minimalNotification(channelId: String, title: String): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_download)
            .setContentTitle(title)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG).apply {
                setReferenceCounted(false)
            }
        }
        handler.removeCallbacks(renewWakeLock)
        refreshWakeLock()
    }

    private fun refreshWakeLock() {
        val lock = wakeLock ?: return
        try {
            lock.acquire(WAKELOCK_TIMEOUT_MS)
        } catch (_: RuntimeException) {
            return
        }
        handler.postDelayed(renewWakeLock, WAKELOCK_RENEW_MS)
    }

    private fun releaseWakeLock() {
        handler.removeCallbacks(renewWakeLock)
        val lock = wakeLock ?: return
        wakeLock = null
        try {
            if (lock.isHeld) lock.release()
        } catch (_: RuntimeException) {
            // Already released.
        }
    }

    private fun notifyStartFailed(error: Exception) {
        try {
            flutterChannel?.invokeMethod(
                "onStartFailed",
                mapOf("error" to "${error.javaClass.simpleName}: ${error.message}"),
            )
        } catch (_: Exception) {
            // Dart already treats a missing callback as best-effort.
        }
    }

    companion object {
        const val CHANNEL = "com.senkjm.media_manager/download_keepalive"
        const val ACTION_STOP = "com.senkjm.media_manager.action.DOWNLOAD_KEEPALIVE_STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_NOTIFICATION_ID = "notificationId"
        const val EXTRA_CHANNEL_ID = "channelId"
        const val DEFAULT_TITLE = "正在下载"
        const val DEFAULT_NOTIFICATION_ID = 2001
        const val DEFAULT_CHANNEL_ID = "com.senkjm.media_manager.downloads.v1"

        private const val WAKELOCK_TAG = "com.senkjm.media_manager:download_keepalive"

        /** Hard ceiling so a leaked service cannot hold the CPU forever. */
        private const val WAKELOCK_TIMEOUT_MS = 10 * 60 * 1000L

        /** Renew well inside the timeout while the queue is still alive. */
        private const val WAKELOCK_RENEW_MS = 4 * 60 * 1000L

        @Volatile
        var running: Boolean = false

        var flutterChannel: MethodChannel? = null

        private var instance: DownloadKeepAliveService? = null

        fun startIntent(
            context: Context,
            title: String,
            notificationId: Int,
            channelId: String,
        ): Intent {
            return Intent(context, DownloadKeepAliveService::class.java).apply {
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_NOTIFICATION_ID, notificationId)
                putExtra(EXTRA_CHANNEL_ID, channelId)
            }
        }

        fun stopIfRunning() {
            instance?.stopGracefully()
        }

        fun diagnostics(context: Context): Map<String, Any?> {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val ignoringBatteryOptimizations = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    pm.isIgnoringBatteryOptimizations(context.packageName)
                } else {
                    true
                }
            } catch (_: Exception) {
                null
            }
            val backgroundRestricted = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    am.isBackgroundRestricted
                } else {
                    null
                }
            } catch (_: Exception) {
                null
            }
            val restrictBackgroundStatus = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    cm.restrictBackgroundStatus
                } else {
                    null
                }
            } catch (_: Exception) {
                null
            }
            val deviceIdleMode = try {
                pm.isDeviceIdleMode
            } catch (_: Exception) {
                null
            }
            return mapOf(
                "ignoringBatteryOptimizations" to ignoringBatteryOptimizations,
                "backgroundRestricted" to backgroundRestricted,
                "restrictBackgroundStatus" to restrictBackgroundStatus,
                "deviceIdleMode" to deviceIdleMode,
                "fgsRunning" to running,
                "sdk" to Build.VERSION.SDK_INT,
            )
        }
    }
}
