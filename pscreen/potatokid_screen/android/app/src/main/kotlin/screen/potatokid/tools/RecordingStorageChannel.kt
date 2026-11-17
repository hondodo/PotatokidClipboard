package screen.potatokid.tools

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.StatFs
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.concurrent.atomic.AtomicInteger

/**
 * 录制存储原生通道（TV / home 两端共用同一份实现）。
 *
 *  Dart 侧：package:pscreen_screen/.../recording/recording_platform.dart
 *  - pickDirectory()      → SAF ACTION_OPEN_DOCUMENT_TREE，持久授权，返回 {uri, displayName}
 *  - freeBytes{location,customUri} → 目标卷可用字节；失败返回 -1
 *  - openOutputStream{uri,name} → 创建文档并打开流，返回句柄 id
 *  - appendBytes{handle,bytes}  → 向句柄写分片
 *  - closeStream{handle}        → 冲刷并关闭
 *
 *  只依赖 Android framework（DocumentsContract / StatFs），不引入 documentfile 依赖。
 */
class RecordingStorageChannel(private val activity: FlutterActivity) {

    companion object {
        private const val TAG = "RecordingStorage"
        private const val CHANNEL = "potatokid/recording"
        private const val REQ_PICK_DIR = 3801
        private const val MIME_TS = "video/mp2t"
    }

    private val handles = mutableMapOf<Int, OutputStream>()
    private val handleSeq = AtomicInteger(1)
    private var pendingPickResult: MethodChannel.Result? = null

