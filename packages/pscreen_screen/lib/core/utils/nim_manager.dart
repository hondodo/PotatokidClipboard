import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nim_core_v2/nim_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pscreen_screen/app/app_log.dart';
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart' hide Log;

class NimManager {
  late NIMSDKOptions options;
  final subsriptions = <StreamSubscription>[];

  /// SDK 是否已初始化（`NimCore.instance` 是全局单例，不可重复 initialize）。
  static bool _sdkInitialized = false;

  /// 当前平台是否有 nim_core_v2 实现：仅 Android/iOS/macOS/Windows/Web，
  /// **无 Linux 实现**（nim_core_v2 未提供 nim_core_v2_linux 包）。
  static bool get _platformSupported =>
      kIsWeb ||
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;

  /// 初始化 NIM SDK（幂等）。返回是否**真正完成初始化**。
  ///
  /// 支持的平台返回 true；不支持的平台（如 Linux 桌面）在读取 [options] 之前
  /// 就返回 false——[options] 是 `late` 字段，未赋值即读会抛
  /// `LateInitializationError`。调用方据返回值跳过 startListen / 自动登录。
  Future<bool> init({required String appKey}) async {
    // NimCore.instance 是全局单例，重复 initialize 会失败。
    // 同一进程内可能有多个封装（如宿主既当发送端又当接收端），因此幂等处理。
    if (_sdkInitialized) {
      Log.i('[NimManager] SDK 已初始化，跳过');
      return true;
    }
    if (!_platformSupported) {
      Log.warn('[NimManager] 当前平台（${Platform.operatingSystem}）无 NIM 实现，跳过初始化');
      return false;
    }
    if (kIsWeb) {
      var base = NIMInitializeOptions(appkey: appKey, apiVersion: 'v2', debugLevel: 'debug');
      options = NIMWebSDKOptions(appKey: appKey, initializeOptions: base);
    } else if (Platform.isAndroid) {
      final directory = await getExternalStorageDirectory();
      options = NIMAndroidSDKOptions(
        appKey: appKey,
        shouldSyncStickTopSessionInfos: true,
        //若需要使用云端会话，请提前开启云端会话
        enableV2CloudConversation: true,
        sdkRootDir: directory != null ? '${directory.path}/NIMFlutter' : null,
      );
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      options = NIMIOSSDKOptions(
        appKey: appKey,
        shouldSyncStickTopSessionInfos: true,
        //若需要使用云端会话，请提前开启云端会话
        enableV2CloudConversation: true,
        sdkRootDir: '${directory.path}/NIMFlutter',
        apnsCername: 'your apnsCername',
        pkCername: 'your pkCername',
      );
    } else {
      // _platformSupported 已收敛：非 Web/Android/iOS 即 macOS / Windows。
      NIMBasicOption basicOption = NIMBasicOption();
      options = NIMPCSDKOptions(basicOption: basicOption, appKey: appKey);
    }

    var value = await NimCore.instance.initialize(options);
    _sdkInitialized = true;
    Log.i('[NimManager] initialize result: $value');
    return true;
  }

  Future startListen() async {
    Log.startEndD('[NimManager] startListen', () {
      subsriptions.add(NimCore.instance.loginService.onLoginStatus.listen(_handleLoginStatus));
      subsriptions.add(NimCore.instance.loginService.onLoginFailed.listen(_handleLoginFailed));
      subsriptions.add(NimCore.instance.loginService.onKickedOffline.listen(_handleKickedOffline));
      subsriptions.add(NimCore.instance.loginService.onLoginClientChanged.listen(_handleLoginClientChanged));
    });
  }

  Future stopListen() async {
    Log.startEndD('[NimManager] stopListen', () {
      for (var subsription in subsriptions) {
        subsription.cancel();
      }
    });
  }

  void _handleLoginStatus(NIMLoginStatus event) {
    Log.i('[NimManager] _handleLoginStatus: $event');
  }

  void _handleLoginFailed(NIMError event) {
    Log.i('[NimManager] _handleLoginFailed: ${event.toJson()}');
  }

  void _handleKickedOffline(NIMKickedOfflineDetail event) {
    Log.i('[NimManager] _handleKickedOffline: ${event.toJson()}');
  }

  void _handleLoginClientChanged(NIMLoginClientChangeEvent event) {
    Log.i('[NimManager] _handleLoginClientChanged: ${event.toJson()}');
  }

  Future<NIMResult<void>> login({required String accountId, required String token}) async {
    final loginResult = await NimCore.instance.loginService.login(accountId, token, NIMLoginOption());
    return loginResult;
  }

  /// 登出当前账号。
  Future<NIMResult<void>> logout() => NimCore.instance.loginService.logout();

  /// 当前登录账号（未登录返回 null）。
  Future<NIMResult<String?>> getLoginUser() => NimCore.instance.loginService.getLoginUser();

  /// 当前登录状态。
  Future<NIMResult<NIMLoginStatus>> getLoginStatus() => NimCore.instance.loginService.getLoginStatus();

  /// 登录状态事件流（透传 SDK，供上层订阅）。
  Stream<NIMLoginStatus> get onLoginStatus => NimCore.instance.loginService.onLoginStatus;

  /// 数据同步事件流。
  Stream<NIMDataSyncDetail> get onDataSync => NimCore.instance.loginService.onDataSync;

  /// 登录失败事件流。
  Stream<NIMError> get onLoginFailed => NimCore.instance.loginService.onLoginFailed;

  /// 被踢下线事件流。
  Stream<NIMKickedOfflineDetail> get onKickedOffline => NimCore.instance.loginService.onKickedOffline;

  /// 新消息事件流（透传 SDK，仅上层关心文本消息）。
  Stream<List<NIMMessage>> get onReceiveMessages => NimCore.instance.messageService.onReceiveMessages;

  /// 发送 P2P 文本消息；任何一步失败记日志并返回 false，不抛出。
  Future<bool> sendTextMessage({
    required String toAccount,
    required String text,
  }) async {
    try {
      final NIMResult<String> cid =
          await NimCore.instance.conversationIdUtil.p2pConversationId(toAccount);
      if (!cid.isSuccess || cid.data == null) {
        Log.error('[NimManager] p2pConversationId 失败: ${cid.code} ${cid.errorDetails}');
        return false;
      }
      final NIMResult<NIMMessage> msg = await MessageCreator.createTextMessage(text);
      if (!msg.isSuccess || msg.data == null) {
        Log.error('[NimManager] createTextMessage 失败: ${msg.code} ${msg.errorDetails}');
        return false;
      }
      final NIMResult<NIMSendMessageResult> r = await NimCore.instance.messageService.sendMessage(
        message: msg.data!,
        conversationId: cid.data!,
      );
      if (!r.isSuccess || r.data == null) {
        Log.error('[NimManager] sendMessage 失败: ${r.code} ${r.errorDetails}');
        return false;
      }
      return true;
    } catch (e) {
      Log.error('[NimManager] sendTextMessage 异常: $e');
      return false;
    }
  }
}
