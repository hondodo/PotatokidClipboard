import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/features/remote_control/data/control_settings.dart';
import 'package:pscreen_home/features/remote_control/data/nim_client.dart';
import 'package:pscreen_home/features/remote_control/data/tv_directory.dart';

/// 遥控模块：注册 NIM 发送端客户端、目标电视目录。
///
/// 依赖共享包 `ScreenModules.register` 已注册的 `NimManager`
/// （NIM SDK 由宿主统一初始化，此处不重复 initialize）。
class RemoteControlModule {
  const RemoteControlModule._();

  static Future<void> register() async {
    // 持久化（账号 / token / 已勾选目标）需先加载完成，
    // 否则 SendCubit 构造时读不到已存目标。
    await ControlSettings.instance.ensureLoaded();

    getIt.registerLazySingleton<NimClient>(() => NimClient());
    getIt.registerLazySingleton<TvDirectory>(() => TvDirectory());
  }

  static Future<void> unregister() async {
    await getIt.unregister<TvDirectory>();
    await getIt.unregister<NimClient>();
  }
}
