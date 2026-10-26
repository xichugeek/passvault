package com.xichugeek.passvault

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * 存储访问框架（SAF）：通过系统文件选择器打开 Google Drive 等云盘中的文件，
 * 获取长期读写权限，读写在后台线程执行。
 */
class SafHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        private const val REQ_OPEN = 7101
        private const val REQ_CREATE = 7102
        private val io = Executors.newCachedThreadPool()

        fun readBytes(activity: android.content.Context, uri: Uri): ByteArray {
            val input = activity.contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("无法打开文件")
            input.use {
                val out = ByteArrayOutputStream()
                it.copyTo(out)
                return out.toByteArray()
            }
        }

        fun writeBytes(context: android.content.Context, uri: Uri, bytes: ByteArray) {
            // "wt" = 截断写入；部分云盘只支持 "w"，失败后回退
            val modes = listOf("wt", "rwt", "w")
            var last: Exception? = null
            for (m in modes) {
                try {
                    val out = context.contentResolver.openOutputStream(uri, m)
                        ?: throw IllegalStateException("无法写入文件")
                    out.use { it.write(bytes); it.flush() }
                    return
                } catch (e: Exception) {
                    last = e
                }
            }
            throw last ?: IllegalStateException("写入失败")
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val appContext = activity.applicationContext
    private var pending: MethodChannel.Result? = null
    private var persist = true

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "passvault/saf").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openDocument" -> {
                persist = call.argument<Boolean>("persist") ?: true
                pending?.error("cancelled", "replaced", null)
                pending = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                    )
                }
                @Suppress("DEPRECATION")
                activity.startActivityForResult(intent, REQ_OPEN)
            }
            "createDocument" -> {
                persist = true
                pending?.error("cancelled", "replaced", null)
                pending = result
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "passvault.kdbx")
                }
                @Suppress("DEPRECATION")
                activity.startActivityForResult(intent, REQ_CREATE)
            }
            "read" -> {
                val uri = Uri.parse(call.argument<String>("uri"))
                io.execute {
                    try {
                        val bytes = readBytes(appContext, uri)
                        main.post { result.success(bytes) }
                    } catch (e: Exception) {
                        main.post { result.error("io", e.message ?: e.toString(), null) }
                    }
                }
            }
            "write" -> {
                val uri = Uri.parse(call.argument<String>("uri"))
                val bytes = call.argument<ByteArray>("bytes")!!
                io.execute {
                    try {
                        writeBytes(appContext, uri, bytes)
                        main.post { result.success(null) }
                    } catch (e: Exception) {
                        main.post { result.error("io", e.message ?: e.toString(), null) }
                    }
                }
            }
            "release" -> {
                try {
                    activity.contentResolver.releasePersistableUriPermission(
                        Uri.parse(call.argument<String>("uri")),
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                } catch (_: Exception) {
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_OPEN && requestCode != REQ_CREATE) return false
        val r = pending
        pending = null
        if (r == null) return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            r.success(null)
            return true
        }
        if (persist) {
            try {
                activity.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (_: SecurityException) {
                // 某些提供方只给读权限
                try {
                    activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } catch (_: Exception) {
                }
            }
        }
        r.success(
            mapOf(
                "uri" to uri.toString(),
                "name" to displayName(uri),
                "provider" to (uri.authority ?: "")
            )
        )
        return true
    }

    private fun displayName(uri: Uri): String {
        try {
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val name = c.getString(0)
                    if (!name.isNullOrBlank()) return name
                }
            }
        } catch (_: Exception) {
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "vault.kdbx"
    }
}
