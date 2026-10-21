import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pscreen_home/app/app.dart';
import 'package:pscreen_home/app/config/ha_config.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_bloc.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_event.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/app/config/data_files.dart';
import 'package:pscreen_screen/app/config/screen_assets.dart';

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 0. 媒体播放库（共享包的 IPTV 能力依赖 media_kit）
      MediaKit.ensureInitialized();

      // 0.1 资产根路径：共享包的资产在宿主 bundle 内位于
      //     packages/pscreen_screen/ 前缀下，读取前必须先告知共享包。
      //     紧接一次接入自检：忘记配置就在启动期立刻失败，
      //     而不是等第一次读资产时被 catch 吞成空串。
      ScreenAssets.configure(root: 'packages/pscreen_screen/');
      ScreenAssets.requireHostConfigured();

      // 1. 加载 .env：HA 连接配置（AS_HOST / AS_KEY）与屏幕侧配置共用同一份
      //    .env。flutter_dotenv 的 load() 会覆盖式重载，重复调用安全。
      await HaConfig.initialize();
      await AppConfig.initialize();

      // 1.1 数据文件（频道顺序 / 隐藏列表 / 天气城市）：先用本地值
      //     （持久化缓存 → 包内 assets 默认）保证后续任意时刻都有可用值。
      await DataFiles.instance.loadLocal();

      // 2. 依赖注入（含网络、本地持久化、路由、业务模块）
      await Injection.init();

      // 3. 应用上次手动设置的连接配置（持久化优先，空则回落 .env）
      HaConfig.applyOverrides(
        host: Injection.get<SettingsStore>().hostOverride,
        token: Injection.get<SettingsStore>().tokenOverride,
      );

      // 4. 初始化路由（异步，决定 initialLocation），必须在 runApp 前
      await Injection.get<AppRouter>().initialize();

      // 5. 启动：连接状态机随应用启动发起连接，
      //    连接就绪后由页面触发 HomeBloc 加载实体
      runApp(
        MultiBlocProvider(
          providers: <BlocProvider<dynamic>>[
            BlocProvider<ConnectionBloc>(create: (_) => Injection.get<ConnectionBloc>()..add(const StartConnection())),
            BlocProvider<HomeBloc>(create: (_) => Injection.get<HomeBloc>()),
          ],
          child: const App(),
        ),
      );
    },
    (Object error, StackTrace stack) {
      FlutterError.presentError(FlutterErrorDetails(exception: error, stack: stack));
    },
  );
}
