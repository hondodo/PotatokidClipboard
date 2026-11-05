import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pscreen_screen/core/update/app_update_api.dart';

/// 拉起系统安装器 / 打开外部链接（Android 走原生 MethodChannel）。
///
/// 原生侧用 FileProvider + `ACTION_VIEW`，并把安装 Intent 交给用户确认；
/// 不假设安装完会自动启动 App（只有 HOME/默认启动器变体会被系统拉起）。
class AppUpdateInstaller {
  const AppUpdateInstaller();

  static const MethodChannel _channel = MethodChannel('potatokid/updater');

  /// 安装 APK；返回是否成功唤起系统安装器。
  Future<bool> installApk(String path) async {
    if (!File(path).existsSync()) {
      throw const AppUpdateException(-1, '安装包不存在，请重新下载');
    }
    try {
      final bool? result = await _channel.invokeMethod<bool>('install', <String, dynamic>{'path': path});
      return result ?? false;
    } on PlatformException catch (error) {
      throw AppUpdateException(-1, error.message ?? '无法唤起系统安装器');
    } on MissingPluginException {
      throw const AppUpdateException(-1, '当前平台不支持自动安装');
    }
  }

  /// iOS 等外部链接版本：只打开商店/TestFlight 地址，不下载、不强更。
  Future<bool> openExternal(String url) async {
    if (url.trim().isEmpty) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>('openUrl', <String, dynamic>{'url': url});
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
