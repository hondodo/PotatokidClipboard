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
/// - **OK 键**（select/enter/space/gameButtonA）在这里统一用于显示/隐藏导航条，
///   因为它冒泡到本壳层（tab/频道项均不消费 OK）。
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
    _TabDescriptor('profile_title', Icons.person_outline, Icons.person),
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
  /// - 左右：导航条显示时切 tab；隐藏时交给页面（页内无左右）。
  /// - 上下：首页切频道、时间页切样式，其余滚动/焦点移动。
  /// - OK：激活焦点按钮，否则显隐导航条（含频道条）。
  /// - 菜单：仅在首页单独呼出频道列表。
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
      // 导航条隐藏时，首页频道名提示可见 → 左右切换当前频道的源。
      if (cur == 0 && HomeNowPlayingController.instance.toastVisible) {
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

    if (key == LogicalKeyboardKey.contextMenu) {
      if (cur == 0) {
        final bool wasShown = context.read<AppBloc>().state.showChannels;
        context.read<AppBloc>().add(const ToggleChannels());
        // 呼出列表时，左下角顺带显示当前频道名。
        if (!wasShown) HomeNowPlayingController.instance.showToast();
        return true;
      }
      return false;
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

  void _pressOk(BuildContext context) {
    final AppState state = context.read<AppBloc>().state;
    // 导航条隐藏时，OK 键优先用于呼出导航（全屏播放时用户的主要意图），
    // 不交给焦点 widget 的 Activate 动作，避免焦点落在视频/列表项上时 OK 无效。
    if (!state.isChromeVisible &&
        navigationShell.currentIndex != _profileBranchIndex) {
      context.read<AppBloc>().add(const ToggleChrome());
      return;
    }
    // 导航条可见时，若焦点在有 Activate 动作的控件上则触发激活（按钮/列表项等）。
    final BuildContext? focusContext =
        FocusManager.instance.primaryFocus?.context;
    if (focusContext != null &&
        Actions.maybeFind<ActivateIntent>(focusContext) != null) {
      Actions.invoke(focusContext, const ActivateIntent());
      return;
    }
    // 「我的」页 tabs 始终显示，OK 不用于显隐。
    if (navigationShell.currentIndex == _profileBranchIndex) return;
    context.read<AppBloc>().add(const ToggleChrome());
  }

  @override
  Widget build(BuildContext context) {
    // 顶部导航条显隐（「我的」页恒显示）。
    final bool chromeVisible =
        context.select<AppBloc, bool>((bloc) => bloc.state.isChromeVisible);
    // 自动收起触发点：切到非「我的」tab / OK 呼出后 10 秒；「我的」不自动收起。
    return AutoHideChrome(
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
                // 触摸降级：点视频/任意空白背景切换导航条（含频道条）显隐。
                // 「我的」页 tabs 始终显示，不参与显隐。
                onTap: () {
                  if (navigationShell.currentIndex == _profileBranchIndex) {
                    return;
                  }
                  context.read<AppBloc>().add(const ToggleChrome());
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
