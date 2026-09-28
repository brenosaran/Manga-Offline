package br.com.mangaoffline.manga_offline

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "manga_offline/volume"
    private var volumeInterceptionEnabled = false
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    volumeInterceptionEnabled = true
                    result.success(true)
                }
                "disable" -> {
                    volumeInterceptionEnabled = false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeInterceptionEnabled && event != null && event.repeatCount == 0) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    channel?.invokeMethod("volumeDown", null)
                    return true
                }
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    channel?.invokeMethod("volumeUp", null)
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onDestroy() {
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }
}
