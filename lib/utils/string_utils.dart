import 'package:flutter/material.dart';

class StringUtils {
  static double getTextWidth(String text, TextStyle style) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    return textPainter.size.width;
  }
}
