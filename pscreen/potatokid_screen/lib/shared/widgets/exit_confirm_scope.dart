import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 返回键二次确认：拦截系统返回，先弹窗确认再退出应用。
///
/// TV 盒子上系统返回键会直接结束应用，容易误触；这里统一拦截并确认。
/// 确认后调用 [SystemNavigator.pop]（结束 Activity），与系统返回的最终效果一致。
class ExitConfirmScope extends StatefulWidget {
  const ExitConfirmScope({super.key, required this.child});

  final Widget child;

  /// 确认框是否正在显示，避免连按返回键叠出多个。
  static bool _showing = false;

  /// 同一次返回键可能在极短时间内被投递两次（按键事件 + 系统 popRoute），
  /// 弹窗打开后这段时间内的返回视为同一次按键，直接忽略。
  static const Duration _samePressWindow = Duration(milliseconds: 400);

  /// 请求退出确认（系统返回键与悬浮遥控器「返回」键共用）。
  static Future<void> requestExit(BuildContext context) async {
    if (_showing) return;
    _showing = true;
    final DateTime openedAt = DateTime.now();

    bool confirmed = false;
    try {
      confirmed = await showDialog<bool>(
            context: context,
            builder: (BuildContext dialogContext) => PopScope(
              // 弹窗自身接管返回：若交给默认的 maybePop，同一次按键的第二个
              // 事件会立刻把刚弹出的弹窗弹掉（表现为闪一下就消失）。
              canPop: false,
              onPopInvokedWithResult: (bool didPop, Object? result) {
                if (didPop) return;
                if (DateTime.now().difference(openedAt) < _samePressWindow) {
                  return;
                }
                Navigator.of(dialogContext).pop(false);
              },
              child: AlertDialog(
                title: Text('exit_confirm_title'.tr()),
                content: Text('exit_confirm_message'.tr()),
                actions: <Widget>[
                  // 默认聚焦「取消」：遥控器误按 OK 不会直接退出。
                  _dialogButton(
                    context: dialogContext,
                    autofocus: true,
                    label: 'exit_confirm_cancel'.tr(),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                  ),
                  _dialogButton(
                    context: dialogContext,
                    label: 'exit_confirm_ok'.tr(),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                  ),
                ],
              ),
            ),
          ) ??
          false;
    } finally {
      // 先复位再退出：进程被系统挂起时 finally 不一定执行，避免守卫永久卡住。
      _showing = false;
    }

    if (confirmed) {
      await SystemNavigator.pop();
    }
  }

  /// 弹窗按钮：两个按钮**基础外观完全一致**，选中状态只由聚焦高亮表达。
  ///
  /// 之前「退出」用实心按钮，未聚焦时也比聚焦的「取消」显眼，
  /// 容易被误认为已选中，故统一为描边按钮。
  static Widget _dialogButton({
    required BuildContext context,
    required String label,
    required VoidCallback onPressed,
    bool autofocus = false,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      autofocus: autofocus,
      onPressed: onPressed,
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll<Color?>(scheme.onSurface),
        backgroundColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.focused)
              ? scheme.primary.withValues(alpha: 0.30)
              : Colors.transparent,
        ),
        side: WidgetStateProperty.resolveWith<BorderSide>(
          (Set<WidgetState> states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? scheme.primary
                : scheme.outline,
            width: states.contains(WidgetState.focused) ? 2 : 1,
          ),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        ),
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      child: Text(label),
    );
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