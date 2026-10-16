/// 全局路由名称/路径常量，禁止在业务代码中硬编码路径字符串
class RouteNames {
  const RouteNames._();

  // 主页面
  static const String home = '/';

  // 设备详情页（home 的子路由，:deviceId 为设备注册表 id）
  static const String deviceDetail = 'device';
  static const String deviceDetailRelative = 'device/:deviceId';

  /// 设备详情页完整路径
  static String deviceDetailPath(String deviceId) => '/device/$deviceId';
}
