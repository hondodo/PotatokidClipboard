import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nim_core_v2/nim_core.dart';
// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart'
    hide Log;
import 'package:path_provider/path_provider.dart';

import 'package:pscreen_home/features/remote_control/core/control_config.dart';
import 'package:pscreen_home/features/remote_control/data/control_settings.dart';
import 'package:pscreen_home/features/remote_control/core/control_log.dart';
import 'package:pscreen_home/features/remote_control/domain/chat_message_item.dart';

/// NIM 客户端薄封装（模式同 TV 端 NimManager；init/login 调用序列照抄）。
class NimClient {
  /// SDK 初始化（幂等；失败记日志并返回 false，UI 层提示）。
  Future<bool> init() async {
    try {
      final NIMSDKOptions options = await _buildOptions(ControlConfig.nimAppKey);
      final NIMResult<void> value = await NimCore.instance.initialize(options);
      ControlLog.i('[NimClient] initialize result: $value');
      return value.isSuccess;
    } catch (e) {
      ControlLog.e('[NimClient] initialize 失败: $e');
      return false;
    }
  }

  /// 照抄 TV NimManager 的平台分支与选项构造。
  Future<NIMSDKOptions> _buildOptions(String appKey) async {
    if (kIsWeb) {
      final NIMInitializeOptions base = NIMInitializeOptions(
        appkey: appKey,
        apiVersion: 'v2',
        debugLevel: 'debug',
      );
      return NIMWebSDKOptions(appKey: appKey, initializeOptions: base);
    } else if (Platform.isAndroid) {
      final directory = await getExternalStorageDirectory();
      return NIMAndroidSDKOptions(
        appKey: appKey,
        shouldSyncStickTopSessionInfos: true,
        enableV2CloudConversation: true,
        sdkRootDir:
            directory != null ? '${directory.path}/NIMFlutter' : null,
      );
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      return NIMIOSSDKOptions(
        appKey: appKey,
        shouldSyncStickTopSessionInfos: true,
        enableV2CloudConversation: true,
        sdkRootDir: '${directory.path}/NIMFlutter',
        apnsCername: 'your apnsCername',
        pkCername: 'your pkCername',
      );
    } else if (Platform.isMacOS || Platform.isWindows) {
      return NIMPCSDKOptions(
        basicOption: NIMBasicOption(),
        appKey: appKey,
      );
    }
    return NIMPCSDKOptions(basicOption: NIMBasicOption(), appKey: appKey);
  }

  /// 自动登录：同账号已在线则跳过。
  Future<bool> autoLogin({required String account}) async {
    final NIMResult<NIMLoginStatus> status =
        await NimCore.instance.loginService.getLoginStatus();
    if (status.data == NIMLoginStatus.loginStatusLogined) {
      return true;
    }
    return _login(account);
  }

  /// 登录并持久化账号。
  Future<bool> login({
    required String account,
    required String token,
  }) async {
    return _login(account, token: token);
  }

  Future<bool> _login(String account, {String? token}) async {
    final String useToken = token ?? ControlSettings.instance.nimToken;
    try {
      final NIMResult<void> result = await NimCore.instance.loginService
          .login(account, useToken, NIMLoginOption());
      if (result.isSuccess) {
        if (token != null) {
          await ControlSettings.instance.setNimToken(token);
        }
        await ControlSettings.instance.setNimAccount(account);
        return true;
      }
      ControlLog.e('[NimClient] login 失败: ${result.code}');
      return false;
    } catch (e) {
      ControlLog.e('[NimClient] login 异常: $e');
      return false;
    }
  }

  Future<void> logout() async {
    await NimCore.instance.loginService.logout();
    await ControlSettings.instance.setNimAccount('');
  }

  /// 发送 P2P 文本（与 TV 端 sendTextMessage 同构）。
  Future<bool> sendText({
    required String toAccount,
    required String text,
  }) async {
    try {
      final NIMResult<String> cid = await NimCore
          .instance.conversationIdUtil.p2pConversationId(toAccount);
      if (!cid.isSuccess || cid.data == null) {
        ControlLog.e('[NimClient] p2pConversationId 失败: ${cid.code}');
        return false;
      }
      final NIMResult<NIMMessage> msg =
          await MessageCreator.createTextMessage(text);
      if (!msg.isSuccess || msg.data == null) {
        ControlLog.e('[NimClient] createTextMessage 失败: ${msg.code}');
        return false;
      }
      final NIMResult<NIMSendMessageResult> r = await NimCore
          .instance.messageService
          .sendMessage(message: msg.data!, conversationId: cid.data!);
      if (!r.isSuccess || r.data == null) {
        ControlLog.e('[NimClient] sendMessage 失败: ${r.code}');
        return false;
      }
      return true;
    } catch (e) {
      ControlLog.e('[NimClient] sendText 异常: $e');
      return false;
    }
  }

  /// 登录态流 / 登录失败流（透传 SDK，接法照抄 TV NimManager）。
  Stream<NIMLoginStatus> get onLoginStatus =>
      NimCore.instance.loginService.onLoginStatus;
  Stream<NIMError> get onLoginFailed =>
      NimCore.instance.loginService.onLoginFailed;
  Stream<NIMKickedOfflineDetail> get onKickedOffline =>
      NimCore.instance.loginService.onKickedOffline;

  /// 本地会话服务（供 ConversationSource 使用）。
  ///
  /// 选用 local 而非 cloud：来消息时自动更新的是本地会话列表；
  /// cloud 会话依赖 `enableV2CloudConversation` 同步，可能不即时物化。
  V2NIMLocalConversationService get localConversationService =>
      NimCore.instance.localConversationService;

  /// 将与 [peerAccount] 的 P2P 会话标为已读（fire-and-forget，失败仅记日志）。
  Future<void> markConversationRead(String peerAccount) async {
    try {
      final NIMResult<String> cid = await NimCore
          .instance.conversationIdUtil
          .p2pConversationId(peerAccount);
      if (!cid.isSuccess || cid.data == null) {
        ControlLog.e('[NimClient] markConversationRead p2pConversationId 失败: ${cid.code}');
        return;
      }
      final NIMResult<int> r = await NimCore
          .instance.localConversationService
          .markConversationRead(cid.data!);
      if (!r.isSuccess) {
        ControlLog.e('[NimClient] markConversationRead 失败: ${r.code}');
      }
    } catch (e) {
      ControlLog.e('[NimClient] markConversationRead 异常: $e');
    }
  }

  /// 某账号的消息流（简化：仅实时接收消息；历史消息拉取不在本期范围）。
  ///
  /// 已知限制：`onReceiveMessages` 仅含他人发来的消息，故 isOutgoing 恒为 false。
  Stream<List<ChatMessageItem>> watchMessages(String account) {
    return NimCore.instance.messageService.onReceiveMessages
        .map((List<NIMMessage> messages) => messages
            .where((NIMMessage m) => _peerOf(m) == account)
            .map((NIMMessage m) => ChatMessageItem(
                  text: _textOf(m) ?? '[非文本]',
                  isOutgoing: false,
                ))
            .toList());
  }

  /// P2P 收到的消息：发送者即对方账号。
  String? _peerOf(NIMMessage m) => m.senderId;

  /// 文本消息取 text；非文本返回 null。
  String? _textOf(NIMMessage m) =>
      m.messageType == NIMMessageType.text ? m.text : null;
}
