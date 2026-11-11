import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:potatokid_screen/features/app/application/app_tab_controller.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:potatokid_screen/features/app/application/remote_key_dispatcher.dart';
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
import 'package:potatokid_screen/features/update/presentation/update_pill.dart';
import 'package:pscreen_screen/features/time/application/time_style_controller.dart';
import 'package:pscreen_screen/core/media/kid_watch_timer_controller.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/core/utils/key_repeat_controller.dart';
import 'package:potatokid_screen/shared/widgets/confirm_dialog.dart';
import 'package:potatokid_screen/shared/widgets/exit_confirm_scope.dart';
import 'package:potatokid_screen/shared/widgets/floating_remote.dart';

/// Tab 外壳：承载 [StatefulShellRoute.indexedStack] 的多分支页面。
///
/// - 全局半透明胶囊 Mask 提供直播、时间、设置页面切换；
/// - 菜单键不再用于导航，预留给后续功能；
/// - 首页按交互层路由：频道信息 → 频道列表 → 胶囊 Mask；
/// - 全屏播放保留上下切台、左右切源；出现控件后方向键只操作当前层；
/// - **返回键**：逐层进入频道信息、频道列表与胶囊 Mask。
class MainApp extends StatelessWidget {
  const MainApp({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// 当前挂载的导航壳（供 [TvNavigator] 远程切 Tab 使用）。
  static StatefulNavigationShell? current;

  /// 部分 Android TV 会把同一次返回同时投递为 KeyEvent 与系统 popRoute。
  static const int _sameBackWindowMs = 280;
  static int _lastHomeBackAt = 0;

  /// 「时间」页面序号（上/下键在此切换时钟样式）。
  static const int _timeBranchIndex = 1;

  /// 「设置」页面序号（上/下键在设置行间移动）。
  static const int _profileBranchIndex = 2;

  void _goTab(BuildContext context, int index) {
    // 儿童模式只能停留在直播页；UI 过滤之外再做一次导航层保护。
    if (ParentalStateController.instance.enabled && index != 0) return;
    if (index != navigationShell.currentIndex) {
      if (index == _profileBranchIndex) {
        ProfileFocusController.instance.reset();
      }
      context.read<AppBloc>().add(const SetChrome(false));
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
      ParentalSelectOverlay.handleGateKey(context, LogicalKeyboardKey.escape);
      return true;
    }

    // 消息浮层：先关浮层，不触发回直播/退出。
    if (MessageOverlayController.instance.visible) {
      MessageOverlayController.instance.onAnyKey();
      MessageOverlayController.instance.handleBack();
      return true;
    }

    final int cur = navigationShell.currentIndex;
    final AppState appState = context.read<AppBloc>().state;

    // 同一次返回可能同时以按键事件与系统 popRoute 投递（见 _sameBackWindowMs）：
    // 统一在这里去重，避免一次按键连走两级迁移——胶囊页会「闪一下又弹回来」。
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastHomeBackAt < _sameBackWindowMs) return true;
    _lastHomeBackAt = now;

    // 系统返回可能不产生键盘事件，不能只依赖 Mask 的 Focus.onKeyEvent。
    // 胶囊页是返回链的最后一站：关闭 Mask（直播页连同频道面板）回到全屏，
    // 避免「列表 → 胶囊 → 列表」来回打转、只能靠「首页」回到直播。
    if (appState.homeRemoteLayer == HomeRemoteLayer.capsuleControls) {
      FocusManager.instance.primaryFocus?.unfocus();
      if (cur == 0) {
        // 内部已取消提示并切回 fullscreen 层。
        HomeNowPlayingController.instance.hideChannelPanel();
      } else {
        context.read<AppBloc>().add(
          const SetHomeRemoteLayer(HomeRemoteLayer.fullscreen),
        );
      }
      return true;
    }

    // 首页返回键按固定状态链前进：全屏 → 频道信息 → 频道列表 → 胶囊 Mask。
    if (cur == 0) {
      switch (appState.homeRemoteLayer) {
        case HomeRemoteLayer.fullscreen:
          HomeNowPlayingController.instance.showChannelInfo();
          return true;
        case HomeRemoteLayer.channelInfo:
          _showHomeChannels(context);
          return true;
        case HomeRemoteLayer.channelList:
          HomeNowPlayingController.instance.hideChannelPanel();
          context.read<AppBloc>().add(
            const SetHomeRemoteLayer(HomeRemoteLayer.capsuleControls),
          );
          return true;
        case HomeRemoteLayer.capsuleControls:
          return true;
      }
    }

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

    // 非首页（时间 / 设置）→ 直接回直播页，不再先弹胶囊菜单。
    if (cur != 0) {
      _goTab(context, 0);
      return true;
    }

    // 非首页的分层处理完毕后才允许退出。
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
    if (ConfirmDialog.isShowing) {
      if (event is KeyDownEvent) {
        ConfirmDialog.handleKey(event.logicalKey);
      }
      return KeyEventResult.handled;
    }

    final bool isVertical =
        event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown;
    final bool isHorizontal =
        event.logicalKey == LogicalKeyboardKey.arrowLeft ||
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
    if (ConfirmDialog.isShowing) {
      ConfirmDialog.handleKey(key);
      return;
    }
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

  /// 统一的按键逻辑（按最上层交互对象分发）：
  /// - 首页：频道信息 → 频道列表 → 胶囊 Mask → 全屏播放；
  /// - 全屏播放：左右切源、上下切台、OK 呼出频道面板；
  /// - 出现可交互 UI 后：方向键与 OK 仅操作当前层，不再穿透到播放器；
  /// - 菜单：预留，不在这里消费。
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
    if (KidWatchTimerController.instance.locked) {
      return ParentalLockOverlay.handleGateKey(key);
    }

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

    // 半透明 Mask 显示时由它独占全部遥控事件。悬浮遥控器不经过焦点树，
    // 因此也通过同一个控制器转发，避免物理键与屏幕遥控行为不同。
    if (state.homeRemoteLayer == HomeRemoteLayer.capsuleControls &&
        CapsuleControlsController.instance.handleKey(key)) {
      return true;
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
      if (cur == 0) {
        _handleHomeOk(context, state);
        return true;
      }
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
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (_handleBack(context)) return true;
      ExitConfirmScope.requestExit(context);
      return true;
    }

    // 菜单键预留给后续功能，不再呼出旧顶部导航。
    if (key == LogicalKeyboardKey.contextMenu) {
      return false;
    }

    // 首页拥有明确的交互层，必须在通用左右/上下逻辑之前处理，避免可见按钮
    // 或频道面板的按键穿透到切源、切台。
    if (cur == 0 &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      return _handleHomeArrow(context, state, key);
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
      return false;
    }

    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final bool up = key == LogicalKeyboardKey.arrowUp;
      switch (cur) {
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

  BuildContext? _focusedActionContext() {
    final BuildContext? context = FocusManager.instance.primaryFocus?.context;
    if (context == null ||
        !_TvContentFocusMarker.contains(context) ||
        Actions.maybeFind<ActivateIntent>(context) == null) {
      return null;
    }
    return context;
  }

  bool _activateFocusedAction() {
    final BuildContext? context = _focusedActionContext();
    if (context == null) return false;
    Actions.invoke(context, const ActivateIntent());
    return true;
  }

  bool _moveFocus(TraversalDirection direction) {
    final FocusScopeNode? scope =
        FocusManager.instance.primaryFocus?.enclosingScope;
    if (scope == null) return false;
    return scope.focusInDirection(direction);
  }

  void _showHomeChannels(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    HomeNowPlayingController.instance.showChannelPanel();
  }

  void _handleHomeOk(BuildContext context, AppState state) {
    switch (state.homeRemoteLayer) {
      case HomeRemoteLayer.fullscreen:
      case HomeRemoteLayer.channelInfo:
        _showHomeChannels(context);
        return;
      case HomeRemoteLayer.channelList:
        // 面板切层后的同一帧若焦点尚未落下，OK 仍应可靠收起而非无响应。
        if (!_activateFocusedAction()) {
          HomeNowPlayingController.instance.hideChannelPanel();
        }
        return;
      case HomeRemoteLayer.capsuleControls:
        if (!_activateFocusedAction()) {
          context.read<AppBloc>().add(
            const SetHomeRemoteLayer(HomeRemoteLayer.fullscreen),
          );
        }
        return;
    }
  }

  bool _handleHomeArrow(
    BuildContext context,
    AppState state,
    LogicalKeyboardKey key,
  ) {
    final bool up = key == LogicalKeyboardKey.arrowUp;
    final bool down = key == LogicalKeyboardKey.arrowDown;
    final bool left = key == LogicalKeyboardKey.arrowLeft;

    // 频道列表层：左/右直接进入胶囊，避免依赖 Flutter 的几何焦点猜测；
    // 上/下仍在频道列表内移动。
    if (state.homeRemoteLayer == HomeRemoteLayer.channelList) {
      if (left || key == LogicalKeyboardKey.arrowRight) {
        HomeNowPlayingController.instance.switchSource(left ? -1 : 1);
        return true;
      }
      final TraversalDirection direction = switch (key) {
        LogicalKeyboardKey.arrowUp => TraversalDirection.up,
        LogicalKeyboardKey.arrowDown => TraversalDirection.down,
        LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
        _ => TraversalDirection.right,
      };
      _moveFocus(direction);
      return true;
    }

    // 首页普通按钮获得焦点后，四向键只做空间焦点移动。实体遥控器与悬浮
    // 遥控器都经这里执行，避免后者绕过 Flutter 焦点树。
    if (_focusedActionContext() != null) {
      final TraversalDirection direction = switch (key) {
        LogicalKeyboardKey.arrowUp => TraversalDirection.up,
        LogicalKeyboardKey.arrowDown => TraversalDirection.down,
        LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
        _ => TraversalDirection.right,
      };
      _moveFocus(direction);
      return true;
    }

    // 全屏和频道信息层始终保持稳定直播语义：上/下切台、左/右切源。
    // 胶囊入口固定为 OK 打开频道列表后再按左/右，避免同一按键含义随更新状态变化。
    if (up) {
      LiveChannelController.instance.previous();
    } else if (down) {
      LiveChannelController.instance.next();
    } else {
      HomeNowPlayingController.instance.switchSource(left ? -1 : 1);
    }
    return true;
  }

  /// OK 键：
  /// - 「我的」页正文焦点内 → 激活当前设置行；
  /// - 首页由 [_handleHomeOk] 按当前交互层处理；
  /// - 其余 → 激活焦点控件（若有）。
  void _pressOk(BuildContext context) {
    final int cur = navigationShell.currentIndex;
    if (cur == _profileBranchIndex &&
        !_profileReadonly &&
        ProfileFocusController.instance.focused) {
      ProfileFocusController.instance.activate();
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
    // 屏幕模拟遥控已挂到 Navigator 之上（见 App.builder），拿不到本壳层的
    // context，故把既有的按键入口注册到全局分发器。这里只接线，不改
    // _handleRootKey / _handleLogical / _handleBack，真实遥控行为不受影响。
    RemoteKeyDispatcher.instance.attach((RemoteButton button) {
      if (!context.mounted) return;
      _onRemoteButton(context, button);
    });
    if (ParentalStateController.instance.enabled &&
        navigationShell.currentIndex != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || !ParentalStateController.instance.enabled) {
          return;
        }
        _goTab(context, 0);
        context.read<AppBloc>().add(
          const SetHomeRemoteLayer(HomeRemoteLayer.fullscreen),
        );
      });
    }
    // 场景注入（阶段 1 收尾）：直播/时间计入观看、「我的」（设置）不计入
    //（口径见儿童模式方案「场景计时」）；值未变时 setViewingScene 内部早返回。
    KidWatchTimerController.instance.setViewingScene(
      navigationShell.currentIndex != _profileBranchIndex,
    );
    return Stack(
      children: <Widget>[
        ExitConfirmScope(
          onBackRequested: () => _handleBack(context),
          child: Focus(
            debugLabel: 'MainApp.rootOkHandler',
            canRequestFocus: false,
            onKeyEvent: (node, event) => _handleRootKey(context, event),
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // 内容区始终铺满整个屏幕；页面切换统一由胶囊 Mask 提供。
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    child: ListenableBuilder(
                      listenable: ParentalStateController.instance,
                      builder: (context, _) {
                        if (ParentalStateController.instance.enabled &&
                            navigationShell.currentIndex != 0) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!context.mounted ||
                                !ParentalStateController.instance.enabled ||
                                navigationShell.currentIndex == 0) {
                              return;
                            }
                            _goTab(context, 0);
                            context.read<AppBloc>().add(
                              const SetHomeRemoteLayer(
                                HomeRemoteLayer.fullscreen,
                              ),
                            );
                          });
                        }
                        // 儿童模式生效时「我的」分支整页替换为只读页
                        //（方案 5.2/5.3）：IndexedStack 翻转——shell 常驻
                        //（保住各分支状态与视频），非选中子节点不绘制、
                        // 不命中、焦点被排除（RenderIndexedStack）；
                        // 判定式不成立时 children 仅 shell 且 index=0，
                        // 与现状等价。
                        final bool readonly = _profileReadonly;
                        return _TvContentFocusMarker(
                          child: IndexedStack(
                            sizing: StackFit.expand,
                            index: readonly ? 1 : 0,
                            children: <Widget>[
                              navigationShell,
                              if (readonly) const ProfileReadonlyPage(),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  BlocBuilder<AppBloc, AppState>(
                    buildWhen: (previous, current) =>
                        previous.homeRemoteLayer != current.homeRemoteLayer,
                    builder: (context, state) => CapsuleControlsOverlay(
                      visible:
                          state.homeRemoteLayer ==
                          HomeRemoteLayer.capsuleControls,
                      currentTab: navigationShell.currentIndex,
                      onExitRequested: () =>
                          ExitConfirmScope.requestExit(context),
                      onTabSelected: (int index) {
                        _goTab(context, index);
                        context.read<AppBloc>().add(
                          const SetHomeRemoteLayer(HomeRemoteLayer.fullscreen),
                        );
                      },
                      // 返回键与系统返回走同一套分层逻辑（含双投递去重），
                      // 否则同一次按键会先关 Mask 再被 popRoute 推回列表。
                      onClose: () => _handleBack(context),
                    ),
                  ),
                ],
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

/// 标记页面正文焦点，供根遥控分发器区分页面按钮与播放器按键。
/// 不参与布局，也不让业务页面依赖壳层的具体 FocusNode。
class _TvContentFocusMarker extends InheritedWidget {
  const _TvContentFocusMarker({required super.child});

  static bool contains(BuildContext context) =>
      context
          .getElementForInheritedWidgetOfExactType<_TvContentFocusMarker>() !=
      null;

  @override
  bool updateShouldNotify(_TvContentFocusMarker oldWidget) => false;
}
