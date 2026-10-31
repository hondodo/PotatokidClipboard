import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';
import 'package:potatokid_clipboard/framework/theme/app_theme.dart';

EdgeInsetsGeometry _scaledPadding(BuildContext context) {
  final ThemeData theme = Theme.of(context);
  double padding1x = 16;
  final double defaultFontSize = theme.textTheme.labelLarge?.fontSize ?? 9.0;
  final double effectiveTextScale =
      MediaQuery.textScalerOf(context).scale(defaultFontSize) / 9.0;

  return ButtonStyleButton.scaledPadding(
    EdgeInsets.symmetric(horizontal: padding1x),
    EdgeInsets.symmetric(horizontal: padding1x / 2),
    EdgeInsets.symmetric(horizontal: padding1x / 2 / 2),
    effectiveTextScale,
  );
}

class AppButton extends ButtonStyleButton {
  static double iconSpacing = 5;
  static final roundedBorder =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));

  /// Create an AppButton.
  const AppButton({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.onHover,
    super.onFocusChange,
    super.style,
    super.focusNode,
    super.autofocus = false,
    super.clipBehavior = Clip.none,
    super.statesController,
    required super.child,
  });

  const factory AppButton.text({
    Key? key,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool? autofocus,
    Clip? clipBehavior,
    WidgetStatesController? statesController,
    required Widget child,
  }) = _AppButtonWithText;

  const factory AppButton.icon({
    Key? key,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool? autofocus,
    Clip? clipBehavior,
    WidgetStatesController? statesController,
    required Widget icon,
  }) = _AppButtonWithIcon;

  // factory AppButton.filled
  const factory AppButton.filled({
    Key? key,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool? autofocus,
    Clip? clipBehavior,
    WidgetStatesController? statesController,
    required Widget child,
  }) = _AppButtonWithFilled;

  const factory AppButton.outlined({
    Key? key,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool? autofocus,
    Clip? clipBehavior,
    WidgetStatesController? statesController,
    required Widget child,
  }) = _AppButtonWithOutlined;

  static AppButton flat({
    Key? key,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool? autofocus,
    Clip? clipBehavior,
    WidgetStatesController? statesController,
    required Widget child,
  }) {
    return AppButton.filled(
        key: key,
        onPressed: onPressed,
        onLongPress: onLongPress,
        onHover: onHover,
        onFocusChange: onFocusChange,
        style: style ??
            const ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
              backgroundColor: WidgetStatePropertyAll(Colors.transparent),
            ),
        focusNode: focusNode,
        autofocus: autofocus,
        clipBehavior: clipBehavior,
        statesController: statesController,
        child: child);
  }

  const factory AppButton.checkable({
    Key? key,
    required bool isChecked,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    ButtonStyle? style,
    FocusNode? focusNode,
    bool? autofocus,
    Clip? clipBehavior,
    WidgetStatesController? statesController,
    required Widget child,
  }) = _AppButtonWithCheckabe;

  static ButtonStyle styleFrom({
    Color? foregroundColor,
    Color? backgroundColor,
    Color? disabledForegroundColor,
    Color? disabledBackgroundColor,
    Color? shadowColor,
    Color? surfaceTintColor,
    double? elevation,
    TextStyle? textStyle,
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? fixedSize,
    Size? maximumSize,
    BorderSide? side,
    OutlinedBorder? shape,
    MouseCursor? enabledMouseCursor,
    MouseCursor? disabledMouseCursor,
    VisualDensity? visualDensity,
    MaterialTapTargetSize? tapTargetSize,
    Duration? animationDuration,
    bool? enableFeedback,
    AlignmentGeometry? alignment,
    InteractiveInkFeatureFactory? splashFactory,
  }) {
    final Color? background = backgroundColor;
    final Color? disabledBackground = disabledBackgroundColor;
    final WidgetStateProperty<Color?>? backgroundColorProp =
        (background == null && disabledBackground == null)
            ? null
            : _AppButtonDefaultColor(background, disabledBackground);
    final Color? foreground = foregroundColor;
    final Color? disabledForeground = disabledForegroundColor;
    final WidgetStateProperty<Color?>? foregroundColorProp =
        (foreground == null && disabledForeground == null)
            ? null
            : _AppButtonDefaultColor(foreground, disabledForeground);
    final WidgetStateProperty<Color?>? overlayColor =
        (foreground == null) ? null : _AppButtonDefaultOverlay(foreground);
    final WidgetStateProperty<double>? elevationValue =
        (elevation == null) ? null : _AppButtonDefaultElevation(elevation);
    final WidgetStateProperty<MouseCursor?> mouseCursor =
        _AppButtonDefaultMouseCursor(enabledMouseCursor, disabledMouseCursor);

    return ButtonStyle(
      textStyle: WidgetStatePropertyAll<TextStyle?>(textStyle),
      backgroundColor: backgroundColorProp,
      foregroundColor: foregroundColorProp,
      overlayColor: overlayColor,
      shadowColor: ButtonStyleButton.allOrNull<Color>(shadowColor),
      surfaceTintColor: ButtonStyleButton.allOrNull<Color>(surfaceTintColor),
      elevation: elevationValue,
      padding: ButtonStyleButton.allOrNull<EdgeInsetsGeometry>(padding),
      minimumSize: ButtonStyleButton.allOrNull<Size>(minimumSize),
      fixedSize: ButtonStyleButton.allOrNull<Size>(fixedSize),
      maximumSize: ButtonStyleButton.allOrNull<Size>(maximumSize),
      side: ButtonStyleButton.allOrNull<BorderSide>(side),
      shape: ButtonStyleButton.allOrNull<OutlinedBorder>(shape),
      mouseCursor: mouseCursor,
      visualDensity: visualDensity,
      tapTargetSize: tapTargetSize,
      animationDuration: animationDuration,
      enableFeedback: enableFeedback,
      alignment: alignment,
      splashFactory: splashFactory,
    );
  }

  @override
  ButtonStyle defaultStyleOf(BuildContext context) {
    // final ThemeData theme = Theme.of(context);
    // final ColorScheme colorScheme = theme.colorScheme;
    return _AppButtonDefaults(context);
  }

  /// Returns the [ElevatedButtonThemeData.style] of the closest
  /// [ElevatedButtonTheme] ancestor.
  @override
  ButtonStyle? themeStyleOf(BuildContext context) {
    return ElevatedButtonTheme.of(context).style;
  }
}

