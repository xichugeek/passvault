package com.xichugeek.passvault.autofill

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.autofill.Dataset
import android.view.WindowManager
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import androidx.annotation.RequiresApi
import com.xichugeek.passvault.BiometricHandler
import com.xichugeek.passvault.SafHandler
import com.xichugeek.passvault.SystemHandler
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 自动填充时弹出的界面：解锁（指纹/主密码）并选择账号，
 * 把账号作为 Dataset 返回给系统完成填充。
 */
@RequiresApi(Build.VERSION_CODES.O)
class AutofillActivity : FlutterFragmentActivity() {
    companion object {
        const val EXTRA_PACKAGE = "pv_package"
        const val EXTRA_DOMAIN = "pv_domain"
        const val EXTRA_LABEL = "pv_label"
        const val EXTRA_USERNAME_ID = "pv_username_id"
        const val EXTRA_PASSWORD_IDS = "pv_password_ids"
        const val EXTRA_OTP_ID = "pv_otp_id"
    }

    private var finished = false

    override fun onCreate(savedInstanceState: Bundle?) {
        AutofillEngine.getOrCreate(this)
        super.onCreate(savedInstanceState)
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun getCachedEngineId(): String = AutofillEngine.ENGINE_ID

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        BiometricHandler(this).register(messenger)
        SafHandler(this).register(messenger)
        SystemHandler(this).register(messenger)
        val channel = AutofillEngine.channel(flutterEngine)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getRequest" -> result.success(requestMap())
                "fill" -> {
                    result.success(null)
                    finishWithFill(
                        call.argument<String>("username") ?: "",
                        call.argument<String>("password") ?: "",
                        call.argument<String>("title") ?: "",
                        call.argument<String>("otp"),
                    )
                }
                "cancel" -> {
                    result.success(null)
                    finishCancelled()
                }
                else -> result.notImplemented()
            }
        }
        // 引擎复用时（之前已打开过填充界面），通知 Dart 有新请求
        channel.invokeMethod("newRequest", requestMap())
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // 界面关闭后，引擎仍需响应 Dart 的调用
        AutofillEngine.channel(flutterEngine).setMethodCallHandler { call, result ->
            when (call.method) {
                "getRequest" -> result.success(null)
                else -> result.success(null)
            }
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun requestMap(): Map<String, String> = mapOf(
        "package" to (intent.getStringExtra(EXTRA_PACKAGE) ?: ""),
        "domain" to (intent.getStringExtra(EXTRA_DOMAIN) ?: ""),
        "label" to (intent.getStringExtra(EXTRA_LABEL) ?: ""),
    )

    @Suppress("DEPRECATION")
    private fun <T> parcelable(key: String, cls: Class<T>): T? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(key, cls) else intent.getParcelableExtra(key)

    @Suppress("DEPRECATION")
    private fun passwordIds(): List<AutofillId> =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(EXTRA_PASSWORD_IDS, AutofillId::class.java) ?: emptyList()
        } else {
            intent.getParcelableArrayListExtra(EXTRA_PASSWORD_IDS) ?: emptyList()
        }

    private fun finishWithFill(username: String, password: String, title: String, otp: String?) {
        if (finished) return
        finished = true
        val usernameId = parcelable(EXTRA_USERNAME_ID, AutofillId::class.java)
        val otpId = parcelable(EXTRA_OTP_ID, AutofillId::class.java)
        val pwIds = passwordIds()
        @Suppress("DEPRECATION")
        val b = Dataset.Builder(Presentations.menu(this, title.ifEmpty { username }, username))
        var any = false
        usernameId?.let { b.setValue(it, AutofillValue.forText(username)); any = true }
        pwIds.forEach { b.setValue(it, AutofillValue.forText(password)); any = true }
        if (otpId != null && !otp.isNullOrEmpty()) {
            b.setValue(otpId, AutofillValue.forText(otp)); any = true
        }
        if (!any) {
            finishCancelled()
            return
        }
        val data = Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, b.build())
        setResult(Activity.RESULT_OK, data)
        finish()
    }

    private fun finishCancelled() {
        if (finished) return
        finished = true
        setResult(Activity.RESULT_CANCELED)
        finish()
    }

    override fun onDestroy() {
        if (!finished && isFinishing) setResult(Activity.RESULT_CANCELED)
        super.onDestroy()
    }

    @Suppress("unused")
    private fun ctx(): Context = this
}
