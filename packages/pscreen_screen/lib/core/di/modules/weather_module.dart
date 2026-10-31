import 'package:get_it/get_it.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/data/repositories/weather_repository_impl.dart';
import 'package:pscreen_screen/features/weather/domain/repositories/weather_repository.dart';

/// 天气模块：注册顺序 Repository → Bloc（Bloc 依赖 Repository）。
class WeatherModule {
  const WeatherModule._();

  static Future<void> register(GetIt it) async {
    it.registerLazySingleton<WeatherRepository>(() => WeatherRepositoryImpl());
    // WeatherBloc 用单例：时间页/屏保页/主页共享同一个天气状态机。
    it.registerLazySingleton<WeatherBloc>(
      () => WeatherBloc(repository: it<WeatherRepository>()),
    );
  }

  static Future<void> unregister(GetIt it) async {
    await it.unregister<WeatherBloc>();
    await it.unregister<WeatherRepository>();
  }
}