class _AppButtonWithText extends AppButton {
  const _AppButtonWithText({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.onHover,
    super.onFocusChange,
    super.style,
    super.focusNode,
    bool? autofocus,
    Clip? clipBehavior,
    super.statesController,
    required Widget child,
  }) : super(
          autofocus: autofocus ?? false,
          clipBehavior: clipBehavior ?? Clip.none,
          child: child,
        );

  @override
  ButtonStyle defaultStyleOf(BuildContext context) {
    return super.defaultStyleOf(context).copyWith(
          backgroundColor:
              const WidgetStatePropertyAll<Color>(Colors.transparent),
        );
  }
}

class _AppButtonWithIcon extends AppButton {
  const _AppButtonWithIcon({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.onHover,
    super.onFocusChange,
    super.style,
    super.focusNode,
    bool? autofocus,
    Clip? clipBehavior,
    super.statesController,
    required Widget icon,
  }) : super(
          autofocus: autofocus ?? false,
          clipBehavior: clipBehavior ?? Clip.none,
          child: icon,
        );

  @override
  ButtonStyle defaultStyleOf(BuildContext context) {
    return super.defaultStyleOf(context).copyWith(
        minimumSize: const WidgetStatePropertyAll<Size?>(Size.zero),
        backgroundColor:
            const WidgetStatePropertyAll<Color?>(Colors.transparent),
        padding: WidgetStatePropertyAll<EdgeInsetsGeometry?>(EdgeInsets.all(5))
        // padding: EdgeInsets.all(12);
        );
  }
}

class _AppButtonWithOutlined extends AppButton {
  const _AppButtonWithOutlined({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.onHover,
    super.onFocusChange,
    super.style,
    super.focusNode,
    bool? autofocus,
    Clip? clipBehavior,
    super.statesController,
    required Widget child,
  }) : super(
          autofocus: autofocus ?? false,
          clipBehavior: clipBehavior ?? Clip.none,
          child: child,
        );

