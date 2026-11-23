/// 空调相关的中文文案与数值格式化。
library;

/// 温度展示：整数不显示小数位，半度保留一位。
String formatTemperature(double? value) {
  if (value == null) return '--';
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

/// HA hvac 模式 → 中文。
String hvacModeLabel(String mode) => switch (mode) {
      'cool' => '制冷',
      'heat' => '制热',
      'dry' => '除湿',
      'fan_only' => '送风',
      'auto' => '自动',
      'off' => '关闭',
      _ => mode,
    };

/// 摆风模式 → 中文（未知值原样展示）。
String swingModeLabel(String mode) => switch (mode) {
      'off' => '关闭',
      'vertical' => '上下',
      'horizontal' => '左右',
      'both' => '上下+左右',
      _ => mode,
    };
