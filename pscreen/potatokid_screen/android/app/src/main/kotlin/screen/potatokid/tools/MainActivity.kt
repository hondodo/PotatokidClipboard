package screen.potatokid.tools

import android.media.AudioManager
import android.media.MediaDrm
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val CHANNEL = "potatokid/volume"
    private val APP_CHANNEL = "potatokid/app"

    /** Widevine 的 UUID：MediaDrm 设备唯一 ID 只在 Widevine 下可取。 */
    private val WIDEVINE_UUID = UUID(-0x121074568629b532L, -0x5c37d8232ae2de13L)

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
                    // 设备唯一编号原始值：ANDROID_ID（API 26+ 由「签名密钥+用户+设备」
                    // 决定，卸载重装不变）+ MediaDrm 设备 ID（ANDROID_ID 不可用时的兜底）。
                    "getDeviceIdentity" -> {
                        result.success(
                            mapOf(
                                "androidId" to (
                                    Settings.Secure.getString(
                                        contentResolver,
                                        Settings.Secure.ANDROID_ID
                                    ) ?: ""
                                    ),
                                "mediaDrmId" to mediaDrmDeviceId()
                            )
                        )
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 定时关闭：先移除整个 task，再结束进程。
                    // 仅 finish() 在多 task / home 栈场景里可能只关掉前台实例，
                    // 用户会看到 App「没退」；这里确保同进程的实例全部结束。
                    "exitApp" -> {
                        result.success(null)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                            finishAndRemoveTask()
                        } else {
                            finish()
                        }
                        Handler(Looper.getMainLooper()).postDelayed(
                            { Process.killProcess(Process.myPid()) },
                            300L,
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** 读取 MediaDrm（Widevine）设备唯一 ID 的十六进制串；不可用时返回空串。 */
    private fun mediaDrmDeviceId(): String {
        var drm: MediaDrm? = null
        return try {
            drm = MediaDrm(WIDEVINE_UUID)
            drm.getPropertyByteArray(MediaDrm.PROPERTY_DEVICE_UNIQUE_ID)
                .joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }
        } catch (e: Throwable) {
            ""
        } finally {
            try {
                // 用 release() 而非 close()：close() 是 API 28 才有的方法，
                // 在 Android 7.x/8.x 上调用会 NoSuchMethodError 崩溃。
                drm?.release()
            } catch (e: Throwable) {
                // 释放失败忽略
            }
        }
    }
}
