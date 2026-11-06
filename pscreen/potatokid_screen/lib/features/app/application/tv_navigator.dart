import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/features/app/application/app_tab_controller.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/presentation/pages/main_app.dart';
import 'package:potatokid_screen/features/profile/application/profile_focus_controller.dart';
import 'package:pscreen_screen/features/msg/application/message_command_executor.dart';

/// 电视端远程导航：`nav` 指令 → 顶部 Tab 分支。
///
/// 电视没有独立天气页，`weather` 映射到「时间页」分支（天气卡片所在）。
/// 电视端已移除屏保页，`screensaver` 返回 false（由中控/家长端入口侧处理）。
class TvNavigator implements HostNavigator {
  const TvNavigator();

  @override
  Future<bool> open(String page) async {
    final int? index = switch (page) {
      'home' || 'live' => 0,
      'weather' => 1,
      'settings' => AppTabController.profileIndex,
      _ => null,
    };
    if (index == null) return false;
    final shell = MainApp.current;
    if (shell == null) return false;
    // 与本地切页保持一致：设置页恒显导航条，其余页面进入即收起。
    // 已在目标页时不改条状态，避免远程指令把用户刚呼出的条收掉。
    final AppBloc bloc = Injection.get<AppBloc>();
    if (index != shell.currentIndex) {
      if (index == AppTabController.profileIndex) {
        ProfileFocusController.instance.reset();
        bloc.add(const SetChrome(true));
      } else {
        bloc.add(const SetChrome(false));
      }
    }
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
    return true;
  }
}
