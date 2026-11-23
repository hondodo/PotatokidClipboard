import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';

/// 注册表本地缓存：记录最近一次成功拉取的房间 / 设备 / 实体归属。
///
/// 只作为网络失败时的兜底，不参与正常数据流：
/// - 拉取成功 → 覆盖缓存；
/// - 拉取失败 → 返回缓存（无缓存时由调用方降级为空注册表）。
abstract class RegistryCache {
  /// 读取当前 HA 地址对应的缓存；无缓存 / 损坏 / 地址不匹配时返回 null。
  HaRegistry? read();

  /// 覆盖写入缓存；实现侧应自行吞掉存储错误，不能影响主流程。
  Future<void> write(HaRegistry registry);
}
