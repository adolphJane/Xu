package com.xu.sequence.mobile

import android.Manifest
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val calendar by lazy { SystemCalendar(contentResolver) }
    private val apiKey by lazy { ApiKeyStorage(applicationContext) }
    private val folder by lazy { SyncFolder(contentResolver) }
    private var pendingPermission: Pair<MethodCall, MethodChannel.Result>? = null
    private var pendingFolder: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.xu.sequence/native")
            .setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "appVersion" -> {
                @Suppress("DEPRECATION")
                val version = packageManager.getPackageInfo(packageName, 0).versionName
                result.success(version)
            }
            "readClipboardImage" -> {
                val clipboard = getSystemService(ClipboardManager::class.java)
                val clip = clipboard.primaryClip
                val uri = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
                if (uri == null || uri.scheme != "content") {
                    result.success(null)
                    return
                }
                work(result, "clipboard", "无法读取剪贴板图片") {
                    if (contentResolver.getType(uri)?.startsWith("image/") != true) null
                    else contentResolver.openInputStream(uri)?.use { input ->
                        val buffer = ByteArray(8192)
                        val output = ByteArrayOutputStream()
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (output.size() + count > 4 * 1024 * 1024) {
                                throw BridgeException("clipboard", "请选择不超过 4 MB 的图片")
                            }
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    }
                }
            }
            "keychainRead" -> work(result, "keychain", "无法读取 API Key") { apiKey.read() }
            "keychainWrite" -> work(result, "keychain", "无法保存 API Key") {
                apiKey.write(call.arguments as String)
            }
            "selectSyncFolder" -> selectFolder(result)
            "restoreSyncFolder" -> work(result, "sync", "无法恢复同步文件夹") {
                folder.restore(call.arguments as? String)
            }
            "readSyncDocument" -> work(result, "sync", "无法读取同步文件夹") {
                folder.read(call.arguments as? String)
            }
            "writeSyncDocument" -> work(result, "sync", "无法写入同步文件夹") {
                folder.write(call.argument("folder"), call.argument("content"), call.argument("previous"))
                null
            }
            "anniversaryNextOccurrence" -> work(result, "anniversary", "无法计算纪念日日期") {
                AnniversaryDate.from(call)?.next()?.let(MobileDate::isoDate)
            }
            "calendarEvents", "calendarCreate", "calendarDelete" -> withPermissions(
                call,
                result,
                arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
            )
            "dailyReviewNotification", "anniversaryNotification" -> {
                if (call.argument<Boolean>("enabled") == true && Build.VERSION.SDK_INT >= 33) {
                    withPermissions(call, result, arrayOf(Manifest.permission.POST_NOTIFICATIONS))
                } else {
                    perform(call, result)
                }
            }
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun selectFolder(result: MethodChannel.Result) {
        if (pendingFolder != null) {
            result.error("sync", "请先完成当前的文件夹选择", null)
            return
        }
        pendingFolder = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
            startActivityForResult(intent, REQUEST_SYNC_FOLDER)
        } catch (_: Exception) {
            pendingFolder = null
            result.error("sync", "无法打开系统文件选择器", null)
        }
    }

    @Deprecated("Activity result callback required by the Flutter activity embedding")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_SYNC_FOLDER) return
        val result = pendingFolder ?: return
        pendingFolder = null
        val selected = data?.data
        if (resultCode != RESULT_OK || selected == null) {
            result.success(null)
        } else {
            work(result, "sync", "无法访问所选文件夹") { folder.select(selected, data.flags) }
        }
    }

    private fun withPermissions(
        call: MethodCall,
        result: MethodChannel.Result,
        permissions: Array<String>,
    ) {
        val missing = permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) {
            perform(call, result)
        } else if (pendingPermission != null) {
            result.error("permission", "请先完成当前的权限确认", null)
        } else {
            pendingPermission = call to result
            requestPermissions(missing.toTypedArray(), REQUEST_PERMISSION)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_PERMISSION) return
        val (call, result) = pendingPermission ?: return
        pendingPermission = null
        if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            perform(call, result)
        } else if (call.method.endsWith("Notification")) {
            result.success(false)
        } else {
            result.error("calendar", "未获得日历访问权限", null)
        }
    }

    private fun perform(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "dailyReviewNotification", "anniversaryNotification" ->
                work(result, "notifications", "无法设置提醒") {
                    Reminders(applicationContext).configure(call)
                }
            else -> work(result, "calendar", "系统日历操作失败") { calendar.handle(call) }
        }
    }

    private fun work(
        result: MethodChannel.Result,
        code: String,
        message: String,
        action: () -> Any?,
    ) {
        worker.execute {
            try {
                result.success(action())
            } catch (error: BridgeException) {
                result.error(error.code, error.message, null)
            } catch (_: Exception) {
                result.error(code, message, null)
            }
        }
    }

    override fun onDestroy() {
        pendingPermission?.second?.error("permission", "权限确认已取消", null)
        pendingPermission = null
        pendingFolder?.success(null)
        pendingFolder = null
        worker.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val REQUEST_PERMISSION = 3170
        private const val REQUEST_SYNC_FOLDER = 3171
    }
}

internal class BridgeException(val code: String, message: String) : RuntimeException(message)
