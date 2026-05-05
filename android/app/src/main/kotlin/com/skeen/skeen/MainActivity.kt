package com.skeen.skeen

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val plugin = SkeenArPlugin(applicationContext).also { it.activity = this }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "skeen.detection/ar"
        ).setMethodCallHandler(plugin)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "skeen.detection/ar/distance"
        ).setStreamHandler(plugin)
    }
}
