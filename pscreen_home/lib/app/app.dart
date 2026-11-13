import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pscreen_home/app/config/app_flavor.dart';
import 'package:pscreen_home/app/screensaver_host.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/screensaver/screensaver_controller.dart';
import 'package:pscreen_home/core/ui/ui_scale.dart';
import 'package:pscreen_home/features/parental/presentation/parental_theme.dart';
import 'package:pscreen_home/features/parental/presentation/parental_unlock_overlay.dart';
import 'package:pscreen_home/features/screen/application/live_stage_controller.dart';
import 'package:pscreen_home/features/screen/presentation/components/live_stage_host.dart';
import 'package:pscreen_home/features/update/presentation/force_update_page.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';

/// 应用根组件：MaterialApp.router + GoRouter 路由配置。
/// 中控屏场景固定使用暗色主题。
///
/// 更新模块的强更页在这里接管整棵 widget 树：只有「强更 + 安装包已下载且
/// sha256 校验通过」时才会出现，替换掉 MaterialApp.router（无关闭入口）。
class App extends StatefulWidget {
  const App({super.key});

  /// 家长端浅色主题对应的系统栏样式：浅底 + 深色图标。
  /// 家长端固定 `ThemeMode.light`，但 Android 状态栏默认黑底，与浅色 UI 割裂
  /// （真机反馈"顶部状态栏是黑色的"）；显式声明后系统栏融入浅色界面。
  /// 其它 flavor（中控屏深色）不设置，保持系统默认，零回归。
  ///
  /// 注意：MIUI 等 ROM 上仅靠 widget 树内 AnnotatedRegion 不足以覆盖启动期
  /// 状态栏着色（实测仍为纯黑），因此提升为公开常量，由 main() 在 `runApp`
  /// 前命令式设置一次，页面内 AnnotatedRegion 兜底，双保险。
  static const SystemUiOverlayStyle parentSystemUi = SystemUiOverlayStyle(
    statusBarColor: Color(0xFFF7F9F8),
    // Android：浅底配深色图标；iOS：statusBarBrightness=light 表示浅底。
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFFF7F9F8),
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    // 避免 Android 10+ 给导航栏加强制半透明遮罩，保证浅底不被压暗。
    systemNavigationBarContrastEnforced: false,
  );

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 网络恢复时补一次静默重试（下载失败只重试，不转阻断）。
    _connectivitySub = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.any((ConnectivityResult result) => result != ConnectivityResult.none)) {
        AppUpdateController.instance.onNetworkRestored();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppUpdateController.instance.onForeground();
      // 部分 ROM 切回前台会把状态栏重置成默认黑底，家长端补设一次浅色样式。
      if (AppFlavorConfig.isParentOnly) {
        SystemChrome.setSystemUIOverlayStyle(App.parentSystemUi);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUpdateState>(
      valueListenable: AppUpdateController.instance,
      builder: (BuildContext context, AppUpdateState update, Widget? _) {
        // parent flavor 走浅色 + 深绿（家长 App 独立视觉）；中控/手机端保持深色。
        final bool parentOnly = AppFlavorConfig.isParentOnly;
        final Widget app;
        if (update.forceBlocked) {
          app = MaterialApp(
            title: parentOnly ? '薯仔电视家长端' : '薯仔的中控台',
            debugShowCheckedModeBanner: false,
            themeMode: parentOnly ? ThemeMode.light : ThemeMode.dark,
            theme: _buildTheme(Brightness.light),
            darkTheme: _buildTheme(Brightness.dark),
            home: const ForceUpdatePage(),
          );
        } else {
          final AppRouter appRouter = Injection.get<AppRouter>();
          final UiScaleController uiScale = Injection.get<UiScaleController>();
          final ScreensaverController screensaver = Injection.get<ScreensaverController>();
          final LiveStageController liveStage = Injection.get<LiveStageController>();
          app = MaterialApp.router(
            title: parentOnly ? '薯仔电视家长端' : '薯仔的中控台',
            debugShowCheckedModeBanner: false,
            themeMode: parentOnly ? ThemeMode.light : ThemeMode.dark,
            theme: _buildTheme(Brightness.light),
            darkTheme: _buildTheme(Brightness.dark),
            routerConfig: appRouter.router,
            // 全局界面缩放：设置页调整后立即生效，Navigator / 弹窗 / 页面一起等比放大
            builder: (BuildContext context, Widget? child) => ListenableBuilder(
              listenable: uiScale,
              builder: (BuildContext context, Widget? _) => UiScaleScope(
                // 未手动设置时按当前屏幕逻辑尺寸自动适配（手机竖屏不放大），
                // 避免 1.5 倍把首页 AppBar 压到放不下。
                scale: uiScale.resolve(MediaQuery.sizeOf(context)),
                // 解锁弹层挂在 UiScaleScope 内（享受等比缩放）、ScreensaverHost
                // 之外（弹层要盖过屏保）；Stack 形态不依赖 Navigator 祖先，
                // 因为 MaterialApp.builder 的 context 在 Navigator 之上。
                child: ParentalUnlockOverlay(
                  child: ScreensaverHost(
                    router: appRouter,
                    controller: screensaver,
                    live: liveStage,
                    child: LiveStageHost(controller: liveStage, child: child ?? const SizedBox.shrink()),
                  ),
                ),
              ),
            ),
          );
        }
        // 家长端显式声明浅色系统栏，覆盖 Android 默认黑底状态栏；
        // 中控/手机端保持系统默认行为，不受影响。
        return parentOnly ? AnnotatedRegion<SystemUiOverlayStyle>(value: App.parentSystemUi, child: app) : app;
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    // 家长端配色对齐交互原型：浅底 #F7F9F8 + 深绿主色 #0F6E56 + 白卡片浅描边。
    // 中控/手机端维持原深色 + 蓝色，互不影响。
    final bool parentOnly = AppFlavorConfig.isParentOnly;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: parentOnly ? const Color(0xFF0F6E56) : const Color(0xFF4F8CFF),
      brightness: brightness,
    );
    final Color surfaceBg = parentOnly
        ? const Color(0xFFF7F9F8)
        : (dark ? const Color(0xFF0E1116) : const Color(0xFFF5F7FA));
    final Color appBarBg = parentOnly && !dark ? Colors.white : surfaceBg;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[
        brightness == Brightness.dark ? ParentalTheme.dark : ParentalTheme.light,
      ],
      scaffoldBackgroundColor: surfaceBg,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBg,
        surfaceTintColor: appBarBg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.onSurface),
        // AppBar 顶部也声明一次浅色系统栏，确保 Tab 页切换时状态栏不被
        // Material 默认样式回写为黑底（AnnotatedRegion 就近优先级更高）。
        systemOverlayStyle: parentOnly && !dark ? App.parentSystemUi : null,
      ),
      cardTheme: CardThemeData(
        color: parentOnly && !dark ? Colors.white : null,
        surfaceTintColor: parentOnly && !dark ? Colors.white : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: parentOnly && !dark ? const BorderSide(color: Color(0xFFE6ECE9)) : BorderSide.none,
        ),
      ),
    );
  }
}
