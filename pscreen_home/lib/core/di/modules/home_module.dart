import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_home/features/home/data/repositories/home_repository_impl.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';

/// 主页模块：注册顺序 Repository → Bloc（Bloc 依赖 Repository）。
class HomeModule {
  const HomeModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<HomeRepository>(
      () => HomeRepositoryImpl(
        client: getIt<HaWsClient>(),
        log: getIt<LogService>(),
      ),
    );
    // HomeBloc 用单例：主页是唯一消费方，连接恢复后由页面重新 LoadHome。
    getIt.registerLazySingleton<HomeBloc>(
      () => HomeBloc(repository: getIt<HomeRepository>()),
    );
  }

  static Future<void> unregister() async {
    await getIt.unregister<HomeBloc>();
    await getIt.unregister<HomeRepository>();
  }
}
