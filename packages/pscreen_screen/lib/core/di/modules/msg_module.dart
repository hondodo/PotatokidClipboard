import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:pscreen_screen/app/app_log.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/core/parental/parental_unlock_code_controller.dart';
import 'package:pscreen_screen/core/utils/platform_channel_service.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/application/relay_policy.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';
import 'package:pscreen_screen/features/msg/application/device_state_reporter.dart';
import 'package:pscreen_screen/features/msg/application/message_command_executor.dart';
import 'package:pscreen_screen/features/msg/application/message_overlay_controller.dart';
import 'package:pscreen_screen/features/msg/application/message_router.dart';
import 'package:pscreen_screen/features/msg/application/reporting_service.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_bloc.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RealtimeChannel 包装的发送器。
class RealtimeMessageSender implements MessageSender {
  RealtimeMessageSender(this._channel);

  final RealtimeChannel _channel;

  @override
  Future<bool> sendText({required String toAccount, required String text}) =>
      _channel.sendText(to: toAccount, body: text);

  @override
  Future<bool> sendEvent({
    required String toAccount,
    required String event,
    Map<String, Object?>? data,
  }) => _channel.sendEvent(
    to: toAccount,
    event: event,
    data: data == null ? null : Map<String, dynamic>.from(data),
  );
}

/// 消息模块：收消息路由 + 上报服务（依赖 RemoteModule 的 [RemoteLoginBloc]
/// 与 NetworkModule 的 [RealtimeChannel]，注册顺序在其后）。
class MsgModule {
  const MsgModule._();

  static StreamSubscription<RealtimeMessage>? _sub;
  static StreamSubscription<RemoteLoginState>? _stateSub;
  static StreamSubscription<Map<String, dynamic>>? _configSub;
  static DeviceStateReporter? _stateReporter;
  static String _lastStartedAccount = '';

  static Future<void> register(GetIt it) async {
    await _sub?.cancel();
    _sub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    await _configSub?.cancel();
    _configSub = null;
    _stateReporter?.stop();
    _stateReporter = null;

    // 状态上报：被控端场景/频道列表/音量 → 服务端缓存 → watch 中的控制端。
    // 与上报服务相互独立（不依赖登录状态），连接成功即开始工作。
    // 先于 executor 构造：音量命令执行后要回调它的 requestPush。
    final DeviceStateReporter stateReporter = DeviceStateReporter(
      channel: it<RealtimeChannel>(),
      sceneProvider: it<CurrentSceneProvider>(),
    )..start();
    _stateReporter = stateReporter;
    it.registerLazySingleton<DeviceStateReporter>(
      () => stateReporter,
      dispose: (_) async => stateReporter.stop(),
    );

    final MessageRouter router = MessageRouter(
      overlay: MessageOverlayController.instance,
      executor: MessageCommandExecutor(
        volume: PlatformChannelService.instance,
        liveChannel: LiveChannelController.instance,
        channelInfo: ChannelInfoProvider.instance,
        // 宿主导航能力（中控屏/电视端各自注册；未注册时 nav 命令按未支持处理）。
        navigator: it.isRegistered<HostNavigator>()
            ? it<HostNavigator>()
            : null,
        // 直播悬浮能力（仅中控屏注册；电视端无应用内悬浮小窗）。
        liveStage: it.isRegistered<LiveStageControl>()
            ? it<LiveStageControl>()
            : null,
        // 音量±/静音执行后刷新最新音量并上报，遥控端音量胶囊立即跟随。
        onVolumeCommand: stateReporter.requestPush,
      ),
    );
    final ReportingService reporting = ReportingService(
      sender: RealtimeMessageSender(it<RealtimeChannel>()),
      deviceModel: () => PlatformChannelService.instance.deviceModel(),
      channelInfo: ChannelInfoProvider.instance,
      liveChannel: LiveChannelController.instance,
      sceneProvider: it<CurrentSceneProvider>(),
      // 换台时丢弃状态上报里的上一频道播放快照（离开直播路径不经过它）。
      onChannelSwitch: stateReporter.clearLastPlayback,
    );
    it.registerLazySingleton<ReportingService>(
      () => reporting,
      dispose: (_) async => reporting.dispose(),
    );

    // 儿童模式选人上报：选人页确认 / 换人（setActiveChildren 有变化）→
    // `parental_child_active` 事件（服务端按 event 落库，零改动）；
    // 未登录时 reportEvent 内部有 _started 门禁，不会误发。
    ParentalStateController.instance.onActiveChildrenChanged =
        (List<String> childIds) {
          reporting.reportEvent('parental_child_active', <String, Object?>{
            'childIds': childIds,
          });
          // 选人变化立即补报一帧观看分账（空列表 = 当前无人在看）。
          reporting.notifyParentalStateChanged();
        };

    // 锁屏 / 解锁同样立即补报，家长端不用等 25 秒采样点。
    ParentalStateController.instance.timer.onLockStateChanged =
        reporting.notifyParentalStateChanged;

    // 收消息：服务端只投递寻址到本账号的消息，直接交给路由。
    _sub = it<RealtimeChannel>().messages.listen((RealtimeMessage message) {
      if (message.body.isNotEmpty) {
        router.handleIncoming(message.body, actor: message.from);
      }
    });

    // 服务端配置下行：管理端改儿童模式（档案 / 档位 / 白名单黑名单）时
    // pushConfigToMachine 实时推送；交给 ParentalStateController 按
    // 「服务端 parental 为对象即为准」的双源规则应用并广播。
    _configSub = it<RealtimeChannel>().deviceConfigs.listen(
      (Map<String, dynamic> config) {
        unawaited(ParentalStateController.instance.applyServerConfig(config));
        unawaited(_applyProgramsUpdate(config, it));
      },
    );

    // 连接态边沿驱动上报启停。
    _stateSub = it<RemoteLoginBloc>().stream.listen((RemoteLoginState state) {
      if (state.status == RemoteLoginStatus.loggedIn) {
        // 中控屏以 ControlSettings 账号（controller）连接主通道，
        // 但 RemoteLoginBloc 可能没有账号；优先使用通道实际账号。
        final String channelAccount = it<RealtimeChannel>().account.trim();
        final String account = channelAccount.isNotEmpty
            ? channelAccount
            : state.account;
        if (account.isEmpty) return;
        if (_lastStartedAccount != account) {
          reporting.stop();
          _lastStartedAccount = account;
        }
        unawaited(reporting.start(account));
        // 解锁短码补发：重启后锁屏可能先于连接建立生成短码（离线期双发失败），
        // 登录成功后按原码补发两条（手机端按 code 去重，重复无副作用）。
        unawaited(ParentalUnlockCodeController.instance.flushPending());
        // 主动拉一次最新生效配置：`config` 帧只在管理端改动时推送（握手不推），
        // report 回包自带服务端配置（含 parental），登录后即与管理端对齐。
        unawaited(_pullServerConfig(it<RealtimeChannel>(), it));
      } else if (state.status == RemoteLoginStatus.error ||
          (state.status == RemoteLoginStatus.notConfigured &&
              it<RealtimeChannel>().account.trim().isEmpty)) {
        // 中控屏的 RemoteLoginBloc 可能没有 AppSettings 账号，断线时会先变成
        // notConfigured。只要通道仍保留账号，这就是临时断线，不能停上报；
        // 否则重连后 start() 会重新发送「登录成功」。
        reporting.stop();
        _lastStartedAccount = '';
      }
    });
  }