    fun attach(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickDirectory" -> pickDirectory(result)
                    "freeBytes" -> {
                        val location = call.argument<String>("location") ?: "internal"
                        val customUri = call.argument<String>("customUri")
                        result.success(freeBytes(location, customUri))
                    }
                    "openOutputStream" -> {
                        val uri = call.argument<String>("uri")
                        val name = call.argument<String>("name")
                        if (uri.isNullOrBlank() || name.isNullOrBlank()) {
                            result.error("invalid_arguments", "uri/name 为空", null)
                        } else {
                            try {
                                result.success(openOutputStream(Uri.parse(uri), name))
                            } catch (e: Exception) {
                                result.error("open_failed", e.message ?: "无法创建文件", null)
                            }
                        }
                    }
                    "appendBytes" -> {
                        val handle = call.argument<Int>("handle")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (handle == null || bytes == null) {
                            result.error("invalid_arguments", "handle/bytes 为空", null)
                        } else {
                            try {
                                handles[handle]?.write(bytes)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("write_failed", e.message ?: "写入失败", null)
                            }
                        }
                    }
                    "closeStream" -> {
                        val handle = call.argument<Int>("handle")
                        if (handle == null) {
                            result.error("invalid_arguments", "handle 为空", null)
                        } else {
                            try {
                                handles.remove(handle)?.close()
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("close_failed", e.message ?: "关闭失败", null)
                            }
                        }
                    }
                    "listFiles" -> {
                        val location = call.argument<String>("location") ?: "internal"
                        val customUri = call.argument<String>("customUri")
                        try {
                            result.success(listRecordings(location, customUri))
                        } catch (e: Exception) {
                            result.error("list_failed", e.message ?: "列举失败", null)
                        }
                    }
                    "deleteFile" -> {
                        val uri = call.argument<String>("uri")
                        val location = call.argument<String>("location") ?: "internal"
                        if (uri.isNullOrBlank()) {
                            result.error("invalid_arguments", "uri 为空", null)
                        } else {
                            try {
                                result.success(deleteRecording(uri, location))
                            } catch (e: Exception) {
                                result.error("delete_failed", e.message ?: "删除失败", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** 转发 Activity 的 onActivityResult；MainActivity 需在自身覆写中调用此方法。 */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PICK_DIR) return false
        val pending = pendingPickResult ?: return true
        pendingPickResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pending.success(null)
            return true
        }
        val uri: Uri = data.data!!
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        try {
            activity.contentResolver.takePersistableUriPermission(uri, flags)
        } catch (e: Exception) {
            Log.w(TAG, "takePersistableUriPermission failed: ${e.message}")
        }
        pending.success(
            mapOf(
                "uri" to uri.toString(),
                "displayName" to displayNameOf(uri),
            )
        )
        return true
    }

    private fun pickDirectory(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("busy", "上一次目录选择尚未完成", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        pendingPickResult = result
        try {
            activity.startActivityForResult(intent, REQ_PICK_DIR)
        } catch (e: Exception) {
            pendingPickResult = null
            result.error("no_file_manager", e.message ?: "无法打开目录选择器", null)
        }
    }

    /** internal: app 私有目录所在卷；custom: SAF tree 对应卷。失败返回 -1。 */
    private fun freeBytes(location: String, customUri: String?): Long = try {
        when (location) {
            "custom" -> {
                if (customUri.isNullOrBlank()) {
                    -1L
                } else {
                    freeBytesForTree(Uri.parse(customUri))
                }
            }
            else -> StatFs(activity.filesDir.path).availableBytes
        }
    } catch (e: Exception) {
        Log.w(TAG, "freeBytes failed: ${e.message}")
        -1L
    }

    /**
     * SAF tree URI（content://.../tree/<docId>）解析到挂载卷路径再用 StatFs。
     * docId 形如 "primary:Download"（内部共享存储）或 "XXXX-XXXX:..."（U 盘/SD 卡）。
     * 解析失败返回 -1，Dart 侧会跳过空间判断。
     */
    private fun freeBytesForTree(treeUri: Uri): Long {
        val docId = DocumentsContract.getTreeDocumentId(treeUri) ?: return -1L
        val volume = docId.substringBefore(':')
        val path = if (volume.equals("primary", ignoreCase = true)) {
            "/storage/emulated/0"
        } else {
            "/storage/$volume"
        }
        return StatFs(path).availableBytes
    }

    private fun openOutputStream(treeUri: Uri, fileName: String): Int {
        val docId = DocumentsContract.getTreeDocumentId(treeUri)
            ?: throw IllegalArgumentException("不是有效的目录 URI")
        val parentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
        val fileUri = DocumentsContract.createDocument(
            activity.contentResolver,
            parentUri,
            MIME_TS,
            fileName,
        ) ?: throw IllegalStateException("无法在目标目录创建文件")
        val out = activity.contentResolver.openOutputStream(fileUri, "w")
            ?: throw IllegalStateException("无法打开输出流")
        val handle = handleSeq.getAndIncrement()
        handles[handle] = out
        return handle
    }

    /** 列举已录文件：internal 扫私有 recordings 目录；custom 扫 SAF tree 下的 .ts。 */
    private fun listRecordings(location: String, customUri: String?): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        if (location == "custom" && !customUri.isNullOrBlank()) {
            val treeUri = Uri.parse(customUri)
            val docId = DocumentsContract.getTreeDocumentId(treeUri) ?: return out
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)
            val projection = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            )
            activity.contentResolver.query(childrenUri, projection, null, null, null)?.use { c ->
                val idIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val sizeIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                val modIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                while (c.moveToNext()) {
                    val name = if (nameIdx >= 0) c.getString(nameIdx) ?: "" else ""
                    if (!name.endsWith(".ts", ignoreCase = true)) continue
                    val id = if (idIdx >= 0) c.getString(idIdx) ?: "" else ""
                    val fileUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id)
                    out.add(
                        mapOf(
                            "uri" to fileUri.toString(),
                            "name" to name,
                            "size" to (if (sizeIdx >= 0) c.getLong(sizeIdx) else 0L),
                            "modified" to (if (modIdx >= 0) c.getLong(modIdx) else 0L),
                        )
                    )
                }
            }
        } else {
            val dir = java.io.File(activity.filesDir, "recordings")
            dir.listFiles()?.filter { it.isFile && it.name.endsWith(".ts", ignoreCase = true) }
                ?.sortedByDescending { it.lastModified() }
                ?.forEach { f ->
                    out.add(
                        mapOf(
                            "uri" to f.absolutePath,
                            "name" to f.name,
                            "size" to f.length(),
                            "modified" to f.lastModified(),
                        )
                    )
                }
        }
        return out
    }

    /** 删除单个录制文件：internal 按路径删；custom 按 SAF document uri 删。 */
    private fun deleteRecording(uri: String, location: String): Boolean = try {
        if (location == "custom" && uri.startsWith("content://")) {
            DocumentsContract.deleteDocument(activity.contentResolver, Uri.parse(uri))
        } else {
            java.io.File(uri).let { if (it.exists()) it.delete() else true }
        }
    } catch (e: Exception) {
        Log.w(TAG, "deleteRecording failed: ${e.message}")
        false
    }

    /** 从 tree URI 取展示名：优先用 OpenableColumns.DISPLAY_NAME，回落 docId。 */
    private fun displayNameOf(uri: Uri): String = try {
        val cursor = activity.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )
        cursor?.use {
            if (it.moveToFirst()) {
                val idx = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) {
                    val name = it.getString(idx)
                    if (!name.isNullOrBlank()) return name
                }
            }
        }
        val docId = DocumentsContract.getTreeDocumentId(uri).orEmpty()
        docId.substringAfter(':', docId).ifBlank { "自定义目录" }
    } catch (e: Exception) {
        "自定义目录"
    }
}
