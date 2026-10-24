import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/screensaver/screensaver_controller.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_home/core/ui/ui_scale.dart';

/// 存储模块：注册本地配置持久化（手动设置的 HA 地址 / 令牌）。
///
/// 依赖 `LogService`（NetworkModule 提供），必须在其之后注册。
class StorageModule {
  const StorageModule._();

  static Future<void> register() async {
    final SettingsStore store = SettingsStore();
    await store.init();
    getIt.registerSingleton<SettingsStore>(store);
    getIt.registerSingleton<ScreensaverController>(
      ScreensaverController(store),
    );
    getIt.registerSingleton<UiScaleController>(UiScaleController(store));
  }

  static Future<void> unregister() async {
    await getIt.unregister<ScreensaverController>();
    await getIt.unregister<UiScaleController>();
    await getIt.unregister<SettingsStore>();
  }
}
