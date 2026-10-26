package com.xichugeek.passvault.autofill

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * 自动填充专用的 Flutter 引擎（运行 Dart 入口 autofillMain）。
 * 引擎在填充界面关闭后继续存活，解锁状态保留到超时，
 * 期间自动填充服务可以直接向它查询匹配的账号，实现"一键填充"。
 */
object AutofillEngine {
    const val ENGINE_ID = "passvault_autofill"
    const val CHANNEL = "passvault/autofill"

    fun get(): FlutterEngine? = FlutterEngineCache.getInstance().get(ENGINE_ID)

    fun getOrCreate(context: Context): FlutterEngine {
        get()?.let { return it }
        val app = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) {
            loader.startInitialization(app)
        }
        loader.ensureInitializationComplete(app, null)
        val engine = FlutterEngine(app)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "autofillMain")
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }

    fun channel(engine: FlutterEngine) =
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
}
