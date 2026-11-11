import 'package:flutter/material.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';

/// 儿童模式视觉基线（纯外观，不含任何业务行为）。
///
/// 取自 `features/parental/presentation/widgets/` 四个既有覆盖层的定稿配色：
/// 深蓝三段渐变 + 暖黄强调 + 白色三级文字。让「有意保留」的更新 / 退出 /
/// 只读页等成人外壳页面在不改动功能的前提下与儿童模式同风格。
abstract final class KidPalette {
  static const Color gradientTop = Color(0xFF234E70);
  static const Color gradientMid = Color(0xFF1B425B);
  static const Color gradientBottom = Color(0xFF16324A);

  static const Color dialogTop = Color(0xFF28566B);
  static const Color dialogMid = Color(0xFF1C465B);
  static const Color dialogBottom = Color(0xFF17384B);

  static const Color accent = Color(0xFFFFD166);
  static const Color accentIdle = Color(0xFFE8B94F);
  static const Color accentInk = Color(0xFF17384B);
  static const Color softBlue = Color(0xFF9CCBFF);

  /// 胶囊 Mask 的遮罩：深蓝半透明，替代普通模式的纯黑 68%。
  static const Color mask = Color(0xCC16324A);

  /// 胶囊本体 / 选中态，替换普通模式的 #263247 / #16865A。
  static const Color capsule = Color(0xFF28566B);
  static const Color capsuleActive = Color(0xFFBA7517);

  static const LinearGradient background = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[gradientTop, gradientMid, gradientBottom],
  );

  static const LinearGradient dialog = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[dialogTop, dialogMid, dialogBottom],
  );
}

/// 是否套用儿童模式外观。与全部业务分支共用同一个生效判定式，只读不改。
bool get kidModeOn => ParentalStateController.instance.enabled;

/// 深蓝渐变面板。强更页 / 弹窗 / 只读页共用。
class KidSurface extends StatelessWidget {
  const KidSurface({
    super.key,
    required this.child,
    this.dialog = false,
    this.expand = false,
    this.borderRadius = 24,
    this.padding,
    this.width,
  });

  final Widget child;
  final bool dialog;
  final bool expand;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double? width;

  @override
  Widget build(BuildContext context) {
    Widget surface = Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        gradient: dialog ? KidPalette.dialog : KidPalette.background,
        borderRadius: BorderRadius.circular(borderRadius),
        border: borderRadius > 0
            ? Border.all(color: Colors.white24)
            : null,
      ),
      child: child,
    );
    if (expand) surface = SizedBox.expand(child: surface);
    // 顶层覆盖层没有 Material 祖先时，Flutter 会给文本套黄色双下划线；
    // 统一兜底白色正文样式。
    return DefaultTextStyle(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        decoration: TextDecoration.none,
        decorationColor: Colors.transparent,
      ),
      child: surface,
    );
  }
}

/// 暖黄主按钮：焦点态白描边 + 发光，未聚焦时降饱和。
/// 用 ButtonStyle 的 WidgetState 表达焦点，不改变按钮的焦点/激活语义。
class KidActionButton extends StatelessWidget {
  const KidActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.focusNode,
    this.autofocus = false,
    this.minimumSize = const Size(260, 56),
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final FocusNode? focusNode;
  final bool autofocus;
  final Size minimumSize;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll<Size?>(minimumSize),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        ),
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        backgroundColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.focused)
              ? KidPalette.accent
              : KidPalette.accentIdle,
        ),
        foregroundColor: const WidgetStatePropertyAll<Color>(
          KidPalette.accentInk,
        ),
        side: WidgetStateProperty.resolveWith<BorderSide>(
          (Set<WidgetState> states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? Colors.white
                : Colors.transparent,
            width: states.contains(WidgetState.focused) ? 3 : 1,
          ),
        ),
        elevation: WidgetStateProperty.resolveWith<double>(
          (Set<WidgetState> states) =>
              states.contains(WidgetState.focused) ? 12 : 2,
        ),
        shadowColor: const WidgetStatePropertyAll<Color>(Color(0x99FFD166)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 22),
            const SizedBox(width: 10),
          ],
          Text(label),
        ],
      ),
    );
  }
}

/// 儿童模式统一的轻量提示条（纯外观）。
///
/// 只替换 SnackBar 的配色与形状，不改变显示时机、时长与触发它的行为。
SnackBar kidSnackBar(String message, {Duration? duration}) => SnackBar(
  content: Text(
    message,
    style: const TextStyle(color: Colors.white, fontSize: 16),
  ),
  backgroundColor: KidPalette.dialogMid,
  behavior: SnackBarBehavior.floating,
  duration: duration ?? const Duration(seconds: 4),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: const BorderSide(color: Colors.white24),
  ),
);

/// 次级描边按钮（稍后 / 重试 / 取消）：白色描边，聚焦时暖黄填充。
class KidOutlineButton extends StatelessWidget {
  const KidOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: onPressed,
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.focused)
              ? KidPalette.accentInk
              : Colors.white,
        ),
        backgroundColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.focused)
              ? KidPalette.accent
              : Colors.transparent,
        ),
        side: WidgetStateProperty.resolveWith<BorderSide>(
          (Set<WidgetState> states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? Colors.white
                : KidPalette.softBlue,
            width: states.contains(WidgetState.focused) ? 3 : 1.5,
          ),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 26, vertical: 16),
        ),
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      child: Text(label),
    );
  }
}
