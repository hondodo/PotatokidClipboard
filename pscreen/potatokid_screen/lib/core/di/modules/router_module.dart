import 'package:potatokid_screen/core/di/get_it.dart';
import 'package:potatokid_screen/core/router/app_router.dart';

/// 路由模块
class RouterModule {
  const RouterModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<AppRouter>(() => AppRouter());
  }

  static Future<void> unregister() async {
    await getIt.unregister<AppRouter>();
  }
}
