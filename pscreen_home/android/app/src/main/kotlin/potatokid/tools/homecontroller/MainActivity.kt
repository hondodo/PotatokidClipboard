package potatokid.tools.homecontroller

import android.content.Intent
import android.media.AudioManager
import android.media.MediaDrm
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/**
 * 宿主 Activity（board / phone / parent 三个 flavor 共用）。
 *
 * 系统栏策略按 flavor 区分：
 * - board（15 寸壁挂中控屏）：彻底隐藏状态栏 / 导航栏，避免压住底部卡片；
 *   开机或弹窗后系统会重新显示，故 onCreate / onResume / 重新获得焦点时都
 *   强制进入沉浸式（IMMERSIVE_STICKY）。
 * - parent（家长端，浅色主题）：**必须显示状态栏**，并且显式设为浅底 + 深色
 *   图标，与浅色 AppBar 融合。此前共用沉浸逻辑会把状态栏藏成黑条（MIUI 上
 *   Flutter 的 SystemUIOverlayStyle 又被忽略），真机表现为顶部纯黑一条。
 * - phone（手机端）：同样不强制沉浸，保持系统默认状态栏。
 *
 * 同时实现共享包 `PlatformChannelService` 使用的
 * `potatokid/volume` 通道：遥控端下发的 volume_up / volume_down / mute
 * 命令经由该通道落到系统音量。
 */
class MainActivity : FlutterActivity() {

    private val CHANNEL = "potatokid/volume"
    private val UPDATER_CHANNEL = "potatokid/updater"

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
                        result.success(androidId())
                    }
                    "getDeviceIdentity" -> {
                        val id = androidId().trim()
                        val normalized = id.lowercase()
                        val needsFallback = normalized.isEmpty() ||
                            normalized == "9774d56d682e549c" ||
                            normalized.none { it in '1'..'9' || it in 'a'..'f' }
                        result.success(
                            mapOf(
                                "androidId" to id,
                                "mediaDrmId" to if (needsFallback) mediaDrmDeviceId() else ""
                            )
                        )
                    }
                    else -> result.notImplemented()
                }
            }
        // 应用内更新：私有目录 APK → FileProvider → 系统安装器；外部链接（iOS 商店）直接打开。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid_arguments", "安装包路径为空", null)
                        } else if (!packageManager.canRequestPackageInstalls()) {
                            // 未授予「安装未知应用」：跳系统授权页；返回 false 让
                            // Dart 侧保持 ready（不误报 installing），用户授权后
                            // 回来再点「更新」即可正常安装。
                            try {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                        Uri.parse("package:$packageName")
                                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                                result.success(false)
                            } catch (e: Exception) {
                                result.error("install_failed", e.message ?: "无法打开授权设置", null)
                            }
                        } else {
                            try {
                                val uri = FileProvider.getUriForFile(
                                    this,
                                    "${packageName}.fileprovider",
                                    File(path)
                                )
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("install_failed", e.message ?: "无法拉起安装器", null)
                            }
                        }
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("invalid_arguments", "链接为空", null)
                        } else {
                            try {
                                startActivity(
                                    Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("open_failed", e.message ?: "无法打开链接", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun androidId(): String = try {
        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: ""
    } catch (e: Exception) {
        ""
    }

    private fun mediaDrmDeviceId(): String {
        var drm: MediaDrm? = null
        return try {
            drm = MediaDrm(UUID(-0x121074568629b532L, -0x5c37d8232ae2de13L))
            drm.getPropertyByteArray(MediaDrm.PROPERTY_DEVICE_UNIQUE_ID)
                .joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }
        } catch (e: Exception) {
            ""
        } finally {
            try {
                drm?.release()
            } catch (e: Exception) {
                // DRM 不可用时，交由共享层使用本地兜底值。
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

    /**
     * flavor 判定用 [getPackageName]（= 各 flavor 的 applicationId），不依赖
     * BuildConfig.FLAVOR——AGP 8.x 默认不再生成 BuildConfig，直接引用会编译失败。
     * 包名：board=potatokid.tools.homecontroller / parent=….parent / phone=….phone。
     */
    private val isBoardFlavor: Boolean
        get() = packageName == "potatokid.tools.homecontroller"
    private val isParentFlavor: Boolean
        get() = packageName.endsWith(".parent")

    @Suppress("DEPRECATION")
    private fun applyImmersiveMode() {
        if (!isBoardFlavor) {
            // 家长端 / 手机端：不隐藏系统栏。家长端显式设置浅色状态栏（浅底 +
            // 深色图标），与 #F7F9F8 的浅色 UI 融合；用 WindowInsetsControllerCompat
            // 而非已废弃的 systemUiVisibility，MIUI 等 ROM 兼容性更好。
            if (isParentFlavor) {
                applyParentLightStatusBar()
            }
            return
        }
        // board 壁挂中控屏：维持原沉浸式全屏，隐藏状态栏 / 导航栏。
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

    /** 家长端浅色状态栏：浅底 #F7F9F8 + 深色图标，导航栏同色系。 */
    private fun applyParentLightStatusBar() {
        val lightBg = 0xFFF7F9F8.toInt()
        WindowCompat.setDecorFitsSystemWindows(window, true)
        window.statusBarColor = lightBg
        window.navigationBarColor = lightBg
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.navigationBarDividerColor = 0x00000000
        }
        // Android 10+ 关闭导航栏强制对比遮罩，避免浅底被系统压暗。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
        // isAppearanceLightStatusBars = true → 浅底配深色图标；导航栏同理。
        WindowInsetsControllerCompat(window, window.decorView).apply {
            isAppearanceLightStatusBars = true
            isAppearanceLightNavigationBars = true
        }
    }
}
