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
import 'package:pscreen_home/features/remote_control/core/control_config.dart';
import 'package:pscreen_home/features/remote_control/core/control_log.dart';
import 'package:pscreen_home/features/remote_control/data/control_settings.dart';
import 'package:pscreen_home/features/remote_control/data/nim_client.dart';
import 'package:pscreen_home/features/remote_control/data/tv_directory.dart';
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/app/config/data_files.dart';
import 'package:pscreen_screen/app/config/screen_assets.dart';
import 'package:pscreen_screen/core/utils/nim_manager.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_event.dart';

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

      // 2.1 遥控目标电视目录（assets/tvs.json）：启动时加载一次，
      //      避免每次进入遥控页重复读资产。
      try {
        await Injection.get<TvDirectory>().loadFromAssets();
      } catch (e) {
        ControlLog.e('[遥控] 目标电视目录加载失败: $e');
      }

      // 3. 应用上次手动设置的连接配置（持久化优先，空则回落 .env）
      HaConfig.applyOverrides(
        host: Injection.get<SettingsStore>().hostOverride,
        token: Injection.get<SettingsStore>().tokenOverride,
      );

      // 4. 初始化路由（异步，决定 initialLocation），必须在 runApp 前
      await Injection.get<AppRouter>().initialize();

      // 4.5 NIM 初始化（DI 单例；不阻塞启动，失败仅记日志）。
      //     SDK 初始化由共享包的 NimManager 统一负责（幂等）。
      //     当前平台无 NIM 实现（如 Linux，缺 nim_core_v2_linux）时 init 返回
      //     false：跳过监听与自动登录，避免后续 MissingPluginException。
      //     成功后自动登录遥控端账号（账号 / token 来自本地持久化）。
      unawaited(() async {
        try {
          final bool inited = await Injection.get<NimManager>().init(appKey: ControlConfig.nimAppKey);
          if (!inited) {
            ControlLog.i('[NIM] 当前平台无 NIM 实现，跳过监听与自动登录');
            return;
          }
          Injection.get<NimManager>().startListen();
          final bool ok = await Injection.get<NimClient>().autoLogin(account: ControlSettings.instance.nimAccount);
          if (!ok) {
            ControlLog.e('[NIM] 自动登录失败，请到设置页检查账号 / Token');
          }
        } catch (e) {
          ControlLog.e('[NIM] initialize failed: $e');
        }
      }());

      // 5. 启动：连接状态机随应用启动发起连接，
      //    连接就绪后由页面触发 HomeBloc 加载实体
      runApp(
        MultiBlocProvider(
          providers: <BlocProvider<dynamic>>[
            BlocProvider<ConnectionBloc>(create: (_) => Injection.get<ConnectionBloc>()..add(const StartConnection())),
            BlocProvider<HomeBloc>(create: (_) => Injection.get<HomeBloc>()),
            // 天气状态机：全局共享，时钟页与天气页消费。
            // BlocProvider 默认 lazy：首次被页面读取时才创建并派发 LoadWeather，
            // 因此天气请求只在真正打开时钟页 / 天气页时发生。
            BlocProvider<WeatherBloc>(create: (_) => Injection.get<WeatherBloc>()..add(const LoadWeather())),
            // 直播频道状态机：全局共享，直播页消费。
            // 同上：只有真正打开直播页时才会拉取频道列表（缓存优先）。
            BlocProvider<IptvBloc>(create: (_) => Injection.get<IptvBloc>()..add(const LoadIptv(useCache: true))),
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
