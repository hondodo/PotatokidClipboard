import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// IPTV 仓库接口：定义「获取直播频道列表」能力。
abstract class IptvRepository {
  /// 拉取远程接口频道列表（两跳地址）；失败抛出网络异常。
  Future<List<IptvChannel>> fetchRemoteChannels();

  /// 读取包内默认频道列表（`assets/datas/guovin-api.m3u`）。
  /// 仅在「接口失败且无持久化缓存」时作为兜底使用。
  Future<List<IptvChannel>> loadDefaultRemoteChannels();

  /// 合成最终播放列表：`collect.m3u` 置顶 + [remote] + `audio.m3u`（广播电台）收尾，
/// 再按 `TV_NAME_ORDER` 提权、剔除 `TV_NAME_HIDE`，同名频道合并源。
///
/// 三部分的可热更新数据文件都由 DataFiles 提供，展示列表每次都由本方法动态拼接；
/// 持久化缓存只保存接口数据。
  Future<List<IptvChannel>> buildPlaylist(List<IptvChannel> remote);
}