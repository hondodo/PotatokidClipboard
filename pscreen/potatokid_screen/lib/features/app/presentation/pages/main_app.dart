import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:potatokid_screen/features/iptv/application/home_now_playing_controller.dart';
import 'package:potatokid_screen/features/iptv/application/live_channel_controller.dart';
import 'package:potatokid_screen/features/profile/application/profile_focus_controller.dart';
import 'package:potatokid_screen/features/time/application/time_style_controller.dart';
import 'package:potatokid_screen/core/utils/key_repeat_controller.dart';
import 'package:potatokid_screen/shared/widgets/auto_hide_chrome.dart';
import 'package:potatokid_screen/shared/widgets/confirm_dialog.dart';
import 'package:potatokid_screen/shared/widgets/exit_confirm_scope.dart';
import 'package:potatokid_screen/shared/widgets/floating_remote.dart';

/// 单个顶部 Tab 的静态描述（图标 + 文案 key）。
class _TabDescriptor {
  const _TabDescriptor(this.labelKey, this.icon, this.selectedIcon);

  final String labelKey;
  final IconData icon;
  final IconData selectedIcon;
}

/// Tab 外壳：承载 [StatefulShellRoute.indexedStack] 的多分支页面。
///
/// - 顶部横向导航条（首页直播 | 时间 | 屏保 | 我的），图标+文字横排；
/// - **左右键焦点移到哪个 tab 即切换页面**（无需 OK）；
/// - **菜单键**（contextMenu）显示/隐藏顶部导航条；手机端点屏同样切换（便于调试）；
/// - **OK 键**：首页显示/隐藏「左下角频道信息 + 右侧频道列表」，
///   「我的」页正文焦点内激活设置行；
/// - **返回键**：二次确认后才退出应用（见 [ExitConfirmScope]）。
class MainApp extends StatelessWidget {
  const MainApp({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// 「时间」Tab 在 [_tabs] 中的序号（上/下键在此切换时钟样式）。
  static const int _timeBranchIndex = 1;

  /// 「我的」Tab 在 [_tabs] 中的序号（上/下键在导航条与设置行间移动）。
  static const int _profileBranchIndex = 3;

  static const List<_TabDescriptor> _tabs = <_TabDescriptor>[
    _TabDescriptor('home_title', Icons.live_tv_outlined, Icons.live_tv),
    _TabDescriptor('time_title', Icons.schedule_outlined, Icons.schedule),
    _TabDescriptor(
      'screensaver_title',
      Icons.wallpaper_outlined,
      Icons.wallpaper,
    ),
    _TabDescriptor('profile_title', Icons.settings_outlined, Icons.settings),
  ];

  void _goTab(int index) {
    // 进入「我的」时回到位于导航条的状态。
    if (index == _profileBranchIndex) {
      ProfileFocusController.instance.reset();
    }
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  KeyEventResult _handleRootKey(BuildContext context, KeyEvent event) {
    // 确认弹窗（退出/重置）打开期间一律让位：把按键交给弹窗自己的焦点树，
    // 否则方向键被这里吃掉（选不中弹窗按钮）、OK 还会触发下层的设置行。
    if (ConfirmDialog.isShowing) return KeyEventResult.ignored;

    final bool isVertical = event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown;
    final bool isHorizontal = event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowRight;

    // 上下方向键：长按快速重复（切频道 / 切设置行 / 切样式等列表型操作）。
    if (isVertical) {
      if (event is KeyDownEvent) {
        bool handled = false;
        KeyRepeatController.instance.keyDown(event.logicalKey, () {
          handled = _handleLogical(context, event.logicalKey);
        });
        return handled ? KeyEventResult.handled : KeyEventResult.ignored;
      }
      if (event is KeyUpEvent) {
        KeyRepeatController.instance.keyUp(event.logicalKey);
      }
      return KeyEventResult.ignored;
    }

    // 左右方向键 / 其他按键：按下时仅处理一次，不做长按重复。
    // （切 tab / 切源 都是单步操作，快速重复容易过头或陷入循环）
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (isHorizontal) {
      // 停止可能存在的上下键重复（避免误触残留），然后正常处理左右。
      KeyRepeatController.instance.keyUp(LogicalKeyboardKey.arrowUp);
      KeyRepeatController.instance.keyUp(LogicalKeyboardKey.arrowDown);
    }
    return _handleLogical(context, event.logicalKey)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  /// 悬浮遥控器按键：映射为逻辑键后走与真实遥控器一致的 [LogicalKeyboardKey] 逻辑。
  void _onRemoteButton(BuildContext context, RemoteButton button) {
    final LogicalKeyboardKey key = switch (button) {
      RemoteButton.up => LogicalKeyboardKey.arrowUp,
      RemoteButton.down => LogicalKeyboardKey.arrowDown,
      RemoteButton.left => LogicalKeyboardKey.arrowLeft,
      RemoteButton.right => LogicalKeyboardKey.arrowRight,
      RemoteButton.ok => LogicalKeyboardKey.enter,
      RemoteButton.menu => LogicalKeyboardKey.contextMenu,
      RemoteButton.back => LogicalKeyboardKey.escape,
    };
    _handleLogical(context, key);
  }

  /// 统一的按键逻辑（按「导航条显隐」分模式）：
  /// - 左右：导航条显示时切 tab；隐藏时首页切换当前频道的源。
  /// - 上下：首页切频道、时间页切样式，其余滚动/焦点移动。
  /// - OK：首页显示/隐藏「频道信息 + 频道列表」，「我的」页激活设置行。
  /// - 菜单：显示/隐藏顶部导航条。
  /// - 返回：二次确认后退出应用。
  bool _handleLogical(BuildContext context, LogicalKeyboardKey key) {
    final AppState state = context.read<AppBloc>().state;
    final int cur = navigationShell.currentIndex;

    final bool ok =
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA;
    if (ok) {
      _pressOk(context);
      return true;
    }

    // 返回键（悬浮遥控器的「返回」按 escape；部分遥控器发 goBack）：
    // 与系统返回一致，走二次确认，避免盒子上误触直接退出。
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      ExitConfirmScope.requestExit(context);
      return true;
    }

    // 菜单键：显示/隐藏顶部菜单（tabs）。「我的」页 tabs 恒显示，不处理。
    if (key == LogicalKeyboardKey.contextMenu) {
      if (cur != _profileBranchIndex) {
        context.read<AppBloc>().add(SetChrome(!state.isChromeVisible));
      }
      return true;
    }

    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final int delta = key == LogicalKeyboardKey.arrowRight ? 1 : -1;
      // 最高优先级：焦点在「我的」设置行内时，左/右改该行的值。
      if (cur == _profileBranchIndex &&
          ProfileFocusController.instance.focused) {
        ProfileFocusController.instance.step(delta);
        return true;
      }
      // 导航条可见时，左右优先用于切换 tab。
      if (state.isChromeVisible) {
        _goTabWrapped(cur, delta);
        return true;
      }
      // 导航条隐藏时，首页左/右始终用于切换当前频道的源。
      // 提示条不可见也照样触发——切源本身会重新显示提示条，
      // 并在 30 秒无操作后自动隐藏（隐藏规则见 LivePlayerWidget）。
      if (cur == 0) {
        HomeNowPlayingController.instance.switchSource(delta);
        return true;
      }
      return false;
    }

    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final bool up = key == LogicalKeyboardKey.arrowUp;
      switch (cur) {
        case 0: // 首页：上下切频道
          up
              ? LiveChannelController.instance.previous()
              : LiveChannelController.instance.next();
          break;
        case _timeBranchIndex: // 时间：上下切样式
          up
              ? TimeStyleController.instance.previous()
              : TimeStyleController.instance.next();
          break;
        case _profileBranchIndex: // 我的：导航条 ↔ 主题/语言/悬浮遥控器
          up
              ? ProfileFocusController.instance.moveUp()
              : ProfileFocusController.instance.moveDown();
          break;
        default: // 其余：滚动 / 焦点移动
          _moveFocus(up ? TraversalDirection.up : TraversalDirection.down);
          break;
      }
      return true;
    }

    return false;
  }

  /// 循环切换 tab（左右）。
  void _goTabWrapped(int current, int delta) {
    final int next =
        (current + delta + MainApp._tabs.length) % MainApp._tabs.length;
    _goTab(next);
  }

  void _moveFocus(TraversalDirection direction) {
    final FocusScopeNode? scope =
        FocusManager.instance.primaryFocus?.enclosingScope;
    if (scope == null) return;
    scope.focusInDirection(direction);
  }

  /// OK 键：
  /// - 「我的」页正文焦点内 → 激活当前设置行；
  /// - 首页 → 显示/隐藏「左下角频道信息 + 右侧频道列表」；
  /// - 其余 → 激活焦点控件（若有）。
  void _pressOk(BuildContext context) {
    final int cur = navigationShell.currentIndex;
    if (cur == _profileBranchIndex && ProfileFocusController.instance.focused) {
      ProfileFocusController.instance.activate();
      return;
    }
    if (cur == 0) {
      HomeNowPlayingController.instance.toggleChannelPanel();
      return;
    }
    final BuildContext? focusContext =
        FocusManager.instance.primaryFocus?.context;
    if (focusContext != null &&
        Actions.maybeFind<ActivateIntent>(focusContext) != null) {
      Actions.invoke(focusContext, const ActivateIntent());
    }
  }

  @override
  Widget build(BuildContext context) {
    // 顶部导航条显隐（「我的」页恒显示）。
    final bool chromeVisible =
        context.select<AppBloc, bool>((bloc) => bloc.state.isChromeVisible);
    // 自动收起触发点：切到非「我的」tab / 菜单键呼出后 10 秒；「我的」不自动收起。
    return ExitConfirmScope(
      child: AutoHideChrome(
        currentIndex: navigationShell.currentIndex,
        profileBranchIndex: _profileBranchIndex,
        child: Focus(
          debugLabel: 'MainApp.rootOkHandler',
          canRequestFocus: false,
          onKeyEvent: (node, event) => _handleRootKey(context, event),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // 内容区（首页为全屏直播视频）始终铺满整个屏幕，
                // 导航条作为悬浮层叠在其上，因此视频永远以最大画面播放。
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  // 触摸降级：点视频/任意空白背景切换顶部导航条显隐（便于手机调试）。
                  // 「我的」页 tabs 始终显示，不参与显隐。
                  onTap: () {
                    if (navigationShell.currentIndex == _profileBranchIndex) {
                      return;
                    }
                    context.read<AppBloc>().add(SetChrome(!chromeVisible));
                  },
                  child: navigationShell,
                ),
                // 顶部导航条：随 isChromeVisible 折叠/展开，悬浮在视频上方。
                // 直接用 context.select 读 chrome，随切分支(父重建)也会刷新 selected。
                Align(
                  alignment: Alignment.topCenter,
                  child: ClipRect(
                    child: AnimatedAlign(
                      alignment: Alignment.topCenter,
                      heightFactor: chromeVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: _TopNavBar(
                        currentIndex: navigationShell.currentIndex,
                        chromeVisible: chromeVisible,
                        onTabSelected: _goTab,
                      ),
                    ),
                  ),
                ),
                // 悬浮遥控器蒙层（手机调试用），置于最上层。
                FloatingRemote(
                  onKey: (button) => _onRemoteButton(context, button),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶部横向导航条：4 个 tab，焦点即切页、高亮显示。
class _TopNavBar extends StatelessWidget {
  const _TopNavBar({
    required this.currentIndex,
    required this.chromeVisible,
    required this.onTabSelected,
  });

  final int currentIndex;
  final bool chromeVisible;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.92),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black45, blurRadius: 8),
        ],
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 12),
          // Expanded 均分剩余宽度，窄屏也不溢出。
          for (int i = 0; i < MainApp._tabs.length; i++)
            Expanded(
              child: _TopTab(
                index: i,
                descriptor: MainApp._tabs[i],
                selected: i == currentIndex,
                canRequestFocus: chromeVisible,
                onFocused: onTabSelected,
              ),
            ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _TopTab extends StatefulWidget {
  const _TopTab({
    required this.index,
    required this.descriptor,
    required this.selected,
    required this.canRequestFocus,
    required this.onFocused,
  });

  final int index;
  final _TabDescriptor descriptor;
  final bool selected;
  final bool canRequestFocus;
  final ValueChanged<int> onFocused;

  @override
  State<_TopTab> createState() => _TopTabState();
}

class _TopTabState extends State<_TopTab> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(_TopTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 导航条收起时释放聚焦点，让焦点落回内容区。
    if (!widget.canRequestFocus && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }
  }

  void _onFocusChanged() {
    // 触摸/聚焦到某 tab 时切换页面。
    if (_focusNode.hasFocus) {
      widget.onFocused(widget.index);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // 高亮仅跟随「当前选中 tab」。
    // 切换 tab 走 goBranch，焦点不会同步到新 tab；若用 selected||focused，
    // 旧 tab 会因残留焦点而持续高亮（遥控器端明显）。
    final bool active = widget.selected;
    final IconData icon = widget.selected
        ? widget.descriptor.selectedIcon
        : widget.descriptor.icon;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Focus(
        focusNode: _focusNode,
        canRequestFocus: widget.canRequestFocus,
        autofocus: widget.selected && widget.canRequestFocus,
        // 触摸降级：手机直接点 tab 也触发切换（requestFocus 会走焦点监听→切页+高亮）
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _focusNode.requestFocus(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? scheme.primary.withValues(alpha: 0.9)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.descriptor.labelKey.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
