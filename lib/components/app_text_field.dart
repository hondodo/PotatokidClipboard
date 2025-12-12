import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:potatokid_clipboard/components/colored_text_controller.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';
import 'package:potatokid_clipboard/framework/theme/app_theme.dart';

/// 输入框,默认高度是48，如果高度为null，则高度为输入框的高度
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.hintText,
    this.controller,
    this.height = 32,
    this.onChanged,
    this.maxLines = 1,
    this.minLines = 1,
    this.maxLength,
    this.disableLenghtText = false,
    this.autoShowCounter = false,
    this.inputFormatters,
    this.labelText,
    this.onEditingComplete,
    this.onSubmitted,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.initText,
    this.borderSide,
    this.enabled,
    this.contentPadding = const EdgeInsets.fromLTRB(2, 0, 2, 0),
    this.style,
    this.hintStyle,
    this.autofocus,
    this.decoration,
    this.maxLengthEnforcement,
    this.showCounterMinLines = 0,
    this.showExceededCounter = false,
    this.exceededColor,
    this.counterStyle,
    this.exceededCounterColor,
    this.isReadOnly = false,
    this.backgroundColor,
    this.unFocusBorderColor,
    this.showClearButton = false,
    this.clearIcon,
    this.onClear,
    this.alwaysShowPrefixIcon = false,
    this.borderRadius = 8,
  });

  final String? hintText;
  final TextEditingController? controller;
  final double? height;
  final Function(String text)? onChanged;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final bool disableLenghtText;
  final List<TextInputFormatter>? inputFormatters;
  final String? labelText;
  final FocusNode? focusNode;
  final bool? enabled;
  final bool isReadOnly;
  final Color? backgroundColor;
  final Color? unFocusBorderColor;

  /// 该特性必须使用ColoredTextController,如果controller为null，则默认使用ColoredTextController
  /// 显示字数统计的最小行数，当输入的字符占用的行数大于或等于showCounterMinLines时，显示字数统计
  /// 默认为0行，即当设置maxLength时，显示字数统计(autoShowCounter时，需要输入字符后显示)
  /// 注：disableLenghtText=true时，不显示字数统计
  final int showCounterMinLines;

  /// 当 maxLengthEnforcement 设置为 MaxLengthEnforcement.none 时，允许超过最大字符限制继续输入
  /// 当 maxLengthEnforcement 设置为 MaxLengthEnforcement.enforced 时，不允许超过最大字符限制
  /// 当 maxLengthEnforcement 设置为 MaxLengthEnforcement.truncateAfterCompositionEnds 时，在输入法组合输入结束后才进行截断
  final MaxLengthEnforcement? maxLengthEnforcement;

  /// 是否自动显示剩余字数，当未输入时则不显示，如果disableLenghtText=true，即使设置了autoShowCounter=true，也不会显示
  /// maxLength=null时，不会显示剩余字数
  final bool autoShowCounter;

  /// 该特性必须使用ColoredTextController,且maxLength>0
  /// 是否显示超出最大长度时的字数统计(-n)，默认false
  final bool showExceededCounter;

  /// 初始化文本
  final String? initText;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final bool? autofocus;

  /// 边框 默认无
  final BorderSide? borderSide;

  /// {@macro flutter.widgets.editableText.onEditingComplete}
  final VoidCallback? onEditingComplete;

  /// 输入完成，提交数据
  /// {@macro flutter.widgets.editableText.onSubmitted}
  ///
  /// See also:
  ///
  ///  * [TextInputAction.next] and [TextInputAction.previous], which
  ///    automatically shift the focus to the next/previous focusable item when
  ///    the user is done editing.
  final ValueChanged<String>? onSubmitted;

  /// 键盘类型
  final TextInputType? keyboardType;

  /// 键盘"完成"按钮类型（注：不同平台支持的类型不同）
  /// {@template flutter.widgets.TextField.textInputAction}
  /// The type of action button to use for the keyboard.
  ///
  /// Defaults to [TextInputAction.newline] if [keyboardType] is
  /// [TextInputType.multiline] and [TextInputAction.done] otherwise.
  /// {@endtemplate}
  final TextInputAction? textInputAction;

  /// An icon that appears before the [prefix] or [prefixText] and before
  /// the editable part of the text field, within the decoration's container.
  ///
  /// The size and color of the prefix icon is configured automatically using an
  /// [IconTheme] and therefore does not need to be explicitly given in the
  /// icon widget.
  ///
  /// The prefix icon is constrained with a minimum size of 48px by 48px, but
  /// can be expanded beyond that. Anything larger than 24px will require
  /// additional padding to ensure it matches the Material Design spec of 12px
  /// padding between the left edge of the input and leading edge of the prefix
  /// icon. The following snippet shows how to pad the leading edge of the
  /// prefix icon:
  ///
  /// ```dart
  /// prefixIcon: Padding(
  ///   padding: const EdgeInsetsDirectional.only(start: 12.0),
  ///   child: _myIcon, // _myIcon is a 48px-wide widget.
  /// )
  /// ```
  ///
  /// {@macro flutter.material.input_decorator.container_description}
  ///
  /// The prefix icon alignment can be changed using [Align] with a fixed `widthFactor` and
  /// `heightFactor`.
  ///
  /// {@tool dartpad}
  /// This example shows how the prefix icon alignment can be changed using [Align] with
  /// a fixed `widthFactor` and `heightFactor`.
  ///
  /// ** See code in examples/api/lib/material/input_decorator/input_decoration.prefix_icon.0.dart **
  /// {@end-tool}
  ///
  /// See also:
  ///
  ///  * [Icon] and [ImageIcon], which are typically used to show icons.
  ///  * [prefix] and [prefixText], which are other ways to show content
  ///    before the text field (but after the icon).
  ///  * [suffixIcon], which is the same but on the trailing edge.
  ///  * [Align] A widget that aligns its child within itself and optionally
  ///    sizes itself based on the child's size.
  final Widget? prefixIcon;

  /// An icon that appears after the editable part of the text field and
  /// after the [suffix] or [suffixText], within the decoration's container.
  ///
  /// The size and color of the suffix icon is configured automatically using an
  /// [IconTheme] and therefore does not need to be explicitly given in the
  /// icon widget.
  ///
  /// The suffix icon is constrained with a minimum size of 48px by 48px, but
  /// can be expanded beyond that. Anything larger than 24px will require
  /// additional padding to ensure it matches the Material Design spec of 12px
  /// padding between the right edge of the input and trailing edge of the
  /// prefix icon. The following snippet shows how to pad the trailing edge of
  /// the suffix icon:
  ///
  /// ```dart
  /// suffixIcon: Padding(
  ///   padding: const EdgeInsetsDirectional.only(end: 12.0),
  ///   child: _myIcon, // myIcon is a 48px-wide widget.
  /// )
  /// ```
  ///
  /// The decoration's container is the area which is filled if [filled] is
  /// true and bordered per the [border]. It's the area adjacent to
  /// [icon] and above the widgets that contain [helperText],
  /// [errorText], and [counterText].
  ///
  /// The suffix icon alignment can be changed using [Align] with a fixed `widthFactor` and
  /// `heightFactor`.
  ///
  /// {@tool dartpad}
  /// This example shows how the suffix icon alignment can be changed using [Align] with
  /// a fixed `widthFactor` and `heightFactor`.
  ///
  /// ** See code in examples/api/lib/material/input_decorator/input_decoration.suffix_icon.0.dart **
  /// {@end-tool}
  ///
  /// See also:
  ///
  ///  * [Icon] and [ImageIcon], which are typically used to show icons.
  ///  * [suffix] and [suffixText], which are other ways to show content
  ///    after the text field (but before the icon).
  ///  * [prefixIcon], which is the same but on the leading edge.
  ///  * [Align] A widget that aligns its child within itself and optionally
  ///    sizes itself based on the child's size.
  final Widget? suffixIcon;

  /// The padding for the input decoration's container.
  ///
  /// {@macro flutter.material.input_decorator.container_description}
  ///
  /// By default the [contentPadding] reflects [isDense] and the type of the
  /// [border].
  ///
  /// If [isCollapsed] is true then [contentPadding] is [EdgeInsets.zero].
  ///
  /// ### Material 3 default content padding
  ///
  /// If `isOutline` property of [border] is false and if [filled] is true then
  /// [contentPadding] is `EdgeInsets.fromLTRB(12, 4, 12, 4)` when [isDense]
  /// is true and `EdgeInsets.fromLTRB(12, 8, 12, 8)` when [isDense] is false.
  ///
  /// If `isOutline` property of [border] is false and if [filled] is false then
  /// [contentPadding] is `EdgeInsets.fromLTRB(0, 4, 0, 4)` when [isDense] is
  /// true and `EdgeInsets.fromLTRB(0, 8, 0, 8)` when [isDense] is false.
  ///
  /// If `isOutline` property of [border] is true then [contentPadding] is
  /// `EdgeInsets.fromLTRB(12, 16, 12, 8)` when [isDense] is true
  /// and `EdgeInsets.fromLTRB(12, 20, 12, 12)` when [isDense] is false.
  ///
  /// ### Material 2 default content padding
  ///
  /// If `isOutline` property of [border] is false and if [filled] is true then
  /// [contentPadding] is `EdgeInsets.fromLTRB(12, 8, 12, 8)` when [isDense]
  /// is true and `EdgeInsets.fromLTRB(12, 12, 12, 12)` when [isDense] is false.
  ///
  /// If `isOutline` property of [border] is false and if [filled] is false then
  /// [contentPadding] is `EdgeInsets.fromLTRB(0, 8, 0, 8)` when [isDense] is
  /// true and `EdgeInsets.fromLTRB(0, 12, 0, 12)` when [isDense] is false.
  ///
  /// If `isOutline` property of [border] is true then [contentPadding] is
  /// `EdgeInsets.fromLTRB(12, 20, 12, 12)` when [isDense] is true
  /// and `EdgeInsets.fromLTRB(12, 24, 12, 16)` when [isDense] is false.
  final EdgeInsetsGeometry? contentPadding;

  /// 是否隐藏输入内容 例如：密码
  /// {@macro flutter.widgets.editableText.obscureText}
  final bool obscureText;

  final InputDecoration? decoration;

  /// 超出最大长度时的文本颜色，默认红色，如果设置了controller，则无效
  final Color? exceededColor;

  /// 字数统计的文本样式，默认使用style的样式，但字体大小减2，颜色为hintMini的颜色
  final TextStyle? counterStyle;

  /// 当开启了showExceededCounter时，
  /// 当字数超出最大限制，显示的-n的文本颜色，样式跟counterStyle一致，但颜色为exceededCounterColor
  /// 默认跟exceededColor一致
  final Color? exceededCounterColor;

  /// 是否显示清除按钮，当有文字时显示，无文字时隐藏
  final bool showClearButton;

  /// 清除按钮的图标，默认为Icons.clear
  final Widget? clearIcon;

  /// 清除按钮的点击回调，默认为清空输入框
  final VoidCallback? onClear;

  /// 是否总是显示前缀图标，默认为false: 当有文字或焦点时才显示
  final bool alwaysShowPrefixIcon;

  /// 边框圆角，默认为8
  final double? borderRadius;

  @override
  State<StatefulWidget> createState() => _AppTextField();

  /// 3-20个字符，并且只能输入数字、字母，下划线，空格
  factory AppTextField.createNickNameInput({
    String? hintText,
    TextEditingController? controller,
    Function(String text)? onChanged,
    int? maxLength = 20,
    FocusNode? focusNode,
    String? initText,
    BorderSide? borderSide,
  }) {
    return AppTextField(
      hintText: hintText,
      controller: controller,
      onChanged: onChanged,
      maxLength: maxLength,
      focusNode: focusNode,
      inputFormatters: [TexInputtFormatLimit.getNicknameFormatter()],
      initText: initText,
      borderSide: borderSide,
    );
  }

  factory AppTextField.createHostInput({
    String? hintText,
    TextEditingController? controller,
    Function(String text)? onChanged,
    int? maxLength,
    String? labelText,
    FocusNode? focusNode,
    String? initText,
    BorderSide? borderSide,
  }) {
    return AppTextField(
      hintText: hintText,
      controller: controller,
      onChanged: onChanged,
      maxLength: maxLength,
      labelText: labelText,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [TexInputtFormatLimit.getNumDotOnly()],
      initText: initText,
      borderSide: borderSide,
    );
  }

  factory AppTextField.createPortInput({
    String? hintText,
    TextEditingController? controller,
    Function(String text)? onChanged,
    int? maxLength,
    String? labelText,
    FocusNode? focusNode,
    String? initText,
    BorderSide? borderSide,
  }) {
    return AppTextField(
      hintText: hintText,
      controller: controller,
      onChanged: onChanged,
      maxLength: maxLength,
      labelText: labelText,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      inputFormatters: [TexInputtFormatLimit.getNumOnly()],
      initText: initText,
      borderSide: borderSide,
    );
  }

  factory AppTextField.createNumberInput({
    String? hintText,
    TextEditingController? controller,
    Function(String text)? onChanged,
    int? maxLength,
    String? labelText,
    FocusNode? focusNode,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool obscureText = false,
    String? initText,
    BorderSide? borderSide,
    TextStyle? style,
    TextStyle? hintStyle,
    bool? autofocus,
  }) {
    return AppTextField(
      autofocus: autofocus,
      style: style,
      hintStyle: hintStyle,
      hintText: hintText,
      controller: controller,
      onChanged: onChanged,
      maxLength: maxLength,
      labelText: labelText,
      focusNode: focusNode,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      keyboardType: const TextInputType.numberWithOptions(),
      inputFormatters: [TexInputtFormatLimit.getNumOnly()],
      obscureText: obscureText,
      initText: initText,
      borderSide: borderSide,
    );
  }
}

