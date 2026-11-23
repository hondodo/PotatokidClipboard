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
