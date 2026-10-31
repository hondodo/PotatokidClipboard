import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pscreen_home/app/app.dart';
import 'package:pscreen_home/app/config/ha_config.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/device/device_identity.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/server/device_reporter.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_bloc.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_event.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_home/features/remote_control/core/control_log.dart';
import 'package:pscreen_home/features/remote_control/data/control_settings.dart';
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/app/config/data_files.dart';
import 'package:pscreen_screen/app/config/screen_assets.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/client_info.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';
import 'package:pscreen_screen/core/utils/ptools_util.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_event.dart';

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      DeviceCredentials.configureDefaultAccountPrefix('home');

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
        serverBaseUrl: Injection.get<SettingsStore>().serverBaseUrlOverride,
      );

      // 3.1 向 Admin 服务端注册设备并拉取「可见家庭 + 首页布局」。
      //     与路由初始化并行，服务端不可达时超时降级，不阻塞启动。
      final DeviceReporter deviceReporter = Injection.get<DeviceReporter>();
      final Future<void> serverSync = deviceReporter.initialize();

      // 4. 初始化路由（异步，决定 initialLocation），必须在 runApp 前
      await Injection.get<AppRouter>().initialize();
      await serverSync;

      // 4.5 实时通道自动连接（DI 单例；不阻塞启动，失败仅记日志）。
      //     凭据统一走共享包 DeviceCredentials（自定义账号 > .env > 本机设备号；
      //     口令自定义 > .env > 123456）。连接前先 HTTP 登录完成账号建档，
      //     再发起 ws，避免握手因「账号不存在」被拒。断线由通道自动重连。
      unawaited(() async {
        try {
          // 旧版遥控账号/口令存在 ControlSettings，迁移一次到 AppSettings
          //（之后以 AppSettings 为准，ControlSettings 只保留已勾选目标）。
          await AppSettings.instance.ensureLoaded();
          if (AppSettings.instance.remoteAccount.isEmpty) {
            final String legacyAccount = ControlSettings.instance.account;
            if (legacyAccount.isNotEmpty) {
              await AppSettings.instance.setRemoteAccount(legacyAccount);
            }
          }
          if (AppSettings.instance.remotePassword.isEmpty) {
            final String legacyToken = ControlSettings.instance.token;
            // 旧默认 '12345678' 是已废弃的全局口令，不迁移（回落 123456）。
            if (legacyToken.isNotEmpty && legacyToken != '12345678') {
              await AppSettings.instance.setRemotePassword(legacyToken);
            }
          }

          final String account = await DeviceCredentials.account();
          if (account.isEmpty) {
            ControlLog.i('[实时通道] 无法确定账号，跳过自动连接');
            return;
          }
          // 先 HTTP 登录完成账号建档（失败返回 false，不阻断：ws 侧独立报错）。
          await PtoolsUtil.loginWithSaved();
          final ClientInfo info = await ClientInfo.current();
          await Injection.get<RealtimeChannel>().connect(
            account: account,
            token: DeviceCredentials.passwordMd5(),
            // 与心跳注册同源（android_/gen_ 前缀），服务端据此回写 admin 设备表。
            deviceId: await DeviceIdentity.deviceId(),
            role: 'controller',
            // 目标设备类型：中控屏（服务端据此在 roster/presence 回显，
            // 控制端据此选择遥控面板）。
            kind: 'home',
            name: '中控台',
            app: info.app,
            version: info.version,
            build: info.build,
          );
          ControlLog.i('[实时通道] 已连接 $account');
        } catch (e) {
          ControlLog.e('[实时通道] 自动连接失败: $e');
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

      // 6. 心跳上报（在线状态 / 当前家庭），并持续接收 Admin 的配置变更。
      deviceReporter.start();
    },
    (Object error, StackTrace stack) {
      FlutterError.presentError(FlutterErrorDetails(exception: error, stack: stack));
    },
  );
}
