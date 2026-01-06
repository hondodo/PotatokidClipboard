import 'package:flutter/material.dart';
import 'package:potatokid_clipboard/framework/components/app_button.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';
import 'package:potatokid_clipboard/framework/theme/app_theme.dart';

class AppButtonNew extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  const AppButtonNew({super.key, required this.onPressed, required this.child});

  @override
  State<AppButtonNew> createState() => _AppButtonNewState();
}

class _AppButtonNewState extends State<AppButtonNew> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.onPressed?.call();
      },
      child: widget.child,
    );
  }
}

enum AppButtonType {
  /// 主按钮
  /// 最小高度：44px（底线，低于此值易误触，尤其对中老年用户不友好）。
  /// 常用高度：48px（主流选择，平衡触控体验与界面紧凑性，适配大多数 App）。
  /// 特殊场景：重要操作按钮（如支付、提交订单）可设为 56px，增强视觉权重和点击容错性。
  /// 圆角：设计稿为：54高时，圆角为12，44高时，圆角为10，32高时，圆角为8，根据高度选择合适的圆角 12/10/8
  primary,

  /// 次级按钮
  /// 最小高度：44px（底线，低于此值易误触，尤其对中老年用户不友好）。
  /// 常用高度：48px（主流选择，平衡触控体验与界面紧凑性，适配大多数 App）。
  /// 特殊场景：重要操作按钮（如支付、提交订单）可设为 56px，增强视觉权重和点击容错性。
  secondary,

  /// 文字按钮
  /// 文字字号 16px，行高 24px，上下内边距各 10px（10+24+10=44px），确保触控容错性。
  text,

  /// 小按钮（特殊）
  /// 文字字号 14px，行高 20px，上下内边距各 6px（12+24+=32px），确保触控容错性。
  /// 最小高度：32px（资料卡片方面的按钮）。
  small,
}

enum TextWeightStyle {
  normal,
  bold,
  medium,
}

enum TextFontSizeStyle {
  notSet,
  mini,
  small,
  medium,
  large,
}

class AppButtonCommon extends StatefulWidget {
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// Called when a pointer enters or exits the button response area.
  ///
  /// The value passed to the callback is true if a pointer has entered this
  /// part of the material and false if a pointer has exited this part of the
  /// material.
  final ValueChanged<bool>? onHover;

  /// Handler called when the focus changes.
  ///
  /// Called with true if this widget's node gains focus, and false if it loses
  /// focus.
  final ValueChanged<bool>? onFocusChange;

  /// Called when a tap down event occurs.
  final GestureTapDownCallback? onTapDown;

  /// Called when a tap up event occurs.
  final GestureTapUpCallback? onTapUp;

  final Widget child;
  final AppButtonType type;
  final double? height;
  final double? width;
  final EdgeInsets? padding;
  final bool isEnabled;

  /// 是否可以点击当按钮禁用时，默认不可以
  final bool canPressWhenDisabled;

  /// 是否选中
  final bool isSelected;

  /// 是否可以选中
  final bool isSelectable;

  /// 圆角
  /// 默认根据高度计算，如果传入，则使用传入的值 >=50:12, >40:10, >30:8, 其它:4
  final double? radius;
  final List<BoxShadow>? boxShadow;
  final bool showShadow;
  final Color? backgroundColor;
  final Color? disabledBackgroundColor;
  final Color? pressedBackgroundColor;
  final Color? unSelectedPressedBackgroundColor;
  final Color? unSelectedBackgroundColor;
  final Color? unSelectedTextColor;

  /// 边框颜色, 如果传入[border]，则使用[border]，不使用[borderColor]
  final Color? borderColor;

  /// 边框, 如果传入，则使用传入的值，不使用[borderColor]
  final BoxBorder? border;

