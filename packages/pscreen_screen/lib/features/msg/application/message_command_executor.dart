import 'dart:async';

import 'package:pscreen_screen/core/media/kid_watch_timer_controller.dart';
import 'package:pscreen_screen/core/media/sleep_timer_controller.dart';
import 'package:pscreen_screen/core/parental/parental_unlock_code_controller.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/channel_number_input_controller.dart';
import 'package:pscreen_screen/features/iptv/application/home_now_playing_controller.dart';
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

/// 命令执行器：音量/切台/导航/定时关闭/直播悬浮/远程解锁（text 命令由
/// Router 直接走浮层，不进这里）。
class MessageCommandExecutor {
  MessageCommandExecutor({
    required this.volume,
    required this.liveChannel,
    required this.channelInfo,
    this.navigator,
    this.liveStage,
    this.onVolumeCommand,
  });

  final VolumeControl volume;
  final LiveChannelController liveChannel;
  final ChannelInfoProvider channelInfo;

  /// 宿主导航能力；未注册时可空（命令按未支持处理）。
  final HostNavigator? navigator;

  /// 直播悬浮能力；未注册时可空（电视端命令按未支持处理）。
  final LiveStageControl? liveStage;

  /// 音量类命令执行后的回调（上报端据此读取最新音量并刷新 state 帧）。
  final void Function()? onVolumeCommand;

  /// 支持的导航页集合。
  static const Set<String> _navPages = <String>{
    'home',
    'live',
    'weather',
    'settings',
    'screensaver',
  };

  /// 执行命令；未知命令名返回 false（调用方记日志）。
  ///
  /// [actor] 为命令发送方账号（实时通道 `from`；未知时为空串），用于
  /// `parental_unlock_ack` 回执标明「谁解锁 / 谁失败」。
  bool execute(String name, Map<String, dynamic>? args, {String actor = ''}) {
    switch (name) {
      case 'volume_up':
        volume.volumeUp();
        onVolumeCommand?.call();
        return true;
      case 'volume_down':
        volume.volumeDown();
        onVolumeCommand?.call();
        return true;
      case 'mute':
        volume.toggleMute();
        onVolumeCommand?.call();
        return true;
      case 'channel_next':
        liveChannel.next();
        return true;
      case 'channel_prev':
        liveChannel.previous();
        return true;
      case 'switch_source':
        return _switchSource(args);
      case 'channel':
        return _channel(args);
      case 'channel_digit':
        return _channelDigit(args);
      case 'channel_digit_resolve':
        return ChannelNumberInputController.instance.resolveNow();
      // 兼容兜底：家长端 UI 已无「清除」键，但保留该命令以便其它控制端
      // 或脚本主动清缓冲（与本机遥控的 2 秒自动清空并存，不影响主路径）。
      case 'channel_digit_clear':
        ChannelNumberInputController.instance.clear();
        return true;
      case 'nav':
        return _nav(args);
      case 'sleep_timer':
        return _sleepTimer(args);
      case 'live_float':
        return _liveFloat();
      case 'parental_unlock':
        return _parentalUnlock(args, actor);
      default:
        return false;
    }
  }

  /// 远程解锁：校验短码（匹配 + 60s 未过期 + 未使用过，全部满足才消费，
  /// 一次性）通过后解除锁屏。**任何 unlockMode 都允许远程解锁**（含 quiz：
  /// 家长端只有家长安装，不假定手机会被儿童拿到）。
  ///
  /// 成功与失败都回执 `parental_unlock_ack`（`ok` / `expired` /
  /// `already-unlocked`；`forbidden` 由服务端在投递前校验发送者时回执）。
  /// 短码状态见 [ParentalUnlockCodeController]（锁屏 UI 同源展示）。
  bool _parentalUnlock(Map<String, dynamic>? args, String actor) {
    final ParentalUnlockCodeController codes =
        ParentalUnlockCodeController.instance;
    final dynamic raw = args?['code'];
    final String code = raw is String ? raw.trim() : '';
    // 已经解锁（本地答题 / 上一次命令已生效）：幂等受理并回执，
    // 但本次命令没有产生新的解锁动作 → 返回 false。
    if (!KidWatchTimerController.instance.locked) {
      unawaited(codes.sendAck(result: 'already-unlocked', actor: actor, code: code));
      return false;
    }
    if (code.isEmpty || !codes.active || !codes.consume(code)) {
      // 无短码 / 已过期 / 已消费 / 不匹配：TV 端统一回执 `expired`
      //（短码无效与过期对家长端是同一个处置：重新请求）。
      unawaited(codes.sendAck(result: 'expired', actor: actor, code: code));
      return false;
    }
    KidWatchTimerController.instance.unlock();
    unawaited(codes.sendAck(result: 'ok', actor: actor, code: code));
    return true;
  }

  /// 切换当前频道的播放源（`delta`：+1 下一个 / -1 上一个，默认 +1）。
  ///
  /// 与两端壳层「左/右键切源」同一条通路：播放器把实现注册到
  /// [HomeNowPlayingController.onSwitchSource]，未打开直播时按未支持处理。
  bool _switchSource(Map<String, dynamic>? args) {
    final void Function(int delta)? callback =
        HomeNowPlayingController.instance.onSwitchSource;
    if (callback == null) return false;
    final dynamic raw = args?['delta'];
    final int delta = raw is num && raw.toInt() != 0 ? raw.toInt() : 1;
    callback(delta);
    return true;
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

  /// 数字键逐位输入：家长端每按一位发一条 `channel_digit {digit}`，
  /// 直接转给电视本机同一个 [ChannelNumberInputController]，复用「累积 →
  /// 2 秒结算 → 频道号浮层 → 超范围提示」。门槛按产品口径「家长随时能
  /// 跳台」——不判断当前 tab / 遮挡层，命令到达即输入。
  bool _channelDigit(Map<String, dynamic>? args) {
    if (args == null) return false;
    final dynamic raw = args['digit'];
    final int? digit = raw is num ? raw.toInt() : null;
    if (digit == null || digit < 0 || digit > 9) return false;
    // 无频道时 input() 内部会直接 return；这里提前返回 false 便于日志区分。
    if (liveChannel.count <= 0) return false;
    ChannelNumberInputController.instance.input(digit);
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
