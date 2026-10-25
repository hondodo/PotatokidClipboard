import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 首页实体状态的本地快照。
///
/// 只用于冷启动 / 断线时先展示上一次的设备卡片，不参与正常数据流：
/// - 全量加载成功 → 覆盖快照；
/// - 启动时读取快照 → 立即渲染卡片，连接就绪后由 [LoadHome] 校准。
abstract class HomeStateCache {
  /// 读取当前 HA 地址对应的快照；无快照 / 损坏 / 地址不匹配时返回 null。
  Future<List<HaEntityStateModel>?> read();

  /// 覆盖写入快照；实现侧应自行吞掉存储错误，不能影响主流程。
  Future<void> write(List<HaEntityStateModel> states);
}