class _AppTextField extends State<AppTextField> {
  AppTheme themeController() {
    return AppTheme.instance; // Get.find<ThemeController>();
  }

  late TextEditingController controller;
  int _characterCount = 0;
  bool _isNewCreatedController = false;
  late FocusNode focusNode;
  bool _isNewCreatedFocusNode = false;
  // late StreamSubscription<bool>? _keyboardListener;
  late Color _fillColor;

  @override
  void initState() {
    super.initState();
    _fillColor = widget.backgroundColor ?? themeController().pageBgColor;
    _isNewCreatedController = widget.controller == null;

    if (widget.maxLength != null && widget.controller == null) {
      controller = ColoredTextController(
        text: widget.initText,
        maxLength: widget.maxLength!,
        exceededColor: widget.exceededColor ?? Colors.red,
      );
    } else {
      controller = widget.controller ??
          ColoredTextController(maxLength: widget.maxLength);
      if (widget.initText != null) {
        controller.text = widget.initText!;
      }
    }

    controller.addListener(_onTextChanged);
    _characterCount = controller.text.length;
    _isNewCreatedFocusNode = widget.focusNode == null;
    focusNode = widget.focusNode ?? FocusNode();
    focusNode.addListener(_focusNodeListener);
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   _keyboardListener =
    //       KeyboardVisibilityController().onChange.listen((bool visible) {
    //     if (!visible) {
    //       setState(() {
    //         if (focusNode.hasFocus) {
    //           focusNode.unfocus();
    //         }
    //       });
    //     }
    //   });
    // });
  }

