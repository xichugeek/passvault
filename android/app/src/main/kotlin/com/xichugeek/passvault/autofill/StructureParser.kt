package com.xichugeek.passvault.autofill

import android.app.assist.AssistStructure
import android.os.Build
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import androidx.annotation.RequiresApi

/** 解析出的登录表单 */
data class ParsedForm(
    val packageName: String,
    val webDomain: String?,
    val usernameId: AutofillId?,
    val passwordIds: List<AutofillId>,
    val otpId: AutofillId?,
) {
    val allIds: List<AutofillId>
        get() = listOfNotNull(usernameId) + passwordIds + listOfNotNull(otpId)

    val isFillable: Boolean get() = usernameId != null || passwordIds.isNotEmpty()
}

/**
 * 从 AssistStructure 中识别用户名、密码、验证码输入框。
 * 依次参考：autofillHints → 网页 input 属性 → inputType → 资源 ID / 提示文字关键词（含中文）。
 */
@RequiresApi(Build.VERSION_CODES.O)
class StructureParser(private val structure: AssistStructure) {

    private enum class Kind { USERNAME, PASSWORD, OTP, OTHER, IGNORE }

    private data class Field(val id: AutofillId, val kind: Kind, val order: Int)

    private var webDomain: String? = null
    private val fields = mutableListOf<Field>()
    private var order = 0

    fun parse(): ParsedForm {
        for (i in 0 until structure.windowNodeCount) {
            visit(structure.getWindowNodeAt(i).rootViewNode)
        }
        val passwords = fields.filter { it.kind == Kind.PASSWORD }
        var username = fields.firstOrNull { it.kind == Kind.USERNAME }
        if (username == null && passwords.isNotEmpty()) {
            // 没有明确的用户名框：取第一个密码框之前最近的普通文本框
            val firstPw = passwords.first().order
            username = fields.lastOrNull { it.kind == Kind.OTHER && it.order < firstPw }
        }
        return ParsedForm(
            packageName = structure.activityComponent?.packageName ?: "",
            webDomain = webDomain,
            usernameId = username?.id,
            passwordIds = passwords.map { it.id },
            otpId = fields.firstOrNull { it.kind == Kind.OTP }?.id,
        )
    }

    private fun visit(node: AssistStructure.ViewNode) {
        node.webDomain?.takeIf { it.isNotBlank() && webDomain == null }?.let { webDomain = it }
        val id = node.autofillId
        if (id != null && node.autofillType == View.AUTOFILL_TYPE_TEXT &&
            node.visibility == View.VISIBLE && node.isEnabled
        ) {
            val kind = classify(node)
            if (kind != Kind.IGNORE) fields.add(Field(id, kind, order++))
        }
        for (i in 0 until node.childCount) visit(node.getChildAt(i))
    }

    private fun classify(node: AssistStructure.ViewNode): Kind {
        // 1. 明确的 autofillHints
        node.autofillHints?.let { hints ->
            for (h in hints) {
                val l = h.lowercase()
                when {
                    l.contains("otp") || l.contains("onetimecode") || l.contains("one-time-code") -> return Kind.OTP
                    l.contains("password") -> return Kind.PASSWORD
                    l.contains("username") || l.contains("email") || l.contains("phone") ||
                        l == "tel" -> return Kind.USERNAME
                    l.contains("creditcard") || l.contains("postal") || l.contains("address") ||
                        l == "name" -> return Kind.IGNORE
                }
            }
        }

        // 2. 网页 input
        val html = node.htmlInfo
        if (html != null) {
            if (!html.tag.equals("input", ignoreCase = true) && !html.tag.equals("textarea", true)) {
                return Kind.IGNORE
            }
            val attrs = html.attributes?.associate { it.first.lowercase() to (it.second ?: "").lowercase() } ?: emptyMap()
            val type = attrs["type"] ?: "text"
            val ac = attrs["autocomplete"] ?: ""
            when {
                type == "hidden" || type == "submit" || type == "button" || type == "checkbox" ||
                    type == "radio" || type == "search" -> return Kind.IGNORE
                ac.contains("one-time-code") -> return Kind.OTP
                type == "password" || ac.contains("password") -> return Kind.PASSWORD
                type == "email" || ac.contains("username") || ac.contains("email") -> return Kind.USERNAME
                type == "tel" -> return Kind.USERNAME
            }
            val nameish = listOf(attrs["name"], attrs["id"], attrs["placeholder"], attrs["aria-label"])
                .joinToString(" ") { it ?: "" }
            keywordKind(nameish)?.let { return it }
            return if (type == "text" || type == "number") Kind.OTHER else Kind.IGNORE
        }

        // 3. 原生控件 inputType
        val it = node.inputType
        val cls = it and InputType.TYPE_MASK_CLASS
        val variation = it and InputType.TYPE_MASK_VARIATION
        if (cls == InputType.TYPE_CLASS_TEXT) {
            when (variation) {
                InputType.TYPE_TEXT_VARIATION_PASSWORD,
                InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
                InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD -> return Kind.PASSWORD
                InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS -> return Kind.USERNAME
                InputType.TYPE_TEXT_VARIATION_URI,
                InputType.TYPE_TEXT_VARIATION_POSTAL_ADDRESS,
                InputType.TYPE_TEXT_VARIATION_PERSON_NAME -> return Kind.IGNORE
            }
        } else if (cls == InputType.TYPE_CLASS_NUMBER &&
            variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
        ) {
            return Kind.PASSWORD
        }

        // 4. 关键词
        val text = listOf(node.idEntry, node.hint, node.contentDescription?.toString())
            .joinToString(" ") { it ?: "" }
        keywordKind(text)?.let { return it }

        val className = node.className ?: ""
        val editable = className.contains("EditText") || className.contains("TextField") ||
            cls == InputType.TYPE_CLASS_TEXT || cls == InputType.TYPE_CLASS_PHONE ||
            cls == InputType.TYPE_CLASS_NUMBER
        if (!editable) return Kind.IGNORE
        if (cls == InputType.TYPE_CLASS_PHONE) return Kind.USERNAME
        return Kind.OTHER
    }

    private fun keywordKind(raw: String): Kind? {
        val s = raw.lowercase()
        if (s.isBlank()) return null
        if (s.contains("search") || s.contains("搜索") || s.contains("captcha") || s.contains("图形验证")) {
            return Kind.IGNORE
        }
        if (s.contains("otp") || s.contains("2fa") || s.contains("totp") || s.contains("verification") ||
            s.contains("验证码") || s.contains("动态码") || s.contains("短信码")
        ) return Kind.OTP
        if (s.contains("password") || s.contains("passwd") || s.contains("pwd") || s.contains("pass_word") ||
            s.contains("密码") || s.contains("口令") || s.contains("passcode")
        ) return Kind.PASSWORD
        if (s.contains("user") || s.contains("login") || s.contains("email") || s.contains("e-mail") ||
            s.contains("account") || s.contains("phone") || s.contains("mobile") || s.contains("username") ||
            s.contains("账号") || s.contains("帐号") || s.contains("用户名") || s.contains("手机") ||
            s.contains("邮箱") || s.contains("登录名") || s.contains("学号") || s.contains("工号")
        ) return Kind.USERNAME
        return null
    }
}
