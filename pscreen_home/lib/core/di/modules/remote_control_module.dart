import 'package:pscreen_home/features/remote_control/data/control_settings.dart';
import 'package:pscreen_home/features/remote_control/data/favorite_store.dart';
import 'package:pscreen_home/features/remote_control/data/thread_targets_store.dart';

/// 遥控模块：加载遥控相关的本地持久化。
///
/// 实时通道由共享包 `NetworkModule` 注册为单例，此处不重复注册。
class RemoteControlModule {
  const RemoteControlModule._();

  static Future<void> register() async {
    // 旧版账号/口令迁移依赖这里先加载完成。
    await ControlSettings.instance.ensureLoaded();
    // 频道收藏（共享包之外的本地偏好，进入遥控面板时立即可用）。
    await FavoriteStore.instance.ensureLoaded();
    // 遥控会话目标设备（会话列表只显示这里添加过的账号）。
    await ThreadTargetsStore.instance.ensureLoaded();
  }

  static Future<void> unregister() async {}
}
