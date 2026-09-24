import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// IPTV 仓库接口：定义「获取直播频道列表」能力。
abstract class IptvRepository {
  /// 拉取远程 m3u 列表并解析为频道列表。
  Future<List<IptvChannel>> fetchChannels();
}