import 'package:pscreen_screen/features/iptv/domain/models/final_channels.dart';

/// IPTV 仓库接口：拉取服务端合并后的最终频道列表。
abstract class IptvRepository {
  /// 拉取最终频道列表。
  ///
  /// [version] 为本地缓存版本，作为 `If-None-Match` 发往服务端：
  /// - 返回 `null` 表示 304，本地缓存仍是最新；
  /// - 返回 payload 表示拿到新版本（实现同时会写回本地缓存）；
  /// - 失败抛出网络/业务异常，由上层决定是否继续使用本地缓存。
  Future<FinalChannelsPayload?> fetchFinalChannels({String? version});
}
