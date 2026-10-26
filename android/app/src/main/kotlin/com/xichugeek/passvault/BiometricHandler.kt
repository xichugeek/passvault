package com.xichugeek.passvault

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * 指纹解锁：数据用 Android Keystore 中的 AES-256-GCM 密钥加密，
 * 该密钥设置为"每次使用都必须通过强生物识别"，并在新增指纹后自动失效。
 * 密钥永远不会离开安全硬件（TEE/StrongBox）。
 */
class BiometricHandler(private val activity: FragmentActivity) : MethodChannel.MethodCallHandler {
    companion object {
        private const val KEY_ALIAS = "passvault_quick_unlock_v1"
        private const val KEYSTORE = "AndroidKeyStore"
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "passvault/biometric").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(
                BiometricManager.from(activity).canAuthenticate(BIOMETRIC_STRONG) ==
                    BiometricManager.BIOMETRIC_SUCCESS
            )
            "encrypt" -> {
                val data = Base64.decode(call.argument<String>("data"), Base64.NO_WRAP)
                val cipher = try {
                    Cipher.getInstance("AES/GCM/NoPadding").apply {
                        init(Cipher.ENCRYPT_MODE, getOrCreateKey(recreate = true))
                    }
                } catch (e: Exception) {
                    result.error("crypto", e.message, null)
                    return
                }
                prompt(call.argument<String>("title") ?: "开启指纹解锁", cipher, result) { c ->
                    val ct = c.doFinal(data)
                    mapOf(
                        "ct" to Base64.encodeToString(ct, Base64.NO_WRAP),
                        "iv" to Base64.encodeToString(c.iv, Base64.NO_WRAP)
                    )
                }
            }
            "decrypt" -> {
                val ct = Base64.decode(call.argument<String>("ct"), Base64.NO_WRAP)
                val iv = Base64.decode(call.argument<String>("iv"), Base64.NO_WRAP)
                val cipher = try {
                    val key = getKey() ?: run {
                        result.error("invalidated", "key missing", null)
                        return
                    }
                    Cipher.getInstance("AES/GCM/NoPadding").apply {
                        init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
                    }
                } catch (e: KeyPermanentlyInvalidatedException) {
                    deleteKey()
                    result.error("invalidated", e.message, null)
                    return
                } catch (e: Exception) {
                    result.error("crypto", e.message, null)
                    return
                }
                prompt(call.argument<String>("title") ?: "解锁密码库", cipher, result) { c ->
                    Base64.encodeToString(c.doFinal(ct), Base64.NO_WRAP)
                }
            }
            "deleteKey" -> {
                deleteKey()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun prompt(
        title: String,
        cipher: Cipher,
        result: MethodChannel.Result,
        onSuccess: (Cipher) -> Any
    ) {
        var done = false
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                if (done) return
                done = true
                try {
                    result.success(onSuccess(r.cryptoObject!!.cipher!!))
                } catch (e: Exception) {
                    result.error("crypto", e.message, null)
                }
            }

            override fun onAuthenticationError(code: Int, msg: CharSequence) {
                if (done) return
                done = true
                val cancelled = code == BiometricPrompt.ERROR_USER_CANCELED ||
                    code == BiometricPrompt.ERROR_NEGATIVE_BUTTON ||
                    code == BiometricPrompt.ERROR_CANCELED
                result.error(if (cancelled) "cancelled" else "auth", msg.toString(), null)
            }
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle("PassVault")
            .setNegativeButtonText("使用主密码")
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .setConfirmationRequired(false)
            .build()
        BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
            .authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    private fun getKey(): SecretKey? {
        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        return ks.getKey(KEY_ALIAS, null) as? SecretKey
    }

    private fun getOrCreateKey(recreate: Boolean): SecretKey {
        if (!recreate) getKey()?.let { return it }
        // 已有数据用旧密钥加密时不能删除；同一设备所有密码库共用一个密钥
        getKey()?.let {
            try {
                Cipher.getInstance("AES/GCM/NoPadding").init(Cipher.ENCRYPT_MODE, it)
                return it
            } catch (_: KeyPermanentlyInvalidatedException) {
                deleteKey()
            }
        }
        val builder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        gen.init(builder.build())
        return gen.generateKey()
    }

    private fun deleteKey() {
        try {
            KeyStore.getInstance(KEYSTORE).apply { load(null) }.deleteEntry(KEY_ALIAS)
        } catch (_: Exception) {
        }
    }
}
