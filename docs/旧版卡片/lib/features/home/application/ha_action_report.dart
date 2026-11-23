import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';
import 'package:pscreen_screen/features/msg/application/reporting_service.dart';

/// 一条 HA 操作上报。
///
/// 统一在 [HomeBloc] 的操作入口生成，避免每个卡片/详情控件重复埋点。
class HaActionReport {
  const HaActionReport({
    required this.eventId,
    required this.at,
    required this.action,
    required this.entityId,
    required this.entityName,
    required this.success,
    required this.trigger,
    this.deviceId,
    this.deviceName,
    this.areaId,
    this.areaName,
    this.value,
    this.previousValue,
    this.error,
    this.cardName,
    this.buttonId,
    this.scene,
  });

  final String eventId;
  final DateTime at;
  final String action;
  final String entityId;
  final String entityName;
  final String? deviceId;
  final String? deviceName;
  final String? areaId;
  final String? areaName;
  final Object? value;
  final Object? previousValue;
  final bool success;
  final String? error;

  /// 点击卡片进入详情时的卡片标题。
  final String? cardName;

  /// 点击按钮类实体时的按钮实体 id。
  final String? buttonId;

  final String trigger;
  final SceneSnapshot? scene;

  Map<String, Object?> toJson() => <String, Object?>{
        'eventId': eventId,
        'ts': at.millisecondsSinceEpoch,
        'action': action,
        'entityId': entityId,
        'entityName': entityName,
        if (deviceId != null && deviceId!.isNotEmpty) 'deviceId': deviceId,
        if (deviceName != null && deviceName!.isNotEmpty)
          'deviceName': deviceName,
        if (areaId != null && areaId!.isNotEmpty) 'areaId': areaId,
        if (areaName != null && areaName!.isNotEmpty) 'areaName': areaName,
        if (value != null) 'value': value,
        if (previousValue != null) 'previousValue': previousValue,
        'success': success,
        if (error != null && error!.isNotEmpty) 'error': error,
        if (cardName != null && cardName!.isNotEmpty) 'cardName': cardName,
        if (buttonId != null && buttonId!.isNotEmpty) 'buttonId': buttonId,
        'trigger': trigger,
        if (scene != null) 'scene': scene!.toJson(),
      };
}

/// HA 操作上报端口；测试可注入 Fake，生产写实时通道事件。
abstract class HaActionReporter {
  void report(HaActionReport report);
}

/// 把 HA 操作转成 `ha_action` 结构化事件。
class ReportingHaActionReporter implements HaActionReporter {
  ReportingHaActionReporter(this._reporting);

  final ReportingService _reporting;

  @override
  void report(HaActionReport report) {
    _reporting.reportEvent('ha_action', report.toJson());
  }
}
