import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/gen/assets.gen.dart';
import 'package:tray_manager/tray_manager.dart' show ImageAsset;

class TryIconHelper {
  /// 原生 API 要求调用方自己持有这些对象：
  /// TrayIcon 被 GC 会直接移除图标，Menu/MenuItem 被 GC 会让右键菜单项失效
  static nativeapi.TrayIcon? _trayIcon;
  static nativeapi.Image? _icon;
  static nativeapi.Menu? _menu;
  static nativeapi.ListenerId? _menuListenerId;
  static final List<nativeapi.MenuItem> _menuItems = <nativeapi.MenuItem>[];
  static nativeapi.ListenerId? _trayListenerId;

  /// 托盘左键点击回调（显示窗口），由 main.dart 注册
  static void Function()? onTrayIconClicked;

  /// 托盘菜单项点击回调，由 main.dart 注册
  static void Function(String action)? onMenuAction;

  static const String actionShowWindow = 'show_window';
  static const String actionHideWindow = 'hide_window';
  static const String actionExitApp = 'exit_app';

  static nativeapi.LaunchAtLogin? _launchAtLogin;
  static nativeapi.MenuItem? _launchAtLoginItem;

  /// 上次已同步到面板的开机启动状态，只有真的变了才需要重挂菜单
  static bool? _lastSyncedEnabled;

