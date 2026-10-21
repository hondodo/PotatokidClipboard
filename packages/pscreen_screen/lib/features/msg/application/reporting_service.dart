import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pscreen_screen/app/app_log.dart';
import 'package:potatokid_screen/features/app/application/app_tab_controller.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';

/// 文本发送抽象（生产为 NimManager 包装；测试用 Fake）。
abstract class MessageSender {
  Future<bool> sendText({required String toAccount, required String text});
}

/// 上行上报服务（设计 §3.2/§5.5）：登录两条、切台防抖、5 分钟心跳。
class ReportingService {
  ReportingService({
    required this.sender,
    required this.deviceModel,
    required this.channelInfo,
    required this.liveChannel,
    DateTime Function()? now,
    Duration? heartbeatInterval,
  })  : _now = now ?? DateTime.now,
        _heartbeatInterval =
            heartbeatInterval ?? ReportingService.heartbeatInterval {
    _playCommitListener = () => notifyChannelCommitted();
    liveChannel.onPlayCommit.addListener(_playCommitListener);
  }

  /// 系统管理员账号。
  static const String adminAccount = '1000001';

  /// 心跳间隔（默认 5 分钟，测试可注入短间隔）。
  static const Duration heartbeatInterval = Duration(minutes: 5);

  /// 切台确认防抖。
  static const Duration channelDebounce = Duration(seconds: 1);

  final MessageSender sender;
  final Future<String> Function() deviceModel;
  final ChannelInfoProvider channelInfo;
  final LiveChannelController liveChannel;
  final DateTime Function() _now;

  /// 实际生效的心跳间隔（构造时可覆盖，默认 [heartbeatInterval]）。
  final Duration _heartbeatInterval;

  late final VoidCallback _playCommitListener;

  Timer? _heartbeat;
  Timer? _channelTimer;
  DateTime? _loginAt;
  bool _started = false;
  String? _model;

  /// 启动纪元：stop/重启时自增，使仍在 await 中的 start 作废。
  int _epoch = 0;

  /// 登录成功（RemoteLoginState.loggedIn 边沿）时调用；先取设备型号再发前两条。
  Future<void> start(String account) async {
    if (_started) return;
    _started = true;
    final int epoch = ++_epoch;
    final DateTime loginAt = _now();
    _loginAt = loginAt;
    final String model = await deviceModel();
    if (!_started || epoch != _epoch) return; // await 期间 stop/重启
    _model = model;
    _send('$account于${_fmt(loginAt)}使用$_deviceModelCache登录成功。');
    _send('正在收看${positionText()}');
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) => _onHeartbeat());
  }

  /// 登出/停止（error/notConfigured 边沿、dispose 时）。
  void stop() {
    _epoch++; // 作废在途的 start
    _started = false;
    _loginAt = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _channelTimer?.cancel();
    _channelTimer = null;
  }

  /// 切台确认（onPlayCommit 钩子）：防抖后发「切换频道」。
  void notifyChannelCommitted() {
    if (!_started) return;
    _channelTimer?.cancel();
    _channelTimer = Timer(channelDebounce, () {
      _channelTimer = null;
      final String? name = channelInfo.nameAt(liveChannel.index);
      if (name == null) return;
      _send('切换频道：$name');
    });
  }

  /// 当前位置文本：在频道上报频道名，否则报当前页名。
  String positionText() {
    if (AppTabController.branchIndex == 0) {
      final String? name = channelInfo.nameAt(liveChannel.index);
      if (name != null) return name;
    }
    return AppTabController.pageName;
  }

  String get _deviceModelCache => _model ?? 'Android TV';

  void _onHeartbeat() {
    if (!_started || _loginAt == null) return;
    final int minutes = _now().difference(_loginAt!).inMinutes;
    _send('已收看$minutes分钟，当前频道是${positionText()}');
  }

  void _send(String text) {
    sender.sendText(toAccount: adminAccount, text: text).then((bool ok) {
      if (!ok) Log.i('[ReportingService] 上报发送失败: $text');
    }).catchError((Object e) {
      Log.error('[ReportingService] 上报异常: $e');
    });
  }

  static String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  void dispose() {
    stop();
    liveChannel.onPlayCommit.removeListener(_playCommitListener);
  }
}
