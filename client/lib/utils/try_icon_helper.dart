import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/gen/assets.gen.dart';
import 'package:tray_manager/tray_manager.dart';

class TryIconHelper {
  static Future<void> setUpTray() async {
    if (Platform.isAndroid || Platform.isIOS) {
      debugPrint('TryIconHelper] 系统托盘图标不支持在 Android 或 iOS 上使用');
      return;
    }
    await trayManager.setToolTip('薯仔工具箱 - 剪贴板'.tr);
    await trayManager.setIcon(
      Platform.isWindows
          ? Assets.images.icon.iconOffIco
          : Assets.images.icon.iconOffPng.path,
    );
    Menu menu = Menu(
      items: [
        MenuItem(
          key: 'show_window',
          label: '显示窗口'.tr,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'hide_window',
          label: '隐藏窗口'.tr,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: '退出应用'.tr,
        ),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  static Future<void> updateTrayIcon(
      {required TrayIconState trayIconState}) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return;
    }
    String iconPath = Platform.isWindows
        ? Assets.images.icon.iconOffIco
        : Assets.images.icon.iconOffPng.path;
    if (trayIconState == TrayIconState.on) {
      iconPath = Platform.isWindows
          ? Assets.images.icon.iconOnIco
          : Assets.images.icon.iconOnPng.path;
    }
    await trayManager.setIcon(iconPath);
  }
}