  const AppButtonCommon({
    super.key,
    required this.onPressed,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.onTapDown,
    this.onTapUp,
    required this.child,
    this.type = AppButtonType.primary,
    this.height,
    this.radius,
    this.width,
    this.padding,
    this.boxShadow,
    this.showShadow = true,
    this.backgroundColor,
    this.disabledBackgroundColor,
    this.pressedBackgroundColor,
    this.unSelectedPressedBackgroundColor,
    this.unSelectedBackgroundColor,
    this.unSelectedTextColor,
    this.isEnabled = true,
    this.canPressWhenDisabled = false,
    this.borderColor,
    this.isSelected = false,
    this.isSelectable = false,
    this.border,
  });

  @override
  State<AppButtonCommon> createState() => _AppButtonCommonState();

  /// 主按钮, 默认高度32px, 圆角8px, 宽度自适应到最大，背景色为主色（当前为紫色），带阴影
  factory AppButtonCommon.primary({
    Key? key,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    GestureTapDownCallback? onTapDown,
    GestureTapUpCallback? onTapUp,
    required Widget child,
    double? height,
    double? radius,
    double? width,
    EdgeInsets? padding,
    List<BoxShadow>? boxShadow,
    bool showShadow = true,
    Color? backgroundColor,
    Color? disabledBackgroundColor,
    Color? pressedBackgroundColor,
    bool isEnabled = true,
    bool canPressWhenDisabled = false,
    Color? borderColor,
    bool isSelected = false,
    bool isSelectable = false,
    Color? unSelectedTextColor,
    Color? unSelectedPressedBackgroundColor,
    Color? unSelectedBackgroundColor,
    BoxBorder? border,
  }) {
    return AppButtonCommon(
      key: key,
      onPressed: onPressed,
      onLongPress: onLongPress,
      onHover: onHover,
      onFocusChange: onFocusChange,
      onTapDown: onTapDown,
      onTapUp: onTapUp,
      height: height ?? 32,
      radius: radius,
      width: width,
      padding: padding ?? EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      boxShadow: boxShadow,
      showShadow: showShadow,
      backgroundColor: backgroundColor,
      disabledBackgroundColor: disabledBackgroundColor,
      pressedBackgroundColor: pressedBackgroundColor,
      isEnabled: isEnabled,
      canPressWhenDisabled: canPressWhenDisabled,
      borderColor: borderColor,
      isSelected: isSelected,
      isSelectable: isSelectable,
      unSelectedTextColor: unSelectedTextColor,
      unSelectedPressedBackgroundColor: unSelectedPressedBackgroundColor,
      unSelectedBackgroundColor: unSelectedBackgroundColor,
      border: border,
      child: child,
    );
  }

  /// 白色按钮, 默认高度32px, 圆角8px, 宽度自适应到最大，背景色为白色，带阴影
  factory AppButtonCommon.primaryWhite({
    Key? key,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    GestureTapDownCallback? onTapDown,
    GestureTapUpCallback? onTapUp,
    required Widget child,
    double? height,
    double? radius,
    double? width,
    EdgeInsets? padding,
    List<BoxShadow>? boxShadow,
    bool showShadow = true,
    Color? backgroundColor,
    Color? disabledBackgroundColor,
    Color? pressedBackgroundColor,
    bool isEnabled = true,
    bool canPressWhenDisabled = false,
    Color? borderColor,
    Color? unSelectedTextColor,
    Color? unSelectedPressedBackgroundColor,
    Color? unSelectedBackgroundColor,
    BoxBorder? border,
  }) {
    final theme = AppTheme.instance;
    return AppButtonCommon.primary(
      key: key,
      onPressed: onPressed,
      onLongPress: onLongPress,
      onHover: onHover,
      onFocusChange: onFocusChange,
      onTapDown: onTapDown,
      onTapUp: onTapUp,
      height: height ?? 32,
      radius: radius,
      width: width,
      padding: padding ?? EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      boxShadow: boxShadow,
      showShadow: showShadow,
      backgroundColor: backgroundColor ?? theme.primaryColor,
      disabledBackgroundColor: disabledBackgroundColor ?? theme.disabledColor,
      pressedBackgroundColor: pressedBackgroundColor ?? theme.pressedColor,
      isEnabled: isEnabled,
      canPressWhenDisabled: canPressWhenDisabled,
      borderColor: borderColor,
      unSelectedTextColor: unSelectedTextColor,
      unSelectedPressedBackgroundColor: unSelectedPressedBackgroundColor,
      unSelectedBackgroundColor: unSelectedBackgroundColor,
      border: border,
      child: child,
    );
  }

