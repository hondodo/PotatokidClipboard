import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pscreen_home/app/app.dart';
import 'package:pscreen_home/app/config/app_flavor.dart';
import 'package:pscreen_home/app/config/ha_config.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/device/device_identity.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/server/account_session.dart';
import 'package:pscreen_home/core/server/device_reporter.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_bloc.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_event.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_home/features/remote_control/core/control_log.dart';
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/app/config/data_files.dart';
import 'package:pscreen_screen/app/config/screen_assets.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';
import 'package:pscreen_screen/core/update/app_update_models.dart';
import 'package:pscreen_screen/core/utils/app_version.dart';
import 'package:pscreen_screen/core/utils/client_info.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_event.dart';

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 0.0 家长端浅色主题：在 runApp 之前命令式设置系统栏为浅底 + 深色图标。
      //     MIUI 等 ROM 上 widget 树内的 AnnotatedRegion 覆盖不到启动期状态栏，
      //     实测纯黑（与浅色 AppBar 割裂）。命令式设置是 TV 端已验证的可靠路径；
      //     其它 flavor（中控屏深色）保持系统默认，不受影响。
      if (AppFlavorConfig.isParentOnly) {
        SystemChrome.setSystemUIOverlayStyle(App.parentSystemUi);
      }

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

      // 1.05 账号作用域 = 当前构建 flavor + 实际 kind（如 `board.home`），
      //      最终账号 = 作用域 + 设备号（见 DeviceCredentials）。
      final ClientInfo clientInfo = await ClientInfo.current();
      DeviceCredentials.configureAccountScope('${AppFlavorConfig.raw}.${kindOfApp(clientInfo.app)}');
      // 只有 parent flavor 允许用已 claim 的自定义登录名；board / phone 与
      // TV 端均保持「账号恒等于派生值」的原有登录链路，行为不变。
      DeviceCredentials.configureClaimEnabled(AppFlavorConfig.isParentOnly);

      // 1.1 数据文件（频道顺序 / 隐藏列表 / 天气城市）：先用本地值
      //     （持久化缓存 → 包内 assets 默认）保证后续任意时刻都有可用值。
      await DataFiles.instance.loadLocal();

      // 2. 依赖注入（含网络、本地持久化、路由、业务模块）
      await Injection.init();

      // 2.5 账号恒定 = `<flavor>.<kind>.<设备号>`：已保存账号与派生值不一致
      //     就改写并重连（旧号不做兼容）。必须早于 loginWithSaved / ws 连接。
      await DeviceCredentials.enforceDerivedAccount();

      // 3. 应用上次手动设置的连接配置（持久化优先，空则回落 .env）
      HaConfig.applyOverrides(
        host: Injection.get<SettingsStore>().hostOverride,
        token: Injection.get<SettingsStore>().tokenOverride,
        serverBaseUrl: Injection.get<SettingsStore>().serverBaseUrlOverride,
      );

      // 3.0 App 更新：启动查一次（走本地 pscreen_server 代理，fail-open）。
      //     非强更静默下载后只在 AppBar 提示；强更也在下载校验通过后才拦截。
      final String? updatePlatform = updatePlatformOf(defaultTargetPlatform);
      if (updatePlatform != null) {
        final AppVersion appVersion = Injection.get<AppVersion>();
        await AppUpdateController.instance.configure(
          AppUpdateRuntime(
            appId: AppFlavorConfig.updateAppId,
            platform: updatePlatform,
            baseUrl: HaConfig.serverBaseUrl,
            version: appVersion.version,
            build: appVersion.build,
            deviceId: await DeviceIdentity.deviceId(),
            checkInterval: const Duration(hours: 12),
            checkJitter: const Duration(minutes: 30),
            // 不注入 canStartDownload：任何页面/时段都允许下载，
            // 家长端从不进屏保（screensaver_host 禁用），按屏保判据会永久拦截。
          ),
        );
      }

      // 3.1 向 Admin 服务端注册设备并拉取「可见家庭 + 首页布局」。
      //     与路由初始化并行，服务端不可达时超时降级，不阻塞启动。
      final DeviceReporter deviceReporter = Injection.get<DeviceReporter>();
      final Future<void> serverSync = deviceReporter.initialize();

      // 3.2 登录取角色：/api/login 响应含 user.role，下面 initialize()
      //     创建路由时读取它决定 initialLocation（parent 直落家长视图），
      //     所以必须先登录；服务端不可达时超时降级为空角色（按 user 处理）。
      await AccountSession.loginWithSaved().timeout(const Duration(seconds: 8), onTimeout: () => false);

      // 4. 初始化路由（异步，决定 initialLocation），必须在 runApp 前
      await Injection.get<AppRouter>().initialize();
      await serverSync;

      // 4.5 实时通道自动连接（DI 单例；不阻塞启动，失败仅记日志）。
      //     ws 恒用**设备派生号**（channelAccount + 默认口令）——它是设备身份证，
      //     永不改名/禁用；家长号只作为 principal 附加声明，让服务端把本连接
      //     也登记到家长号名下，保证按 machine.parents 扇出的事件仍能送达。
      //     连接前先 HTTP 登录完成账号建档，再发起 ws，避免握手被拒。
      unawaited(() async {
        try {
          final String channel = await DeviceCredentials.channelAccount();
          if (channel.isEmpty) {
            ControlLog.i('[实时通道] 无法确定设备账号，跳过自动连接');
            return;
          }
          // 先 HTTP 登录完成账号建档（失败返回 false，不阻断：ws 侧独立报错）。
          await AccountSession.loginWithSaved();
          final ClientInfo info = await ClientInfo.current();
          // 家长号身份：仅 parent flavor、且已设置家长号时才随握手上报。
          final String principal = AppFlavorConfig.isParentOnly
              ? (await DeviceCredentials.account()).trim()
              : '';
          final String principalToken = principal.isNotEmpty
              ? DeviceCredentials.passwordMd5()
              : '';
          await Injection.get<RealtimeChannel>().connect(
            account: channel,
            token: DeviceCredentials.channelPasswordMd5(),
            principal: principal,
            principalToken: principalToken,
            // 与心跳注册同源（android_/gen_ 前缀），服务端据此回写 admin 设备表。
            deviceId: await DeviceIdentity.deviceId(),
            role: 'controller',
            // 目标设备类型：中控屏 `home` / 家长端 `parent`（服务端据此在
            // roster/presence 回显，控制端据此选择遥控面板）。
            kind: AppFlavorConfig.deviceKind,
            name: AppFlavorConfig.deviceName,
            app: info.app,
            version: info.version,
            build: info.build,
            // 型号/平台只随连接上报一次，服务端回写 admin 设备表并刷新
            // 「最后连接时间」；心跳与 report 不重复携带。
            model: await DeviceIdentity.model(),
            platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
          );
          ControlLog.i('[实时通道] 已连接 $channel${principal.isNotEmpty ? '（家长号 $principal）' : ''}');
        } catch (e) {
          ControlLog.e('[实时通道] 自动连接失败: $e');
        }
      }());

      // 5. 启动：连接状态机随应用启动发起连接，
      //    连接就绪后由页面触发 HomeBloc 加载实体
      runApp(
        MultiBlocProvider(
          providers: <BlocProvider<dynamic>>[
            BlocProvider<ConnectionBloc>(
              create: (_) {
                final ConnectionBloc bloc = Injection.get<ConnectionBloc>();
                // parent 端产品定义不接入 Home Assistant，不发起 HA 连接，
                // 否则会每 30s 无限重连（家长端无 HA 可连）。
                if (!AppFlavorConfig.isParentOnly) {
                  bloc.add(const StartConnection());
                }
                return bloc;
              },
            ),
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
