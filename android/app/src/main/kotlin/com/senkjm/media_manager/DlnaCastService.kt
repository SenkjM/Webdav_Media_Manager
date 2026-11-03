package com.senkjm.media_manager

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground service that holds a [WifiManager.MulticastLock] for the duration
 * of a DLNA discovery + cast session.
 *
 * Lifecycle (controlled via Dart [DlnaCastChannel]):
 *   start  → enter foreground, acquire MulticastLock
 *   stop   → release MulticastLock, leave foreground
 *
 * The lock is reference-counted by Android: acquire/release must be paired.
 * We hold exactly one lock for the lifetime of the service. If `start` is
 * called while already running the lock is left alone, but the foreground
 * promotion still happens because the platform demands one per start.
 */
class DlnaCastService : Service() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var running = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Every `startForegroundService()` intent must be answered with a
        // `startForeground()` before this method returns: the platform arms a
        // deadline per start and kills the whole process with
        // `ForegroundServiceDidNotStartInTimeException` when the service goes
        // away first. That is why the promotion happens before *every* branch
        // below — the "already running" no-op and the stop path included. The
        // old order (early return while running, stop without ever promoting)
        // crashed the app on the cast button.
        promoteToForeground()
        if (intent?.action == ACTION_STOP) {
            stopGracefully()
            return START_NOT_STICKY
        }
        if (running) return START_NOT_STICKY
        try {
            acquireMulticastLock()
            running = true
            instance = this
            Log.d(TAG, "DLNA cast service started, MulticastLock acquired")
            flutterChannel?.invokeMethod("onStarted", null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire the DLNA multicast lock", e)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseMulticastLock()
        running = false
        instance = null
        stopForegroundSafely()
        super.onDestroy()
        Log.d(TAG, "DLNA cast service destroyed")
    }

    // ── private helpers ──────────────────────────────────────────────────────

    /**
     * Enters the foreground state, idempotently.
     *
     * Kept separate from the lock bookkeeping because the promotion is required
     * by the platform on *every* start, while `running` only tracks the lock.
     * A failure here must not take the cast path down: the caller still gets a
     * working service (the notification is cosmetic), so it is logged only.
     */
    private fun promoteToForeground() {
        try {
            ensureChannel()
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to enter the foreground state", e)
        }
    }

    private fun stopForegroundSafely() {
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to leave the foreground state", e)
        }
    }

    private fun acquireMulticastLock() {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return
        val lock = wifi.createMulticastLock(LOCK_TAG)
        lock.setReferenceCounted(false)
        lock.acquire()
        multicastLock = lock
    }

    private fun releaseMulticastLock() {
        multicastLock?.let { lock ->
            if (lock.isHeld) lock.release()
        }
        multicastLock = null
    }

    private fun stopGracefully() {
        stopForegroundSafely()
        stopSelf()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val ch = NotificationChannel(
            CHANNEL_ID,
            "DLNA Cast",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Holds Wi-Fi multicast lock during DLNA discovery"
            setShowBadge(false)
        }
        nm.createNotificationChannel(ch)
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("DLNA cast active")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setOngoing(true)
            .setSilent(true)
            .build()

    // ── companion ────────────────────────────────────────────────────────────

    companion object {
        private const val TAG = "DlnaCastService"
        private const val LOCK_TAG = "wdmm:dlna"

        const val CHANNEL = "com.senkjm.media_manager/dlna_cast"
        const val NOTIFICATION_ID = 2002
        const val CHANNEL_ID = "com.senkjm.media_manager.dlna_cast.v1"
        const val ACTION_STOP = "com.senkjm.media_manager.DLNA_CAST_STOP"

        @Volatile var instance: DlnaCastService? = null
        var flutterChannel: MethodChannel? = null

        val isRunning: Boolean get() = instance != null

        fun startIntent(ctx: Context): Intent =
            Intent(ctx, DlnaCastService::class.java)

        fun stopIntent(ctx: Context): Intent =
            Intent(ctx, DlnaCastService::class.java).apply { action = ACTION_STOP }
    }
}
