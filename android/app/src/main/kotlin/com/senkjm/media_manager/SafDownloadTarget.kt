// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025 SenkjM
package com.senkjm.media_manager

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.IOException

/**
 * SAF (Storage Access Framework) 下载目录管理。
 *
 * 允许用户选择自定义下载目录并通过 SAF 写入，作为 MediaStore Downloads 的替代。
 * 所有结果 map 带 "ok" 键；失败带 "error"（人类可读）和 "errorKind"。
 */
object SafDownloadTarget {

    /**
     * 错误分类：用于决定是否回落到 MediaStore 默认目录。
     * - safInvalid: SAF 授权失效/根目录不可写，触发全局回落
     * - io: I/O 错误（空间不足、写入失败），不回落
     * - other: 其它错误，不回落
     */
    object ErrorKind {
        const val SAF_INVALID = "safInvalid"
        const val IO = "io"
        const val OTHER = "other"
    }

    /**
     * 检查树授权是否可用且根目录支持创建文件。
     */
    fun isTreeUsable(resolver: ContentResolver, treeUri: Uri): Boolean {
        // (a) 检查持久化写权限
        val hasPermission = resolver.persistedUriPermissions.any { permission ->
            permission.uri == treeUri && permission.isWritePermission
        }
        if (!hasPermission) return false

        // (b) 检查根文档可查询
        val rootId = try {
            DocumentsContract.getTreeDocumentId(treeUri)
        } catch (e: Exception) {
            return false
        }
        val rootDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)

