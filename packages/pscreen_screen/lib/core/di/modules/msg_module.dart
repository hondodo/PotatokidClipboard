import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/utils/platform_channel_service.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';
import 'package:pscreen_screen/features/msg/application/device_state_reporter.dart';
import 'package:pscreen_screen/features/msg/application/message_command_executor.dart';
import 'package:pscreen_screen/features/msg/application/message_overlay_controller.dart';
import 'package:pscreen_screen/features/msg/application/message_router.dart';
import 'package:pscreen_screen/features/msg/application/reporting_service.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_bloc.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_state.dart';

/// RealtimeChannel 包装的发送器。
class RealtimeMessageSender implements MessageSender {
  RealtimeMessageSender(this._channel);

  final RealtimeChannel _channel;

  @override
  Future<bool> sendText({
    required String toAccount,
    required String text,
  }) =>
      _channel.sendText(to: toAccount, body: text);

  @override
  Future<bool> sendEvent({
    required String toAccount,
    required String event,
    Map<String, Object?>? data,
  }) =>
      _channel.sendEvent(
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
  static DeviceStateReporter? _stateReporter;
  static String _lastStartedAccount = '';

  static Future<void> register(GetIt it) async {
    await _sub?.cancel();
    _sub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    _stateReporter?.stop();
    _stateReporter = null;

    final MessageRouter router = MessageRouter(
      overlay: MessageOverlayController.instance,
      executor: MessageCommandExecutor(
        volume: PlatformChannelService.instance,
        liveChannel: LiveChannelController.instance,
        channelInfo: ChannelInfoProvider.instance,
        // 宿主导航能力（中控屏/电视端各自注册；未注册时 nav 命令按未支持处理）。
        navigator: it.isRegistered<HostNavigator>() ? it<HostNavigator>() : null,
      ),
    );
    final ReportingService reporting = ReportingService(
      sender: RealtimeMessageSender(it<RealtimeChannel>()),
      deviceModel: () => PlatformChannelService.instance.deviceModel(),
      channelInfo: ChannelInfoProvider.instance,
      liveChannel: LiveChannelController.instance,
      sceneProvider: it<CurrentSceneProvider>(),
    );
    it.registerLazySingleton<ReportingService>(
      () => reporting,
      dispose: (_) async => reporting.dispose(),
    );

    // 状态上报：被控端场景/频道列表 → 服务端缓存 → watch 中的控制端。
    // 与上报服务相互独立（不依赖登录状态），连接成功即开始工作。
    final DeviceStateReporter stateReporter = DeviceStateReporter(
      channel: it<RealtimeChannel>(),
      sceneProvider: it<CurrentSceneProvider>(),
    )..start();
    _stateReporter = stateReporter;
    it.registerLazySingleton<DeviceStateReporter>(
      () => stateReporter,
      dispose: (_) async => stateReporter.stop(),
    );

    // 收消息：服务端只投递寻址到本账号的消息，直接交给路由。
    _sub = it<RealtimeChannel>().messages.listen((RealtimeMessage message) {
      if (message.body.isNotEmpty) {
        router.handleIncoming(message.body);
      }
    });

    // 连接态边沿驱动上报启停。
    _stateSub = it<RemoteLoginBloc>().stream.listen((RemoteLoginState state) {
      if (state.status == RemoteLoginStatus.loggedIn) {
        // 中控屏以 ControlSettings 账号（controller）连接主通道，
        // 但 RemoteLoginBloc 可能没有账号；优先使用通道实际账号。
        final String channelAccount = it<RealtimeChannel>().account.trim();
        final String account =
            channelAccount.isNotEmpty ? channelAccount : state.account;
        if (account.isEmpty) return;
        if (_lastStartedAccount != account) {
          reporting.stop();
          _lastStartedAccount = account;
        }
        unawaited(reporting.start(account));
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

  static Future<void> unregister(GetIt it) async {
    await _sub?.cancel();
    _sub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    _stateReporter?.stop();
    _stateReporter = null;
    _lastStartedAccount = '';
    if (it.isRegistered<DeviceStateReporter>()) {
      await it.unregister<DeviceStateReporter>();
    }
    if (it.isRegistered<ReportingService>()) {
      await it.unregister<ReportingService>();
    }
  }
}
