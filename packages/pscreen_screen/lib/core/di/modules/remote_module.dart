import 'package:get_it/get_it.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_bloc.dart';
import 'package:pscreen_screen/features/remote/data/repositories/remote_login_repository_impl.dart';
import 'package:pscreen_screen/features/remote/domain/repositories/remote_login_repository.dart';

/// 远程登录模块：实时通道账号连接（Repository + Bloc）。
///
/// 依赖 NetworkModule 的 [RealtimeChannel]，必须在其之后注册；
/// 注册时先 await 账号持久化加载，保证 Bloc 初始 State 读到已存账号。
class RemoteModule {
  const RemoteModule._();

  static Future<void> register(GetIt it) async {
    final RemoteLoginRepositoryImpl repository =
        RemoteLoginRepositoryImpl(channel: it<RealtimeChannel>());
    await repository.ensureLoaded();
    it.registerLazySingleton<RemoteLoginRepository>(() => repository);
    it.registerLazySingleton<RemoteLoginBloc>(
      () => RemoteLoginBloc(repository: it<RemoteLoginRepository>()),
    );
  }

  static Future<void> unregister(GetIt it) async {
    await it.unregister<RemoteLoginBloc>();
    await it.unregister<RemoteLoginRepository>();
  }
}
