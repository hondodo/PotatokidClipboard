import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:potatokid_screen/core/app_exit_controller.dart';
import 'package:potatokid_screen/shared/widgets/confirm_dialog.dart';
import 'package:potatokid_screen/shared/widgets/kid_chrome.dart';

/// 返回键二次确认：拦截系统返回，先弹窗确认再退出应用。
///
/// TV 盒子上系统返回键会直接结束应用，容易误触；这里统一拦截并确认。
/// 确认后先停止播放器，再通过 [AppExitController] 执行平台对应的完整退出。
/// 弹窗外观与返回键处理由 [ConfirmDialog] 统一提供（与「重置」弹窗一致）。
class ExitConfirmScope extends StatefulWidget {
  const ExitConfirmScope({
    super.key,
    required this.child,
    this.onBackRequested,
  });

  final Widget child;

  /// 返回键先经过宿主的分层拦截（子页面 → 回直播 → 首页才退出）。
  /// 返回 true 表示已被宿主消费，不再弹退出确认。
  final bool Function()? onBackRequested;

  /// 确认框是否正在显示，避免连按返回键叠出多个。
  static bool _showing = false;

  /// 请求退出确认（系统返回键与悬浮遥控器「返回」键共用）。
  static Future<void> requestExit(BuildContext context) async {
    if (_showing) return;
    _showing = true;

    bool confirmed = false;
    // 儿童模式只换文案与配色，二次确认 / 默认聚焦取消 / 退出流程不变。
    final bool kid = kidModeOn;
    try {
      confirmed = await ConfirmDialog.show(
        context,
        title: (kid ? 'kid_exit_confirm_title' : 'exit_confirm_title').tr(),
        message: (kid ? 'kid_exit_confirm_message' : 'exit_confirm_message').tr(),
        cancelLabel: (kid ? 'kid_exit_confirm_cancel' : 'exit_confirm_cancel').tr(),
        confirmLabel: (kid ? 'kid_exit_confirm_ok' : 'exit_confirm_ok').tr(),
        kidStyle: kid,
      );
    } finally {
      // 先复位再退出：进程被系统挂起时 finally 不一定执行，避免守卫永久卡住。
      _showing = false;
    }

    if (confirmed) {
      await AppExitController.instance.exit();
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
        if (widget.onBackRequested?.call() ?? false) return;
        ExitConfirmScope.requestExit(context);
      },
      child: widget.child,
    );
  }
}
