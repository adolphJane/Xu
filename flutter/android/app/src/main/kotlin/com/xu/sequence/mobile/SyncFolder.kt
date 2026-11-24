package com.xu.sequence.mobile

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract as Documents
import android.provider.DocumentsContract.Document
import java.util.UUID

internal class SyncFolder(private val resolver: ContentResolver) {
    private var selected: Uri? = null

    fun select(folder: Uri, flags: Int): Map<String, String> {
        resolver.takePersistableUriPermission(
            folder,
            flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION),
        )
        val key = restore(folder.toString())
        return mapOf("path" to key, "bookmark" to key)
    }

    fun restore(bookmark: String?): String {
        val folder = bookmark?.let(Uri::parse)
        if (folder == null || !Documents.isTreeUri(folder) ||
            resolver.persistedUriPermissions.none {
                it.uri == folder && it.isReadPermission && it.isWritePermission
            }
        ) throw BridgeException("sync", "文件夹授权已失效，请重新选择")
        selected = folder
        return folder.toString()
    }

    fun read(key: String?): String? = withFolder(key) { folder ->
        (find(folder, FILE_NAME) ?: find(folder, RECOVERY_NAME))?.let(::contents)
    }

    fun write(key: String?, content: String?, previous: String?) = withFolder(key) { folder ->
        if (content == null) throw BridgeException("sync", "同步内容无效")
        val parent = document(folder, Documents.getTreeDocumentId(folder))
        val stageName = ".xu-sync-${UUID.randomUUID()}.tmp"
        val temporary = Documents.createDocument(resolver, parent, "application/json", stageName)
            ?: throw BridgeException("sync", "无法在同步文件夹创建文件")
        var stage: Uri? = temporary
        try {
            val output = resolver.openOutputStream(temporary, "wt")
                ?: throw BridgeException("sync", "无法写入同步文件夹")
            output.bufferedWriter(Charsets.UTF_8).use { it.write(content) }
            if (contents(temporary) != content) throw BridgeException("sync", "同步文件写入校验失败")

            val current = find(folder, FILE_NAME)
            var recovery = find(folder, RECOVERY_NAME)
            if ((current ?: recovery)?.let(::contents) != previous) {
                throw BridgeException("sync", "同步文件已被更新，请重新同步")
            }
            if (current != null) {
                if (recovery != null) Documents.deleteDocument(resolver, recovery)
                recovery = rename(current, RECOVERY_NAME)
            }
            val backup = recovery
            try {
                if (find(folder, FILE_NAME) != null) {
                    throw BridgeException("sync", "同步文件已被更新，请重新同步")
                }
                rename(temporary, FILE_NAME)
                stage = null
            } catch (error: Exception) {
                if (backup != null && find(folder, FILE_NAME) == null) {
                    runCatching { rename(backup, FILE_NAME) }
                }
                throw error
            }
            if (backup != null) runCatching { Documents.deleteDocument(resolver, backup) }
        } finally {
            stage?.let { runCatching { Documents.deleteDocument(resolver, it) } }
        }
    }

    private fun <T> withFolder(key: String?, action: (Uri) -> T): T {
        val folder = selected
        if (folder == null || folder.toString() != key) {
            throw BridgeException("sync", "文件夹授权已失效，请重新选择")
        }
        return action(folder)
    }

    private fun document(folder: Uri, id: String): Uri =
        Documents.buildDocumentUriUsingTree(folder, id)

    private fun find(folder: Uri, name: String): Uri? {
        val children = Documents.buildChildDocumentsUriUsingTree(folder, Documents.getTreeDocumentId(folder))
        val projection = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME)
        val items = resolver.query(children, projection, null, null, null)
            ?: throw BridgeException("sync", "无法读取同步文件夹")
        return items.use {
            while (it.moveToNext()) {
                if (it.getString(1) == name) return@use document(folder, it.getString(0))
            }
            null
        }
    }

    private fun contents(uri: Uri): String =
        resolver.openInputStream(uri)?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }
            ?: throw BridgeException("sync", "无法读取同步文件")

    private fun rename(uri: Uri, name: String): Uri {
        return Documents.renameDocument(resolver, uri, name)
            ?: throw BridgeException("sync", "文件提供方不支持安全替换同步文件")
    }

    companion object {
        private const val FILE_NAME = "xu-workspace-v1.json"
        private const val RECOVERY_NAME = "xu-workspace-v1.recovery.json"
    }
}
