import 'dart:async';

import 'package:nim_core_v2/nim_core.dart';
import 'package:potatokid_screen/core/di/get_it.dart';
import 'package:potatokid_screen/core/utils/nim_manager.dart';
import 'package:potatokid_screen/core/utils/platform_channel_service.dart';
import 'package:potatokid_screen/features/iptv/application/channel_info_provider.dart';
import 'package:potatokid_screen/features/iptv/application/live_channel_controller.dart';
import 'package:potatokid_screen/features/msg/application/message_command_executor.dart';
import 'package:potatokid_screen/features/msg/application/message_overlay_controller.dart';
import 'package:potatokid_screen/features/msg/application/message_router.dart';
import 'package:potatokid_screen/features/msg/application/reporting_service.dart';
import 'package:potatokid_screen/features/remote/application/bloc/remote_login_bloc.dart';
import 'package:potatokid_screen/features/remote/application/bloc/remote_login_state.dart';

/// NimManager 包装的发送器。
class NimMessageSender implements MessageSender {
  NimMessageSender(this._nim);

  final NimManager _nim;

  @override
  Future<bool> sendText({
    required String toAccount,
    required String text,
  }) =>
      _nim.sendTextMessage(toAccount: toAccount, text: text);
}

/// 消息模块：收消息路由 + 上报服务（依赖 RemoteModule 的 [RemoteLoginBloc]
/// 与 CoreModule 的 [NimManager]，注册顺序在其后）。
class MsgModule {
  const MsgModule._();

  static StreamSubscription<List<NIMMessage>>? _sub;
  static StreamSubscription<RemoteLoginState>? _stateSub;
  static ReportingService? _reporting;

  static Future<void> register() async {
    final MessageRouter router = MessageRouter(
      overlay: MessageOverlayController.instance,
      executor: MessageCommandExecutor(
        volume: PlatformChannelService.instance,
        liveChannel: LiveChannelController.instance,
        channelInfo: ChannelInfoProvider.instance,
      ),
    );
    final ReportingService reporting = ReportingService(
      sender: NimMessageSender(getIt<NimManager>()),
      deviceModel: () => PlatformChannelService.instance.deviceModel(),
      channelInfo: ChannelInfoProvider.instance,
      liveChannel: LiveChannelController.instance,
    );
    _reporting = reporting;
    getIt.registerLazySingleton<ReportingService>(
      () => reporting,
      dispose: (_) async => reporting.dispose(),
    );

    // 收消息：仅文本进路由；未登录静默丢弃由 SDK 侧保证（未登录收不到）。
    _sub = getIt<NimManager>().onReceiveMessages.listen((messages) {
      for (final NIMMessage message in messages) {
        final String? text = _textOf(message);
        if (text != null && text.isNotEmpty) {
          router.handleIncoming(text);
        }
      }
    });

    // 登录态边沿驱动上报启停。
    _stateSub = getIt<RemoteLoginBloc>().stream.listen((RemoteLoginState state) {
      if (state.status == RemoteLoginStatus.loggedIn) {
        unawaited(reporting.start(state.account));
      } else if (state.status == RemoteLoginStatus.notConfigured ||
          state.status == RemoteLoginStatus.error) {
        reporting.stop();
      }
    });
  }

  /// 从 NIMMessage 提取文本。SDK 无 NIMTextAttachment——文本直挂
  /// [NIMMessage.text] 字段；非文本消息返回 null。
  static String? _textOf(NIMMessage message) {
    if (message.messageType != NIMMessageType.text) return null;
    return message.text;
  }

  static Future<void> unregister() async {
    await _sub?.cancel();
    _sub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    _reporting?.dispose();
    _reporting = null;
    if (getIt.isRegistered<ReportingService>()) {
      await getIt.unregister<ReportingService>();
    }
  }
}
