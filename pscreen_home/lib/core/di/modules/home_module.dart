import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_home/features/home/application/history_service.dart';
import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/home/data/repositories/home_repository_impl.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';

/// 主页模块：Repository → 指标历史/采样器 → 历史服务 → Bloc。
class HomeModule {
  const HomeModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<HomeRepository>(
      () => HomeRepositoryImpl(
        client: getIt<HaWsClient>(),
        log: getIt<LogService>(),
      ),
    );
    // 指标历史仅驻内存；采样间隔取自持久化配置（默认 5 秒）。
    getIt.registerLazySingleton<MetricHistoryStore>(() => MetricHistoryStore());
    getIt.registerLazySingleton<MetricSampler>(
      () => MetricSampler(
        store: getIt<MetricHistoryStore>(),
        log: getIt<LogService>(),
        interval: Duration(
          seconds: getIt<SettingsStore>().powerSampleSeconds,
        ),
      ),
    );
    getIt.registerLazySingleton<HistoryService>(
      () => HistoryService(
        repository: getIt<HomeRepository>(),
        store: getIt<MetricHistoryStore>(),
      ),
    );
    // HomeBloc 用单例：主页是唯一消费方，连接恢复后由页面重新 LoadHome。
    getIt.registerLazySingleton<HomeBloc>(
      () => HomeBloc(
        repository: getIt<HomeRepository>(),
        sampler: getIt<MetricSampler>(),
      ),
    );
  }

  static Future<void> unregister() async {
    await getIt.unregister<HomeBloc>();
    await getIt.unregister<HistoryService>();
    await getIt.unregister<MetricSampler>();
    await getIt.unregister<MetricHistoryStore>();
    await getIt.unregister<HomeRepository>();
  }
}
