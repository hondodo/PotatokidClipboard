import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/core/screensaver/screensaver_controller.dart';

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
    required this.child,
  });

  final AppRouter router;
  final ScreensaverController controller;
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
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.router.routeChanges.removeListener(_onRouteChanged);
    widget.controller.removeListener(_onSettingsChanged);
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

  void _onPointerDown(PointerDownEvent event) {
    // 点击时钟页返回时，先退出屏保语义，再按新路由重新计时。
    widget.controller.active = false;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!mounted) return;

    final String path = widget.router.currentPath;
    if (path == RouteNames.livePath || path == RouteNames.clockPath) return;

    final int minutes = widget.controller.minutes;
    if (minutes <= 0) return;
    _timer = Timer(Duration(minutes: minutes), _enterScreensaver);
  }

  void _enterScreensaver() {
    if (!mounted) return;
    final String path = widget.router.currentPath;
    if (path == RouteNames.livePath || path == RouteNames.clockPath) {
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
