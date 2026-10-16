import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/router/app_router.dart';

/// 路由模块：注册 AppRouter（GoRouter 封装）。
class RouterModule {
  const RouterModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<AppRouter>(() => AppRouter());
  }

  static Future<void> unregister() async {
    await getIt.unregister<AppRouter>();
  }
}
