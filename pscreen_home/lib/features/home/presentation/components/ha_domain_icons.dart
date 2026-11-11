import 'package:flutter/material.dart';

/// HA domain → 图标映射（网格 / 详情页统一使用）。
///
/// 覆盖全部常见 domain；未收录的用设备图标兜底。
class HaDomainIcons {
  const HaDomainIcons._();

  static const Map<String, IconData> _icons = <String, IconData>{
    // 可开关类
    'light': Icons.lightbulb_rounded,
    'switch': Icons.toggle_on_rounded,
    'fan': Icons.air_rounded,
    // 数据类
    'sensor': Icons.sensors_rounded,
    'binary_sensor': Icons.motion_photos_on_rounded,
    'number': Icons.numbers_rounded,
    'text': Icons.text_fields_rounded,
    'select': Icons.tune_rounded,
    'calendar': Icons.calendar_month_rounded,
    'device_tracker': Icons.location_on_rounded,
    'person': Icons.person_rounded,
    'zone': Icons.place_rounded,
    'sun': Icons.wb_sunny_rounded,
    'weather': Icons.cloud_rounded,
    // 动作类（暂不支持交互，仅展示）
    'button': Icons.smart_button_rounded,
    'event': Icons.bolt_rounded,
    'notify': Icons.notifications_rounded,
    'script': Icons.code_rounded,
    'automation': Icons.auto_awesome_motion_rounded,
    'scene': Icons.theaters_rounded,
    'remote': Icons.settings_remote_rounded,
    'tts': Icons.record_voice_over_rounded,
    'conversation': Icons.chat_bubble_rounded,
    'todo': Icons.checklist_rounded,
    'update': Icons.system_update_rounded,
    // 复杂控制域（暂不支持交互，仅展示）
    'media_player': Icons.tv_rounded,
    'climate': Icons.thermostat_rounded,
    'cover': Icons.blinds_rounded,
    'water_heater': Icons.hot_tub_rounded,
    'camera': Icons.videocam_rounded,
    'vacuum': Icons.cleaning_services_rounded,
    'lock': Icons.lock_rounded,
    'alarm_control_panel': Icons.security_rounded,
    'humidifier': Icons.water_drop_rounded,
    'water': Icons.water_rounded,
    'gas': Icons.local_gas_station_rounded,
    'energy': Icons.bolt_rounded,
    'button_play': Icons.play_arrow_rounded,
  };

  /// domain 对应图标（未收录时用设备图标兜底）
  static IconData of(String domain) =>
      _icons[domain] ?? Icons.devices_other_rounded;
}

/// HA domain → 配色映射（首页卡片按类型着色，老人扫一眼即可区分）。
///
/// 颜色语义：
/// - 灯：暖黄；开关 / 插座：绿；风扇：青；空调 / 油烟机：青蓝；
/// - 热水器 / 电热水瓶：橙红；窗帘：紫；摄像头 / 门锁：红；
/// - 净水 / 卫浴：蓝绿；未收录兜底蓝灰。
class HaDomainColors {
  const HaDomainColors._();

  static const Map<String, Color> _colors = <String, Color>{
    // 灯
    'light': Color(0xFFFFB74D),
    // 开关 / 插座
    'switch': Color(0xFF66BB6A),
    'switch_status': Color(0xFF66BB6A),
    'input_boolean': Color(0xFF66BB6A),
    // 风扇
    'fan': Color(0xFF4DD0C4),
    // 空调 / 油烟机
    'climate': Color(0xFF5C9CE6),
    'range_hood': Color(0xFF5C9CE6),
    // 热水器 / 电热水瓶
    'water_heater': Color(0xFFFF7043),
    'kettle': Color(0xFFFF7043),
    // 窗帘 / 遮阳
    'cover': Color(0xFFAB47BC),
    // 摄像头 / 门锁
    'camera': Color(0xFFEF5350),
    'lock': Color(0xFFEF5350),
    'alarm_control_panel': Color(0xFFEF5350),
    // 净水 / 卫浴
    'water_purifier': Color(0xFF26A69A),
    'humidifier': Color(0xFF26A69A),
    // 投影 / 媒体
    'media_player': Color(0xFF7E8AA2),
    // 洗衣机等白色家电兜底蓝灰
  };

  /// domain 对应强调色（未收录时用蓝灰兜底）
  static Color of(String domain) =>
      _colors[domain] ?? const Color(0xFF78909C);

  /// 取适合卡片强调用的颜色：开启态返回原色，关闭态降透明度。
  static Color soft(Color color, {required bool on}) =>
      on ? color : color.withValues(alpha: 0.55);
}
