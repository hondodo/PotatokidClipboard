// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/app/pre_config.dart';
import 'package:potatokid_clipboard/app/root_binding.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';
import 'package:potatokid_clipboard/pages/home/home_page.dart';
import 'package:potatokid_clipboard/routes/router_names.dart';
import 'package:potatokid_clipboard/routes/routers_manager.dart';
import 'package:potatokid_clipboard/services/app_lifecycles_state_service.dart';
import 'package:potatokid_clipboard/services/settings_service.dart';
import 'package:potatokid_clipboard/utils/device_utils.dart';
import 'package:tray_manager/tray_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PreConfig.init();
  runApp(const MyApp());
  if (DeviceUtils.instance.isDesktop()) {
    doWhenWindowReady(() {
      const initialSize = Size(340, 600);
      appWindow.minSize = initialSize;
      appWindow.size = initialSize;
      appWindow.alignment = Alignment.center;
      if (Platform.isWindows) {
        if (Get.find<SettingsService>().isHideWindowOnStartup.value) {
          appWindow.hide();
        } else {
          appWindow.show();
        }
      } else {
        appWindow.show();
      }
    });
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp>
    with WidgetsBindingObserver, TrayListener {
  Timer? appStateTimer;

  @override
  void initState() {
    trayManager.addListener(this);
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    // 注：如果是打开选择图片控件，会一直快速发送 inactive / resumed 事件，导致刷新频繁的访问接口
    // 所以增加延时发送最后一个事件
    debugPrint('didChangeAppLifecycleState state: $state');
    super.didChangeAppLifecycleState(state);
    appStateTimer?.cancel();
    appStateTimer = Timer(const Duration(milliseconds: 100), () {
      try {
        switch (state) {
          case AppLifecycleState.resumed:
            Log.i('应用进入前台');
            debugPrint('应用进入前台');
            break;
          case AppLifecycleState.inactive:
            Log.i('应用处于不活跃状态');
            debugPrint('应用处于不活跃状态');
            break;
          case AppLifecycleState.paused:
            Log.i('应用进入后台');
            debugPrint('应用进入后台');
            break;
          case AppLifecycleState.detached:
            Log.i('应用被终止');
            debugPrint('应用被终止');
            break;
          case AppLifecycleState.hidden:
            Log.i('应用被隐藏');
            debugPrint('应用被隐藏');
            break;
        }
        AppLifecyclesStateService.onAppLifecycleStateChange(state);
      } catch (e) {
        Log.e('AppLifecycleStateService 异常: $e');
      }
    });
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '薯仔工具箱 - 剪贴板'.tr,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      initialBinding: RootBinding(),
      // 设置初始路由
      initialRoute: RouterNames.root,
      // 配置路由
      routes: RouterManager.routes,
      // getPages: RouterManager.pages,  // 使用getPages会出现按下F5刷新页面时，页面会重新加载，导致页面状态丢失
      // 处理未知路由
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => const HomePage(),
        );
      },
      // 初始化SmartDialog，这是Windows平台正常显示toast的关键
      builder: FlutterSmartDialog.init(),
    );
  }

  @override
  void onTrayIconMouseDown() {
    // do something, for example pop up the menu
    onShowWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // do something
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseUp() {
    // do something
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      // do something
      onShowWindow();
    } else if (menuItem.key == 'hide_window') {
      // do something
      appWindow.minimize();
      if (!Platform.isMacOS) {
        appWindow.hide(); // macOS下调用会直接退出，如果延迟调用，也不会隐藏应用列表里的显示，相当于无效
      }
    } else if (menuItem.key == 'exit_app') {
      // do something
      appWindow.close();
    }
  }

  void onShowWindow() {
    appWindow.show();
    appWindow.restore();
  }
}
