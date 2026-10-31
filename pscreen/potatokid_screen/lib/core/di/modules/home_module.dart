import 'package:potatokid_screen/core/di/get_it.dart';
import 'package:potatokid_screen/features/home/application/bloc/home_bloc.dart';
import 'package:potatokid_screen/features/home/data/repositories/home_repository_impl.dart';
import 'package:potatokid_screen/features/home/domain/repositories/home_repository.dart';

/// 首页模块：注册顺序 Repository → Bloc（Bloc 依赖 Repository）
class HomeModule {
  const HomeModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<HomeRepository>(() => HomeRepositoryImpl());
    getIt.registerFactory<HomeBloc>(
      () => HomeBloc(repository: getIt<HomeRepository>()),
    );
  }

  static Future<void> unregister() async {
    await getIt.unregister<HomeBloc>();
    await getIt.unregister<HomeRepository>();
  }
}
