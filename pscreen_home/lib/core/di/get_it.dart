import 'package:get_it/get_it.dart';

/// 全局 get_it 实例
///
/// 注意：宿主**不要**与自己的 `core/di/get_it.dart` 同时 import 本文件
/// —— 两边都有同名的 `getIt` / `GetItConfig`，同时 import 会产生歧义引用错误。
/// 共享包内部只用本文件；宿主侧继续用自己的那份。
final GetIt getIt = GetIt.instance;

/// get_it 的底层封装（初始化 / 重置）
class GetItConfig {
  const GetItConfig._();

  static Future<void> init() async => getIt.reset();

  static Future<void> reset() async => getIt.reset();
}
