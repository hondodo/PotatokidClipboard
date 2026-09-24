import 'package:potatokid_screen/app/config/app_config.dart';

/// 环境开关的语义化封装（来自 myStar 方案）
class DotEnvUtil {
  const DotEnvUtil._();

  static bool get isDebugMode => AppConfig.isDebug;

  static bool get isForceOpenProxy => AppConfig.enableProxy;

  static bool get isEnableDevTools => AppConfig.enableDevTools;
}
