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
      subsriptions.add(NimCore.instance.loginService.onLoginStatus.listen(onLoginStatus));
      subsriptions.add(NimCore.instance.loginService.onLoginFailed.listen(onLoginFailed));
      subsriptions.add(NimCore.instance.loginService.onKickedOffline.listen(onKickedOffline));
      subsriptions.add(NimCore.instance.loginService.onLoginClientChanged.listen(onLoginClientChanged));
    });
  }

  Future stopListen() async {
    Log.startEndD('[NimManager] stopListen', () {
      for (var subsription in subsriptions) {
        subsription.cancel();
      }
    });
  }

  void onLoginStatus(NIMLoginStatus event) {
    Log.i('[NimManager] onLoginStatus: $event');
  }

  void onLoginFailed(NIMError event) {
    Log.i('[NimManager] onLoginFailed: $event');
  }

  void onKickedOffline(NIMKickedOfflineDetail event) {
    Log.i('[NimManager] onKickedOffline: $event');
  }

  void onLoginClientChanged(NIMLoginClientChangeEvent event) {
    Log.i('[NimManager] onLoginClientChanged: $event');
  }

  Future<NIMResult<void>> login({required String accountId, required String token}) async {
    final loginResult = await NimCore.instance.loginService.login(accountId, token, NIMLoginOption());
    return loginResult;
  }
}
