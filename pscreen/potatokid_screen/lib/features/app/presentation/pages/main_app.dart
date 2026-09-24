import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:potatokid_screen/features/iptv/application/live_channel_controller.dart';
import 'package:potatokid_screen/features/time/application/time_style_controller.dart';
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
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  KeyEventResult _handleRootKey(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
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

    final bool ok = key == LogicalKeyboardKey.select ||
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
      if (!state.isChromeVisible) return false; // 隐藏时页内无左右
      final int delta = key == LogicalKeyboardKey.arrowRight ? 1 : -1;
      _goTabWrapped(cur, delta);
      return true;
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
        default: // 其余：滚动 / 焦点移动
          _moveFocus(up ? TraversalDirection.up : TraversalDirection.down);
          break;
      }
      return true;
    }

    if (key == LogicalKeyboardKey.contextMenu) {
      if (cur == 0) {
        context.read<AppBloc>().add(const ToggleChannels());
        return true;
      }
      return false;
    }

    return false;
  }

  /// 循环切换 tab（左右）。
  void _goTabWrapped(int current, int delta) {
    final int next = (current + delta + MainApp._tabs.length) % MainApp._tabs.length;
    _goTab(next);
  }

  void _moveFocus(TraversalDirection direction) {
    final FocusScopeNode? scope =
        FocusManager.instance.primaryFocus?.enclosingScope;
    if (scope == null) return;
    scope.focusInDirection(direction);
  }

  void _pressOk(BuildContext context) {
    final BuildContext? focusContext =
        FocusManager.instance.primaryFocus?.context;
    // 焦点落在可聚焦且注册了 Activate 动作的控件上时触发其激活（按钮/列表项）；
    // 否则与真实遥控器一致，OK 冒泡到壳层用于显隐导航条。
    if (focusContext != null &&
        Actions.maybeFind<ActivateIntent>(focusContext) != null) {
      Actions.invoke(focusContext, const ActivateIntent());
    } else {
      context.read<AppBloc>().add(const ToggleChrome());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppBloc, AppState>(
      buildWhen: (previous, current) =>
          previous.isChromeVisible != current.isChromeVisible,
      builder: (context, state) {
        return Focus(
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
                  onTap: () =>
                      context.read<AppBloc>().add(const ToggleChrome()),
                  child: navigationShell,
                ),
                // 顶部导航条：随 isChromeVisible 折叠/展开，悬浮在视频上方。
                Align(
                  alignment: Alignment.topCenter,
                  child: ClipRect(
                    child: AnimatedAlign(
                      alignment: Alignment.topCenter,
                      heightFactor: state.isChromeVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: _TopNavBar(
                        currentIndex: navigationShell.currentIndex,
                        chromeVisible: state.isChromeVisible,
                        onTabSelected: _goTab,
                      ),
                    ),
                  ),
                ),
                // 悬浮遥控器蒙层（手机调试用），置于最上层。
                FloatingRemote(onKey: (button) => _onRemoteButton(context, button)),
              ],
            ),
          ),
        );
      },
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
          for (int i = 0; i < MainApp._tabs.length; i++)
            _TopTab(
              index: i,
              descriptor: MainApp._tabs[i],
              selected: i == currentIndex,
              canRequestFocus: chromeVisible,
              onFocused: onTabSelected,
            ),
          const Spacer(),
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
  bool _focused = false;

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
    final bool focused = _focusNode.hasFocus;
    if (focused) {
      widget.onFocused(widget.index);
    }
    if (!mounted) return;
    setState(() => _focused = focused);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool active = widget.selected || _focused;
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? scheme.primary.withValues(alpha: 0.9)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(
                  widget.descriptor.labelKey.tr(),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
