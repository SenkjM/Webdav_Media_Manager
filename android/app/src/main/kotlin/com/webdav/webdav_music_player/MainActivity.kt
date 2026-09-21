package com.webdav.webdav_music_player

import android.app.Activity
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.media.session.MediaSessionManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * Hosts a small MethodChannel so Flutter can:
 * - send the task to the background (same as Home) without finishing the Activity
 * - probe whether the media notification / MediaSession are alive
 * - export files into the system gallery / Downloads via MediaStore
 * - observe picture-in-picture transitions
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
    private var appChannel: MethodChannel? = null

    /** Pending SAF pick result; the platform allows only one dialog at a time. */
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        )
        appChannel = channel
        channel.setMethodCallHandler { call, result ->
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
                "saveToGallery" -> {
                    val args = call.arguments as? Map<*, *>
                    result.success(
                        runCatching {
                            saveToGallery(
                                args?.get("path") as? String,
                                args?.get("fileName") as? String,
                                args?.get("mimeType") as? String,
                                args?.get("album") as? String,
                            )
                        }.getOrElse { e ->
                            mapOf("ok" to false, "error" to (e.message ?: e.toString()))
                        },
                    )
                }
                "saveToDownloads" -> {
                    val args = call.arguments as? Map<*, *>
                    result.success(
                        runCatching {
                            saveToDownloads(
                                args?.get("path") as? String,
                                args?.get("fileName") as? String,
                                args?.get("mimeType") as? String,
                                args?.get("subdir") as? String,
                            )
                        }.getOrElse { e ->
                            mapOf("ok" to false, "error" to (e.message ?: e.toString()))
                        },
                    )
                }
                "pickFile" -> {
                    val args = call.arguments as? Map<*, *>
                    pickFile(args?.get("mimeType") as? String, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Opens the system document picker (SAF) and copies the chosen document into
     * the app cache so Dart gets a readable path. The copy is deleted by the
     * caller after import.
     */
    private fun pickFile(mimeType: String?, result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "已有文件选择正在进行", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType?.takeIf { it.isNotBlank() } ?: "*/*"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf("application/zip", "application/octet-stream", "*/*"),
                )
            }
        }
        try {
            startActivityForResult(intent, REQUEST_PICK_FILE)
        } catch (e: Exception) {
            pendingPick = null
            result.error("unavailable", e.message ?: "无法打开文件选择器", null)
        }
    }

    @Deprecated("Flutter embedding still routes SAF results through onActivityResult")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_FILE) return
        val result = pendingPick ?: return
        pendingPick = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            result.success(null)
            return
        }
        result.success(
            runCatching { copyPickedFile(uri) }.getOrElse { e ->
                mapOf("ok" to false, "error" to (e.message ?: e.toString()))
            },
        )
    }

    private fun copyPickedFile(uri: Uri): Map<String, Any?> {
        val name = displayNameFor(uri)
        val dir = File(cacheDir, "imports")
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("无法创建导入缓存目录")
        }
        val target = File(dir, name)
        contentResolver.openInputStream(uri).use { input ->
            if (input == null) throw IllegalStateException("无法读取所选文件")
            FileOutputStream(target).use { out -> input.copyTo(out) }
        }
        return mapOf(
            "ok" to true,
            "path" to target.absolutePath,
            "fileName" to name,
            "size" to target.length(),
        )
    }

    private fun displayNameFor(uri: Uri): String {
        var name: String? = null
        try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && cursor.moveToFirst()) name = cursor.getString(idx)
            }
        } catch (_: Exception) {
            // Fall through to the URI path segment.
        }
        val raw = name?.takeIf { it.isNotBlank() }
            ?: uri.lastPathSegment?.substringAfterLast('/')
            ?: "import.wmpbak"
        return sanitizeName(raw)
    }

    /**
     * Called by the system on every PiP transition. Mirrors the flag to Dart so
     * the player screen can hide its overlay controls in the small window.
     */
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        appChannel?.invokeMethod("pictureInPictureChanged", isInPictureInPictureMode)
    }

    // ---------------------------------------------------------------------
    // MediaStore / Downloads export
    // ---------------------------------------------------------------------

    /** Resolve the exported file name from the caller's name, keeping the extension. */
    private fun resolveFileName(filePath: File, name: String?): String {
        val raw = (name ?: "").trim().ifEmpty { filePath.name }
        if (raw.contains('.')) return raw
        val ext = filePath.extension
        return if (ext.isEmpty()) raw else "$raw.$ext"
    }

    private fun sanitizeName(name: String): String {
        val cleaned = name.replace(Regex("""[\\/:*?"<>|\u0000-\u001f]"""), "_").trim()
        return cleaned.ifEmpty { "file" }
    }

    private fun subdirOrDefault(value: String?, fallback: String): String =
        (value ?: "").trim().trim('/').ifEmpty { fallback }

    /**
     * Copy [path] into the system gallery.
     *
     * The gallery is the union of MediaStore's Images + Video collections, so
     * audio files (which are not gallery media) land in the audio collection
     * instead — see the `collection` key in the result.
     */
    private fun saveToGallery(
        path: String?,
        name: String?,
        mimeType: String?,
        album: String?,
    ): Map<String, Any?> {
        val src = File(path ?: "")
        if (!src.exists()) return mapOf("ok" to false, "error" to "源文件不存在")
        val fileName = sanitizeName(resolveFileName(src, name))
        val mime = (mimeType ?: "").trim().ifEmpty { mimeFor(src) }
        val dir = subdirOrDefault(album, "WebDAVMusic")
        val kind = mediaKindFor(mime, fileName)
        val collection = when (kind) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            -> "gallery"
            else -> "audio"
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    when (kind) {
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI ->
                            "${Environment.DIRECTORY_PICTURES}/$dir"
                        MediaStore.Video.Media.EXTERNAL_CONTENT_URI ->
                            "${Environment.DIRECTORY_MOVIES}/$dir"
                        else -> "${Environment.DIRECTORY_MUSIC}/$dir"
                    },
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(kind, values)
                ?: return mapOf("ok" to false, "error" to "MediaStore 插入失败")
            try {
                resolver.openOutputStream(uri).use { out ->
                    if (out == null) throw IllegalStateException("无法打开输出流")
                    FileInputStream(src).use { input -> input.copyTo(out) }
                }
                resolver.update(
                    uri,
                    ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                    null,
                    null,
                )
            } catch (e: Exception) {
                runCatching { resolver.delete(uri, null, null) }
                throw e
            }
            return mapOf(
                "ok" to true,
                "uri" to uri.toString(),
                "fileName" to fileName,
                "collection" to collection,
                "location" to "系统相册",
            )
        }

        val base = when (kind) {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI -> Environment.DIRECTORY_PICTURES
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI -> Environment.DIRECTORY_MOVIES
            else -> Environment.DIRECTORY_MUSIC
        }
        val targetDir = File(Environment.getExternalStoragePublicDirectory(base), dir)
        val written = writePublicFile(src, targetDir, fileName)
        MediaScannerConnection.scanFile(
            this,
            arrayOf(written.absolutePath),
            arrayOf(mime),
            null,
        )
        return mapOf(
            "ok" to true,
            "uri" to "file://${written.absolutePath}",
            "fileName" to written.name,
            "collection" to collection,
            "location" to "系统相册",
        )
    }

    /** Copy [path] into the public Downloads collection (local backup export). */
    private fun saveToDownloads(
        path: String?,
        name: String?,
        mimeType: String?,
        subdir: String?,
    ): Map<String, Any?> {
        val src = File(path ?: "")
        if (!src.exists()) return mapOf("ok" to false, "error" to "源文件不存在")
        val fileName = sanitizeName(resolveFileName(src, name))
        val mime = (mimeType ?: "").trim().ifEmpty { "application/octet-stream" }
        val dir = subdirOrDefault(subdir, "WebDAVMusic")
        val relative = "${Environment.DIRECTORY_DOWNLOADS}/$dir"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return mapOf("ok" to false, "error" to "MediaStore 插入失败")
            try {
                resolver.openOutputStream(uri).use { out ->
                    if (out == null) throw IllegalStateException("无法打开输出流")
                    FileInputStream(src).use { input -> input.copyTo(out) }
                }
                resolver.update(
                    uri,
                    ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                    null,
                    null,
                )
            } catch (e: Exception) {
                runCatching { resolver.delete(uri, null, null) }
                throw e
            }
            return mapOf(
                "ok" to true,
                "uri" to uri.toString(),
                "fileName" to fileName,
                "location" to "下载目录/$dir",
                "path" to "$relative/$fileName",
            )
        }

        val targetDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), dir)
        val written = writePublicFile(src, targetDir, fileName)
        MediaScannerConnection.scanFile(this, arrayOf(written.absolutePath), arrayOf(mime), null)
        return mapOf(
            "ok" to true,
            "uri" to "file://${written.absolutePath}",
            "fileName" to written.name,
            "location" to "下载目录/$dir",
            "path" to written.absolutePath,
        )
    }

    /**
     * Legacy (API < 29) public-directory write. Returns the file that must be
     * scanned into MediaStore; [File.createNewFile] fails when the file already
     * exists, so a numeric suffix is added instead of silently overwriting.
     */
    private fun writePublicFile(src: File, dir: File, fileName: String): File {
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("无法创建目录：${dir.absolutePath}")
        }
        var target = File(dir, fileName)
        if (target.exists()) {
            val dot = fileName.lastIndexOf('.')
            val stem = if (dot > 0) fileName.substring(0, dot) else fileName
            val ext = if (dot > 0) fileName.substring(dot) else ""
            var n = 1
            while (target.exists() && n < 1000) {
                target = File(dir, "$stem ($n)$ext")
                n++
            }
        }
        try {
            FileOutputStream(target).use { out -> FileInputStream(src).use { it.copyTo(out) } }
        } catch (e: SecurityException) {
            val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                ContextCompat.checkSelfPermission(
                    this,
                    android.Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                throw IllegalStateException("Android 9 及以下需要存储权限才能写入公共目录")
            }
            throw e
        }
        return target
    }

    private fun mediaKindFor(mime: String, fileName: String): android.net.Uri {
        val m = mime.lowercase()
        val ext = fileName.substringAfterLast('.', "").lowercase()
        return when {
            m.startsWith("video/") || ext in LEGACY_VIDEO_EXTS ->
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            m.startsWith("image/") || ext in LEGACY_IMAGE_EXTS ->
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            else -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }
    }

    private fun mimeFor(file: File): String =
        when (file.extension.lowercase()) {
            "mp4", "m4v" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "webm" -> "video/webm"
            "avi" -> "video/x-msvideo"
            "mov" -> "video/quicktime"
            "flv" -> "video/x-flv"
            "ts" -> "video/mp2t"
            "wmv" -> "video/x-ms-wmv"
            "3gp" -> "video/3gpp"
            "mpg", "mpeg" -> "video/mpeg"
            "mp3" -> "audio/mpeg"
            "flac" -> "audio/flac"
            "m4a", "aac" -> "audio/mp4"
            "ogg", "opus" -> "audio/ogg"
            "wav" -> "audio/wav"
            "wma" -> "audio/x-ms-wma"
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "zip" -> "application/zip"
            "json" -> "application/json"
            else -> "application/octet-stream"
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
        private const val REQUEST_PICK_FILE = 4711

        private val LEGACY_VIDEO_EXTS = setOf(
            "mp4", "mkv", "avi", "mov", "webm", "flv", "ts",
            "m4v", "wmv", "3gp", "mpg", "mpeg",
        )
        private val LEGACY_IMAGE_EXTS = setOf("jpg", "jpeg", "png", "webp", "gif")
    }
}