  @override
  ButtonStyle defaultStyleOf(BuildContext context) {
    // final colors = Theme.of(context).colorScheme;
    final theme = AppTheme.instance;
    return super.defaultStyleOf(context).copyWith(
        foregroundColor: WidgetStatePropertyAll(theme.primaryColor),
        shape: WidgetStatePropertyAll(AppButton.roundedBorder),
        side: WidgetStatePropertyAll(BorderSide(color: theme.primaryColor))
        // side: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        //   if (states.contains(WidgetState.disabled)) {
        //     return BorderSide(color: colors.onSurface.withOpacity(0.12));
        //   }
        //   if (states.contains(WidgetState.focused)) {
        //     return BorderSide(color: colors.primary);
        //   }
        //   return BorderSide(color: colors.outline);
        // }),
        // minimumSize: const MaterialStatePropertyAll<Size?>(Size.zero),
        // backgroundColor:
        // const MaterialStatePropertyAll<Color?>(Colors.transparent),
        // padding: const MaterialStatePropertyAll<EdgeInsetsGeometry?>(EdgeInsets.all(5))
        // padding: EdgeInsets.all(12);
        );
  }
}

class _AppButtonWithFilled extends AppButton {
  const _AppButtonWithFilled({
    super.key,
    required super.onPressed,
    super.onLongPress,
    super.onHover,
    super.onFocusChange,
    super.style,
    super.focusNode,
    bool? autofocus,
    Clip? clipBehavior,
    super.statesController,
    required Widget child,
  }) : super(
          autofocus: autofocus ?? false,
          clipBehavior: clipBehavior ?? Clip.none,
          child: child,
        );

  @override
  ButtonStyle defaultStyleOf(BuildContext context) {
    // final colors = Theme.of(context).colorScheme;
    final theme = AppTheme.instance; // Get.find<ThemeController>().data;
    return super.defaultStyleOf(context).copyWith(
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        backgroundColor:
            WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return theme.disabledColor;
          }
          return theme.primaryColor;
        }));
  }
}

class _AppButtonWithCheckabe extends AppButton {
  final bool isChecked;
  const _AppButtonWithCheckabe({
    super.key,
    required this.isChecked,
    required super.onPressed,
    super.onLongPress,
    super.onHover,
    super.onFocusChange,
    super.style,
    super.focusNode,
    bool? autofocus,
    Clip? clipBehavior,
    super.statesController,
    required Widget child,
  }) : super(
          autofocus: autofocus ?? false,
          clipBehavior: clipBehavior ?? Clip.none,
          child: child,
        );

  @override
  ButtonStyle defaultStyleOf(BuildContext context) {
    // final colors = Theme.of(context).colorScheme;
    final theme = AppTheme.instance; // Get.find<ThemeController>().data;
    return super.defaultStyleOf(context).copyWith(
        backgroundColor: WidgetStatePropertyAll(
            isChecked ? theme.primaryColor : Colors.transparent));
  }
}

class _AppButtonDefaults extends ButtonStyle {
  _AppButtonDefaults(this.context)
      : super(
          animationDuration: kThemeChangeDuration,
          enableFeedback: true,
          alignment: Alignment.center,
        );

  final BuildContext context;
  // late final ColorScheme _colors = Theme.of(context).colorScheme;
  // late final ThemeModel theme = Get.find<ThemeController>().data;
  final AppTheme theme = AppTheme.instance;

  @override
  WidgetStateProperty<TextStyle?> get textStyle =>
      WidgetStatePropertyAll<TextStyle?>(AppTextTheme.textStyle.body.medium);

