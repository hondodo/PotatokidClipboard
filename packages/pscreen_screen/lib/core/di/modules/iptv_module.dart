import 'package:get_it/get_it.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:pscreen_screen/features/iptv/data/repositories/iptv_repository_impl.dart';
import 'package:pscreen_screen/features/iptv/domain/repositories/iptv_repository.dart';

/// IPTV 模块：注册顺序 Repository → Bloc（Bloc 依赖 Repository）。
class IptvModule {
  const IptvModule._();

  static Future<void> register(GetIt it) async {
    it.registerLazySingleton<IptvRepository>(() => IptvRepositoryImpl());
    // IptvBloc 用单例，使「我的」页与首页共享同一个状态机，
    // 修改/刷新频道列表后首页能跟随更新。
    it.registerLazySingleton<IptvBloc>(
      () => IptvBloc(repository: it<IptvRepository>()),
    );
  }

  static Future<void> unregister(GetIt it) async {
    await it.unregister<IptvBloc>();
    await it.unregister<IptvRepository>();
  }
}