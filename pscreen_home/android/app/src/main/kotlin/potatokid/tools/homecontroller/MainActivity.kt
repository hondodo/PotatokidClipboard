package potatokid.tools.homecontroller

import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 中控屏宿主 Activity。
 *
 * 除了承载 Flutter 界面，还负责把系统状态栏 / 底部导航栏彻底隐藏：
 * 15 寸壁挂面板上系统栏会压住底部卡片，而且开机或弹窗后系统会把导航栏
 * 重新显示出来，所以除了 onCreate，还要在 onResume 和每次重新获得焦点时
 * 重新进入沉浸式（IMMERSIVE_STICKY：从边缘上滑可临时唤出，随后自动隐藏）。
 *
 * 同时实现共享包 `PlatformChannelService` 使用的
 * `potatokid/volume` 通道：遥控端下发的 volume_up / volume_down / mute
 * 命令经由该通道落到系统音量。
 */
class MainActivity : FlutterActivity() {

    private val CHANNEL = "potatokid/volume"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                when (call.method) {
                    "volumeUp" -> {
                        audio.adjustStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            AudioManager.ADJUST_RAISE,
                            AudioManager.FLAG_SHOW_UI
                        )
                        result.success(null)
                    }
                    "volumeDown" -> {
                        audio.adjustStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            AudioManager.ADJUST_LOWER,
                            AudioManager.FLAG_SHOW_UI
                        )
                        result.success(null)
                    }
                    "toggleMute" -> {
                        val muted = audio.isStreamMute(AudioManager.STREAM_MUSIC)
                        audio.setStreamMute(AudioManager.STREAM_MUSIC, !muted)
                        result.success(null)
                    }
                    // 当前媒体音量（0-100 百分比），供遥控端显示。
                    "getVolume" -> {
                        val current = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        result.success(if (max > 0) current * 100 / max else 0)
                    }
                    "getDeviceModel" -> {
                        result.success(Build.MODEL ?: "Android TV")
                    }
                    "getAndroidId" -> {
                        // 卸载重装后 ANDROID_ID 不变，用它作为设备唯一标识。
                        val androidId = try {
                            Settings.Secure.getString(
                                contentResolver,
                                Settings.Secure.ANDROID_ID
                            )
                        } catch (e: Exception) {
                            null
                        }
                        result.success(androidId)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyImmersiveMode()
    }

    override fun onResume() {
        super.onResume()
        applyImmersiveMode()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // 系统弹窗、通知栏、软键盘收起后系统会恢复系统栏，这里再次强制全屏。
        if (hasFocus) applyImmersiveMode()
    }

    @Suppress("DEPRECATION")
    private fun applyImmersiveMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        }
    }
}
