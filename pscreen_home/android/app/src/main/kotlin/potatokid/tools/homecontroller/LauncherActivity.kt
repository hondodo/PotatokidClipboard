package potatokid.tools.homecontroller

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * 桌面图标入口（只注册 LAUNCHER，不注册 HOME）。
 *
 * 主界面 [MainActivity] 是系统默认桌面，只接受 HOME 意图，因此永远位于
 * home 栈。若让 MainActivity 自己带 LAUNCHER，从第三方桌面点图标会新建一个
 * 普通任务栈实例，而按 Home 系统又会在 home 栈新建一个；singleTop / singleTask
 * 跨栈无法复用，一个进程里就会出现两个 FlutterActivity / 两个 FlutterEngine，
 * 各自跑一套心跳上报。
 *
 * 这里用一个不含 Flutter 的空壳 Activity 承接图标点击：拉起 HOME 意图后立即
 * 结束自己，不会产生第二个引擎。开机自启依赖的 HOME 过滤仍在 MainActivity 上。
 */
class LauncherActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            // setPackage 限定只解析到本应用，避免设备上未把本应用设为默认桌面时
            // 打开别的 Launcher；action/category 保持 HOME 语义，任务会落回 home 栈。
            val home = Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .setPackage(packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(home)
        } catch (e: Exception) {
            // 极端情况下解析不到桌面进程（例如包被禁用），直接拉起主界面兜底。
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
        finish()
    }
}
