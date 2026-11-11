import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/router/app_router.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:potatokid_screen/features/app/application/remote_key_dispatcher.dart';
import 'package:potatokid_screen/features/update/presentation/force_update_page.dart';
import 'package:potatokid_screen/features/update/presentation/update_prompt_gate.dart';
import 'package:potatokid_screen/shared/widgets/floating_remote.dart';
import 'package:potatokid_screen/shared/widgets/tv_design_viewport.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';

/// 应用根组件：MaterialApp.router + GoRouter 路由配置，主题由 [AppBloc] 驱动。
///
/// 强更页（安装包已下载并校验通过）时替换整棵路由树，确保没有关闭入口。
class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppRouter appRouter = Injection.get<AppRouter>();
    return BlocBuilder<AppBloc, AppState>(
      builder: (context, state) {
        final ThemeData light = ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        );
        final ThemeData dark = ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
          useMaterial3: true,
        );
        return ValueListenableBuilder<AppUpdateState>(
          valueListenable: AppUpdateController.instance,
          builder: (BuildContext context, AppUpdateState update, Widget? _) {
            if (update.forceBlocked) {
              return MaterialApp(
                title: 'app_name'.tr(),
                debugShowCheckedModeBanner: false,
                themeMode: ThemeMode.dark,
                theme: light,
                darkTheme: dark,
                home: const ForceUpdatePage(),
                builder: (BuildContext context, Widget? child) =>
                    TvDesignViewport(child: child ?? const SizedBox.shrink()),
              );
            }
            return MaterialApp.router(
              title: 'app_name'.tr(),
              debugShowCheckedModeBanner: false,
              themeMode: state.themeMode,
              theme: light,
              darkTheme: dark,
              routerConfig: appRouter.router,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              // 可用更新弹窗门控：同一次启动只提示一次，遥控可操作。
              // 传根 Navigator key：门控挂在 builder 上，自身 context 在 Navigator 之上。
              // 屏幕模拟遥控挂在 Navigator 之上：所有 DialogRoute 都在它下面，
              // 弹窗期间也不会被遮住。按键经 RemoteKeyDispatcher 回到 MainApp，
              // 真实遥控的焦点链路径不变（遥控器自身 ExcludeFocus）。
              builder: (BuildContext ctx, Widget? child) => TvDesignViewport(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    UpdatePromptGate(
                      navigatorKey: appRouter.navigatorKey,
                      child: child ?? const SizedBox.shrink(),
                    ),
                    FloatingRemote(onKey: RemoteKeyDispatcher.instance.dispatch),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
