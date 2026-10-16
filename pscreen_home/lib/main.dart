import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/app/app.dart';
import 'package:pscreen_home/app/config/app_config.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_bloc.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_event.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 1. 加载 .env（AS_HOST / AS_KEY）
      await AppConfig.initialize();

      // 2. 依赖注入（含网络、路由、业务模块）
      await Injection.init();

      // 3. 初始化路由（异步，决定 initialLocation），必须在 runApp 前
      await Injection.get<AppRouter>().initialize();

      // 4. 启动：连接状态机随应用启动发起连接，
      //    连接就绪后由页面触发 HomeBloc 加载实体
      runApp(
        MultiBlocProvider(
          providers: <BlocProvider<dynamic>>[
            BlocProvider<ConnectionBloc>(
              create: (_) => Injection.get<ConnectionBloc>()
                ..add(const StartConnection()),
            ),
            BlocProvider<HomeBloc>(create: (_) => Injection.get<HomeBloc>()),
          ],
          child: const App(),
        ),
      );
    },
    (Object error, StackTrace stack) {
      FlutterError.presentError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}
