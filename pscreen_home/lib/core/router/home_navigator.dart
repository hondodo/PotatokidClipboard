import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/core/screensaver/screensaver_controller.dart';
import 'package:pscreen_home/features/screen/application/live_stage_controller.dart';
import 'package:pscreen_screen/features/msg/application/message_command_executor.dart';

/// 中控屏宿主导航：遥控端下发的 `nav` 命令落到这里。
///
/// `screensaver` 是切换语义：屏保中再按一次则退出并回到主页。
class HomeNavigator implements HostNavigator {
  HomeNavigator({
    required AppRouter Function() router,
    required ScreensaverController Function() screensaver,
    required LiveStageController Function() live,
  }) : _router = router,
       _screensaver = screensaver,
       _live = live;

  final AppRouter Function() _router;
  final ScreensaverController Function() _screensaver;
  final LiveStageController Function() _live;

  @override
  Future<bool> open(String page) async {
    final AppRouter router = _router();
    final LiveStageController live = _live();
    switch (page) {
      case 'home':
        // 悬浮时只切底层页，保留小窗；全屏时离开直播按现状关闭。
        if (live.isFullscreen) {
          live.close(goTo: RouteNames.home);
        } else {
          router.go(RouteNames.home);
        }
        return true;
      case 'live':
        // 未打开则打开；悬浮则回到全屏；全屏则幂等。
        live.toFullscreen();
        return true;
      case 'weather':
        if (live.isFullscreen) {
          live.close(goTo: RouteNames.weatherPath);
        } else {
          router.go(RouteNames.weatherPath);
        }
        return true;
      case 'settings':
        if (live.isFullscreen) {
          live.close(goTo: RouteNames.settingsPath);
        } else {
          router.go(RouteNames.settingsPath);
        }
        return true;
      case 'screensaver':
        // 屏保会盖住全屏/小窗，先关闭直播再进屏保。
        if (live.isActive) live.close();
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
