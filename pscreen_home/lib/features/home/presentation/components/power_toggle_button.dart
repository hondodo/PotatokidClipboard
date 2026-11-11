import 'package:flutter/material.dart';

/// 大号圆形电源键：墙面屏老人友好，点击区大、状态醒目。
///
/// - 开启态：填充强调色 + 同色描边；
/// - 关闭态：中性描边、透明底；
/// - 执行中：转圈，禁用点击。
///
/// 替代原 22~32dp 的小 [IconButton]，解决「快捷开关太小不好点」的问题。
class PowerToggleButton extends StatelessWidget {
  const PowerToggleButton({
    super.key,
    required this.on,
    this.isToggling = false,
    this.color,
    required this.onPressed,
    this.tooltip,
    this.size = 46,
  });

  /// 是否开启
  final bool on;

  /// 指令执行中（显示转圈、禁用）
  final bool isToggling;

  /// 强调色；为空时取主题 primary
  final Color? color;

  /// 点击回调（on 时切关、off 时切开）
  final VoidCallback? onPressed;

  final String? tooltip;

  /// 按钮边长（默认 46，点击区足够大）
  final double size;

  static const Color _neutral = Color(0xFF9AA0A6);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = color ?? theme.colorScheme.primary;
    final Color active = on ? accent : _neutral;
    final Color bg = on ? accent.withValues(alpha: 0.16) : Colors.transparent;
    final Color border =
        on ? accent : theme.colorScheme.outlineVariant;

    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        splashRadius: size * 0.62,
        onPressed: isToggling ? null : onPressed,
        icon: isToggling
            ? SizedBox(
                width: size * 0.42,
                height: size * 0.42,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: active,
                ),
              )
            : Icon(
                Icons.power_settings_new_rounded,
                size: size * 0.5,
                color: active,
              ),
        style: IconButton.styleFrom(
          backgroundColor: bg,
          side: BorderSide(color: border, width: 2),
          shape: const CircleBorder(),
          minimumSize: Size(size, size),
        ),
      ),
    );
  }
}
