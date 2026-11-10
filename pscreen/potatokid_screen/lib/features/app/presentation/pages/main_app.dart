import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:potatokid_screen/features/app/application/app_tab_controller.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:pscreen_screen/features/iptv/application/channel_number_input_controller.dart';
import 'package:pscreen_screen/features/iptv/application/home_now_playing_controller.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/msg/application/message_overlay_controller.dart';
import 'package:potatokid_screen/features/msg/presentation/widgets/message_overlay.dart';
import 'package:potatokid_screen/features/parental/presentation/widgets/parental_lock_overlay.dart';
import 'package:potatokid_screen/features/parental/presentation/widgets/parental_select_overlay.dart';
import 'package:potatokid_screen/features/profile/application/profile_focus_controller.dart';
import 'package:potatokid_screen/features/profile/presentation/pages/profile_page.dart';
import 'package:potatokid_screen/features/profile/presentation/pages/profile_readonly_page.dart';
import 'package:pscreen_screen/features/time/application/time_style_controller.dart';
import 'package:pscreen_screen/core/media/kid_watch_timer_controller.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/core/utils/key_repeat_controller.dart';
import 'package:potatokid_screen/shared/widgets/auto_hide_chrome.dart';
import 'package:potatokid_screen/shared/widgets/confirm_dialog.dart';
import 'package:potatokid_screen/shared/widgets/exit_confirm_scope.dart';
import 'package:potatokid_screen/shared/widgets/floating_remote.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单个顶部 Tab 的静态描述（图标 + 文案 key）。
class _TabDescriptor {
  const _TabDescriptor(this.labelKey, this.icon, this.selectedIcon);

  final String labelKey;
  final IconData icon;
  final IconData selectedIcon;
}

