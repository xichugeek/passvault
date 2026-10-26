package com.xichugeek.passvault

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * 主界面。继承 FlutterFragmentActivity 以支持 BiometricPrompt（指纹解锁）。
 */
class MainActivity : FlutterFragmentActivity() {
    private lateinit var saf: SafHandler

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 默认禁止截屏，Flutter 端可按设置关闭
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        saf = SafHandler(this)
        saf.register(messenger)
        BiometricHandler(this).register(messenger)
        SystemHandler(this).register(messenger)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (::saf.isInitialized && saf.onActivityResult(requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
