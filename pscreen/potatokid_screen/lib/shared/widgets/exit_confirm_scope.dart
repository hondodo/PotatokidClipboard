import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:potatokid_screen/shared/widgets/confirm_dialog.dart';

/// 返回键二次确认：拦截系统返回，先弹窗确认再退出应用。
///
/// TV 盒子上系统返回键会直接结束应用，容易误触；这里统一拦截并确认。
/// 确认后调用 [SystemNavigator.pop]（结束 Activity），与系统返回的最终效果一致。
/// 弹窗外观与返回键处理由 [ConfirmDialog] 统一提供（与「重置」弹窗一致）。
class ExitConfirmScope extends StatefulWidget {
  const ExitConfirmScope({super.key, required this.child});

  final Widget child;

  /// 确认框是否正在显示，避免连按返回键叠出多个。
  static bool _showing = false;

  /// 请求退出确认（系统返回键与悬浮遥控器「返回」键共用）。
  static Future<void> requestExit(BuildContext context) async {
    if (_showing) return;
    _showing = true;

    bool confirmed = false;
    try {
      confirmed = await ConfirmDialog.show(
        context,
        title: 'exit_confirm_title'.tr(),
        message: 'exit_confirm_message'.tr(),
        cancelLabel: 'exit_confirm_cancel'.tr(),
        confirmLabel: 'exit_confirm_ok'.tr(),
      );
    } finally {
      // 先复位再退出：进程被系统挂起时 finally 不一定执行，避免守卫永久卡住。
      _showing = false;
    }

    if (confirmed) {
      await SystemNavigator.pop();
    }
  }

  @override
  State<ExitConfirmScope> createState() => _ExitConfirmScopeState();
}

class _ExitConfirmScopeState extends State<ExitConfirmScope> {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 恒不直接弹出：系统返回一律转成确认框。
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        ExitConfirmScope.requestExit(context);
      },
      child: widget.child,
    );
  }
}