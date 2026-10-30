import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/gen/assets.gen.dart';
import 'package:tray_manager/tray_manager.dart' as tray;

class TryIconHelper {
  /// 原生 API 要求调用方自己持有这些对象：
  /// TrayIcon 被 GC 会直接移除图标，Menu/MenuItem 被 GC 会让右键菜单项失效
  static tray.TrayIcon? _trayIcon;
  static tray.Image? _icon;
  static tray.Menu? _menu;
  static final List<tray.MenuItem> _menuItems = <tray.MenuItem>[];
  static tray.ListenerId? _trayListenerId;

  /// 托盘左键点击回调（显示窗口），由 main.dart 注册
  static void Function()? onTrayIconClicked;

  /// 托盘菜单项点击回调，由 main.dart 注册
  static void Function(String action)? onMenuAction;

  static const String actionShowWindow = 'show_window';
  static const String actionHideWindow = 'hide_window';
  static const String actionExitApp = 'exit_app';

  static Future<tray.TrayIcon?> setUpTray() async {
    if (Platform.isAndroid || Platform.isIOS) {
      debugPrint('TryIconHelper] 系统托盘图标不支持在 Android 或 iOS 上使用');
      return null;
    }
    final trayIcon = _trayIcon ??= tray.TrayIcon.create();
    if (trayIcon == null) {
      debugPrint('TryIconHelper] 创建托盘图标失败');
      return null;
    }
    trayIcon.setTooltip('薯仔工具箱 - 剪贴板'.tr);
    // 右键直接弹出菜单，对应旧版 onTrayIconRightMouseDown 里的 popUpContextMenu()
    trayIcon.setContextMenuTrigger(tray.ContextMenuTrigger.rightClicked);

    final menu = tray.Menu.create()!;
    final menuItems = <tray.MenuItem>[];
    _addMenuItem(menu, menuItems, '显示窗口'.tr, actionShowWindow);
    menu.addSeparator();
    _addMenuItem(menu, menuItems, '隐藏窗口'.tr, actionHideWindow);
    menu.addSeparator();
    _addMenuItem(menu, menuItems, '退出应用'.tr, actionExitApp);

    // 先挂上新菜单再释放旧菜单，避免旧菜单项在仍被使用时被回收
    final oldMenu = _menu;
    trayIcon.setContextMenu(menu);
    _menu = menu;
    _menuItems
      ..clear()
      ..addAll(menuItems);
    oldMenu?.dispose();

    _listenTrayIcon(trayIcon);
    _setIcon(trayIcon, TrayIconState.off);
    return trayIcon;
  }

  static Future<void> updateTrayIcon(
      {required TrayIconState trayIconState}) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return;
    }
    final trayIcon = _trayIcon ?? await setUpTray();
    if (trayIcon == null) {
      return;
    }
    _setIcon(trayIcon, trayIconState);
  }

  static void _addMenuItem(tray.Menu menu, List<tray.MenuItem> items,
      String label, String action) {
    final item = tray.MenuItem
        .createWithLabelAndType(label, tray.MenuItemType.normal)!;
    item.addListener((event) {
      if (event is tray.MenuItemClickedEvent) {
        onMenuAction?.call(action);
      }
    });
    items.add(item);
    menu.addItem(item);
  }

  static void _listenTrayIcon(tray.TrayIcon trayIcon) {
    if (_trayListenerId != null) {
      return;
    }
    _trayListenerId = trayIcon.addListener((event) {
      if (event is tray.TrayIconClickedEvent) {
        onTrayIconClicked?.call();
      }
    });
  }

  static void _setIcon(tray.TrayIcon trayIcon, TrayIconState trayIconState) {
    final String assetName;
    if (trayIconState == TrayIconState.on) {
      assetName = Platform.isWindows
          ? Assets.images.icon.iconOnIco
          : Assets.images.icon.iconOnPng.path;
    } else {
      assetName = Platform.isWindows
          ? Assets.images.icon.iconOffIco
          : Assets.images.icon.iconOffPng.path;
    }
    final image = tray.ImageAsset.fromAsset(assetName);
    if (image == null) {
      debugPrint('TryIconHelper] 加载托盘图标失败: $assetName');
      return;
    }
    final oldIcon = _icon;
    trayIcon.icon = image;
    _icon = image;
    oldIcon?.dispose();
  }
}
