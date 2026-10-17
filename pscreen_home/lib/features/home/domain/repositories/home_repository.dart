import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';
import 'package:pscreen_home/features/home/domain/models/water_usage_record.dart';

/// 主页数据仓库（抽象接口，只定义方法签名）
abstract class HomeRepository {
  /// 拉取全部实体状态（get_states）
  Future<List<HaEntityStateModel>> fetchStates();

  /// 拉取注册表快照（房间 / 设备 / 实体归属），用于按房间分组展示。
  /// 实现侧失败时降级为空注册表，不阻断主页加载。
  Future<HaRegistry> fetchRegistry();

  /// 实时实体状态变更流（state_changed 事件的 new_state）
  Stream<HaEntityStateModel> watchStateChanges();

  /// 控制实体开关（light/switch 域的 turn_on / turn_off；
  /// climate 域同样走 turn_on / turn_off，保留空调上次模式）
  Future<void> setEntityPower({
    required String entityId,
    required bool turnOn,
  });

  /// 设置灯光亮度（percent：0-100，实现侧换算为 HA 的 0-255）
  Future<void> setLightBrightness({
    required String entityId,
    required int percent,
  });

  /// 设置灯光色温（开尔文）
  Future<void> setLightColorTemperature({
    required String entityId,
    required int kelvin,
  });

  /// 选择灯光效果 / 情景模式（来自 effect_list）
  Future<void> setLightEffect({
    required String entityId,
    required String effect,
  });

  /// 设置空调目标温度
  Future<void> setClimateTemperature({
    required String entityId,
    required double temperature,
  });

  /// 设置空调运行模式（cool / heat / dry / fan_only / auto / off）
  Future<void> setClimateHvacMode({
    required String entityId,
    required String mode,
  });

  /// 设置空调风速档位
  Future<void> setClimateFanMode({
    required String entityId,
    required String mode,
  });

  /// 设置空调摆风模式
  Future<void> setClimateSwingMode({
    required String entityId,
    required String mode,
  });

  /// 按下 button 实体（洗衣机启动 / 暂停 / 停止等）
  Future<void> pressButton({required String entityId});

  /// 选择 select 实体的选项（洗衣机模式、水温、转速等）
  Future<void> selectOption({
    required String entityId,
    required String option,
  });

  /// 设置热水器目标温度
  Future<void> setWaterHeaterTemperature({
    required String entityId,
    required double temperature,
  });

  /// 切换热水器洗浴模式（自定义 / AI控温 / 婴童洗 …）
  Future<void> setWaterHeaterOperationMode({
    required String entityId,
    required String mode,
  });

  /// 读取热水器使用记录（按时间范围拉 event 历史）
  Future<List<WaterUsageRecord>> fetchWaterUsageRecords({
    required String entityId,
    required DateTime start,
    required DateTime end,
  });

  /// 写入 text 实体（热水器定时预热编码串）
  Future<void> setTextValue({
    required String entityId,
    required String value,
  });

  /// 设置 number 实体的数值（热水瓶目标温度 / 保温温度）
  Future<void> setNumberValue({
    required String entityId,
    required double value,
  });

  /// 触发 notify 动作实体（电热水瓶「开始加热」，message 为动作参数列表）
  Future<void> pressNotifyAction({
    required String entityId,
    required String message,
  });
}