  static Future<nativeapi.TrayIcon?> setUpTray() async {
    if (Platform.isAndroid || Platform.isIOS) {
      debugPrint('TryIconHelper] 系统托盘图标不支持在 Android 或 iOS 上使用');
      return null;
    }
    final trayIcon = _trayIcon ??= nativeapi.TrayIcon.create();
    if (trayIcon == null) {
      debugPrint('TryIconHelper] 创建托盘图标失败');
      return null;
    }
    trayIcon.setTooltip('薯仔工具箱 - 剪贴板'.tr);
    // 右键直接弹出菜单，对应旧版 onTrayIconRightMouseDown 里的 popUpContextMenu()
    trayIcon.setContextMenuTrigger(nativeapi.ContextMenuTrigger.rightClicked);

    final menu = nativeapi.Menu.create()!;
    final menuItems = <nativeapi.MenuItem>[];
    _addMenuItem(menu, menuItems, '显示窗口'.tr, actionShowWindow);
    menu.addSeparator();
    _addMenuItem(menu, menuItems, '隐藏窗口'.tr, actionHideWindow);
    menu.addSeparator();
    nativeapi.MenuItem? launchAtLoginItem;
    final launchAtLogin = _ensureLaunchAtLogin();
    if (launchAtLogin != null) {
      launchAtLoginItem = _addLaunchAtLoginItem(menu, menuItems, launchAtLogin);
      menu.addSeparator();
    }
    _addMenuItem(menu, menuItems, '退出应用'.tr, actionExitApp);

    // 先挂上新菜单，再释放旧菜单及其监听，避免旧菜单项在仍被使用时被回收
    final oldMenu = _menu;
    final oldMenuListenerId = _menuListenerId;
    trayIcon.setContextMenu(menu);
    _menu = menu;
    _menuItems
      ..clear()
      ..addAll(menuItems);
    _launchAtLoginItem = launchAtLoginItem;
    if (oldMenu != null) {
      if (oldMenuListenerId != null) {
        oldMenu.removeListener(oldMenuListenerId);
      }
      oldMenu.dispose();
    }

    // 每次弹出菜单都重新读系统状态，外部（如桌面的自启动管理）改过后勾选不会过期
    _menuListenerId = menu.addListener((event) {
      if (event is nativeapi.MenuOpenedEvent) {
        debugPrint('TryIconHelper] MenuOpenedEvent → 重新查询开机启动状态');
        _syncLaunchAtLoginState();
      } else if (event is nativeapi.MenuClosedEvent) {
        debugPrint('TryIconHelper] MenuClosedEvent');
      }
    });

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

  static void _addMenuItem(nativeapi.Menu menu,
      List<nativeapi.MenuItem> items, String label, String action) {
    final item = nativeapi.MenuItem.createWithLabelAndType(
        label, nativeapi.MenuItemType.normal)!;
    item.addListener((event) {
      if (event is nativeapi.MenuItemClickedEvent) {
        onMenuAction?.call(action);
      }
    });
    items.add(item);
    menu.addItem(item);
  }

  static nativeapi.LaunchAtLogin? _ensureLaunchAtLogin() {
    final cached = _launchAtLogin;
    if (cached != null) {
      return cached;
    }
    if (!nativeapi.LaunchAtLogin.isSupported()) {
      debugPrint('TryIconHelper] 当前系统不支持开机启动');
      return null;
    }
    final launchAtLogin = nativeapi.LaunchAtLogin.create();
    if (launchAtLogin == null) {
      debugPrint('TryIconHelper] 创建开机启动实例失败');
      return null;
    }
    launchAtLogin.setDisplayName('薯仔工具箱 - 剪贴板'.tr);
    _launchAtLogin = launchAtLogin;
    return launchAtLogin;
  }

  static bool get _launchAtLoginEnabled {
    final launchAtLogin = _launchAtLogin;
    return launchAtLogin != null && launchAtLogin.isEnabled;
  }

  static nativeapi.MenuItem _addLaunchAtLoginItem(
      nativeapi.Menu menu,
      List<nativeapi.MenuItem> items,
      nativeapi.LaunchAtLogin launchAtLogin) {
    final enabled = launchAtLogin.isEnabled;
    debugPrint('TryIconHelper] 构建开机启动项: id=${launchAtLogin.id} '
        'enabled=$enabled');
    _lastSyncedEnabled = enabled;
    final item = nativeapi.MenuItem.createWithLabelAndType(
        '开机启动'.tr, nativeapi.MenuItemType.checkbox)!;
    item.state =
        enabled ? nativeapi.MenuItemState.checked : nativeapi.MenuItemState.unchecked;
    item.addListener((event) {
      if (event is nativeapi.MenuItemClickedEvent) {
        debugPrint('TryIconHelper] MenuItemClickedEvent → 切换开机启动');
        _toggleLaunchAtLogin(launchAtLogin);
      }
    });
    items.add(item);
    menu.addItem(item);
    return item;
  }

  static void _toggleLaunchAtLogin(nativeapi.LaunchAtLogin launchAtLogin) {
    final wasEnabled = launchAtLogin.isEnabled;
    final bool ok;
    if (wasEnabled) {
      ok = launchAtLogin.disable();
    } else {
      ok = launchAtLogin.enable();
    }
    debugPrint('TryIconHelper] ${wasEnabled ? 'disable' : 'enable'}() '
        '返回=$ok → isEnabled=${launchAtLogin.isEnabled}');
    // 平台可能在点击时自己勾上，写回真实状态才能把失败的开关纠正回来
    _syncLaunchAtLoginState();
  }

  /// nativeapi 只有 setContextMenu 才会发 LayoutUpdated / ItemsPropertiesUpdated，
  /// 单独改 label 或 state 面板不会重拉布局，所以改完必须重挂一次菜单
  static void _refreshContextMenu() {
    final trayIcon = _trayIcon;
    final menu = _menu;
    if (trayIcon == null || menu == null) {
      return;
    }
    trayIcon.setContextMenu(menu);
  }

  static void _syncLaunchAtLoginState() {
    final item = _launchAtLoginItem;
    if (item == null) {
      debugPrint('TryIconHelper] 跳过同步：开机启动菜单项不存在');
      return;
    }
    final enabled = _launchAtLoginEnabled;
    item.state = enabled
        ? nativeapi.MenuItemState.checked
        : nativeapi.MenuItemState.unchecked;
    item.label = '开机启动'.tr;
    debugPrint('TryIconHelper] 同步状态: enabled=$enabled');
    if (enabled == _lastSyncedEnabled) {
      debugPrint('TryIconHelper] 状态未变，跳过重挂菜单');
      return;
    }
    _lastSyncedEnabled = enabled;
    // 状态没变时重挂是白挨的：菜单展开期间调 setContextMenu 会报
    // Gdk-CRITICAL(gdk_device_get_axis) 并可能让菜单闪烁
    _refreshContextMenu();
  }

  static void _listenTrayIcon(nativeapi.TrayIcon trayIcon) {
    if (_trayListenerId != null) {
      return;
    }
    _trayListenerId = trayIcon.addListener((event) {
      if (event is nativeapi.TrayIconClickedEvent) {
        onTrayIconClicked?.call();
      }
    });
  }

  static void _setIcon(nativeapi.TrayIcon trayIcon,
      TrayIconState trayIconState) {
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
    final image = ImageAsset.fromAsset(assetName);
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
