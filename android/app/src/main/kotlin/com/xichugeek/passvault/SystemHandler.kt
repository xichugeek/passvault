package com.xichugeek.passvault

import android.app.Activity
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PersistableBundle
import android.provider.Settings
import android.view.WindowManager
import android.view.autofill.AutofillManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** 剪贴板（敏感标记）、自动填充状态、防截屏 */
class SystemHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "passvault/system").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "copy" -> {
                val cm = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clip = ClipData.newPlainText("PassVault", call.argument<String>("text") ?: "")
                if (call.argument<Boolean>("sensitive") == true) {
                    val extras = PersistableBundle()
                    if (Build.VERSION.SDK_INT >= 33) {
                        extras.putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                    } else {
                        extras.putBoolean("android.content.extra.IS_SENSITIVE", true)
                    }
                    clip.description.extras = extras
                }
                cm.setPrimaryClip(clip)
                result.success(null)
            }
            "clearClipboard" -> {
                val cm = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                if (Build.VERSION.SDK_INT >= 28) {
                    cm.clearPrimaryClip()
                } else {
                    cm.setPrimaryClip(ClipData.newPlainText("", ""))
                }
                result.success(null)
            }
            "isAutofillSupported" -> {
                if (Build.VERSION.SDK_INT < 26) {
                    result.success(false)
                } else {
                    val am = activity.getSystemService(AutofillManager::class.java)
                    result.success(am?.isAutofillSupported == true)
                }
            }
            "isAutofillEnabled" -> {
                if (Build.VERSION.SDK_INT < 26) {
                    result.success(false)
                } else {
                    val am = activity.getSystemService(AutofillManager::class.java)
                    result.success(am?.hasEnabledAutofillServices() == true)
                }
            }
            "requestAutofill" -> {
                if (Build.VERSION.SDK_INT >= 26) {
                    try {
                        val intent = Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE)
                        intent.data = Uri.parse("package:${activity.packageName}")
                        activity.startActivity(intent)
                    } catch (_: Exception) {
                        // 部分厂商系统不支持直接跳转，退回到设置首页
                        activity.startActivity(Intent(Settings.ACTION_SETTINGS))
                    }
                }
                result.success(null)
            }
            "setSecure" -> {
                if (call.argument<Boolean>("secure") == true) {
                    activity.window.setFlags(
                        WindowManager.LayoutParams.FLAG_SECURE,
                        WindowManager.LayoutParams.FLAG_SECURE
                    )
                } else {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
