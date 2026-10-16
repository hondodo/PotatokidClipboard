import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 主页数据仓库（抽象接口，只定义方法签名）
abstract class HomeRepository {
  /// 拉取全部实体状态（get_states）
  Future<List<HaEntityStateModel>> fetchStates();

  /// 实时实体状态变更流（state_changed 事件的 new_state）
  Stream<HaEntityStateModel> watchStateChanges();

  /// 控制实体开关（light/switch 等域的 turn_on / turn_off）
  Future<void> setEntityPower({
    required String entityId,
    required bool turnOn,
  });
}
