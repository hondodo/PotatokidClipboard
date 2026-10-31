import 'package:flutter/material.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';

/// 用于在输入框中显示超出最大长度时的文本颜色
/// 使用方式：
/// 1. 在输入框中使用 ColoredTextController 代替 TextEditingController
/// 2. TextField 的 maxLengthEnforcement 设置为 MaxLengthEnforcement.none
class ColoredTextController extends TextEditingController {
  int? maxLength;
  Color exceededColor;
  TextStyle? _textStyle;
  BuildContext? _context;

  // /// 输入框中输入的字符长度，但不计算输入法时输入的文字（如iOS 中文输入法）
  // int _textLength = 0;

  int get exceededLength {
    if ((maxLength ?? 0) <= 0) return 0;
    return maxLength! - text.length;
  }

  // int get inputLength => _textLength;

  ColoredTextController({
    super.text = '',
    this.maxLength,
    this.exceededColor = Colors.red,
  });

  /// 计算文本所需的行数
  int getTextLines() {
    try {
      if (_context == null || _textStyle == null) return 1;

      // 获取当前可用宽度
      final RenderBox? renderBox = _context!.findRenderObject() as RenderBox?;
      if (renderBox == null) return 1;

      final maxWidth = renderBox.size.width;

      final TextPainter textPainter = TextPainter(
        text: TextSpan(text: text, style: _textStyle),
        maxLines: null,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);

      return textPainter.computeLineMetrics().length;
    } catch (e) {
      Log.e('getTextLines error: $e');
      return 1;
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // 保存 context 用于计算行数
    _context = context;
    _textStyle = style;
    int calcMaxLength = maxLength ?? 0;
    if (calcMaxLength <= 0) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    if (!value.composing.isValid || !withComposing) {
      final text = value.text;
      final spans = <TextSpan>[];

      if (text.length <= calcMaxLength) {
        spans.add(TextSpan(
          text: text,
          style: style,
        ));
      } else {
        spans.add(TextSpan(
          text: text.substring(0, calcMaxLength),
          style: style,
        ));
        spans.add(TextSpan(
          text: text.substring(calcMaxLength),
          style: style?.copyWith(color: exceededColor),
        ));
      }

      return TextSpan(children: spans);
    }

    return TextSpan(
      text: value.text,
      style: style,
    );
  }
}
