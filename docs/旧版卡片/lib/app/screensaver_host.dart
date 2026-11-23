import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/core/screensaver/screensaver_controller.dart';
import 'package:pscreen_home/core/server/account_session.dart';
import 'package:pscreen_home/features/screen/application/live_stage_controller.dart';

/// 全局屏保宿主：无触摸操作达到设定时长后进入时钟页。
///
/// 规则：
/// - 任意 pointer down 重新计时；
/// - 直播页不触发（不打断播放）；
/// - 时钟页本身不重复触发；点击时钟页由页面自己返回上一页；
/// - 路由切换、屏保时长变更、应用回到前台时重新计时。
class ScreensaverHost extends StatefulWidget {
  const ScreensaverHost({
    super.key,
    required this.router,
    required this.controller,
    this.live,
    required this.child,
  });

  final AppRouter router;
  final ScreensaverController controller;

  /// 直播全屏或悬浮时跳过屏保，避免打断播放。
  final LiveStageController? live;

  final Widget child;

  @override
  State<ScreensaverHost> createState() => _ScreensaverHostState();
}

class _ScreensaverHostState extends State<ScreensaverHost>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.router.routeChanges.addListener(_onRouteChanged);
    widget.controller.addListener(_onSettingsChanged);
    widget.live?.addListener(_onLiveChanged);
    AccountSession.roleNotifier.addListener(_onRoleChanged);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ScreensaverHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routeChanges.removeListener(_onRouteChanged);
      widget.router.routeChanges.addListener(_onRouteChanged);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onSettingsChanged);
      widget.controller.addListener(_onSettingsChanged);
    }
    if (oldWidget.live != widget.live) {
      oldWidget.live?.removeListener(_onLiveChanged);
      widget.live?.addListener(_onLiveChanged);
    }
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.router.routeChanges.removeListener(_onRouteChanged);
    widget.controller.removeListener(_onSettingsChanged);
    widget.live?.removeListener(_onLiveChanged);
    AccountSession.roleNotifier.removeListener(_onRoleChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _schedule();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _onRouteChanged() {
    if (widget.router.currentPath != RouteNames.clockPath) {
      widget.controller.active = false;
    }
    _schedule();
  }

  void _onSettingsChanged() => _schedule();

  void _onLiveChanged() => _schedule();

  /// 登录角色变化（后台登录回写 / 账号切换）后重新判定是否允许屏保。
  void _onRoleChanged() => _schedule();

  void _onPointerDown(PointerDownEvent event) {
    // 点击时钟页返回时，先退出屏保语义，再按新路由重新计时。
    widget.controller.active = false;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!mounted) return;

    // 家长身份不自动进入屏保：无论是否配置了屏保时长、是否到点都不触发；
    // admin / 普通成员保持原规则。
    if (AccountSession.isParent) return;

    final String path = widget.router.currentPath;
    if (path == RouteNames.livePath || path == RouteNames.clockPath) return;
    // 悬浮直播时底层仍可操作，但屏保会盖住小窗/打断观看，同样跳过。
    if (widget.live?.isActive ?? false) return;

    final int minutes = widget.controller.minutes;
    if (minutes <= 0) return;
    _timer = Timer(Duration(minutes: minutes), _enterScreensaver);
  }

  void _enterScreensaver() {
    if (!mounted) return;
    // 计时期间角色切换为家长时兜底取消（例如账号在后台刷新后变成 parent）。
    if (AccountSession.isParent) {
      _schedule();
      return;
    }
    final String path = widget.router.currentPath;
    if (path == RouteNames.livePath ||
        path == RouteNames.clockPath ||
        (widget.live?.isActive ?? false)) {
      _schedule();
      return;
    }
    widget.controller.active = true;
    widget.router.push(RouteNames.clockPath);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      child: widget.child,
    );
  }
}
