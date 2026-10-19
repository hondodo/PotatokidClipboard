import 'package:potatokid_screen/features/iptv/application/channel_info_provider.dart';
import 'package:potatokid_screen/features/iptv/application/live_channel_controller.dart';
import 'package:potatokid_screen/features/iptv/domain/channel_name_normalizer.dart';

/// 音量控制抽象（生产 PlatformChannelService implements 它；测试 Fake）。
abstract class VolumeControl {
  Future<void> volumeUp();
  Future<void> volumeDown();
  Future<void> toggleMute();
}

/// 命令执行器：音量/切台（text 命令由 Router 直接走浮层，不进这里）。
class MessageCommandExecutor {
  MessageCommandExecutor({
    required this.volume,
    required this.liveChannel,
    required this.channelInfo,
  });

  final VolumeControl volume;
  final LiveChannelController liveChannel;
  final ChannelInfoProvider channelInfo;

  /// 执行命令；未知命令名返回 false（调用方记日志）。
  bool execute(String name, Map<String, dynamic>? args) {
    switch (name) {
      case 'volume_up':
        volume.volumeUp();
        return true;
      case 'volume_down':
        volume.volumeDown();
        return true;
      case 'mute':
        volume.toggleMute();
        return true;
      case 'channel':
        return _channel(args);
      default:
        return false;
    }
  }

  bool _channel(Map<String, dynamic>? args) {
    if (args == null) return false;
    final dynamic byName = args['name'];
    if (byName is String && byName.isNotEmpty) {
      final int idx = channelInfo.channels.indexWhere(
        (c) => normalizeChannelName(c.name) == normalizeChannelName(byName),
      );
      if (idx < 0) return false;
      liveChannel.select(idx);
      return true;
    }
    final dynamic byIndex = args['index'];
    if (byIndex is int) {
      liveChannel.select(byIndex);
      return true;
    }
    return false;
  }
}
