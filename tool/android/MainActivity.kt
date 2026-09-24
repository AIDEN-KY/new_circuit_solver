package com.example.circuit_solver

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SHARE_CHANNEL = "circuit_solver/share"
        private const val SHARE_METHOD = "shareText"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method != SHARE_METHOD) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val text = call.argument<String>("text").orEmpty()
            val subject = call.argument<String>("subject")
                ?.takeIf { it.isNotBlank() }
                ?: "电路题求解结果"
            if (text.isBlank()) {
                result.error("EMPTY_SHARE_TEXT", "没有可分享的答案内容。", null)
                return@setMethodCallHandler
            }
            try {
                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_SUBJECT, subject)
                    putExtra(Intent.EXTRA_TEXT, text)
                }
                startActivity(Intent.createChooser(shareIntent, "分享答案"))
                result.success(null)
            } catch (error: Exception) {
                result.error("SHARE_FAILED", "无法调起系统分享。", error.message)
            }
        }
    }
}
