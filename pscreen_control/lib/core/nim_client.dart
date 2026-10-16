import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nim_core_v2/nim_core.dart';
// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart'
    hide Log;
import 'package:path_provider/path_provider.dart';

import 'package:pscreen_control/app/config/app_config.dart';
import 'package:pscreen_control/app/storage/app_settings.dart';
import 'package:pscreen_control/app/utils/app_log.dart';

/// NIM 客户端薄封装（模式同 TV 端 NimManager；init/login 调用序列照抄）。
class NimClient {
  /// SDK 初始化（幂等；失败记日志并返回 false，UI 层提示）。
  Future<bool> init() async {
    try {
      final NIMSDKOptions options = await _buildOptions(AppConfig.nimAppKey);
      final NIMResult<void> value = await NimCore.instance.initialize(options);
      AppLog.i('[NimClient] initialize result: $value');
      return value.isSuccess;
    } catch (e) {
      AppLog.e('[NimClient] initialize 失败: $e');
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
    await AppSettings.instance.setNimToken(token);
    return _login(account, token: token);
  }

  Future<bool> _login(String account, {String? token}) async {
    final String useToken = token ?? AppSettings.instance.nimToken;
    try {
      final NIMResult<void> result = await NimCore.instance.loginService
          .login(account, useToken, NIMLoginOption());
      if (result.isSuccess) {
        await AppSettings.instance.setNimAccount(account);
        return true;
      }
      AppLog.e('[NimClient] login 失败: ${result.code}');
      return false;
    } catch (e) {
      AppLog.e('[NimClient] login 异常: $e');
      return false;
    }
  }

  Future<void> logout() async {
    await NimCore.instance.loginService.logout();
    await AppSettings.instance.setNimAccount('');
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
        AppLog.e('[NimClient] p2pConversationId 失败: ${cid.code}');
        return false;
      }
      final NIMResult<NIMMessage> msg =
          await MessageCreator.createTextMessage(text);
      if (!msg.isSuccess || msg.data == null) {
        AppLog.e('[NimClient] createTextMessage 失败: ${msg.code}');
        return false;
      }
      final NIMResult<NIMSendMessageResult> r = await NimCore
          .instance.messageService
          .sendMessage(message: msg.data!, conversationId: cid.data!);
      if (!r.isSuccess || r.data == null) {
        AppLog.e('[NimClient] sendMessage 失败: ${r.code}');
        return false;
      }
      return true;
    } catch (e) {
      AppLog.e('[NimClient] sendText 异常: $e');
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
}
