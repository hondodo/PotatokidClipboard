import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_home/features/home/application/power_history.dart';
import 'package:pscreen_home/features/home/data/repositories/home_repository_impl.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';

/// 主页模块：注册顺序 Repository → 功率历史/采样器 → Bloc。
class HomeModule {
  const HomeModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<HomeRepository>(
      () => HomeRepositoryImpl(
        client: getIt<HaWsClient>(),
        log: getIt<LogService>(),
      ),
    );
    // 功率历史仅驻内存；采样间隔取自持久化配置（默认 5 秒）。
    getIt.registerLazySingleton<PowerHistoryStore>(() => PowerHistoryStore());
    getIt.registerLazySingleton<PowerSampler>(
      () => PowerSampler(
        store: getIt<PowerHistoryStore>(),
        log: getIt<LogService>(),
        interval: Duration(
          seconds: getIt<SettingsStore>().powerSampleSeconds,
        ),
      ),
    );
    // HomeBloc 用单例：主页是唯一消费方，连接恢复后由页面重新 LoadHome。
    getIt.registerLazySingleton<HomeBloc>(
      () => HomeBloc(
        repository: getIt<HomeRepository>(),
        sampler: getIt<PowerSampler>(),
      ),
    );
  }

  static Future<void> unregister() async {
    await getIt.unregister<HomeBloc>();
    await getIt.unregister<PowerSampler>();
    await getIt.unregister<PowerHistoryStore>();
    await getIt.unregister<HomeRepository>();
  }
}
