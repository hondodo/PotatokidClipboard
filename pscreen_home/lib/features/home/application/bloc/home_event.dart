import 'dart:async';

import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 主页状态机事件基类。
abstract class HomeEvent {
  const HomeEvent();
}

/// 加载全部实体状态（连接就绪 / 重连成功后触发）。
class LoadHome extends HomeEvent {
  const LoadHome({this.completer});

  /// 供调用方 await 事件完成。
  final Completer<bool>? completer;
}

/// 收到一条实时实体状态变更（state_changed）。
class EntityStateChanged extends HomeEvent {
  const EntityStateChanged(this.entity);

  final HaEntityStateModel entity;
}

/// 点击快捷控件切换开关（乐观更新，失败回滚）。
class ToggleEntity extends HomeEvent {
  const ToggleEntity({required this.entityId, this.completer});

  final String entityId;

  /// 供调用方 await 事件完成。
  final Completer<bool>? completer;
}

/// 选择家庭标签（homeName 为 `''` 表示「全部」）。切换家庭会清空已选房间。
class HomeSelected extends HomeEvent {
  const HomeSelected(this.homeName);

  final String homeName;
}

/// 选择房间标签（areaId 为 `''` 表示「全部」）。
class AreaSelected extends HomeEvent {
  const AreaSelected(this.areaId);

  final String areaId;
}

/// 调整灯光亮度（percent：0-100）。
class SetLightBrightness extends HomeEvent {
  const SetLightBrightness({
    required this.entityId,
    required this.percent,
    this.completer,
  });

  final String entityId;
  final int percent;
  final Completer<bool>? completer;
}

/// 调整灯光色温（开尔文）。
class SetLightColorTemperature extends HomeEvent {
  const SetLightColorTemperature({
    required this.entityId,
    required this.kelvin,
    this.completer,
  });

  final String entityId;
  final int kelvin;
  final Completer<bool>? completer;
}

/// 选择灯光效果（effect_list 中的一项）。
class SetLightEffect extends HomeEvent {
  const SetLightEffect({
    required this.entityId,
    required this.effect,
    this.completer,
  });

  final String entityId;
  final String effect;
  final Completer<bool>? completer;
}

/// 调整空调目标温度。
class SetClimateTemperature extends HomeEvent {
  const SetClimateTemperature({
    required this.entityId,
    required this.temperature,
    this.completer,
  });

  final String entityId;
  final double temperature;
  final Completer<bool>? completer;
}

/// 切换空调运行模式（cool / heat / dry / fan_only / auto / off）。
class SetClimateHvacMode extends HomeEvent {
  const SetClimateHvacMode({
    required this.entityId,
    required this.mode,
    this.completer,
  });

  final String entityId;
  final String mode;
  final Completer<bool>? completer;
}

/// 切换空调风速档位。
class SetClimateFanMode extends HomeEvent {
  const SetClimateFanMode({
    required this.entityId,
    required this.mode,
    this.completer,
  });

  final String entityId;
  final String mode;
  final Completer<bool>? completer;
}

/// 切换空调摆风模式。
class SetClimateSwingMode extends HomeEvent {
  const SetClimateSwingMode({
    required this.entityId,
    required this.mode,
    this.completer,
  });

  final String entityId;
  final String mode;
  final Completer<bool>? completer;
}

/// 按下 button 实体（洗衣机启动 / 暂停 / 停止等）。
class PressEntityButton extends HomeEvent {
  const PressEntityButton({
    required this.entityId,
    this.completer,
  });

  final String entityId;
  final Completer<bool>? completer;
}

/// 选择 select 实体的选项（洗衣机模式等）。
class SelectEntityOption extends HomeEvent {
  const SelectEntityOption({
    required this.entityId,
    required this.option,
    this.completer,
  });

  final String entityId;
  final String option;
  final Completer<bool>? completer;
}

/// 设置热水器目标温度。
class SetWaterHeaterTemperature extends HomeEvent {
  const SetWaterHeaterTemperature({
    required this.entityId,
    required this.temperature,
    this.completer,
  });

  final String entityId;
  final double temperature;
  final Completer<bool>? completer;
}

/// 切换热水器洗浴模式。
class SetWaterHeaterOperationMode extends HomeEvent {
  const SetWaterHeaterOperationMode({
    required this.entityId,
    required this.mode,
    this.completer,
  });

  final String entityId;
  final String mode;
  final Completer<bool>? completer;
}

/// 写入 text 实体（热水器定时预热编码串）。
class SetTextEntityValue extends HomeEvent {
  const SetTextEntityValue({
    required this.entityId,
    required this.value,
    this.completer,
  });

  final String entityId;
  final String value;
  final Completer<bool>? completer;
}

/// 设置 number 实体数值（热水瓶温度）。
class SetNumberEntityValue extends HomeEvent {
  const SetNumberEntityValue({
    required this.entityId,
    required this.value,
    this.completer,
  });

  final String entityId;
  final double value;
  final Completer<bool>? completer;
}

/// 触发 notify 动作实体（热水瓶开始加热）。
class PressNotifyAction extends HomeEvent {
  const PressNotifyAction({
    required this.entityId,
    this.completer,
  });

  final String entityId;
  final Completer<bool>? completer;
}

/// 清除错误提示（页面展示 SnackBar 后调用）。
class ClearHomeError extends HomeEvent {
  const ClearHomeError();
}
