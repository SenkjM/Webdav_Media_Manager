package com.senkjm.media_manager

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
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
 *   start  → acquire MulticastLock, enter foreground with a silent notification
 *   stop   → release MulticastLock, stop foreground
 *
 * The lock is reference-counted by Android: acquire/release must be paired.
 * We hold exactly one lock for the lifetime of the service. If `start` is
 * called while already running the duplicate start is a no-op (idempotent).
 */
class DlnaCastService : Service() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var running = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopGracefully()
            return START_NOT_STICKY
        }
        if (running) return START_NOT_STICKY
        try {
            ensureChannel()
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            acquireMulticastLock()
            running = true
            instance = this
            Log.d(TAG, "DLNA cast service started, MulticastLock acquired")
            flutterChannel?.invokeMethod("onStarted", null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start DLNA cast service", e)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseMulticastLock()
        running = false
        instance = null
        super.onDestroy()
        Log.d(TAG, "DLNA cast service destroyed")
    }

    // ── private helpers ──────────────────────────────────────────────────────

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
        stopForeground(STOP_FOREGROUND_REMOVE)
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
