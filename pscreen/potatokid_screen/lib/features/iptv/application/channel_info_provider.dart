import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// 频道名查询（非 UI 服务用：上报/命令解析），真值由 LivePlayerWidget 供给。
class ChannelInfoProvider {
  ChannelInfoProvider._();

  /// 全局单例。
  static final ChannelInfoProvider instance = ChannelInfoProvider._();

  /// 当前生效的频道列表。
  List<IptvChannel> channels = <IptvChannel>[];

  /// 供给列表（频道加载/刷新时调用）。
  void setChannels(List<IptvChannel> value) {
    channels = value;
  }

  /// 序号对应的频道名；越界返回 null。
  String? nameAt(int index) {
    if (index < 0 || index >= channels.length) return null;
    return channels[index].name;
  }
}
