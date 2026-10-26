package com.xichugeek.passvault.autofill

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.view.autofill.AutofillValue
import android.view.inputmethod.InlineSuggestionsRequest
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * PassVault 自动填充服务。
 *
 * - 密码库未解锁：显示"用 PassVault 解锁填充"，点击后弹出指纹验证并选择账号。
 * - 已解锁（几分钟内用过）：直接在输入框下拉/键盘上方列出匹配的账号，一点即填。
 */
@RequiresApi(Build.VERSION_CODES.O)
class PassVaultAutofillService : AutofillService() {

    private val main = Handler(Looper.getMainLooper())
    private var requestCounter = 0

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback
    ) {
        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess(null)
            return
        }
        val form = try {
            StructureParser(structure).parse()
        } catch (e: Exception) {
            callback.onSuccess(null)
            return
        }
        if (!form.isFillable || form.packageName == packageName) {
            callback.onSuccess(null)
            return
        }
        val inlineReq = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) request.inlineSuggestionsRequest else null

        val engine = AutofillEngine.get()
        if (engine == null) {
            callback.onSuccess(buildResponse(form, emptyList(), inlineReq))
            return
        }

        // 引擎存在：询问是否已解锁，最多等 1.5 秒
        val answered = AtomicBoolean(false)
        val timeout = Runnable {
            if (answered.compareAndSet(false, true)) {
                callback.onSuccess(buildResponse(form, emptyList(), inlineReq))
            }
        }
        main.postDelayed(timeout, 1500)
        cancellationSignal.setOnCancelListener {
            if (answered.compareAndSet(false, true)) main.removeCallbacks(timeout)
        }
        AutofillEngine.channel(engine).invokeMethod(
            "query",
            mapOf("package" to form.packageName, "domain" to (form.webDomain ?: "")),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (!answered.compareAndSet(false, true)) return
                    main.removeCallbacks(timeout)
                    @Suppress("UNCHECKED_CAST")
                    val list = (result as? List<Map<String, Any?>>)?.map {
                        Credential(
                            it["title"] as? String ?: "",
                            it["username"] as? String ?: "",
                            it["password"] as? String ?: ""
                        )
                    } ?: emptyList()
                    callback.onSuccess(buildResponse(form, list, inlineReq, unlocked = result != null))
                }

                override fun error(code: String, msg: String?, details: Any?) = fallback()
                override fun notImplemented() = fallback()

                private fun fallback() {
                    if (!answered.compareAndSet(false, true)) return
                    main.removeCallbacks(timeout)
                    callback.onSuccess(buildResponse(form, emptyList(), inlineReq))
                }
            }
        )
    }

    data class Credential(val title: String, val username: String, val password: String)

    private fun buildResponse(
        form: ParsedForm,
        matches: List<Credential>,
        inlineReq: Any?,
        unlocked: Boolean = false,
    ): FillResponse? {
        val ids = form.allIds
        if (ids.isEmpty()) return null
        val response = FillResponse.Builder()
        var inlineIndex = 0
        val maxInline = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && inlineReq is InlineSuggestionsRequest)
            inlineReq.maxSuggestionCount else 0

        fun inlineSpecFor(index: Int): android.widget.inline.InlinePresentationSpec? {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
            val r = inlineReq as? InlineSuggestionsRequest ?: return null
            if (index >= maxInline) return null
            val specs = r.inlinePresentationSpecs
            if (specs.isEmpty()) return null
            return specs[minOf(index, specs.size - 1)]
        }

        // 1. 已解锁时直接列出匹配账号
        for (c in matches) {
            val title = c.title.ifEmpty { c.username }
            val b = Dataset.Builder(Presentations.menu(this, title, c.username))
            form.usernameId?.let { b.setValue(it, AutofillValue.forText(c.username)) }
            form.passwordIds.forEach { b.setValue(it, AutofillValue.forText(c.password)) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                inlineSpecFor(inlineIndex)?.let { spec ->
                    Presentations.inline(this, spec, title, c.username, false)?.let {
                        b.setInlinePresentation(it)
                        inlineIndex++
                    }
                }
            }
            if (form.usernameId == null && form.passwordIds.isEmpty()) continue
            response.addDataset(b.build())
        }

        // 2. 解锁 / 选择其他账号
        val label = if (unlocked) "选择其他账号…" else "PassVault 解锁填充"
        val sub = if (unlocked) "PassVault" else (form.webDomain ?: appLabel(form.packageName))
        val auth = Dataset.Builder(Presentations.menu(this, label, sub))
        for (id in ids) auth.setValue(id, null)
        auth.setAuthentication(authIntent(form).intentSender)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            inlineSpecFor(inlineIndex)?.let { spec ->
                Presentations.inline(this, spec, if (unlocked) "其他账号" else "PassVault", null, !unlocked)
                    ?.let { auth.setInlinePresentation(it) }
            }
        }
        response.addDataset(auth.build())
        return response.build()
    }

    private fun authIntent(form: ParsedForm): PendingIntent {
        val intent = Intent(this, AutofillActivity::class.java).apply {
            putExtra(AutofillActivity.EXTRA_PACKAGE, form.packageName)
            putExtra(AutofillActivity.EXTRA_DOMAIN, form.webDomain ?: "")
            putExtra(AutofillActivity.EXTRA_LABEL, appLabel(form.packageName))
            putExtra(AutofillActivity.EXTRA_USERNAME_ID, form.usernameId)
            putParcelableArrayListExtra(AutofillActivity.EXTRA_PASSWORD_IDS, ArrayList(form.passwordIds))
            putExtra(AutofillActivity.EXTRA_OTP_ID, form.otpId)
        }
        var flags = PendingIntent.FLAG_CANCEL_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags = flags or PendingIntent.FLAG_MUTABLE
        return PendingIntent.getActivity(this, ++requestCounter, intent, flags)
    }

    private fun appLabel(pkg: String): String = try {
        val pm = packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, PackageManager.GET_META_DATA)).toString()
    } catch (_: Exception) {
        pkg
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        callback.onSuccess()
    }
}
