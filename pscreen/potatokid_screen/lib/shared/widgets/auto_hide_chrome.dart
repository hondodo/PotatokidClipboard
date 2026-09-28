import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';

/// 顶部导航条的自动收起调度器。
///
/// 只要处于「导航条可见且非 [profileBranchIndex]」这一状态，就维持一个倒计时；
/// 在倒计时期间若发生以下触发事件则**重置**倒计时：
/// - `isChromeVisible` 再次变为可见（如 OK 键呼出）；
/// - 切换到非「[profileBranchIndex]」的 tab。
///
/// 命中「[profileBranchIndex]（我的）」或导航条已隐藏时取消计时：
/// 因此「我的」页 tabs 恒显示、不自动收起。
/// 启动默认停在「首页（非我的）」时，首次即维持计时，到期自动收起。
class AutoHideChrome extends StatefulWidget {
  const AutoHideChrome({
    super.key,
    required this.child,
    required this.currentIndex,
    required this.profileBranchIndex,
    this.delay = const Duration(seconds: 10),
  });

  final Widget child;

  /// 当前 tab 序号（来自 [MainApp] 的 navigationShell）。
  final int currentIndex;

  /// 「我的」tab 的序号：此 tab 上不自动收起。
  final int profileBranchIndex;

  /// 计时时长。
  final Duration delay;

  @override
  State<AutoHideChrome> createState() => _AutoHideChromeState();
}

class _AutoHideChromeState extends State<AutoHideChrome> {
  Timer? _timer;
  bool _lastVisible = false;
  int _lastIndex = 0;

  bool get _onProfile => widget.currentIndex == widget.profileBranchIndex;

  void _arm() {
    _cancel();
    _timer = Timer(widget.delay, () {
      if (!mounted) return;
      // 只收起顶部 tab 条，不动首页频道列表（它有自己的 30 秒逻辑）。
      context.read<AppBloc>().add(const SetChrome(false));
      _timer = null;
    });
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool visible =
        context.select<AppBloc, bool>((bloc) => bloc.state.isChromeVisible);
    final bool becameShown = visible && !_lastVisible;
    final bool indexSwitchedWhileVisible = visible &&
        widget.currentIndex != _lastIndex &&
        !_onProfile;

    // 不满足自动收起状态（隐藏了 / 在「我的」）→ 取消；
    // 满足则确保有倒计时，处于“刚可见/切 tab”时重置。
    if (!visible || _onProfile) {
      _cancel();
    } else if (_timer == null ||
        becameShown ||
        indexSwitchedWhileVisible) {
      _arm();
    }

    _lastVisible = visible;
    _lastIndex = widget.currentIndex;
    return widget.child;
  }
}