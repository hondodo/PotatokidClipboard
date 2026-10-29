import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/core/screensaver/screensaver_controller.dart';
import 'package:pscreen_screen/features/msg/application/message_command_executor.dart';

/// 中控屏宿主导航：遥控端下发的 `nav` 命令落到这里。
///
/// `screensaver` 是切换语义：屏保中再按一次则退出并回到主页。
class HomeNavigator implements HostNavigator {
  HomeNavigator({
    required AppRouter Function() router,
    required ScreensaverController Function() screensaver,
  })  : _router = router,
        _screensaver = screensaver;

  final AppRouter Function() _router;
  final ScreensaverController Function() _screensaver;

  @override
  Future<bool> open(String page) async {
    final AppRouter router = _router();
    switch (page) {
      case 'home':
        router.go(RouteNames.home);
        return true;
      case 'live':
        router.go(RouteNames.livePath);
        return true;
      case 'weather':
        router.go(RouteNames.weatherPath);
        return true;
      case 'settings':
        router.go(RouteNames.settingsPath);
        return true;
      case 'screensaver':
        if (_screensaver().active) {
          // 已在屏保：退出并回到主页（路由监听会自动清 active）。
          _screensaver().active = false;
          router.go(RouteNames.home);
        } else {
          _screensaver().active = true;
          router.push(RouteNames.clockPath);
        }
        return true;
      default:
        return false;
    }
  }
}
