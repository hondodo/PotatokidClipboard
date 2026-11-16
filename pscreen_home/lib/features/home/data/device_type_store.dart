import 'package:pscreen_home/core/server/server_api.dart';
import 'package:pscreen_home/features/home/domain/models/device_type_dictionary.dart';

/// 设备类型字典的运行时持有者：内置 fallback 立即可用，后台异步用服务端规则覆盖。
///
/// 设计取舍：
/// - 构造即用 fallback，保证首页文案/标签不依赖网络；
/// - [refresh] 走公开接口，失败静默保留 fallback（fail-open，不阻塞启动）；
/// - 显式分类映射（HA device_id → deviceType）更新后，下一帧 Summary 即生效。
class DeviceTypeStore {
  DeviceTypeStore(this._api);

  final ServerApiClient _api;

  DeviceTypeDictionary _dictionary = DeviceTypeDictionary();
  DeviceTypeDictionary get dictionary => _dictionary;

  DateTime? lastUpdated;

  /// 从服务端刷新字典；返回是否成功。任何失败都保留现有（fallback）字典。
  Future<bool> refresh() async {
    if (!_api.isConfigured) return false;
    try {
      final Map<String, dynamic> data = await _api.fetchDeviceTypes();
      _dictionary = DeviceTypeDictionary.fromApiJson(data);
      DeviceTypeDictionary.active = _dictionary; // 各 Summary tryBuild 立即可见
      lastUpdated = DateTime.now();
      return true;
    } catch (_) {
      return false;
    }
  }
}
