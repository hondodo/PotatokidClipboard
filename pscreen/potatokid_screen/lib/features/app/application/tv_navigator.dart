import 'package:potatokid_screen/features/app/presentation/pages/main_app.dart';
import 'package:pscreen_screen/features/msg/application/message_command_executor.dart';

/// 电视端远程导航：`nav` 指令 → 顶部 Tab 分支。
///
/// 电视没有独立天气页，`weather` 映射到「时间页」分支（天气卡片所在）。
class TvNavigator implements HostNavigator {
  const TvNavigator();

  @override
  Future<bool> open(String page) async {
    final int? index = switch (page) {
      'home' || 'live' => 0,
      'weather' => 1,
      'screensaver' => 2,
      'settings' => 3,
      _ => null,
    };
    if (index == null) return false;
    final shell = MainApp.current;
    if (shell == null) return false;
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
    return true;
  }
}
