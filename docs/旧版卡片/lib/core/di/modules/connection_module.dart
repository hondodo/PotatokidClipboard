import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_bloc.dart';
import 'package:pscreen_home/features/connection/data/repositories/connection_repository_impl.dart';
import 'package:pscreen_home/features/connection/domain/repositories/connection_repository.dart';

/// 连接模块：注册顺序 Repository → Bloc（Bloc 依赖 Repository）。
class ConnectionModule {
  const ConnectionModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<ConnectionRepository>(
      () => ConnectionRepositoryImpl(client: getIt<HaWsClient>()),
    );
    getIt.registerLazySingleton<ConnectionBloc>(
      () => ConnectionBloc(repository: getIt<ConnectionRepository>()),
    );
  }

  static Future<void> unregister() async {
    await getIt.unregister<ConnectionBloc>();
    await getIt.unregister<ConnectionRepository>();
  }
}