  /// 登录成功后主动上报一次，取回服务端生效配置（`report` 回包自带
  /// config，含 parental）并交给 ParentalStateController 应用。
  static Future<void> _pullServerConfig(
    RealtimeChannel channel,
    GetIt it,
  ) async {
    try {
      final Map<String, dynamic>? config = await channel.sendReport();
      if (config != null) {
        await ParentalStateController.instance.applyServerConfig(config);
        await _applyProgramsUpdate(config, it);
      }
    } catch (e) {
      Log.error('[MsgModule] 拉取服务端配置失败: $e');
    }
  }

  /// 节目文件版本（管理端保存频道/源列表后递增）。
  ///
  /// config 帧只带版本号，不带文件本体；发现比本地记录新就派发一次
  /// [LoadIptv.isRefresh]，由 IPTV 链路带本地 version 重新校验最终频道列表。
  static const String _programsVersionKey = 'programs_updated_at_v1';

  static Future<void> _applyProgramsUpdate(
    Map<String, dynamic> config,
    GetIt it,
  ) async {
    final int updatedAt = _asInt(config['programsUpdatedAt']);
    if (updatedAt <= 0) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int applied = prefs.getInt(_programsVersionKey) ?? 0;
      if (updatedAt <= applied) return;
      // 节目文件保存也可能改了 relay 白名单：强制重拉一次，失败静默。
      unawaited(RelayPolicy.instance.refreshNow());
      // IptvModule 注册在本模块之后；未就绪时先不落版本号，避免漏掉这次刷新。
      if (!it.isRegistered<IptvBloc>()) return;
      it<IptvBloc>().add(const LoadIptv(isRefresh: true));
      await prefs.setInt(_programsVersionKey, updatedAt);
      Log.i('[MsgModule] 节目文件已更新，重新拉取频道: $updatedAt');
    } catch (e) {
      Log.error('[MsgModule] 应用节目版本失败: $e');
    }
  }

  static int _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  static Future<void> unregister(GetIt it) async {
    await _sub?.cancel();
    _sub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    await _configSub?.cancel();
    _configSub = null;
    _stateReporter?.stop();
    _stateReporter = null;
    _lastStartedAccount = '';
    // 回调随上报服务一起摘除，避免 ReportingService 销毁后仍被回调。
    ParentalStateController.instance.onActiveChildrenChanged = null;
    ParentalStateController.instance.timer.onLockStateChanged = null;
    if (it.isRegistered<DeviceStateReporter>()) {
      await it.unregister<DeviceStateReporter>();
    }
    if (it.isRegistered<ReportingService>()) {
      await it.unregister<ReportingService>();
    }
  }
}
