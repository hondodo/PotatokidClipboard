import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/features/remote_control/data/control_settings.dart';
import 'package:pscreen_home/features/remote_control/data/favorite_store.dart';
import 'package:pscreen_home/features/remote_control/data/tv_directory.dart';

/// 遥控模块：注册目标电视目录。
///
/// 实时通道由共享包 `NetworkModule` 注册为单例，此处不重复注册。
class RemoteControlModule {
  const RemoteControlModule._();

  static Future<void> register() async {
    // 持久化（账号 / 口令 / 已勾选目标）需先加载完成，
    // 否则 SendCubit 构造时读不到已存目标。
    await ControlSettings.instance.ensureLoaded();
    // 频道收藏（共享包之外的本地偏好，进入遥控面板时立即可用）。
    await FavoriteStore.instance.ensureLoaded();

    getIt.registerLazySingleton<TvDirectory>(() => TvDirectory());
  }

  static Future<void> unregister() async {
    await getIt.unregister<TvDirectory>();
  }
}
