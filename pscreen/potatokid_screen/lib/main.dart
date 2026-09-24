import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:media_kit/media_kit.dart';
import 'package:potatokid_screen/app/app.dart';
import 'package:potatokid_screen/app/config/app_config.dart';
import 'package:potatokid_screen/app/hosts/app_hosts.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/router/app_router.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 1. 锁定横屏（电视场景）
      await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      // 1.1 初始化媒体播放库（media_kit）
      MediaKit.ensureInitialized();

      // 2. 加载 .env 与环境配置
      await AppConfig.initialize();
      AppHosts.init();

      // 3. 国际化
      await EasyLocalization.ensureInitialized();
      await initializeDateFormatting('zh_CN');
      await initializeDateFormatting('zh_TW');
      await initializeDateFormatting('en_US');
      await initializeDateFormatting('ja_JP');

      // 4. 依赖注入（含网络、路由、业务模块）
      await Injection.init();

      // 5. 初始化路由（异步，决定 initialLocation），必须在 runApp 前
      await Injection.get<AppRouter>().initialize();

      // 6. 启动
      runApp(
        EasyLocalization(
          supportedLocales: const <Locale>[
            Locale('zh', 'CN'),
            Locale('zh', 'TW'),
            Locale('en', 'US'),
            Locale('ja', 'JP'),
          ],
          path: 'assets/translations',
          fallbackLocale: const Locale('zh', 'CN'),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AppBloc>(create: (_) => Injection.get<AppBloc>()),
            ],
            child: const App(),
          ),
        ),
      );
    },
    (error, stack) {
      FlutterError.presentError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}
