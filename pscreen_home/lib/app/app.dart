import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:pscreen_home/app/screensaver_host.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/screensaver/screensaver_controller.dart';
import 'package:pscreen_home/core/ui/ui_scale.dart';
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

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  ScreensaverController? _screensaver;
  LiveStageController? _liveStage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _screensaver = Injection.get<ScreensaverController>()
      ..addListener(_onUpdateSceneChanged);
    _liveStage = Injection.get<LiveStageController>()
      ..addListener(_onUpdateSceneChanged);
    // 网络恢复时补一次静默重试（下载失败只重试，不转阻断）。
    _connectivitySub = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.any((ConnectivityResult result) => result != ConnectivityResult.none)) {
        AppUpdateController.instance.onNetworkRestored();
      }
    });
  }

  @override
  void dispose() {
    _screensaver?.removeListener(_onUpdateSceneChanged);
    _liveStage?.removeListener(_onUpdateSceneChanged);
    _connectivitySub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onUpdateSceneChanged() => AppUpdateController.instance.onSceneChanged();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppUpdateController.instance.onForeground();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUpdateState>(
      valueListenable: AppUpdateController.instance,
      builder: (BuildContext context, AppUpdateState update, Widget? _) {
        if (update.forceBlocked) {
          return MaterialApp(
            title: '薯仔的中控台',
            debugShowCheckedModeBanner: false,
            themeMode: ThemeMode.dark,
            theme: _buildTheme(Brightness.light),
            darkTheme: _buildTheme(Brightness.dark),
            home: const ForceUpdatePage(),
          );
        }
        final AppRouter appRouter = Injection.get<AppRouter>();
        final UiScaleController uiScale = Injection.get<UiScaleController>();
        final ScreensaverController screensaver = Injection.get<ScreensaverController>();
        final LiveStageController liveStage = Injection.get<LiveStageController>();
        return MaterialApp.router(
          title: '薯仔的中控台',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
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
                  child: LiveStageHost(
                    controller: liveStage,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4F8CFF),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF0E1116)
          : const Color(0xFFF5F7FA),
      appBarTheme: AppBarTheme(
        backgroundColor: dark
            ? const Color(0xFF0E1116)
            : const Color(0xFFF5F7FA),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
