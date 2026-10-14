import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nim_core_v2/nim_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:potatokid_screen/app/app_log.dart';
// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart' hide Log;

class NimManager {
  late NIMSDKOptions options;
  final subsriptions = <StreamSubscription>[];

  Future init({required String appKey}) async {
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
    } else if (Platform.isMacOS || Platform.isWindows) {
      NIMBasicOption basicOption = NIMBasicOption();
      options = NIMPCSDKOptions(basicOption: basicOption, appKey: appKey);
    }

    var value = await NimCore.instance.initialize(options);
    Log.i('[NimManager] initialize result: $value');
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
}
