import 'package:pscreen_screen/core/media/sleep_timer_controller.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/channel_name_normalizer.dart';

/// 音量控制抽象（生产 PlatformChannelService implements 它；测试 Fake）。
abstract class VolumeControl {
  Future<void> volumeUp();
  Future<void> volumeDown();
  Future<void> toggleMute();
}

/// 宿主导航抽象（生产由各宿主实现：中控屏走 GoRouter，电视端走 Tab 分支）。
///
/// [page] 取值：`home`（主页）/ `live`（直播）/ `weather`（天气）/
/// `settings`（设置）/ `screensaver`（进入或退出屏保，由宿主决定切换语义）。
abstract class HostNavigator {
  Future<bool> open(String page);
}

/// 直播窗口形态控制（仅中控屏实现；电视端直播常驻底层，没有应用内悬浮小窗）。
abstract class LiveStageControl {
  /// 全屏直播 → 应用内悬浮小窗；非全屏时幂等（不生效）。
  void toFloating();
}

/// 命令执行器：音量/切台/导航/定时关闭/直播悬浮（text 命令由 Router 直接走浮层，不进这里）。
class MessageCommandExecutor {
  MessageCommandExecutor({
    required this.volume,
    required this.liveChannel,
    required this.channelInfo,
    this.navigator,
    this.liveStage,
  });

  final VolumeControl volume;
  final LiveChannelController liveChannel;
  final ChannelInfoProvider channelInfo;

  /// 宿主导航能力；未注册时可空（命令按未支持处理）。
  final HostNavigator? navigator;

  /// 直播悬浮能力；未注册时可空（电视端命令按未支持处理）。
  final LiveStageControl? liveStage;

  /// 支持的导航页集合。
  static const Set<String> _navPages = <String>{
    'home',
    'live',
    'weather',
    'settings',
    'screensaver',
  };

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
      case 'nav':
        return _nav(args);
      case 'sleep_timer':
        return _sleepTimer(args);
      case 'live_float':
        return _liveFloat();
      default:
        return false;
    }
  }

  /// 直播悬浮：全屏 → 应用内悬浮小窗。
  ///
  /// 仅中控屏注册了 [liveStage]；电视端未注册时返回 false，由 Router 记日志忽略。
  bool _liveFloat() {
    final LiveStageControl? stage = liveStage;
    if (stage == null) return false;
    stage.toFloating();
    return true;
  }

  /// 定时关闭：`minutes` ≤ 0 或缺失 = 取消；否则开始倒计时。
  ///
  /// 到点动作由宿主注入的 [SleepTimerController.onExpire] 决定：
  /// 中控屏关闭直播回主页，电视端默认退出应用。
  ///
  /// 复用本机「我的/设置」页同一个 [SleepTimerController]，
  /// 因此遥控设置的时长与本地 UI 显示的剩余时间始终一致。
  bool _sleepTimer(Map<String, dynamic>? args) {
    final dynamic raw = args?['minutes'];
    final int minutes = raw is num ? raw.toInt() : 0;
    SleepTimerController.instance.setMinutes(minutes <= 0 ? null : minutes);
    return true;
  }

  bool _nav(Map<String, dynamic>? args) {
    final HostNavigator? host = navigator;
    if (host == null || args == null) return false;
    final dynamic rawPage = args['page'];
    if (rawPage is! String) return false;
    final String page = rawPage.trim();
    if (!_navPages.contains(page)) return false;
    // 导航是异步的（路由跳转/切 Tab），命令本身已受理。
    host.open(page);
    return true;
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
