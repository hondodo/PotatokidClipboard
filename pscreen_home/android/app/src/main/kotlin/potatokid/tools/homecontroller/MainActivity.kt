package potatokid.tools.homecontroller

import android.os.Build
import android.os.Bundle
import android.view.View
import io.flutter.embedding.android.FlutterActivity

/**
 * 中控屏宿主 Activity。
 *
 * 除了承载 Flutter 界面，还负责把系统状态栏 / 底部导航栏彻底隐藏：
 * 15 寸壁挂面板上系统栏会压住底部卡片，而且开机或弹窗后系统会把导航栏
 * 重新显示出来，所以除了 onCreate，还要在 onResume 和每次重新获得焦点时
 * 重新进入沉浸式（IMMERSIVE_STICKY：从边缘上滑可临时唤出，随后自动隐藏）。
 */
class MainActivity : FlutterActivity() {

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