  /// 主按钮, 默认高度32px, 圆角8px, 宽度最小，如果要宽度最大由设置[width]为double.infinity，背景色为主色（当前为紫色），带阴影，
  /// 可带前缀图标[prefixIcon]，图标和文字的间距[iconTextSpacing]，默认：32px（小于40）时，间距为4px，其它时，间距为8px
  /// 文字颜色为白色, 文字大小为12px(mini), 文字粗细为Medium, 文字居中
  factory AppButtonCommon.primaryWithTextIcon({
    Key? key,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    GestureTapDownCallback? onTapDown,
    GestureTapUpCallback? onTapUp,
    required String text,
    double? height,
    double? radius,
    double? width,
    EdgeInsets? padding,
    List<BoxShadow>? boxShadow,
    bool showShadow = true,
    Color? backgroundColor,
    Color? disabledBackgroundColor,
    Color? pressedBackgroundColor,
    Color? unSelectedPressedBackgroundColor,
    bool isEnabled = true,

    /// 文字样式，
    /// 如果[textStyle]为空，则根据高度自动分配文字大小和样式
    /// 否则以传入的[textStyle]为准
    /// 如果不传入则使用themeService的buttonLabelMini样式，
    /// 再根据[textColor],[textSize],[textFontSizeStyle],[textWeightStyle]调整
    /// 未列出的文字样式如斜体，画线等，需要使用[textStyle]调整，或开放出可设置的更多样式，
    /// 如斜体，画线等
    TextStyle? textStyle,

    /// 文字颜色
    Color? textColor,

    /// 文字大小1，如果传入，则使用传入的值，不使用[textFontSizeStyle]
    double? textSize,

    /// 文字大小2，当[textSize]为null时，按[textFontSizeStyle]使用不同和值，
    /// 按themeService对应的mini/small/medium/large取值，
    /// 当前的样式配置为mini：12px, small：14px, medium：16px, large：24px
    TextFontSizeStyle? textFontSizeStyle,

    /// 文字粗细
    TextWeightStyle? textWeightStyle = TextWeightStyle.medium,

    /// 前缀图标
    Widget? prefixIcon,

    /// 图标和文字的间距  默认：32px（小于40）时，间距为4px，其它时，间距为8px
    double? iconTextSpacing,

    /// 是否可以点击当按钮禁用时，默认不可以
    bool canPressWhenDisabled = false,
    Color? borderColor,
    bool isSelected = false,
    bool isSelectable = false,
    Color? unSelectedTextColor,
    Color? unSelectedBackgroundColor,
    BoxBorder? border,
    int? maxLine,
    TextOverflow? overflow,
  }) {
    TextStyle useTextStyle = textStyle ?? AppTextTheme.textStyle.title;
    double? useTextSize = textSize;
    // 如果textStyle为空，则根据高度自动分配文字大小和样式
    // 否则以传入的textStyle为准
    if (textStyle == null) {
      TextFontSizeStyle useTextFontSizeStyle =
          textFontSizeStyle ?? TextFontSizeStyle.notSet;
      // 没设置过文字大小和样式，根据高度自动分配
      if (useTextSize == null &&
          useTextFontSizeStyle == TextFontSizeStyle.notSet) {
        if (height != null && height != double.infinity) {
          if (height < 40) {
            useTextFontSizeStyle = TextFontSizeStyle.mini;
          } else if (height < 54) {
            useTextFontSizeStyle = TextFontSizeStyle.small;
          } else {
            useTextFontSizeStyle = TextFontSizeStyle.medium;
          }
        }
      }
      if (useTextSize == null &&
          useTextFontSizeStyle != TextFontSizeStyle.notSet) {
        if (useTextFontSizeStyle == TextFontSizeStyle.mini) {
          useTextSize = AppTextTheme.fontSizeMini;
        } else if (useTextFontSizeStyle == TextFontSizeStyle.small) {
          useTextSize = AppTextTheme.fontSizeSmall;
        } else if (useTextFontSizeStyle == TextFontSizeStyle.medium) {
          useTextSize = AppTextTheme.fontSizeMedium;
        } else if (useTextFontSizeStyle == TextFontSizeStyle.large) {
          useTextSize = AppTextTheme.fontSizeLarge;
        }
      }

      Color useTextColor = textColor ??
          (isEnabled
              ? AppTextTheme.buttonTextColor
              : AppTextTheme.disabledColor);

      if (isSelectable && !isSelected) {
        useTextColor = unSelectedTextColor ?? AppTextTheme.disabledColor;
      }

      useTextStyle = useTextStyle.copyWith(
        color: useTextColor,
        fontSize: useTextSize,
      );

      if (textWeightStyle == TextWeightStyle.bold) {
        useTextStyle = useTextStyle.bold;
      } else if (textWeightStyle == TextWeightStyle.medium) {
        useTextStyle = useTextStyle.medium;
      }
    }

    double buttonHeight = height ?? 32;
    double useIconTextSpacing = iconTextSpacing ?? (buttonHeight < 40 ? 4 : 8);

    return AppButtonCommon.primary(
      key: key,
      onPressed: onPressed,
      onLongPress: onLongPress,
      onHover: onHover,
      onFocusChange: onFocusChange,
      onTapDown: onTapDown,
      onTapUp: onTapUp,
      height: buttonHeight,
      radius: radius,
      width: width,
      padding: padding ?? EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      boxShadow: boxShadow,
      showShadow: showShadow,
      backgroundColor: backgroundColor,
      disabledBackgroundColor: disabledBackgroundColor,
      pressedBackgroundColor: pressedBackgroundColor,
      unSelectedPressedBackgroundColor: unSelectedPressedBackgroundColor,
      isEnabled: isEnabled,
      canPressWhenDisabled: canPressWhenDisabled,
      borderColor: borderColor,
      isSelected: isSelected,
      isSelectable: isSelectable,
      border: border,
      child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Visibility(
                visible: prefixIcon != null,
                child: prefixIcon == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: EdgeInsets.only(right: useIconTextSpacing),
                        child: prefixIcon,
                      )),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                text,
                style: useTextStyle,
                textAlign: TextAlign.center,
                maxLines: maxLine ?? 1,
                overflow: overflow ?? TextOverflow.ellipsis,
              ),
            ),
          ]),
    );
  }

  factory AppButtonCommon.outlineWhitePrimary({
    Key? key,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    GestureTapDownCallback? onTapDown,
    GestureTapUpCallback? onTapUp,
    required String text,
    double? height,
    double? radius,
    double? width,
    EdgeInsets? padding,
    List<BoxShadow>? boxShadow,
    bool showShadow = true,
    Color? backgroundColor,
    Color? disabledBackgroundColor,
    Color? pressedBackgroundColor,
    Color? unSelectedPressedBackgroundColor,
    bool isEnabled = true,
    TextStyle? textStyle,
    Color? textColor,
    Color? disabledTextColor,
    double? textSize,
    TextFontSizeStyle? textFontSizeStyle,
    TextWeightStyle? textWeightStyle = TextWeightStyle.medium,
    Widget? prefixIcon,
    double? iconTextSpacing,
    bool canPressWhenDisabled = false,
    Color? borderColor,
    BoxBorder? border,
    Color? disabledBorderColor,
  }) {
    final theme = AppTheme.instance;
    return AppButtonCommon.primaryWithTextIcon(
      key: key,
      onPressed: onPressed,
      onLongPress: onLongPress,
      onHover: onHover,
      onFocusChange: onFocusChange,
      onTapDown: onTapDown,
      onTapUp: onTapUp,
      text: text,
      textSize: textSize,
      height: height,
      radius: radius,
      width: width,
      padding: padding,
      boxShadow: boxShadow,
      showShadow: showShadow,
      textFontSizeStyle: textFontSizeStyle,
      textWeightStyle: textWeightStyle,
      prefixIcon: prefixIcon,
      iconTextSpacing: iconTextSpacing,
      canPressWhenDisabled: canPressWhenDisabled,
      backgroundColor: backgroundColor ?? theme.primaryColor,
      textColor: isEnabled
          ? textColor ?? AppTextTheme.buttonTextColor
          : disabledTextColor ?? AppTextTheme.disabledColor,
      unSelectedPressedBackgroundColor: unSelectedPressedBackgroundColor,
      pressedBackgroundColor: pressedBackgroundColor ?? theme.pressedColor,
      borderColor: isEnabled
          ? borderColor ?? theme.primaryColor
          : disabledBorderColor ?? AppTextTheme.disabledColor,
      border: border,
      textStyle: textStyle,
    );
  }

  factory AppButtonCommon.outlineWhite({
    Key? key,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    ValueChanged<bool>? onHover,
    ValueChanged<bool>? onFocusChange,
    GestureTapDownCallback? onTapDown,
    GestureTapUpCallback? onTapUp,
    required String text,
    double? height,
    double? radius,
    double? width,
    EdgeInsets? padding,
    List<BoxShadow>? boxShadow,
    bool showShadow = true,
    Color? backgroundColor,
    Color? disabledBackgroundColor,
    Color? pressedBackgroundColor,
    Color? unSelectedPressedBackgroundColor,
    bool isEnabled = true,
    TextStyle? textStyle,
    Color? textColor,
    double? textSize,
    TextFontSizeStyle? textFontSizeStyle,
    TextWeightStyle? textWeightStyle = TextWeightStyle.medium,
    Widget? prefixIcon,
    double? iconTextSpacing,
    bool canPressWhenDisabled = false,
    Color? borderColor,
    BoxBorder? border,
  }) {
    final theme = AppTheme.instance;
    return AppButtonCommon.primaryWithTextIcon(
      key: key,
      onPressed: onPressed,
      onLongPress: onLongPress,
      onHover: onHover,
      onFocusChange: onFocusChange,
      onTapDown: onTapDown,
      onTapUp: onTapUp,
      text: text,
      textSize: textSize,
      height: height,
      radius: radius,
      width: width,
      padding: padding,
      boxShadow: boxShadow,
      showShadow: showShadow,
      textFontSizeStyle: textFontSizeStyle,
      textWeightStyle: textWeightStyle,
      prefixIcon: prefixIcon,
      iconTextSpacing: iconTextSpacing,
      canPressWhenDisabled: canPressWhenDisabled,
      backgroundColor: backgroundColor ?? theme.primaryColor,
      textColor: textColor ?? AppTextTheme.buttonTextColor,
      unSelectedPressedBackgroundColor: unSelectedPressedBackgroundColor,
      pressedBackgroundColor: pressedBackgroundColor ?? theme.pressedColor,
      borderColor: borderColor ?? theme.primaryColor,
      border: border,
      textStyle: textStyle,
    );
  }
}