  @override
  WidgetStateProperty<Color?>? get backgroundColor =>
      WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) {
          return theme.disabledColor.withValues(alpha: 0.12);
        }
        return theme.primaryColor;
      });

  @override
  WidgetStateProperty<Color?>? get foregroundColor =>
      WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) {
          return theme.disabledColor.withValues(alpha: 0.38);
        }
        return theme.primaryColor;
      });

  @override
  WidgetStateProperty<Color?>? get overlayColor =>
      const WidgetStatePropertyAll<Color>(Colors.transparent); // 点击交互动画颜色
  // MaterialStateProperty.resolveWith((Set<MaterialState> states) {
  //   if (states.contains(MaterialState.pressed)) {
  //     return _colors.primary.withOpacity(0.12);
  //   }
  //   if (states.contains(MaterialState.hovered)) {
  //     return _colors.primary.withOpacity(0.08);
  //   }
  //   if (states.contains(MaterialState.focused)) {
  //     return _colors.primary.withOpacity(0.12);
  //   }
  //   return null;
  // });

  @override
  WidgetStateProperty<Color>? get shadowColor =>
      const WidgetStatePropertyAll<Color>(Colors.transparent);
  // MaterialStatePropertyAll<Color>(_colors.shadow);

  @override
  WidgetStateProperty<Color>? get surfaceTintColor =>
      const WidgetStatePropertyAll<Color>(Colors.transparent); // 悬浮颜色
  // MaterialStatePropertyAll<Color>(_colors.surfaceTint);

  @override
  WidgetStateProperty<double>? get elevation =>
      WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        // if (states.contains(MaterialState.disabled)) {
        //   return 0.0;
        // }
        // if (states.contains(MaterialState.pressed)) {
        //   return 1.0;
        // }
        // if (states.contains(MaterialState.hovered)) {
        //   return 3.0;
        // }
        // if (states.contains(MaterialState.focused)) {
        //   return 1.0;
        // }
        // return 1.0;
        return 0.0;
      });

  @override
  WidgetStateProperty<EdgeInsetsGeometry>? get padding =>
      WidgetStatePropertyAll<EdgeInsetsGeometry>(_scaledPadding(context));

  @override
  WidgetStateProperty<Size>? get minimumSize =>
      WidgetStatePropertyAll<Size>(Size(64, 40));

  // No default fixedSize

  @override
  WidgetStateProperty<Size>? get maximumSize =>
      const WidgetStatePropertyAll<Size>(Size.infinite);

  // No default side

  @override
  WidgetStateProperty<OutlinedBorder>? get shape =>
      // const MaterialStatePropertyAll<RoundedRectangleBorder>(
      //  RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8.0))));
      const WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder());
  /*
    斜切角: BeveledRectangleBorder
    圆角: RoundedRectangleBorder
    超椭圆: SuperellipseShape
    体育场: StadiumBorder
    圆形: CircleBorder
     */

  @override
  WidgetStateProperty<MouseCursor?>? get mouseCursor =>
      WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) {
          return SystemMouseCursors.basic;
        }
        return SystemMouseCursors.click;
      });

  @override
  VisualDensity? get visualDensity => Theme.of(context).visualDensity;

  @override
  MaterialTapTargetSize? get tapTargetSize =>
      Theme.of(context).materialTapTargetSize;

  @override
  InteractiveInkFeatureFactory? get splashFactory => NoSplash.splashFactory;
  // Theme.of(context).splashFactory;
}

@immutable
class _AppButtonDefaultColor extends WidgetStateProperty<Color?>
    with Diagnosticable {
  _AppButtonDefaultColor(this.color, this.disabled);

  final Color? color;
  final Color? disabled;

  @override
  Color? resolve(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) {
      return disabled;
    }
    return color;
  }
}

@immutable
class _AppButtonDefaultOverlay extends WidgetStateProperty<Color?>
    with Diagnosticable {
  _AppButtonDefaultOverlay(this.overlay);

  final Color overlay;

  @override
  Color? resolve(Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed)) {
      return overlay.withValues(alpha: 0.24);
    }
    if (states.contains(WidgetState.hovered)) {
      return overlay.withValues(alpha: 0.08);
    }
    if (states.contains(WidgetState.focused)) {
      return overlay.withValues(alpha: 0.24);
    }
    return null;
  }
}

@immutable
class _AppButtonDefaultElevation extends WidgetStateProperty<double>
    with Diagnosticable {
  _AppButtonDefaultElevation(this.elevation);

  final double elevation;

  @override
  double resolve(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) {
      return 0;
    }
    if (states.contains(WidgetState.pressed)) {
      return elevation + 6;
    }
    if (states.contains(WidgetState.hovered)) {
      return elevation + 2;
    }
    if (states.contains(WidgetState.focused)) {
      return elevation + 2;
    }
    return elevation;
  }
}

@immutable
class _AppButtonDefaultMouseCursor extends WidgetStateProperty<MouseCursor?>
    with Diagnosticable {
  _AppButtonDefaultMouseCursor(this.enabledCursor, this.disabledCursor);

  final MouseCursor? enabledCursor;
  final MouseCursor? disabledCursor;

  @override
  MouseCursor? resolve(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) {
      return disabledCursor;
    }
    return enabledCursor;
  }
}
