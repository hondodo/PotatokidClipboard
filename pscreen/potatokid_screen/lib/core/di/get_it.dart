import 'package:get_it/get_it.dart';

/// 全局 get_it 实例
final GetIt getIt = GetIt.instance;

/// get_it 的底层封装（初始化 / 重置）
class GetItConfig {
  const GetItConfig._();

  static Future<void> init() async => getIt.reset();

  static Future<void> reset() async => getIt.reset();
}
