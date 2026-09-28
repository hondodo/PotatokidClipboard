import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';

/// 启动后自动隐藏导航条的组件：进入界面 N 秒后，若导航条仍可见则收起。
///
/// 只触发一次；若期间用户已手动收起，则不再动作（避免又显示出来）。
class AutoHideChrome extends StatefulWidget {
  const AutoHideChrome({super.key, required this.child, this.delay = 10});

  final Widget child;

  /// 自动收起的等待秒数
  final int delay;

  @override
  State<AutoHideChrome> createState() => _AutoHideChromeState();
}

class _AutoHideChromeState extends State<AutoHideChrome> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Duration(seconds: widget.delay), _autoHide);
  }

  void _autoHide() {
    if (!mounted) return;
    final AppBloc bloc = context.read<AppBloc>();
    if (bloc.state.isChromeVisible) {
      bloc.add(const ToggleChrome());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