/// Tab 外壳：承载 [StatefulShellRoute.indexedStack] 的多分支页面。
///
/// - 顶部横向导航条（首页直播 | 时间 | 我的），图标+文字横排；
/// - **左右键焦点移到哪个 tab 即切换页面**（无需 OK）；
/// - **菜单键**（contextMenu）显示/隐藏顶部导航条；手机端点屏同样切换（便于调试）；
/// - **进入内容页（首页直播/时间）时导航条立即收起**，仅按键时短暂预览（时间页）；
/// - **OK 键**：首页显示/隐藏「左下角频道信息 + 右侧频道列表」，
///   「我的」页正文焦点内激活设置行；
/// - **返回键**：非首页先回直播；「我的」页先退出正文选中；仅首页才二次确认退出。
class MainApp extends StatelessWidget {
  const MainApp({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// 当前挂载的导航壳（供 [TvNavigator] 远程切 Tab 使用）。
  static StatefulNavigationShell? current;

  /// 「时间」Tab 在 [_tabs] 中的序号（上/下键在此切换时钟样式）。
  static const int _timeBranchIndex = 1;

  /// 「我的」Tab 在 [_tabs] 中的序号（上/下键在导航条与设置行间移动）。
  static const int _profileBranchIndex = 2;

  static const List<_TabDescriptor> _tabs = <_TabDescriptor>[
    _TabDescriptor('home_title', Icons.live_tv_outlined, Icons.live_tv),
    _TabDescriptor('time_title', Icons.schedule_outlined, Icons.schedule),
    _TabDescriptor('profile_title', Icons.settings_outlined, Icons.settings),
  ];

  void _goTab(BuildContext context, int index, {bool keepChrome = true}) {
    // 进入「我的」时回到位于导航条的状态，并保持导航条常显（设置页需要可见的选择态）。
    // 其余页面切完仍保持导航条可见（[keepChrome] 默认 true），由 AutoHideChrome
    // 在 10 秒无操作后统一收起；否则点/按一次 tab 就立刻收起，要再切必须重新
    // 呼出（触摸/遥控都表现为「点一下就收起、很难切回」）。
    // 已在目标页时不改条状态：否则菜单键呼出导航条后，选中 tab 的 autofocus
    // 回调会再次走本方法把条立刻收起（表现为「按键没反应」）。
    final AppBloc bloc = context.read<AppBloc>();
    if (index != navigationShell.currentIndex) {
      if (index == _profileBranchIndex) {
        ProfileFocusController.instance.reset();
        bloc.add(const SetChrome(true));
      } else {
        bloc.add(SetChrome(keepChrome));
      }
    }
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  /// 返回键分层处理：返回 true 表示已消费（不再弹退出确认）。
  ///
  /// 顺序与根处理器一致：确认弹窗/消息浮层/选人页/锁屏 → 行内编辑 →
  /// 设置页正文选中 → 非首页回直播 → 首页才退出。
  /// 根处理器与 [ExitConfirmScope] 的 `PopScope` 共用本方法，
  /// 保证悬浮遥控器与实体遥控器行为一致。
  bool _handleBack(BuildContext context) {
    // 锁屏期间不响应返回（不能把用户送回直播或弹出退出框）。
    if (KidWatchTimerController.instance.locked) return true;

    // 儿童模式选人页：交给选人页自己的返回逻辑，其余按键被它吞掉。
    if (ParentalSelectOverlay.gateVisible) {
      ParentalSelectOverlay.handleGateKey(
        context,
        LogicalKeyboardKey.escape,
      );
      return true;
    }

    // 消息浮层：先关浮层，不触发回直播/退出。
    if (MessageOverlayController.instance.visible) {
      MessageOverlayController.instance.onAnyKey();
      MessageOverlayController.instance.handleBack();
      return true;
    }

    final int cur = navigationShell.currentIndex;

    // 设置页行内编辑 → 先取消编辑（页面内返回）。
    final VoidCallback? cancelInline = ProfilePage.onCancelInlineEdit;
    if (cur == _profileBranchIndex &&
        !_profileReadonly &&
        ProfilePage.isInlineEditing &&
        cancelInline != null) {
      cancelInline();
      return true;
    }

    // 设置页正文选中 → 先退回导航条（页面内返回）。
    if (cur == _profileBranchIndex &&
        !_profileReadonly &&
        ProfileFocusController.instance.focused) {
      ProfileFocusController.instance.reset();
      return true;
    }

    // 非首页 → 回直播。
    if (cur != 0) {
      _goTab(context, 0);
      unawaited(_BackToLiveHint.maybeShow(context));
      return true;
    }

    // 首页 → 维持现有二次确认退出。
    return false;
  }

  /// 「我的」Tab 儿童模式只读替换是否生效（方案 5.2 生效判定式）。
  /// 判定式不成立时为 false：内容区渲染与全部按键路径与现状完全一致。
  bool get _profileReadonly =>
      navigationShell.currentIndex == _profileBranchIndex &&
      ParentalStateController.instance.enabled;

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

  /// 数字键（主键盘数字区 / 小键盘）→ 0~9；非数字键返回 null。
  static int? _digitOf(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.digit0 || LogicalKeyboardKey.numpad0 => 0,
    LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1 => 1,
    LogicalKeyboardKey.digit2 || LogicalKeyboardKey.numpad2 => 2,
    LogicalKeyboardKey.digit3 || LogicalKeyboardKey.numpad3 => 3,
    LogicalKeyboardKey.digit4 || LogicalKeyboardKey.numpad4 => 4,
    LogicalKeyboardKey.digit5 || LogicalKeyboardKey.numpad5 => 5,
    LogicalKeyboardKey.digit6 || LogicalKeyboardKey.numpad6 => 6,
    LogicalKeyboardKey.digit7 || LogicalKeyboardKey.numpad7 => 7,
    LogicalKeyboardKey.digit8 || LogicalKeyboardKey.numpad8 => 8,
    LogicalKeyboardKey.digit9 || LogicalKeyboardKey.numpad9 => 9,
    _ => null,
  };

  /// 统一的按键逻辑（按「导航条显隐」分模式）：
  /// - 左右：导航条显示时切 tab；隐藏时首页切换当前频道的源。
  /// - 上下：首页切频道、时间页切样式，其余滚动/焦点移动。
  /// - OK：首页显示/隐藏「频道信息 + 频道列表」，「我的」页激活设置行。
  /// - 菜单：显示/隐藏顶部导航条。
  /// - 返回：二次确认后退出应用。
  /// - 数字：首页直选频道号（见 [ChannelNumberInputController]）。
  bool _handleLogical(BuildContext context, LogicalKeyboardKey key) {
    // 儿童模式选人页可见：全部按键交给选人页（上下移动光标 / 确定勾选与
    // 确认，其余吞掉）——未确定不进直播、不操作底层；锁屏在其上层时让位
    //（锁屏页优先经自己的焦点树处理，维持阶段 2 行为不变）。
    if (ParentalSelectOverlay.gateVisible &&
        !KidWatchTimerController.instance.locked) {
      ParentalSelectOverlay.handleGateKey(context, key);
      return true;
    }

    // 锁屏期间（方案 5.2「根按键拦截」）：锁屏页/家长验证层各有自己的焦点
    // 节点，按键经其焦点链处理、不经本根分发；焦点仍留在内容区/导航条时
    // 按键会走到这里——一律吞掉，不再下钻 Tab 切换、频道与设置行导航
    //（覆盖悬浮遥控器直调路径；解锁相关按键由最上层覆盖层焦点链放行）。
    if (KidWatchTimerController.instance.locked) return true;

    // 消息浮层可见：OK 开详情 / 返回 关闭；详情内上下键转发浮层滚动全文
    //（D-pad，长按经 KeyRepeatController 连续滚）；其余按键吞掉（防止浮层下
    // 页面被操作，详情内 OK 亦忽略），并重置自动关闭计时。
    if (MessageOverlayController.instance.visible) {
      MessageOverlayController.instance.onAnyKey();
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack) {
        MessageOverlayController.instance.handleBack();
        return true;
      }
      final bool ok =
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.gameButtonA;
      if (ok) {
        MessageOverlayController.instance.handleOk(); // 详情内为 no-op（忽略）
        return true;
      }
      if (MessageOverlayController.instance.detail &&
          key == LogicalKeyboardKey.arrowUp) {
        MessageOverlay.scrollDetail(-1);
        return true;
      }
      if (MessageOverlayController.instance.detail &&
          key == LogicalKeyboardKey.arrowDown) {
        MessageOverlay.scrollDetail(1);
        return true;
      }
      return true; // 吞掉其余按键
    }

    final AppState state = context.read<AppBloc>().state;
    final int cur = navigationShell.currentIndex;

    // 时间页：导航条隐藏时，左/右键直接呼出并切换 tab（切完保持 10 秒再自动
    // 收起），不必先按菜单键；上/下键只让导航条短暂露出（仅显示、不可聚焦，
    // 3 秒自动收起），切样式的动作照常执行。首页不做，避免与切源/切台/OK 叠加。
    if (cur == _timeBranchIndex && !state.isChromeVisible) {
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        _goTabWrapped(
          context,
          cur,
          key == LogicalKeyboardKey.arrowRight ? 1 : -1,
        );
        return true;
      }
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        context.read<AppBloc>().add(const SetChromePeek(true));
      }
    }

    // 数字键：仅首页生效 —— 累积输入频道号，2 秒无输入后跳台（超范围会提示）。
    if (cur == 0) {
      final int? digit = _digitOf(key);
      if (digit != null) {
        ChannelNumberInputController.instance.input(digit);
        return true;
      }
    }

    final bool ok =
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA;
    if (ok) {
      // 行内输入编辑态 OK = 提交输入，不走 activate。
      // 悬浮遥控器直调本方法、不经焦点链，页面 Focus 拦截不到，故在此优先处理；
      // 物理/蓝牙遥控器的 OK 已被页面 Focus 消费（见 ProfilePage._handlePageKey）。
      // 仅在「我的」分支生效：ProfilePage State 在 IndexedStack 常驻，
      // 切走后 editingRow 可能仍非 null，不限分支会吞掉其它页的 OK。
      final Future<void> Function()? submitInline =
          ProfilePage.onSubmitInlineEdit;
      if (cur == _profileBranchIndex &&
          !_profileReadonly &&
          ProfilePage.isInlineEditing &&
          submitInline != null) {
        unawaited(submitInline());
        return true;
      }
      _pressOk(context);
      return true;
    }

    // 返回键（悬浮遥控器的「返回」按 escape；部分遥控器发 goBack）：
    // 与系统返回共用 [_handleBack]：非首页回直播、设置页先退正文，
    // 仅首页才二次确认退出，避免盒子上误触直接退出。
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      if (_handleBack(context)) return true;
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
          !_profileReadonly &&
          ProfileFocusController.instance.focused) {
        ProfileFocusController.instance.step(delta);
        return true;
      }
      // 导航条可见时，左右优先用于切换 tab。
      if (state.isChromeVisible) {
        _goTabWrapped(context, cur, delta);
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
          if (_profileReadonly) {
            // 只读页无正文行（方案 5.2）：吞掉上下键，防止选中态落到
            // 常驻但不可命中的原页行上（不穿透原页）。
            break;
          }
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

  /// 循环切换 tab（左右）：保持导航条可见，方便连续左右切换。
  void _goTabWrapped(BuildContext context, int current, int delta) {
    final int next =
        (current + delta + MainApp._tabs.length) % MainApp._tabs.length;
    _goTab(context, next, keepChrome: true);
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
    if (cur == _profileBranchIndex &&
        !_profileReadonly &&
        ProfileFocusController.instance.focused) {
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
    // Tab 状态填充（上报/浮层互斥读这里）。
    // 同时记录导航壳，供远程 nav 指令切页。
    MainApp.current = navigationShell;
    AppTabController.branchIndex = navigationShell.currentIndex;
    // 场景注入（阶段 1 收尾）：直播/时间计入观看、「我的」（设置）不计入
    //（口径见儿童模式方案「场景计时」）；值未变时 setViewingScene 内部早返回。
    KidWatchTimerController.instance.setViewingScene(navigationShell.currentIndex != _profileBranchIndex);
    // 顶部导航条显隐（「我的」页恒显示）。
    final bool chromeVisible =
        context.select<AppBloc, bool>((bloc) => bloc.state.isChromeVisible);
    // 预览态只影响绘制，不参与焦点/切页（避免显示瞬间抢走正文焦点或误切页）。
    final bool chromePeek =
        context.select<AppBloc, bool>((bloc) => bloc.state.isChromePeek);
    final bool chromeShown = chromeVisible || chromePeek;
    // 自动收起触发点：切到非「我的」tab / 菜单键呼出后 10 秒；「我的」不自动收起。
    return Stack(
      children: <Widget>[
        ExitConfirmScope(
          onBackRequested: () => _handleBack(context),
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
                        if (navigationShell.currentIndex ==
                            _profileBranchIndex) {
                          return;
                        }
                        context
                            .read<AppBloc>()
                            .add(SetChrome(!chromeShown));
                      },
                      child: ListenableBuilder(
                        listenable: ParentalStateController.instance,
                        builder: (context, _) {
                          // 儿童模式生效时「我的」分支整页替换为只读页
                          //（方案 5.2/5.3）：IndexedStack 翻转——shell 常驻
                          //（保住各分支状态与视频），非选中子节点不绘制、
                          // 不命中、焦点被排除（RenderIndexedStack）；
                          // 判定式不成立时 children 仅 shell 且 index=0，
                          // 与现状等价。
                          final bool readonly = _profileReadonly;
                          return IndexedStack(
                            sizing: StackFit.expand,
                            index: readonly ? 1 : 0,
                            children: <Widget>[
                              navigationShell,
                              if (readonly) const ProfileReadonlyPage(),
                            ],
                          );
                        },
                      ),
                    ),
                    // 顶部导航条：随 isChromeVisible 折叠/展开，悬浮在视频上方。
                    // 直接用 context.select 读 chrome，随切分支(父重建)也会刷新 selected。
                    Align(
                      alignment: Alignment.topCenter,
                      child: ClipRect(
                        child: AnimatedAlign(
                          alignment: Alignment.topCenter,
                          heightFactor: chromeShown ? 1 : 0,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          child: _TopNavBar(
                            currentIndex: navigationShell.currentIndex,
                            chromeVisible: chromeVisible,
                            onTabSelected: (index) => _goTab(context, index),
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
        ),
        // 三个覆盖层（消息浮层 / 选人页 / 锁屏）都在 Scaffold.body 的 Stack
        // 顶层，不在 Material → DefaultTextStyle 子树里，导致无样式祖先时
        // 走 Flutter 兜底（黄色 + 双下划线）。统一包 DefaultTextStyle，
        // 用 theme.bodyMedium 兜底并显式关 decoration。
        DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
              ),
          child: Stack(
            children: const <Widget>[
              Positioned.fill(child: MessageOverlay()),
              Positioned.fill(child: ParentalSelectOverlay()),
              Positioned.fill(child: ParentalLockOverlay()),
            ],
          ),
        ),
      ],
    );
  }
}

/// 顶部横向导航条：3 个 tab，焦点即切页、高亮显示。
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

/// 「二级页按返回键回直播」的一次性提示。
///
/// 只在首次真正触发时提示一次；用本地持久化记住，重启不再打扰。
class _BackToLiveHint {
  static const String _prefsKey = 'tv_back_to_live_hint_shown';

  /// 同进程内只尝试一次，避免预置未落盘时反复弹。
  static bool _attempted = false;

  static Future<void> maybeShow(BuildContext context) async {
    if (_attempted) return;
    _attempted = true;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsKey) ?? false) return;
    await prefs.setBool(_prefsKey, true);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('back_to_live_hint'.tr()),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
