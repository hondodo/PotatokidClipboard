import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';

/// 存储模块：注册本地配置持久化（手动设置的 HA 地址 / 令牌）。
///
/// 依赖 `LogService`（NetworkModule 提供），必须在其之后注册。
class StorageModule {
  const StorageModule._();

  static Future<void> register() async {
    final SettingsStore store = SettingsStore();
    await store.init();
    getIt.registerSingleton<SettingsStore>(store);
  }

  static Future<void> unregister() async {
    await getIt.unregister<SettingsStore>();
  }
}
