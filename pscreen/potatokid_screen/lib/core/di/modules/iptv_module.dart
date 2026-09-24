import 'package:potatokid_screen/core/di/get_it.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:potatokid_screen/features/iptv/data/repositories/iptv_repository_impl.dart';
import 'package:potatokid_screen/features/iptv/domain/repositories/iptv_repository.dart';

/// IPTV 模块：注册顺序 Repository → Bloc（Bloc 依赖 Repository）。
class IptvModule {
  const IptvModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<IptvRepository>(() => IptvRepositoryImpl());
    getIt.registerFactory<IptvBloc>(
      () => IptvBloc(repository: getIt<IptvRepository>()),
    );
  }

  static Future<void> unregister() async {
    await getIt.unregister<IptvBloc>();
    await getIt.unregister<IptvRepository>();
  }
}