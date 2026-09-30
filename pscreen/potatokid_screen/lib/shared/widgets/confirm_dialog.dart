import 'package:flutter/material.dart';

/// 共用确认弹窗：TV 遥控器可用（聚焦高亮 + 默认聚焦安全项），返回键即取消。
///
/// 统一了「退出应用」与「重置」等危险操作的交互与外观：
/// - 两个按钮**基础外观完全一致**，选中状态只由聚焦高亮表达（避免实心按钮
///   在未聚焦时显得更显眼而被误认为已选中）；
/// - [cancelAutofocus] 默认 true，即默认聚焦「取消」，遥控器误按 OK 不会执行危险操作；
/// - 弹窗自身接管返回键（[PopScope] + `canPop: false`），并按 [_samePressWindow]
///   忽略同一次返回键被投递两次的第二下，避免弹窗闪一下就消失。
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    this.cancelAutofocus = true,
  });

  /// 标题文案。
  final String title;

  /// 正文文案。
  final String message;

  /// 取消按钮文案。
  final String cancelLabel;

  /// 确认按钮文案。
  final String confirmLabel;

  /// 是否默认聚焦「取消」（危险操作应保持 true）。
  final bool cancelAutofocus;

  /// 同一次返回键可能在极短时间内被投递两次（按键事件 + 系统 popRoute），
  /// 弹窗打开后这段时间内的返回视为同一次按键，直接忽略。
  static const Duration _samePressWindow = Duration(milliseconds: 400);

  /// 是否有确认弹窗正在显示。
  ///
  /// 壳层（[MainApp] 的根 KeyEvent 处理器）会拦截方向键/OK 键把遥控器操作
  /// 路由到自己的焦点控制器；弹窗打开期间必须先让位，否则遥控器既选不中
  /// 弹窗按钮（方向键被壳层吃掉）、OK 又会触发下层设置行，弹窗形同虚设。
  static bool get isShowing => _showing;

  static bool _showing = false;

  /// 弹出确认框，返回 true=用户确认，false=取消/返回键关闭。
  ///
  /// 打开瞬间的同一次返回键会被忽略，不会让弹窗闪一下就消失。
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    required String cancelLabel,
    required String confirmLabel,
    bool cancelAutofocus = true,
  }) async {
    final DateTime openedAt = DateTime.now();
    _showing = true;
    try {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => PopScope(
          // 弹窗自身接管返回：若交给默认的 maybePop，同一次按键的第二个
          // 事件会立刻把刚弹出的弹窗弹掉（表现为闪一下就消失）。
          canPop: false,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (didPop) return;
            if (DateTime.now().difference(openedAt) < _samePressWindow) return;
            Navigator.of(dialogContext).pop(false);
          },
          child: ConfirmDialog(
            title: title,
            message: message,
            cancelLabel: cancelLabel,
            confirmLabel: confirmLabel,
            cancelAutofocus: cancelAutofocus,
          ),
        ),
      );
      return confirmed ?? false;
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        // 默认聚焦「取消」：遥控器误按 OK 不会直接执行危险操作。
        ConfirmDialogButton(
          autofocus: cancelAutofocus,
          label: cancelLabel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        ConfirmDialogButton(
          label: confirmLabel,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// 确认弹窗按钮：所有弹窗按钮**基础外观完全一致**，选中状态只由聚焦高亮表达。
///
/// 之前「退出」用实心按钮，未聚焦时也比聚焦的「取消」显眼，
/// 容易被误认为已选中，故统一为描边按钮。
class ConfirmDialogButton extends StatelessWidget {
  const ConfirmDialogButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
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
}