class _AppButtonCommonState extends State<AppButtonCommon> {
  final AppTheme theme = AppTheme.instance;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: getBoxShadow(),
        borderRadius: BorderRadius.circular(getRadius()),
        border: widget.border ??
            (widget.borderColor == null
                ? null
                : Border.all(
                    color: widget.borderColor ?? Colors.transparent,
                    width: 1,
                  )),
      ),
      height: widget.height,
      width: widget.width,
      child: widget.isSelectable
          ? AppButton.checkable(
              isChecked: widget.isSelected,
              onPressed: widget.canPressWhenDisabled
                  ? widget.onPressed
                  : widget.isEnabled
                      ? widget.onPressed
                      : null,
              onLongPress: widget.canPressWhenDisabled
                  ? widget.onLongPress
                  : widget.isEnabled
                      ? widget.onLongPress
                      : null,
              onHover: widget.canPressWhenDisabled
                  ? widget.onHover
                  : widget.isEnabled
                      ? widget.onHover
                      : null,
              onFocusChange: widget.canPressWhenDisabled
                  ? widget.onFocusChange
                  : widget.isEnabled
                      ? widget.onFocusChange
                      : null,
              onTapDown: widget.canPressWhenDisabled
                  ? widget.onTapDown
                  : widget.isEnabled
                      ? widget.onTapDown
                      : null,
              onTapUp: widget.canPressWhenDisabled
                  ? widget.onTapUp
                  : widget.isEnabled
                      ? widget.onTapUp
                      : null,
              style: getButtonStyle(),
              child: widget.child,
            )
          : AppButton.filled(
              onLongPress: widget.canPressWhenDisabled
                  ? widget.onLongPress
                  : widget.isEnabled
                      ? widget.onLongPress
                      : null,
              onHover: widget.canPressWhenDisabled
                  ? widget.onHover
                  : widget.isEnabled
                      ? widget.onHover
                      : null,
              onFocusChange: widget.canPressWhenDisabled
                  ? widget.onFocusChange
                  : widget.isEnabled
                      ? widget.onFocusChange
                      : null,
              onPressed: widget.canPressWhenDisabled
                  ? widget.onPressed
                  : widget.isEnabled
                      ? widget.onPressed
                      : null,
              onTapDown: widget.canPressWhenDisabled
                  ? widget.onTapDown
                  : widget.isEnabled
                      ? widget.onTapDown
                      : null,
              onTapUp: widget.canPressWhenDisabled
                  ? widget.onTapUp
                  : widget.isEnabled
                      ? widget.onTapUp
                      : null,
              style: getButtonStyle(),
              child: widget.child),
    );
  }

  ButtonStyle getButtonStyle() {
    switch (widget.type) {
      case AppButtonType.primary:
        return primaryButtonStyle();
      case AppButtonType.secondary:
        return const ButtonStyle();
      case AppButtonType.text:
        return const ButtonStyle();
      case AppButtonType.small:
        return const ButtonStyle();
    }
  }

  ButtonStyle primaryButtonStyle() {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (!widget.isEnabled || states.contains(WidgetState.disabled)) {
          return widget.disabledBackgroundColor ?? theme.disabledColor;
        }
        if (states.contains(WidgetState.pressed)) {
          if (widget.isSelectable && !widget.isSelected) {
            return widget.unSelectedPressedBackgroundColor ??
                theme.unselectedPressedColor;
          }
          return widget.pressedBackgroundColor ?? theme.pressedColor;
        }
        // if (states.contains(WidgetState.selected)) {
        //   return widget.backgroundColor ?? theme.primaryButtonColor;
        // }
        if (widget.isSelectable) {
          return widget.isSelected
              ? (widget.backgroundColor ?? theme.primaryColor)
              : (widget.unSelectedBackgroundColor ??
                  theme.unselectedBackgroundColor);
        }
        return widget.backgroundColor ?? theme.primaryColor;
      }),
      foregroundColor: WidgetStateProperty.all(Colors.transparent),
      padding: WidgetStateProperty.all(widget.padding ?? EdgeInsets.zero),
      shape: WidgetStateProperty.all(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(getRadius()))),
    );
  }

  List<BoxShadow>? getBoxShadow() {
    if (!widget.showShadow) {
      return null;
    }
    if (widget.boxShadow != null) {
      return widget.boxShadow;
    }
    return [
      BoxShadow(
        color: theme.shadowColor,
        blurRadius: 2,
        offset: Offset(0, 1),
      ),
    ];
  }

  double getRadius() {
    double height = widget.height ?? 0;
    if (widget.radius == null && height != double.infinity && height > 0) {
      if (height >= 50) {
        return 12;
      } else if (height > 40) {
        return 10;
      } else if (height >= 30) {
        return 8;
      } else {
        return 4;
      }
    }
    return widget.radius ?? 12;
  }
}