        var cursor: Cursor? = null
        try {
            cursor = resolver.query(
                rootDocUri,
                arrayOf(DocumentsContract.Document.COLUMN_FLAGS),
                null,
                null,
                null
            )
            if (cursor == null || !cursor.moveToFirst()) return false

            // (c) 检查 FLAG_DIR_SUPPORTS_CREATE
            val flagsIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_FLAGS)
            if (flagsIndex < 0) return false
            val flags = cursor.getInt(flagsIndex)
            return (flags and DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE) != 0
        } catch (e: Exception) {
            return false
        } finally {
            cursor?.close()
        }
    }

    /**
     * 分类异常为 errorKind。
     */
    fun classifyError(
        e: Exception,
        resolver: ContentResolver,
        treeUri: Uri
    ): String {
        return when (e) {
            is SecurityException -> ErrorKind.SAF_INVALID
            is FileNotFoundException,
            is IllegalArgumentException,
            is IllegalStateException -> {
                // 复跑 isTreeUsable 判断
                if (!isTreeUsable(resolver, treeUri)) {
                    ErrorKind.SAF_INVALID
                } else {
                    ErrorKind.IO
                }
            }
            is IOException -> ErrorKind.IO
            else -> ErrorKind.OTHER
        }
    }

    /**
     * 检查下载树授权的有效性。
     * @return {ok:true} 或 {ok:false, errorKind:"safInvalid"}
     */
    fun checkDownloadTree(resolver: ContentResolver, uri: String): Map<String, Any> {
        val treeUri = try {
            Uri.parse(uri)
        } catch (e: Exception) {
            return mapOf(
                "ok" to false,
                "errorKind" to ErrorKind.SAF_INVALID,
                "error" to "无效的 URI"
            )
        }

        return if (isTreeUsable(resolver, treeUri)) {
            mapOf("ok" to true)
        } else {
            mapOf(
                "ok" to false,
                "errorKind" to ErrorKind.SAF_INVALID,
                "error" to "SAF 授权已失效或目录不可写"
            )
        }
    }

    /**
     * 释放下载树的持久化权限。
     */
    fun releaseDownloadTree(resolver: ContentResolver, uri: String): Map<String, Any> {
        return try {
            val treeUri = Uri.parse(uri)
            resolver.releasePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            mapOf("ok" to true)
        } catch (e: Exception) {
            // 吞异常，返回成功
            mapOf("ok" to true)
        }
    }

    /**
     * 写入文件到选中的树目录根（平铺，无子目录）。
     */
    fun saveToTree(
        resolver: ContentResolver,
        treeUri: String,
        sourcePath: String,
        fileName: String,
        // mimeType 忽略，固定用 octet-stream
    ): Map<String, Any> {
        val uri = try {
            Uri.parse(treeUri)
        } catch (e: Exception) {
            return mapOf(
                "ok" to false,
                "error" to "无效的树 URI",
                "errorKind" to ErrorKind.SAF_INVALID
            )
        }

        val src = File(sourcePath)
        if (!src.exists()) {
            return mapOf(
                "ok" to false,
                "error" to "源文件不存在",
                "errorKind" to ErrorKind.IO
            )
        }

        // 预检有效性
        if (!isTreeUsable(resolver, uri)) {
            return mapOf(
                "ok" to false,
                "error" to "SAF 授权已失效或目录不可写",
                "errorKind" to ErrorKind.SAF_INVALID
            )
        }

        try {
            // 获取根文档 URI
            val rootId = DocumentsContract.getTreeDocumentId(uri)
            val parentDocUri = DocumentsContract.buildDocumentUriUsingTree(uri, rootId)

            // 创建文档（固定 octet-stream）
            val sanitizedName = sanitizeName(fileName)
            val docUri = DocumentsContract.createDocument(
                resolver,
                parentDocUri,
                "application/octet-stream",
                sanitizedName
            )

            if (docUri == null) {
                // 再次预检判断 errorKind
                val kind = if (!isTreeUsable(resolver, uri)) {
                    ErrorKind.SAF_INVALID
                } else {
                    ErrorKind.IO
                }
                return mapOf(
                    "ok" to false,
                    "error" to "无法创建文档",
                    "errorKind" to kind
                )
            }

            // 拷贝内容
            try {
                resolver.openOutputStream(docUri, "w").use { out ->
                    if (out == null) throw IOException("无法打开输出流")
                    FileInputStream(src).use { input ->
                        input.copyTo(out)
                    }
                }
            } catch (e: Exception) {
                // 删除半截文档
                try {
                    DocumentsContract.deleteDocument(resolver, docUri)
                } catch (_: Exception) {
                    // 吞异常
                }
                throw e
            }

            // 查询实际文件名（provider 可能自动改名）
            var actualFileName = sanitizedName
            try {
                resolver.query(
                    docUri,
                    arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                    null,
                    null,
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                        if (nameIdx >= 0) {
                            actualFileName = cursor.getString(nameIdx) ?: sanitizedName
                        }
                    }
                }
            } catch (_: Exception) {
                // 查询失败，使用 sanitizedName
            }

            // 查询树的显示名
            val displayName = getTreeDisplayName(resolver, uri) ?: "自定义目录"

            return mapOf(
                "ok" to true,
                "uri" to docUri.toString(),
                "fileName" to actualFileName,
                "location" to "custom",
                "path" to "$displayName/$actualFileName"
            )

        } catch (e: Exception) {
            val errorKind = classifyError(e, resolver, uri)
            return mapOf(
                "ok" to false,
                "error" to (e.message ?: e.toString()),
                "errorKind" to errorKind
            )
        }
    }

    /**
     * 在树根目录中创建或删除 .nomedia 文件。
     */
    fun setTreeNomedia(
        resolver: ContentResolver,
        treeUri: String,
        enabled: Boolean
    ): Map<String, Any> {
        val uri = try {
            Uri.parse(treeUri)
        } catch (e: Exception) {
            return mapOf(
                "ok" to false,
                "error" to "无效的树 URI",
                "errorKind" to ErrorKind.SAF_INVALID
            )
        }

        try {
            val rootId = DocumentsContract.getTreeDocumentId(uri)
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(uri, rootId)

            // 查询显示名为 .nomedia 的文件
            val existingNomedia = mutableListOf<Uri>()
            resolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME
                ),
                null,
                null,
                null
            )?.use { cursor ->
                val idIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                if (idIdx >= 0 && nameIdx >= 0) {
                    while (cursor.moveToNext()) {
                        val name = cursor.getString(nameIdx)
                        if (name == ".nomedia") {
                            val docId = cursor.getString(idIdx)
                            existingNomedia.add(DocumentsContract.buildDocumentUriUsingTree(uri, docId))
                        }
                    }
                }
            }

            val alreadyPresent = existingNomedia.isNotEmpty()

            // 状态已匹配
            if (alreadyPresent == enabled) {
                return mapOf("ok" to true, "already" to true)
            }

            if (enabled) {
                // 创建 .nomedia
                val parentDocUri = DocumentsContract.buildDocumentUriUsingTree(uri, rootId)
                val docUri = DocumentsContract.createDocument(
                    resolver,
                    parentDocUri,
                    "application/octet-stream",
                    ".nomedia"
                )

                if (docUri == null) {
                    return mapOf(
                        "ok" to false,
                        "error" to "无法创建 .nomedia",
                        "errorKind" to ErrorKind.IO
                    )
                }

                // 查询实际显示名
                var actualName = ".nomedia"
                try {
                    resolver.query(
                        docUri,
                        arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                        null,
                        null,
                        null
                    )?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                            if (nameIdx >= 0) {
                                actualName = cursor.getString(nameIdx) ?: ".nomedia"
                            }
                        }
                    }
                } catch (_: Exception) {
                    // 查询失败
                }

                if (actualName != ".nomedia") {
                    // 删除错误的文件
                    try {
                        DocumentsContract.deleteDocument(resolver, docUri)
                    } catch (_: Exception) {
                        // 吞异常
                    }
                    return mapOf(
                        "ok" to false,
                        "error" to "目录未保留显示名 .nomedia（实际为 $actualName）",
                        "errorKind" to ErrorKind.IO
                    )
                }

                return mapOf("ok" to true)
            } else {
                // 删除所有 .nomedia
                for (nomediaUri in existingNomedia) {
                    try {
                        DocumentsContract.deleteDocument(resolver, nomediaUri)
                    } catch (e: Exception) {
                        return mapOf(
                            "ok" to false,
                            "error" to "无法删除 .nomedia：${e.message ?: e}",
                            "errorKind" to ErrorKind.IO
                        )
                    }
                }
                return mapOf("ok" to true)
            }

        } catch (e: Exception) {
            val errorKind = classifyError(e, resolver, uri)
            return mapOf(
                "ok" to false,
                "error" to (e.message ?: e.toString()),
                "errorKind" to errorKind
            )
        }
    }

    /**
     * 列举所有持久化的树授权（uri path 以 /tree/ 开头）。
     */
    fun listPersistedTreeGrants(resolver: ContentResolver): Map<String, Any> {
        val grants = mutableListOf<Map<String, Any>>()

        for (permission in resolver.persistedUriPermissions) {
            val uri = permission.uri
            if (uri.path?.contains("/tree/") == true) {
                grants.add(
                    mapOf(
                        "uri" to uri.toString(),
                        "read" to permission.isReadPermission,
                        "write" to permission.isWritePermission
                    )
                )
            }
        }

        return mapOf("ok" to true, "grants" to grants)
    }

    /**
     * 释放只读树授权。
     */
    fun releaseReadTree(resolver: ContentResolver, uri: String): Map<String, Any> {
        return try {
            val treeUri = Uri.parse(uri)
            resolver.releasePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
            mapOf("ok" to true)
        } catch (e: Exception) {
            // 吞异常
            mapOf("ok" to true)
        }
    }

    private fun sanitizeName(name: String): String {
        val cleaned = name.replace(Regex("""[\\/:*?"<>|\u0000-\u001f]"""), "_").trim()
        return cleaned.ifEmpty { "file" }
    }

    private fun getTreeDisplayName(resolver: ContentResolver, treeUri: Uri): String? {
        return try {
            DocumentFile.fromTreeUri(null, treeUri)?.name
                ?: queryTreeDisplayName(resolver, treeUri)
        } catch (_: Exception) {
            queryTreeDisplayName(resolver, treeUri)
        }
    }

    private fun queryTreeDisplayName(resolver: ContentResolver, treeUri: Uri): String? {
        return try {
            val rootId = DocumentsContract.getTreeDocumentId(treeUri)
            val rootDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)
            resolver.query(
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
        } catch (_: Exception) {
            null
        }
    }
}
