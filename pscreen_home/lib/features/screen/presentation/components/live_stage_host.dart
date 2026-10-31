import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/features/screen/application/live_stage_controller.dart';
import 'package:pscreen_home/features/screen/presentation/pages/live_page.dart';

/// 全局直播宿主：挂在 Navigator 之上，负责全屏 / 应用内悬浮小窗的布局。
///
/// 全屏 ⇄ 悬浮只改变 [Positioned] 的 rect，`LivePage` 始终是同一个 child，
/// 因此播放器不会被 dispose / 重建，直播不中断。悬浮时宿主接管 tap（回全屏）
/// 和拖动；底层 Navigator 仍然正常接收小窗以外的点击与滚动。
class LiveStageHost extends StatefulWidget {
  const LiveStageHost({
    super.key,
    required this.controller,
    required this.child,
    this.enablePlayer = true,
  });

  final LiveStageController controller;
  final Widget child;

  /// 是否实例化真实播放器（测试环境置 false）。
  final bool enablePlayer;

  @override
  State<LiveStageHost> createState() => _LiveStageHostState();
}

class _LiveStageHostState extends State<LiveStageHost>
    with WidgetsBindingObserver {
  static const double _margin = 24;
  static const double _floatingMinWidth = 360;
  static const double _floatingMaxWidth = 560;
  static const double _aspectRatio = 16 / 9;

  /// 拖动过程中的临时位置；拖动结束写入 [LiveStageController]。
  Offset? _dragOffset;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 系统返回：全屏 / 悬浮都先关闭直播，而不是把底层页面一起 pop 掉。
  ///
  /// 返回 true 表示已消费这次返回事件，Navigator 不会再执行默认 pop。
  @override
  Future<bool> didPopRoute() async {
    if (!widget.controller.isActive) return false;
    widget.controller.close();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final Size screen = MediaQuery.sizeOf(context);
        // 夹紧 / 默认位置都收在屏幕安全区内（刘海、圆角、系统栏内缩）。
        final EdgeInsets safe = MediaQuery.paddingOf(context);
        final bool active = widget.controller.isActive;
        final bool floating = widget.controller.isFloating;
        final Rect rect = !active
            ? Rect.zero
            : floating
            ? _floatingRect(screen, safe)
            : Offset.zero & screen;

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            widget.child,
            if (active)
              Positioned.fromRect(
                rect: rect,
                child: MouseRegion(
                  cursor: floating
                      ? SystemMouseCursors.grab
                      : MouseCursor.defer,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // 只有悬浮态接管手势；全屏时事件仍交给 LivePage 自己。
                    onTap: floating ? widget.controller.toFullscreen : null,
                    onPanStart: floating ? _onPanStart : null,
                    onPanUpdate: floating ? _onPanUpdate : null,
                    onPanEnd: floating ? _onPanEnd : null,
                    onPanCancel: floating ? _onPanCancel : null,
                    child: Material(
                      color: Colors.black,
                      elevation: floating ? 16 : 0,
                      shadowColor: Colors.black54,
                      borderRadius: BorderRadius.circular(floating ? 12 : 0),
                      clipBehavior: floating ? Clip.antiAlias : Clip.none,
                      child: LivePage(
                        enablePlayer: widget.enablePlayer,
                        floating: floating,
                        onFloat: floating ? null : widget.controller.toFloating,
                        onClose: () => widget.controller.close(),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 小窗尺寸：宽约屏宽 1/3，限制在 360~560；固定 16:9。
  Size _floatingSize(Size screen) {
    double width = (screen.width / 3)
        .clamp(_floatingMinWidth, _floatingMaxWidth)
        .toDouble();
    final double maxWidth = math.max(1.0, screen.width - _margin * 2);
    final double maxHeight = math.max(1.0, screen.height - _margin * 2);
    if (width > maxWidth) width = maxWidth;
    double height = width / _aspectRatio;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * _aspectRatio;
    }
    return Size(width, height);
  }

  Rect _floatingRect(Size screen, EdgeInsets safe) {
    final Size window = _floatingSize(screen);
    final Offset raw =
        _dragOffset ??
        widget.controller.floatingOffset ??
        _defaultOffset(screen, window, safe);
    final Offset offset = _clampOffset(raw, screen, window, safe);
    return offset & window;
  }

  /// 默认右下角：贴着安全区右下角再留一个边距。
  Offset _defaultOffset(Size screen, Size window, EdgeInsets safe) => Offset(
    screen.width - safe.right - window.width - _margin,
    screen.height - safe.bottom - window.height - _margin,
  );

  /// 夹紧到安全区：小窗四边不越过 safe 区域边界。
  Offset _clampOffset(
    Offset offset,
    Size screen,
    Size window,
    EdgeInsets safe,
  ) {
    final double minLeft = safe.left;
    final double minTop = safe.top;
    final double maxLeft = math.max(
      minLeft,
      screen.width - safe.right - window.width,
    );
    final double maxTop = math.max(
      minTop,
      screen.height - safe.bottom - window.height,
    );
    return Offset(
      offset.dx.clamp(minLeft, maxLeft).toDouble(),
      offset.dy.clamp(minTop, maxTop).toDouble(),
    );
  }

  void _onPanStart(DragStartDetails details) {
    setState(
      () => _dragOffset = _floatingRect(
        MediaQuery.sizeOf(context),
        MediaQuery.paddingOf(context),
      ).topLeft,
    );
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final Offset current =
        _dragOffset ?? _floatingRect(MediaQuery.sizeOf(context), safe).topLeft;
    setState(() => _dragOffset = current + details.delta);
  }

  void _onPanEnd(DragEndDetails details) => _commitDrag();

  void _onPanCancel() => _commitDrag();

  void _commitDrag() {
    final Offset? offset = _dragOffset;
    if (offset == null) return;
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final Size window = _floatingSize(screen);
    widget.controller.setFloatingOffset(
      _clampOffset(offset, screen, window, safe),
    );
    setState(() => _dragOffset = null);
  }
}

/// `/live` 路由占位入口。
///
/// 真正的播放器由 [LiveStageHost] 渲染；直接访问 `/live`（例如旧代码/深链）
/// 时也切到全屏，并保留一个空页面给 Navigator。正常从首页打开时，
/// [LiveStageController.openFullscreen] 已经把形态设为 fullscreen，这里
/// 只是幂等兜底。
class LiveRouteEntry extends StatefulWidget {
  const LiveRouteEntry({super.key});

  @override
  State<LiveRouteEntry> createState() => _LiveRouteEntryState();
}

class _LiveRouteEntryState extends State<LiveRouteEntry> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!getIt.isRegistered<LiveStageController>()) return;
      getIt<LiveStageController>().openFullscreen();
    });
  }

  @override
  Widget build(BuildContext context) {
    // iOS 侧滑 / 路由级返回：先关闭直播，再回到底层页。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (!getIt.isRegistered<LiveStageController>()) return;
        getIt<LiveStageController>().close();
      },
      child: const SizedBox.shrink(),
    );
  }
}
