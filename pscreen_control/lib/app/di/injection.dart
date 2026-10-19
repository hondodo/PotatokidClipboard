import 'package:get_it/get_it.dart';
import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/send/data/tv_directory.dart';

final GetIt getIt = GetIt.instance;

/// 依赖注入门面。
class Injection {
  const Injection._();

  static Future<void> init() async {
    await getIt.allReady();
    if (!getIt.isRegistered<NimClient>()) {
      getIt.registerLazySingleton<NimClient>(() => NimClient());
    }
    if (!getIt.isRegistered<TvDirectory>()) {
      getIt.registerLazySingleton<TvDirectory>(() => TvDirectory());
    }
  }
}
