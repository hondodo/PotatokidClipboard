/// 全局路由名称/路径常量，禁止在业务代码中硬编码路径字符串
class RouteNames {
  const RouteNames._();

  // Tab 页面
  static const String home = '/';
  static const String profile = '/profile';

  // 普通页面
  static const String homeDetail = '/home/detail';

  // 弹层页面
  static const String settingsSheet = '/settings';
}