  void _focusNodeListener() {
    setState(() {});
  }

  void _onTextChanged() {
    if (widget.maxLength != null) {
      setState(() {
        _characterCount = controller.text.length;
      });
    }
  }

  /// 构建后缀图标，包括清除按钮和用户自定义的suffixIcon
  Widget? _buildSuffixIcon() {
    List<Widget> icons = [];

    // 如果启用了清除按钮且有文字，显示清除按钮
    if (widget.showClearButton && controller.text.isNotEmpty) {
      icons.add(
        GestureDetector(
          onTap: () {
            if (widget.onClear != null) {
              widget.onClear!();
            } else {
              controller.clear();
            }
          },
          child: widget.clearIcon ??
              Container(
                width: 24,
                height: 24,
                color: Colors.transparent,
                alignment: Alignment.center,
                child: Icon(
                  Icons.close,
                  size: 24,
                ),
              ),
        ),
      );
    }

    // 添加用户自定义的suffixIcon
    if (widget.suffixIcon != null) {
      icons.add(widget.suffixIcon!);
    }

    if (icons.isEmpty) {
      return null;
    } else if (icons.length == 1) {
      return icons.first;
    } else {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: icons,
      );
    }
  }

  @override
  void dispose() {
    // _keyboardListener?.cancel();
    controller.removeListener(_onTextChanged);
    if (_isNewCreatedController) {
      controller.dispose();
    }
    focusNode.removeListener(_focusNodeListener);
    if (_isNewCreatedFocusNode) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget input = TextField(
      autofocus: widget.autofocus ?? false,
      style: widget.style ?? AppTextTheme.textStyle.body,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      maxLengthEnforcement: widget.maxLengthEnforcement,
      enabled: widget.enabled,
      controller: controller,
      focusNode: focusNode,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      obscureText: widget.obscureText,
      onChanged: (value) {
        if (widget.onChanged != null) {
          widget.onChanged!(value);
        }
      },
      readOnly: widget.isReadOnly,
      onEditingComplete: widget.onEditingComplete,
      onSubmitted: widget.onSubmitted,
      decoration: widget.decoration ??
          InputDecoration(
              contentPadding: widget.contentPadding,
              isDense: true,
              hintText: widget.hintText,
              hintStyle: widget.hintStyle ?? AppTextTheme.textStyle.hint,
              labelText: widget.labelText,
              labelStyle: focusNode.hasFocus
                  ? AppTextTheme.textStyle.hint.copyWith(
                      color: themeController().primaryColor,
                      background: Paint()
                        ..color = themeController().pageBgColor,
                    )
                  : AppTextTheme.textStyle.hint.copyWith(
                      color: AppTextTheme.hintColor,
                      background: Paint()..color = Colors.transparent,
                    ),
              prefixIcon: (focusNode.hasFocus ||
                      controller.text.isNotEmpty ||
                      widget.alwaysShowPrefixIcon)
                  ? widget.prefixIcon
                  : null,
              suffixIcon: _buildSuffixIcon(),
              focusColor: themeController().primaryColor,
              // suffixText: widget.maxLength != null
              //     ? '$_characterCount/${widget.maxLength}'
              //     : '',
              // suffixText: '',  // 设置''后会有1.8px高度的超出范围 20250226(iPhoneSe we, 提交评价页)
              counterText: '',
              border: OutlineInputBorder(
                  borderSide: widget.borderSide ?? BorderSide.none,
                  borderRadius:
                      BorderRadius.circular(widget.borderRadius ?? 8)),

              // 启用状态的边框
              enabledBorder: OutlineInputBorder(
                borderSide: widget.borderSide ??
                    BorderSide(
                        color: widget.height == null
                            ? AppTextTheme.hintColor
                            : Colors.transparent,
                        width: 1.0),
                borderRadius: BorderRadius.circular(widget.borderRadius ?? 8),
              ),
              // fillColor: _fillColor,
              // filled: true,
              // 有焦点时边框
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(widget.borderRadius ?? 8),
                  borderSide: BorderSide(
                      color: widget.height == null
                          ? themeController().primaryColor
                          : Colors.transparent))),
      inputFormatters: widget.inputFormatters,
    );

    String counterText = widget.maxLength != null && !widget.disableLenghtText
        ? '$_characterCount/${widget.maxLength}'
        : '';

    if (widget.autoShowCounter &&
        _characterCount == 0 &&
        counterText.isNotEmpty) {
      counterText = '';
    }

    if (counterText.isNotEmpty &&
        controller is ColoredTextController &&
        widget.showCounterMinLines >= 0) {
      int textLines = (controller as ColoredTextController).getTextLines();
      if (textLines >= widget.showCounterMinLines) {
        counterText = '$_characterCount/${widget.maxLength}';
      } else {
        counterText = '';
      }
    }

    var counterStyle = widget.counterStyle ??
        // 默认使用style的样式，但字体大小减2，颜色为hintMini的颜色
        (widget.style != null
            ? widget.style!.copyWith(
                fontSize: (widget.style?.fontSize ?? 2) - 2,
                color: AppTextTheme.hintColor)
            : AppTextTheme.textStyle.hint);

    if (widget.showExceededCounter && controller is ColoredTextController) {
      int exceededLength = (controller as ColoredTextController).exceededLength;
      if (exceededLength < 0) {
        counterText = '$exceededLength';
        if (widget.exceededCounterColor != null) {
          counterStyle = counterStyle.setColor(widget.exceededCounterColor);
        }
      }
    }

    Widget counterWidget = Visibility(
      visible: counterText.isNotEmpty,
      child: Text(counterText, style: counterStyle),
    );

    if (widget.height == null) {
      input = Stack(
        children: [
          input,
          Positioned(bottom: 4, right: 4, child: counterWidget),
        ],
      );

      return input;
    } else {
      input = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: input),
          Container(
              height: double.infinity,
              alignment: Alignment.bottomRight,
              child: GestureDetector(
                onTap: () {
                  // 如果输入框没有焦点，则请求焦点；区分点击输入框空白和输入字符数提示区域
                  if (!focusNode.hasFocus) {
                    focusNode.requestFocus();
                    // 将光标移动到文本末尾
                    controller.selection =
                        TextSelection.collapsed(offset: controller.text.length);
                  }
                },
                child: counterWidget,
              )),
          SizedBox(width: 4),
        ],
      );

      input = Container(
        alignment: Alignment.topCenter,
        // color: Colors.red,
        decoration: BoxDecoration(
          color: _fillColor,
          borderRadius: BorderRadius.circular(widget.borderRadius ?? 8),
          border: Border.all(
              color: focusNode.hasFocus
                  ? themeController().primaryColor
                  : widget.unFocusBorderColor ??
                      themeController().primaryColor.withValues(alpha: 0.2)),
        ),
        height: widget.height,
        child: input,
      );

      return GestureDetector(
          onTap: () {
            // 只要点击了输入空白区域（不包括输入字符数提示区域，和原生输入框的输入区域）则请求焦点；
            // 区分点击输入框空白和输入字符数提示区域
            focusNode.requestFocus();
            // 将光标移动到文本末尾
            controller.selection =
                TextSelection.collapsed(offset: controller.text.length);
          },
          child: input);
    }
  }
}

class TexInputtFormatLimit {
  static FilteringTextInputFormatter getEnglishNumSpaceOnly() {
    return FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 ]'));
  }

  static FilteringTextInputFormatter getNicknameFormatter() {
    return FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 _]'));
  }

  static FilteringTextInputFormatter getNumOnly() {
    return FilteringTextInputFormatter.allow(RegExp(r'[0-9]'));
  }

  static FilteringTextInputFormatter getNumDotOnly() {
    return FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));
  }

  static FilteringTextInputFormatter getPWDFormatter() {
    return FilteringTextInputFormatter.allow(
        RegExp(r'[a-zA-Z0-9!@#$%^&*()_+\-=\[\]{};:,.<>?]'));
  }
}
