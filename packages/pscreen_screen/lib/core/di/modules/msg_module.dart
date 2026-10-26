import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/utils/platform_channel_service.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';
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
}

/// 消息模块：收消息路由 + 上报服务（依赖 RemoteModule 的 [RemoteLoginBloc]
/// 与 NetworkModule 的 [RealtimeChannel]，注册顺序在其后）。
class MsgModule {
  const MsgModule._();

  static StreamSubscription<RealtimeMessage>? _sub;
  static StreamSubscription<RemoteLoginState>? _stateSub;
  static String _lastStartedAccount = '';

  static Future<void> register(GetIt it) async {
    await _sub?.cancel();
    _sub = null;
    await _stateSub?.cancel();
    _stateSub = null;

    final MessageRouter router = MessageRouter(
      overlay: MessageOverlayController.instance,
      executor: MessageCommandExecutor(
        volume: PlatformChannelService.instance,
        liveChannel: LiveChannelController.instance,
        channelInfo: ChannelInfoProvider.instance,
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

    // 收消息：服务端只投递寻址到本账号的消息，直接交给路由。
    _sub = it<RealtimeChannel>().messages.listen((RealtimeMessage message) {
      if (message.body.isNotEmpty) {
        router.handleIncoming(message.body);
      }
    });

    // 连接态边沿驱动上报启停。
    _stateSub = it<RemoteLoginBloc>().stream.listen((RemoteLoginState state) {
      if (state.status == RemoteLoginStatus.loggedIn) {
        if (_lastStartedAccount != state.account) {
          reporting.stop();
          _lastStartedAccount = state.account;
        }
        unawaited(reporting.start(state.account));
      } else if (state.status == RemoteLoginStatus.notConfigured ||
          state.status == RemoteLoginStatus.error) {
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
    _lastStartedAccount = '';
    if (it.isRegistered<ReportingService>()) {
      await it.unregister<ReportingService>();
    }
  }
}
