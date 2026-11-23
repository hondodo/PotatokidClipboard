import 'package:flutter/material.dart';

/// 门锁状态与电量图标 / 配色。
///
/// - 已上锁：蓝色实心锁；未上锁：红色开锁；
/// - 电量：≥80% 绿色、≥50% 蓝色、≥20% 黄色、<20% 红色；
///   图标随电量档位变化。
class LockStatusIcons {
  const LockStatusIcons._();

  static const Color lockedColor = Color(0xFF64B5F6);
  static const Color unlockedColor = Color(0xFFEF5350);
  static const Color batteryHighColor = Color(0xFF66BB6A);
  static const Color batteryMediumColor = Color(0xFF64B5F6);
  static const Color batteryLowColor = Color(0xFFFFB74D);
  static const Color batteryCriticalColor = Color(0xFFEF5350);

  /// 上锁 / 开锁图标
  static IconData lockIcon(bool? locked) =>
      locked == true ? Icons.lock_rounded : Icons.lock_open_rounded;

  /// 上锁（蓝）/ 开锁（红）/ 未知（灰）
  static Color lockColor(ThemeData theme, bool? locked) {
    if (locked == null) return theme.colorScheme.outline;
    return locked ? lockedColor : unlockedColor;
  }

  /// 按电量选择电池图标
  static IconData batteryIcon(int? percent) {
    final int value = percent ?? 0;
    if (value >= 90) return Icons.battery_full_rounded;
    if (value >= 70) return Icons.battery_6_bar_rounded;
    if (value >= 50) return Icons.battery_5_bar_rounded;
    if (value >= 30) return Icons.battery_3_bar_rounded;
    if (value >= 15) return Icons.battery_1_bar_rounded;
    return Icons.battery_alert_rounded;
  }

  /// 按电量选择颜色
  static Color batteryColor(ThemeData theme, int? percent) {
    final int value = percent ?? 0;
    if (value >= 80) return batteryHighColor;
    if (value >= 50) return batteryMediumColor;
    if (value >= 20) return batteryLowColor;
    return batteryCriticalColor;
  }
}
