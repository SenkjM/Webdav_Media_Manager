package com.senkjm.media_manager

import android.app.Activity
import android.app.NotificationManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.media.session.MediaSessionManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import kotlin.concurrent.thread

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
    private var pendingListFolderTree: MethodChannel.Result? = null
    private var pendingPickDownloadTree: MethodChannel.Result? = null
    /** Old tree URI to release after a successful re-pick. */
    private var pendingOldDownloadTreeUri: String? = null
    private var pendingLegacyStoragePermission: MethodChannel.Result? = null

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
                            mapOf(
                                "ok" to false,
                                "error" to (e.message ?: e.toString()),
                                "errorKind" to "io"
                            )
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
                            mapOf(
                                "ok" to false,
                                "error" to (e.message ?: e.toString()),
                                "errorKind" to "io"
                            )
                        },
                    )
                }
                "setDownloadsNomedia" -> {
                    val args = call.arguments as? Map<*, *>
                    val enabled = args?.get("enabled") == true
                    result.success(
                        runCatching { setDownloadsNomedia(enabled) }.getOrElse { e ->
                            mapOf("ok" to false, "error" to (e.message ?: e.toString()))
                        },
                    )
                }
                "pickFile" -> {
                    val args = call.arguments as? Map<*, *>
                    pickFile(args?.get("mimeType") as? String, result)
                }
                "pickFolder" -> pickFolder(result)
                "listFolderTree" -> listFolderTree(result)
                "readUriToCache" -> {
                    val args = call.arguments as? Map<*, *>
                    val uri = args?.get("uri") as? String
                    if (uri == null) {
                        result.error("INVALID_ARG", "uri required", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "saf-read-uri") {
                        val path = runCatching { readUriToCache(uri) }.getOrElse { e ->
                            runOnUiThread { result.error("SAF_ERROR", e.message ?: e.toString(), null) }
                            null
                        }
                        if (path != null) runOnUiThread { result.success(path) }
                    }
                }
                "updateInstallInfo" -> result.success(
                    mapOf("packageName" to packageName, "abis" to Build.SUPPORTED_ABIS.toList()),
                )
                "installApk" -> {
                    val args = call.arguments as? Map<*, *>
                    result.success(installApk(args?.get("path") as? String))
                }
                "openInstallPermissionSettings" -> {
                    openInstallPermissionSettings()
                    result.success(null)
                }
                "openUrl" -> {
                    val args = call.arguments as? Map<*, *>
                    result.success(openExternalUrl(args?.get("url") as? String))
                }
                "pickDownloadTree" -> pickDownloadTree(call.arguments as? Map<*, *>, result)
                "releaseDownloadTree" -> {
                    val args = call.arguments as? Map<*, *>
                    val uri = args?.get("uri") as? String
                    result.success(
                        if (uri != null) {
                            SafDownloadTarget.releaseDownloadTree(contentResolver, uri)
                        } else {
                            mapOf("ok" to false, "error" to "uri required")
                        }
                    )
                }
                "checkDownloadTree" -> {
                    val args = call.arguments as? Map<*, *>
                    val uri = args?.get("uri") as? String
                    result.success(
                        if (uri != null) {
                            SafDownloadTarget.checkDownloadTree(contentResolver, uri)
                        } else {
                            mapOf("ok" to false, "error" to "uri required", "errorKind" to "other")
                        }
                    )
                }
                "saveToTree" -> {
                    val args = call.arguments as? Map<*, *>
                    result.success(
                        runCatching {
                            SafDownloadTarget.saveToTree(
                                contentResolver,
                                args?.get("uri") as? String ?: "",
                                args?.get("path") as? String ?: "",
                                args?.get("fileName") as? String ?: "",
                            )
                        }.getOrElse { e ->
                            mapOf(
                                "ok" to false,
                                "error" to (e.message ?: e.toString()),
                                "errorKind" to "other"
                            )
                        }
                    )
                }
                "setTreeNomedia" -> {
                    val args = call.arguments as? Map<*, *>
                    val uri = args?.get("uri") as? String
                    val enabled = args?.get("enabled") == true
                    result.success(
                        if (uri != null) {
                            SafDownloadTarget.setTreeNomedia(contentResolver, uri, enabled)
                        } else {
                            mapOf("ok" to false, "error" to "uri required", "errorKind" to "other")
                        }
                    )
                }
                "ensureLegacyStoragePermission" -> ensureLegacyStoragePermission(result)
                "listPersistedTreeGrants" -> {
                    result.success(SafDownloadTarget.listPersistedTreeGrants(contentResolver))
                }
                "releaseReadTree" -> {
                    val args = call.arguments as? Map<*, *>
                    val uri = args?.get("uri") as? String
                    result.success(
                        if (uri != null) {
                            SafDownloadTarget.releaseReadTree(contentResolver, uri)
                        } else {
                            mapOf("ok" to false, "error" to "uri required")
                        }
                    )
                }
                else -> result.notImplemented()
            }
        }
        registerDownloadKeepAliveChannel(flutterEngine)
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
            // Multi-select stays inside SAF: the same system picker grants
            // per-URI read access, still no storage permission involved.
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
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

    /**
     * Opens the system folder picker (SAF document tree) and copies every file
     * under the chosen directory into the app cache, preserving the relative
     * path below that directory. No storage permission is involved: SAF grants
     * read access to the tree the user picked.
     */
    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "已有文件选择正在进行", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        try {
            startActivityForResult(intent, REQUEST_PICK_FOLDER)
        } catch (e: Exception) {
            pendingPick = null
            result.error("unavailable", e.message ?: "无法打开文件夹选择器", null)
        }
    }

    

    /**
     * Launches ACTION_OPEN_DOCUMENT_TREE and returns a flat list of all files
     * under the chosen tree via [enumerateFolderTree]. Does not copy any data.
     */
    private fun listFolderTree(result: MethodChannel.Result) {
        if (pendingListFolderTree != null) {
            result.error("BUSY", "listFolderTree already pending", null)
            return
        }
        pendingListFolderTree = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, REQUEST_LIST_FOLDER_TREE)
    }

    /**
     * Enumerates all files under the SAF tree rooted at [treeUri].
     */
    private fun enumerateFolderTree(treeUri: android.net.Uri): Map<String, Any> {
        val docFile = androidx.documentfile.provider.DocumentFile.fromTreeUri(this, treeUri)
        val files = mutableListOf<Map<String, Any?>>()
        val folderName = docFile?.name ?: treeUri.lastPathSegment ?: "folder"
        if (docFile != null) enumerateTree(docFile, "", files)
        return mapOf("ok" to true, "folderName" to folderName, "files" to files)
    }

    private fun enumerateTree(
        dir: androidx.documentfile.provider.DocumentFile,
        prefix: String,
        out: MutableList<Map<String, Any?>>,
    ) {
        for (child in dir.listFiles()) {
            val name = child.name ?: continue
            val rel = if (prefix.isEmpty()) name else "$prefix/$name"
            if (child.isDirectory) {
                enumerateTree(child, rel, out)
            } else {
                out.add(mapOf(
                    "uri" to child.uri.toString(),
                    "relativePath" to rel,
                    "fileName" to name,
                    "size" to child.length(),
                ))
            }
        }
    }

    /**
     * Copies a SAF content URI into the app cache directory and returns the
     * resulting absolute file path.
     */
    private fun readUriToCache(uriString: String): String {
        val uri = android.net.Uri.parse(uriString)
        val fileName = uri.lastPathSegment?.substringAfterLast('/') ?: "import_saf"
        val dest = java.io.File(cacheDir, "saf_import_$fileName")
        contentResolver.openInputStream(uri)?.use { input ->
            dest.outputStream().use { output -> input.copyTo(output) }
        } ?: error("Failed to open SAF URI: $uriString")
        return dest.absolutePath
    }

    @Deprecated("Flutter embedding still routes SAF results through onActivityResult")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQUEST_PICK_DOWNLOAD_TREE) {
            val r = pendingPickDownloadTree ?: return
            pendingPickDownloadTree = null
            val oldTree = pendingOldDownloadTreeUri
            pendingOldDownloadTreeUri = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                r.success(mapOf("ok" to false, "cancelled" to true))
                return
            }
            val treeUri = data.data!!

            try {
                contentResolver.takePersistableUriPermission(
                    treeUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (e: Exception) {
                r.success(mapOf(
                    "ok" to false,
                    "error" to "无法获取持久化权限：${e.message ?: e}",
                    "errorKind" to "other"
                ))
                return
            }
            if (!oldTree.isNullOrBlank() && oldTree != treeUri.toString()) {
                runCatching {
                    SafDownloadTarget.releaseDownloadTree(contentResolver, oldTree)
                }
            }

            // 获取显示名
            val displayName = try {
                DocumentFile.fromTreeUri(this, treeUri)?.name
            } catch (e: Exception) {
                null
            } ?: try {
                val rootId = DocumentsContract.getTreeDocumentId(treeUri)
                val rootDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)
                contentResolver.query(
                    rootDocUri,
                    arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                    null,
                    null,
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                        if (nameIdx >= 0) cursor.getString(nameIdx) else null
                    } else null
                }
            } catch (e: Exception) {
                null
            }

            r.success(mapOf(
                "ok" to true,
                "uri" to treeUri.toString(),
                "displayName" to (displayName ?: "自定义目录")
            ))
            return
        }

        if (requestCode == REQUEST_LIST_FOLDER_TREE) {
            val r = pendingListFolderTree ?: return
            pendingListFolderTree = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                r.success(mapOf("ok" to false, "cancelled" to (resultCode != Activity.RESULT_OK), "files" to emptyList<Any>()))
                return
            }
            val treeUri = data.data!!
            contentResolver.takePersistableUriPermission(treeUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            thread(name = "saf-list-tree") {
                val payload = runCatching { enumerateFolderTree(treeUri) }.getOrElse { e ->
                    mapOf("ok" to false, "error" to (e.message ?: e.toString()), "files" to emptyList<Any>())
                }
                runOnUiThread { r.success(payload) }
            }
            return
        }
        if (requestCode != REQUEST_PICK_FILE && requestCode != REQUEST_PICK_FOLDER) return
        val result = pendingPick ?: return
        pendingPick = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        if (requestCode == REQUEST_PICK_FOLDER) {
            val uri = data?.data
            if (uri == null) {
                result.success(null)
                return
            }
            // Copying a whole tree can take a while on big folders; run it off
            // the main thread so the UI (and every other channel) stays live,
            // then deliver the result back on the main thread.
            thread(name = "saf-folder-import") {
                val payload = runCatching { copyPickedFolder(uri) }.getOrElse { e ->
                    mapOf("ok" to false, "error" to (e.message ?: e.toString()))
                }
                runOnUiThread { result.success(payload) }
            }
            return
        }
        // With EXTRA_ALLOW_MULTIPLE some pickers report every selection only via
        // clipData and leave data.data null — even for a single pick. Collect
        // clipData first and fall back to data.data, so single-select callers
        // (backup import, subtitle pick, …) are not misread as a cancel.
        thread(name = "saf-file-import") {
            val payload = runCatching {
                val uris = mutableListOf<Uri>()
                data?.clipData?.let { clip ->
                    for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
                }
                data?.data?.let { uris.add(it) }
                if (uris.isEmpty()) {
                    runOnUiThread { result.success(null) }
                    return@thread
                }
                val files = uris.distinct().map { copyPickedFile(it) }
                mapOf("ok" to true, "files" to files)
            }.getOrElse { e ->
                mapOf("ok" to false, "error" to (e.message ?: e.toString()))
            }
            runOnUiThread { result.success(payload) }
        }
    }

    private fun copyPickedFile(uri: Uri, relativePath: String? = null): Map<String, Any?> {
        val name = displayNameFor(uri)
        val dir = File(cacheDir, "imports")
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("无法创建导入缓存目录")
        }
        val target = uniqueImportTarget(dir, name)
        contentResolver.openInputStream(uri).use { input ->
            if (input == null) throw IllegalStateException("无法读取所选文件")
            FileOutputStream(target).use { out -> input.copyTo(out) }
        }
        val map = mutableMapOf<String, Any?>(
            "ok" to true,
            "path" to target.absolutePath,
            "fileName" to name,
            "size" to target.length(),
        )
        if (relativePath != null) map["relativePath"] = relativePath
        return map
    }

    /** Same-named picks in one batch must not overwrite each other's cache copy. */
    private fun uniqueImportTarget(dir: File, name: String): File {
        var target = File(dir, name)
        if (!target.exists()) return target
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var i = 2
        while (target.exists()) {
            target = File(dir, "$stem-$i$ext")
            i++
        }
        return target
    }

    /** Recursively copy every file under the picked tree into `cacheDir/imports`. */
    private fun copyPickedFolder(treeUri: Uri): Map<String, Any?> {
        val root = DocumentFile.fromTreeUri(this, treeUri)
            ?: throw IllegalStateException("无法读取所选文件夹")
        val folderName = sanitizeName(root.name?.takeIf { it.isNotBlank() } ?: "folder")
        val files = mutableListOf<Map<String, Any?>>()
        copyTree(root, folderName, files)
        return mapOf(
            "ok" to true,
            "folderName" to folderName,
            "files" to files,
        )
    }

    private fun copyTree(
        dir: DocumentFile,
        prefix: String,
        out: MutableList<Map<String, Any?>>,
    ) {
        for (child in dir.listFiles()) {
            if (child.isDirectory) {
                val name = sanitizeName(
                    child.name?.takeIf { it.isNotBlank() } ?: "folder",
                )
                copyTree(child, "$prefix/$name", out)
            } else if (child.isFile) {
                out.add(copyPickedFile(child.uri, "$prefix/${displayNameFor(child.uri)}"))
            }
        }
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
            ?: "import.wdmm"
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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_LEGACY_STORAGE_PERMISSION) {
            val r = pendingLegacyStoragePermission ?: return
            pendingLegacyStoragePermission = null
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            r.success(mapOf("ok" to true, "granted" to granted))
        }
    }

    /**
     * 启动 ACTION_OPEN_DOCUMENT_TREE 选择自定义下载目录。
     */
    private fun pickDownloadTree(args: Map<*, *>?, result: MethodChannel.Result) {
        if (pendingPickDownloadTree != null) {
            result.error("BUSY", "pickDownloadTree already pending", null)
            return
        }
        pendingPickDownloadTree = result
        pendingOldDownloadTreeUri = (args?.get("oldUri") as? String)?.takeIf { it.isNotBlank() }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
            // API 26+ 设置初始目录为 Download
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    val downloadUri = DocumentsContract.buildDocumentUri(
                        "com.android.externalstorage.documents",
                        "primary:Download"
                    )
                    putExtra(DocumentsContract.EXTRA_INITIAL_URI, downloadUri)
                } catch (e: Exception) {
                    // 忽略，某些设备可能不支持
                }
            }
        }

        try {
            startActivityForResult(intent, REQUEST_PICK_DOWNLOAD_TREE)
        } catch (e: Exception) {
            pendingPickDownloadTree = null
            pendingOldDownloadTreeUri = null
            result.success(mapOf(
                "ok" to false,
                "error" to (e.message ?: "无法打开文件夹选择器")
            ))
        }
    }

    /**
     * 确保遗留存储权限（API ≤ 28）。
     * API 29+ 直接返回 granted:true；API ≤ 28 检查或请求权限。
     */
    private fun ensureLegacyStoragePermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            result.success(mapOf("ok" to true, "granted" to true))
            return
        }

        val granted = ContextCompat.checkSelfPermission(
            this,
            android.Manifest.permission.WRITE_EXTERNAL_STORAGE
        ) == PackageManager.PERMISSION_GRANTED

        if (granted) {
            result.success(mapOf("ok" to true, "granted" to true))
            return
        }

        if (pendingLegacyStoragePermission != null) {
            result.success(mapOf("ok" to false, "error" to "权限请求已在进行中"))
            return
        }

        pendingLegacyStoragePermission = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE),
            REQUEST_LEGACY_STORAGE_PERMISSION
        )
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
        val dir = subdirOrDefault(album, "WebdavMediaManager")
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

            // 查询实际文件名（API 29+ MediaStore 可能自动改名）
            var actualFileName = fileName
            try {
                resolver.query(
                    uri,
                    arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
                    null,
                    null,
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                        if (nameIdx >= 0) {
                            actualFileName = cursor.getString(nameIdx) ?: fileName
                        }
                    }
                }
            } catch (_: Exception) {
                // 查询失败，使用原 fileName
            }

            return mapOf(
                "ok" to true,
                "uri" to uri.toString(),
                "fileName" to actualFileName,
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
        val dir = subdirOrDefault(subdir, "WebdavMediaManager")
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

            // 查询实际文件名（API 29+ MediaStore 可能自动改名）
            var actualFileName = fileName
            try {
                resolver.query(
                    uri,
                    arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
                    null,
                    null,
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                        if (nameIdx >= 0) {
                            actualFileName = cursor.getString(nameIdx) ?: fileName
                        }
                    }
                }
            } catch (_: Exception) {
                // 查询失败，使用原 fileName
            }

            return mapOf(
                "ok" to true,
                "uri" to uri.toString(),
                "fileName" to actualFileName,
                "location" to "下载目录/$dir",
                "path" to "$relative/$actualFileName"
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
     * `.nomedia` lives only in the public download folder
     * `Download/WebdavMediaManager` (the 「下载」 action). Gallery export
     * (Pictures / Movies) must not call this.
     *
     * API < 28 is ignored. API 28 looks at the file on disk and does **not**
     * scan it. API 29+ looks at a MediaStore.Downloads row whose display name
     * is exactly `.nomedia` (a renamed display name does not count).
     *
     * If that state already matches [enabled], nothing is written or deleted
     * (`already` = true). A write or delete runs only when it does not match.
     */
    private fun setDownloadsNomedia(enabled: Boolean): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return mapOf("ok" to true, "skipped" to true, "reason" to "api<28")
        }
        if (downloadsNomediaPresent() == enabled) {
            return mapOf("ok" to true, "already" to true)
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (enabled) insertNomediaQ() else deleteNomediaQ()
        } else if (enabled) {
            writeNomediaApi28()
        } else {
            deleteNomediaApi28()
        }
    }

    /** API 28 file, or API 29+ MediaStore row with display name `.nomedia`. */
    private fun downloadsNomediaPresent(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            findNomediaUris(contentResolver).isNotEmpty()
        } else {
            nomediaFileApi28().isFile
        }
    }

    private fun nomediaFileApi28(): File {
        return File(
            File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "WebdavMediaManager",
            ),
            ".nomedia",
        )
    }

    private fun nomediaRelativePaths(): List<String> {
        val base = "${Environment.DIRECTORY_DOWNLOADS}/WebdavMediaManager"
        return listOf(base, "$base/")
    }

    private fun insertNomediaQ(): Map<String, Any?> {
        val resolver = contentResolver
        if (findNomediaUris(resolver).isNotEmpty()) {
            return mapOf("ok" to true, "already" to true)
        }
        val relative = "${Environment.DIRECTORY_DOWNLOADS}/WebdavMediaManager"
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, ".nomedia")
            put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
            put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = try {
            resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
        } catch (e: Exception) {
            return mapOf(
                "ok" to false,
                "error" to "MediaStore 拒绝了显示名 .nomedia：${e.message ?: e}",
            )
        } ?: return mapOf("ok" to false, "error" to "MediaStore 拒绝了显示名 .nomedia")
        try {
            resolver.openOutputStream(uri).use { out ->
                if (out == null) throw IllegalStateException("无法打开输出流")
            }
            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null,
            )
        } catch (e: Exception) {
            runCatching { resolver.delete(uri, null, null) }
            return mapOf(
                "ok" to false,
                "error" to "MediaStore 拒绝了显示名 .nomedia：${e.message ?: e}",
            )
        }
        val stored = resolver.query(
            uri,
            arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        if (stored != null && stored != ".nomedia") {
            runCatching { resolver.delete(uri, null, null) }
            return mapOf(
                "ok" to false,
                "error" to "MediaStore 未保留显示名 .nomedia（实际为 $stored）",
            )
        }
        return mapOf("ok" to true, "uri" to uri.toString(), "fileName" to ".nomedia")
    }

    private fun deleteNomediaQ(): Map<String, Any?> {
        val resolver = contentResolver
        val uris = findNomediaUris(resolver)
        if (uris.isEmpty()) {
            return mapOf("ok" to true, "already" to true)
        }
        for (uri in uris) {
            try {
                if (resolver.delete(uri, null, null) <= 0) {
                    return mapOf("ok" to false, "error" to "无法删除 .nomedia")
                }
            } catch (e: Exception) {
                return mapOf(
                    "ok" to false,
                    "error" to (e.message ?: "无法删除 .nomedia"),
                )
            }
        }
        return mapOf("ok" to true)
    }

    private fun findNomediaUris(resolver: android.content.ContentResolver): List<Uri> {
        val found = mutableListOf<Uri>()
        val projection = arrayOf(MediaStore.Downloads._ID)
        for (rel in nomediaRelativePaths()) {
            resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                projection,
                "${MediaStore.Downloads.DISPLAY_NAME}=? AND ${MediaStore.Downloads.RELATIVE_PATH}=?",
                arrayOf(".nomedia", rel),
                null,
            )?.use { c ->
                val idIdx = c.getColumnIndexOrThrow(MediaStore.Downloads._ID)
                while (c.moveToNext()) {
                    found += ContentUris.withAppendedId(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                        c.getLong(idIdx),
                    )
                }
            }
        }
        return found
    }

    /** API 28 only. Do not media-scan `.nomedia`. Does not create a second file. */
    private fun writeNomediaApi28(): Map<String, Any?> {
        val file = nomediaFileApi28()
        if (file.isFile) {
            return mapOf("ok" to true, "already" to true, "path" to file.absolutePath)
        }
        val dir = file.parentFile
            ?: return mapOf("ok" to false, "error" to "无法创建 .nomedia")
        if (!dir.exists() && !dir.mkdirs()) {
            return mapOf("ok" to false, "error" to "无法创建目录：${dir.absolutePath}")
        }
        try {
            if (!file.createNewFile()) {
                return mapOf("ok" to false, "error" to "无法创建 .nomedia")
            }
        } catch (e: SecurityException) {
            return mapOf("ok" to false, "error" to (e.message ?: "写入 .nomedia 被拒绝"))
        }
        return mapOf("ok" to true, "path" to file.absolutePath)
    }

    private fun deleteNomediaApi28(): Map<String, Any?> {
        val file = nomediaFileApi28()
        if (!file.exists()) {
            return mapOf("ok" to true, "already" to true)
        }
        return if (file.delete()) {
            mapOf("ok" to true)
        } else {
            mapOf("ok" to false, "error" to "无法删除 .nomedia")
        }
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
            "gif" -> "image/gif"
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
        val channelId = "com.senkjm.media_manager.audio.v4"
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

    /** Opens the system package installer for a verified APK in cache/updates. */
    private fun openExternalUrl(raw: String?): Boolean {
        val url = raw?.trim().orEmpty()
        if (url.isEmpty()) return false
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return runCatching {
            startActivity(intent)
            true
        }.getOrDefault(false)
    }
    private fun installApk(path: String?): Map<String, String> {
        val apk = File(path ?: "")
        if (!apk.isFile || !apk.name.endsWith(".apk", ignoreCase = true)) {
            return mapOf("state" to "failed")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            return mapOf("state" to "permission_required")
        }
        return try {
            val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", apk)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            mapOf("state" to "started")
        } catch (_: Exception) {
            mapOf("state" to "failed")
        }
    }

    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        startActivity(
            Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:$packageName")
            },
        )
    }

    private fun registerDownloadKeepAliveChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DownloadKeepAliveService.CHANNEL,
        )
        DownloadKeepAliveService.flutterChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val args = call.arguments as? Map<*, *>
                    val title = (args?.get("title") as? String)?.takeIf { it.isNotBlank() }
                        ?: DownloadKeepAliveService.DEFAULT_TITLE
                    val notificationId = (args?.get("notificationId") as? Number)?.toInt()
                        ?: DownloadKeepAliveService.DEFAULT_NOTIFICATION_ID
                    val channelId = (args?.get("channelId") as? String)?.takeIf { it.isNotBlank() }
                        ?: DownloadKeepAliveService.DEFAULT_CHANNEL_ID
                    try {
                        ContextCompat.startForegroundService(
                            this,
                            DownloadKeepAliveService.startIntent(
                                this,
                                title,
                                notificationId,
                                channelId,
                            ),
                        )
                        result.success(mapOf("ok" to true))
                    } catch (e: Exception) {
                        result.success(
                            mapOf(
                                "ok" to false,
                                "error" to "${e.javaClass.simpleName}: ${e.message}",
                            ),
                        )
                    }
                }
                "stop" -> {
                    DownloadKeepAliveService.stopIfRunning()
                    result.success(true)
                }
                "isRunning" -> {
                    // Cheap liveness probe: no PowerManager/ActivityManager
                    // work, so Dart can afford it before every start decision.
                    result.success(mapOf("running" to DownloadKeepAliveService.running))
                }
                "diagnostics" -> {
                    result.success(DownloadKeepAliveService.diagnostics(applicationContext))
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val CHANNEL = "com.senkjm.media_manager/app"
        /** Must match AudioService.NOTIFICATION_ID */
        private const val AUDIO_SERVICE_NOTIFICATION_ID = 1124
        private const val REQUEST_PICK_FILE = 4711
        private const val REQUEST_PICK_FOLDER = 4712
        private const val REQUEST_LIST_FOLDER_TREE = 4713
        private const val REQUEST_PICK_DOWNLOAD_TREE = 4714
        private const val REQUEST_LEGACY_STORAGE_PERMISSION = 4715

        private val LEGACY_VIDEO_EXTS = setOf(
            "mp4", "mkv", "avi", "mov", "webm", "flv", "ts",
            "m4v", "wmv", "3gp", "mpg", "mpeg",
        )
        private val LEGACY_IMAGE_EXTS = setOf("jpg", "jpeg", "png", "webp", "gif")
    }
}
