import 'package:potatokid_screen/core/di/get_it.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';

/// 应用级模块：注册全局 Bloc（无依赖，可最先注册）
class AppModule {
  const AppModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<AppBloc>(() => AppBloc());
  }

  static Future<void> unregister() async {
    await getIt.unregister<AppBloc>();
  }
}
