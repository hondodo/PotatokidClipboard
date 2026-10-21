# 屏幕能力共享包 + 中控屏一体化 设计文档

日期：2026-10-21
状态：待评审

## 背景

仓库 `potatokid_clipboard` 内有三个相关 Flutter 项目：

| 项目 | 定位 | 形态 | 交互 |
| --- | --- | --- | --- |
| `pscreen_home` | 薯仔的中控台（Home Assistant 智能家居控制） | 触屏屏端 | 触屏 |
| `pscreen/potatokid_screen` | 电视端（IPTV / 屏保 / 时钟 / 天气） | 电视端 | 遥控（方向键 / 焦点） |
| `pscreen_control` | 遥控端（NIM 下发音量 / 切台 / 文本指令） | 手机 / 平板 | 触屏 |

三者当前为**完全独立的复制粘贴代码**：`potatokid_screen` 的路由 / 状态机 / DI 三件套是 `pscreen_home` 的架构来源（见 `pscreen_home/AGENT.md` §0），但两者的 `features/home` 目录同名不同义（HA 设备摘要 vs IPTV 首页），任何形式的目录级合并都会撞名。

## 目标

1. **消除重复**：屏幕侧能力（IPTV 数据、播放器、时钟、天气、消息协议）只维护一份源码。
2. **合成一个 App**：`pscreen_home` 作为宿主，把媒体/屏幕能力纳入中控屏，同时保留 `potatokid_screen` 独立发布（电视端继续出包）。
3. **交互分离**：共享代码只含能力层，UI 由各 App 按自己的交互范式（TV 遥控 / 触屏）自行实现。
4. **遥控能力内聚**：`pscreen_control` 废弃，其能力并入 `pscreen_home`，形成"中控屏 + 遥控器"一体。

## 方案决策

| 备选 | 说明 | 结论 |
| --- | --- | --- |
| A. 纯拷贝进 `pscreen_home` | 物理复制 `potatokid_screen` 的 `lib/` | **否决**。两个 App 都要发版且同时演进同一批屏幕代码，必然分叉 |
| B. 抽真正的共享 package | 新建 `packages/pscreen_screen/`，两个 App 都 path 依赖 | **采用**。边界清晰、单一真源、依赖方向单向 |
| C. path 依赖整个 App 目录 | `pscreen_home` 依赖 `../pscreen/potatokid_screen` | **否决**。一个目录既是 App 又是被依赖包；`flutter: assets:` 在依赖方不生效；host 级代码（router / DI / 首页 / profile）泄漏进共享边界 |
| D. git submodule | 只解决版本管理 | **否决**。不解决代码复用；本仓库 `.gitmodules` 现仅有 `3rd/camera-rtsp` |

## 已确认的产品决策

| # | 决策 |
| --- | --- |
| 1 | 合成一个 App，宿主为 `pscreen_home`（包名 / applicationId / Windows exe 保持不变） |
| 2 | 只迁屏幕 / 媒体侧；`potatokid_screen` 的 `features/home`（IPTV 首页）与 `features/profile` 丢弃 |
| 3 | `pscreen_home` 不做 tab 壳；扁平路由，中控板 AppBar action 作为入口 |
| 4 | 屏保功能暂留空白；**时间页充当屏保** |
| 5 | `potatokid_screen` 继续独立发布 → 必须走共享 package |
| 6 | 共享包**只含能力层**（data / domain / application），UI 各写各的 |
| 7 | `pscreen_control` 废弃，能力并入 `pscreen_home`；遥控面板 + 会话列表两 tab |
| 8 | 一次性交付 5 个页面：时钟 / 直播 / 天气 / 消息（遥控）/ 设置 |
| 9 | `pscreen_home` 保持强制暗色 + 纯中文硬编码（不引入 easy_localization）；`potatokid_screen` 保留 4 语种与主题切换 |

---

## 一、总体架构

```
potatokid_clipboard/
├── packages/
│   └── pscreen_screen/                 # 新增：共享 Flutter package（只含能力层）
│       ├── pubspec.yaml                # name: pscreen_screen
│       └── lib/
│           ├── core/
│           │   ├── di/                 # ScreenModules：向宿主 GetIt 注册屏幕侧依赖
│           │   ├── logging/            # LogService
│           │   ├── network/            # Dio 封装 / HTTP 异常体系 / .env 工具
│           │   ├── utils/              # bloc_event / error_message / app_settings / nim / ptools
│           │   └── media/              # video_aspect_mode / sleep_timer_controller
│           ├── app/
│           │   ├── config/             # AppConfig / AppConstants / DataFiles
│           │   └── hosts/              # AppHosts
│           └── features/
│               ├── iptv/               # data + domain + application
│               ├── msg/                # application + protocol（解析 + 构造）
│               ├── remote/             # data + domain + application（NIM 登录）
│               ├── time/               # application + domain
│               └── weather/            # data + domain + application
│
├── pscreen_home/                       # App A：中控屏（宿主）
│   └── lib/
│       ├── core/                       # 保留 HA 专属：ha_ws_client / ha_net_exceptions
│       ├── features/
│       │   ├── connection/ home/ settings/     # 现有 HA 能力
│       │   ├── screen/                 # 新增：触屏版 时钟/直播/天气 页面
│       │   └── remote_control/         # 新增：并入自 pscreen_control（遥控面板 + 会话列表）
│       └── app/                        # 保留 HA 专属 AppConfig
│
└── pscreen/
    └── potatokid_screen/               # App B：电视端（4-tab，TV 交互）
        └── lib/                        # 保留外壳：router / DI / features/app / features/home / features/profile / presentation
```

依赖方向严格单向：`宿主 App → pscreen_screen`。共享包**不依赖**任何宿主，反之亦然。

## 二、共享包边界

### 2.1 移入 `packages/pscreen_screen`（66 个文件）

| 分组 | 文件 |
| --- | --- |
| `app/` | `app_log.dart`（`Log`）、`config/app_config.dart`、`config/app_constants.dart`、`config/data_files.dart`、`hosts/app_hosts.dart` |
| `core/logging/` | `log_service.dart`（`LogService`） |
| `core/network/` | `dio_helper` `dio_manager` `dio_pretty_logger` `dot_env_util` `http_base_request` `http_method` `net_exceptions` `raw_content_url_resolver` |
| `core/utils/` | `app_settings` `app_version` `bloc_event` `error_message` `key_repeat_controller` `nim_manager` `platform_channel_service` `ptools_util` `wordpress_util` |
| `core/media/`（新） | `video_aspect_mode` `sleep_timer_controller`（原 `features/app/application/`） |
| `features/iptv/` | `application/`（7 个控制器 + bloc/event/state）、`data/`（asset_source / source_rules / api_service / m3u_parser / proxy_pool / repository_impl）、`domain/`（channel matcher / normalizer / model / repository） |
| `features/msg/` | `application/`（command_executor / overlay_controller / router / reporting_service）、`protocol/message_envelope.dart` |
| `features/remote/` | `application/bloc/`、`data/repositories/`、`domain/repositories/` |
| `features/time/` | `application/time_style_controller.dart`、`domain/lunar_calendar.dart` |
| `features/weather/` | `application/bloc/`、`data/`（convert / api_service / ip_geo / repository_impl）、`domain/`（models / repository） |

### 2.2 留在 `potatokid_screen`（宿主级外壳）

- `core/router/`（`AppRouter` / `RouteNames` / `route_params`）—— 每个 App 自己的路由树
- `core/di/`（`get_it` / `injection` / `modules/*`）—— DI 根归宿主所有
- `features/app/`（`app_bloc` / `app_tab_controller` / `main_app` 4-tab 壳）—— TV 专属
- `features/home/`（IPTV 首页）、`features/profile/`（我的）—— 按决策 2 丢弃
- `features/settings/presentation/pages/settings_sheet_page.dart` —— TV 专属设置弹层
- `shared/widgets/`（`auto_hide_chrome` / `confirm_dialog` / `exit_confirm_scope` / `floating_remote`）—— 均为 UI
- `features/*/presentation/` —— 全部 UI（TV 风格）

### 2.3 留在 `pscreen_home`（HA 专属）

- `core/network/ha_ws_client.dart` —— HA 唯一网络入口
- `core/network/ha_net_exceptions.dart`（由现有 `net_exceptions.dart` 重命名而来，见 §四）
- `app/config/app_config.dart`（`AS_HOST` / `AS_KEY` / `haWsUrl`）
- `core/storage/settings_store.dart`
- `features/connection/`、`features/home/`、`features/settings/`

### 2.4 边界判定规则

> **presentation 层不共享。** 共享包只允许出现 `data` / `domain` / `application` 三层 + `core`（基础设施）。

判据：该文件是否依赖宿主的外壳（路由、DI 根、Tab、主题、本地化资源）？依赖则留在宿主；否则可共享。

## 三、`pscreen_control` 并入 `pscreen_home`

`pscreen_control` 废弃，代码按职责拆入 `pscreen_home`：

| pscreen_control 原路径 | pscreen_home 新路径 | 说明 |
| --- | --- | --- |
| `features/send/application/send_cubit.dart` `send_state.dart` | `features/remote_control/application/` | 遥控面板状态机 |
| `features/send/data/tv_directory.dart` | `features/remote_control/data/` | 目标电视目录 |
| `features/send/presentation/` | `features/remote_control/presentation/` | 遥控面板 UI（含 `command_panel` / `target_picker`） |
| `features/admin/` | `features/remote_control/presentation/conversation/` | 会话列表 + 聊天页 |
| `features/scan/presentation/qr_scan_page.dart` | `features/remote_control/presentation/` | 扫码绑定目标电视 |
| `features/protocol/envelope_builder.dart` | **共享包** `features/msg/protocol/envelope_builder.dart` | 与解析器同源，防止协议漂移 |
| `core/nim_client.dart` | `features/remote_control/data/nim_client.dart` | 发送端 NIM 封装（宿主级） |
| `core/chat_message_item.dart` | `features/remote_control/domain/` | 消息模型 |
| `app/storage/app_settings.dart` | `features/remote_control/data/control_settings.dart` | 重命名，见 §四 |
| `app/utils/app_log.dart` | `features/remote_control/core/control_log.dart` | 重命名 `AppLog` → `ControlLog` |
| `app/config/app_config.dart` | `features/remote_control/core/control_config.dart` | 重命名 `AppConfig` → `ControlConfig` |
| `app/di/injection.dart` | 并入 `pscreen_home/lib/core/di/modules/remote_control_module.dart` | 注册项迁入宿主 DI |

**NIM 双角色**：`pscreen_home` 同时是**遥控发送端**（并入 pscreen_control 的能力）与**媒体播放端**（共享包的 IPTV 能力）。发送端 NIM 封装留在宿主（`NimClient`），接收端 NIM 封装（`NimManager`）在共享包内（`core/utils/nim_manager.dart`），两者 `nimAppKey` 已确认一致（`8e3cb3b1...`），`adminAccount` 均为 `1000001`。

## 四、命名冲突与重命名（7 处）

`pscreen_home` 将同时引入共享包与 `pscreen_control` 的类型名，以下为实测冲突清单：

| 冲突名 | 现状 | 处理 |
| --- | --- | --- |
| `AppConfig` | 共享包 / pscreen_control / pscreen_home **三处** | 共享包保持 `AppConfig`；pscreen_control 侧改名 `ControlConfig`；pscreen_home 保持 `AppConfig`（HA） |
| `AppSettings` | 共享包 `core/utils/app_settings.dart` vs pscreen_control `app/storage/app_settings.dart` | pscreen_control 侧改名 `ControlSettings` |
| `Injection` | pscreen_control `app/di/injection.dart` vs pscreen_home `core/di/injection.dart` | 删除 pscreen_control 的，注册项并入宿主 `remote_control_module.dart` |
| `LogService` | 共享包 vs pscreen_home | 内容一致（仅行尾差异）→ pscreen_home 删除本地副本，改用共享包 |
| `NetErrorType` / `NetExceptionX` | 共享包（Dio 语义）vs pscreen_home（HA 语义） | pscreen_home 侧改名 `HaErrorType` / `HaExceptionX`，文件改名 `ha_net_exceptions.dart` |
| `mapErrorToMessage` | 共享包（Dio 文案）vs pscreen_home（HA 文案） | pscreen_home 侧改名 `mapHaErrorToMessage` |
| `SettingsPage` | pscreen_control vs pscreen_home | pscreen_control 的 NIM 账号设置**并入** pscreen_home 现有设置页（新增分组），删除 pscreen_control 的页面 |

另：`bloc_event.dart` 两边内容完全一致 → pscreen_home 删除本地副本。

## 五、依赖 / 资产 / 配置合并

### 5.1 `pscreen_home/pubspec.yaml`

| 类别 | 依赖 |
| --- | --- |
| **共享包** | `pscreen_screen: {path: ../packages/pscreen_screen}` |
| **并入 pscreen_control 所需**（直接依赖） | `nim_core_v2: ^10.9.91`、`mobile_scanner: ^6.0.0`、`equatable: ^2.0.7`、`path_provider: ^2.1.6` |
| **随共享包传递**（无需重复声明，但需验证原生插件注册） | `media_kit` / `media_kit_video` / `media_kit_libs_video`、`dio` / `dio_cookie_manager` / `pretty_dio_logger` / `cookie_jar`、`connectivity_plus`、`crypto`、`intl`、`freezed_annotation` / `json_annotation`、`package_info_plus` |

**不引入**：

- `easy_localization` —— `pscreen_control` 实测 `.tr()` 调用数为 0，依赖实为未使用；`pscreen_home` 走纯中文硬编码
- `qr_flutter` / `restart_app` —— 实测**仅**被 `potatokid_screen` 的 `features/profile/presentation/pages/profile_page.dart` 使用，属 TV 专属 UI，不共享、不需要

### 5.2 资产

共享包的资产经 `packages/pscreen_screen/assets/...` 路径被宿主声明：

```yaml
flutter:
  assets:
    - .env
    - assets/icon/                       # 宿主原有
    - packages/pscreen_screen/assets/datas/
    - packages/pscreen_screen/assets/translations/
    - packages/pscreen_screen/assets/weather/
    - packages/pscreen_screen/assets/logo/
```

`assets/translations/` 仅 `potatokid_screen` 使用（easy_localization）；`pscreen_home` 声明无害（未被引用）。

### 5.3 `.env`

`pscreen_home/.env` 需并入屏幕侧键（`pscreen_home` 当前只有 `AS_HOST` / `AS_KEY`）：

```
BASE_URL  IS_DEBUG  ENABLE_PROXY  ENABLE_DEV_TOOLS
SENIVERSE_V3_KEY  SENIVERSE_WEATHER_HOST_V3  SENIVERSE_DEFAULT_LOCATION
SENIVERSE_PUBLIC_KEY  SENIVERSE_SECRET_KEY  SENIVERSE_WEATHER_HOST
SENIVERSE_IP_GEO_HOST  SENIVERSE_IP_GEO_HOST_B  WEATHER_CITIES  NIM_PASSWORD
```

`.env` 由宿主根资产提供，共享包的 `dot_env_util` 通过 `rootBundle.load('.env')` 读取宿主 `.env` —— 两个 App 各自持有自己的 `.env`，天然隔离。

### 5.4 依赖注入

两个 App 都使用 `GetIt.instance`（全局单例），无 DI 根冲突。共享包**不持有** DI 根，改为暴露注册入口：

```dart
// packages/pscreen_screen/lib/core/di/screen_modules.dart
class ScreenModules {
  const ScreenModules._();
  static Future<void> register(GetIt it) async {
    it.registerLazySingleton<LogService>(LogService.new);
    // ... 屏幕侧各 feature 的 repository / bloc / controller
  }
}
```

宿主 `Injection.init()` 中新增一步：

```dart
await ScreenModules.register(getIt);
```

顺序：宿主网络模块 → 存储模块 → `ScreenModules.register` → 宿主路由模块 → 宿主业务模块。

## 六、`pscreen_home` 路由与页面

扁平路由（无 tab 壳），`RouteNames` 新增 5 条：

| 路径 | 页面 | 职责 | 交互 |
| --- | --- | --- | --- |
| `/clock` | `ClockPage` | **充当屏保**：全屏沉浸、深色背景、大字号时钟 + 农历 + 天气摘要；无 AppBar | 触屏：点击返回 / 拖动切分钟 |
| `/live` | `LivePage` | IPTV 直播：频道列表 + 播放器 | 触屏：频道列表点击切换、播放器触屏控制条 |
| `/weather` | `WeatherPage` | 天气：当前 + 逐时 + 多日 | 触屏滚动 / 城市切换 |
| `/remote` | `RemoteControlPage` | **遥控面板 + 会话列表** 两 tab | 触屏按钮 / 扫码 / 聊天输入 |
| `/settings` | `SettingsPage`（扩展） | 现有 HA 设置 + 新增「遥控」分组（NIM 账号 / 令牌 / 目标电视） | 触屏 |

中控板 AppBar actions 调整为：

```
[时钟] [直播] [天气] [遥控] | [连接状态] [刷新] [设置]
```

页面 UI 为触屏自研，**不复用** `potatokid_screen` 的 TV 版页面；但直播/天气的数据与状态直接来自共享包的 bloc / repository。

## 七、交互差异处理

| 维度 | `potatokid_screen`（TV） | `pscreen_home`（触屏） |
| --- | --- | --- |
| 导航 | 焦点 / 方向键，4-tab 壳，遥控器 | 触屏点击，扁平路由 |
| 播放器控制 | 方向键 + 自动隐藏控制条 | 触屏控制条，显式常驻 |
| 页面留白 | 焦点高亮边框 | 无焦点态 |
| 主题 | light / dark 切换（`AppBloc`） | 强制 dark |
| 语言 | 4 语种（easy_localization） | 纯中文硬编码 |

共享包能力层**不含**任何主题 / 本地化 / 焦点依赖（实测：97 个非 presentation 文件中仅 2 处 `.tr()`，且均属宿主级 `app/app.dart` 与 UI widget）。

## 八、消息协议与 NIM 链路

`pscreen_control`（已并入 `pscreen_home`）→ NIM P2P → 电视端 `potatokid_screen`：

| 信封 | 语义 | 屏幕端处理 |
| --- | --- | --- |
| 任意非 `{` 开头文本 | plainText | 消息浮层显示 |
| `{"t":"txt","content":"..."}` | 文本 | 消息浮层显示 |
| `{"t":"cmd","name":"text","args":{"content":"..."}}` | 文本命令 | 消息浮层显示 |
| `{"t":"cmd","name":"volume_up" \| "volume_down" \| "mute"}` | 音量 | `MessageCommandExecutor` → `VolumeControl` |
| `{"t":"cmd","name":"channel","args":{"name":...} \| {"index":...}}` | 切台 | 频道名归一化匹配 → `LiveChannelController.select` |

上行：`ReportingService` 在登录成功时上报两条、每 5 分钟心跳、切台防抖 1 秒上报。

**共享包改造点**：`reporting_service.dart` 当前直接 import 宿主级 `features/app/application/app_tab_controller.dart`（TV 的 Tab 状态）。抽包时改为注入抽象：

```dart
abstract class CurrentSceneProvider {
  String describe();   // 例：'正在收看 CCTV-1' / '停留在中控台'
}
```

`potatokid_screen` 注入 Tab 实现，`pscreen_home` 注入中控台实现。

`features/msg/protocol/` 同时承载 `message_envelope.dart`（解析）与 `envelope_builder.dart`（构造），协议单点定义，杜绝遥控端与电视端格式漂移。

## 九、实施顺序（四个可独立验收的阶段）

| 阶段 | 内容 | 验收标准 |
| --- | --- | --- |
| **S1 抽包** | 建 `packages/pscreen_screen`，迁入 66 个文件，import 重写为 `package:pscreen_screen/...`；`potatokid_screen` 改为 path 依赖 | `potatokid_screen` 的 `flutter analyze` 零错误 + `flutter build windows` 通过（**现有发布产物不受影响**） |
| **S2 宿主接线** | `pscreen_home` 加 path 依赖 + 依赖合并 + `.env` / 资产合并 + DI 注册 + §四 重命名 | `pscreen_home` `flutter analyze` 零错误 + 现有中控台功能正常（回归） |
| **S3 遥控并入** | `pscreen_control` 代码迁入 `features/remote_control/`，`envelope_builder` 移入共享包，`RemoteControlPage` 两 tab | 遥控端可扫码绑定电视、发音量/切台/文本指令；电视端浮层与执行正常（端到端） |
| **S4 屏幕页面** | `pscreen_home` 新增时钟 / 直播 / 天气 三个触屏页 + AppBar 入口 + 设置页扩展 | 三个页面可用；中控板 AppBar 五个入口通达 |

阶段顺序不可调换：S1 是所有后续阶段的地基；S2 必须在 S3/S4 之前完成，否则 pscreen_home 会同时承载两套未验证的变更。

## 十、风险与验证点

| # | 风险 | 验证方式 |
| --- | --- | --- |
| 1 | path 依赖的原生插件（`media_kit` / `nim_core_v2` / `mobile_scanner` / `media_kit_libs_video`）在 `pscreen_home` 中未注册 | **S2 末尾**立即 `flutter build windows` 与 `flutter build apk --debug` 验证 |
| 2 | 依赖方的 `flutter: assets:` 不生效，翻译 / 数据文件 404 | `flutter build` 后检查 `build/flutter_assets/packages/pscreen_screen/` |
| 3 | `mobile_scanner` 需要相机权限：`AndroidManifest.xml` 加 `CAMERA`，iOS 加 `NSCameraUsageDescription` | 真机扫码验证（S3） |
| 4 | `media_kit` 在 `pscreen_home` 的 linux 平台无原生支持（`potatokid_screen` 无 linux 工程） | 明确 `pscreen_home` 的 linux 构建是否需要支持 media_kit；若需要则该平台排除直播页 |
| 5 | 共享包内 `freezed` 生成产物（`weather_models` / `home_model` 的 `.freezed.dart` / `.g.dart`）需随包提交 | 生成产物提交入库；注意 `pscreen_home/AGENT.md` §1 记载 freezed 3.2.5 在 Dart 3.13 上对含集合字段的模型生成非法的 `final` 构造参数（`extraneous_modifier`），沿用该规避方式 |
| 6 | `pscreen_home` 的 `mapErrorToMessage` / `NetErrorType` 重命名波及面 | 全仓 grep 校验，见 §四 |
| 7 | `pscreen_control` 的 `easy_localization` 依赖实为未使用 | 已实测 `.tr()` = 0，移除依赖后需 `flutter analyze` 复核 |
| 8 | `pscreen_control` 废弃后其 `main.dart` / 平台工程残留 | 保留目录作为回退路径，README 顶部标注「已废弃，代码已并入 pscreen_home」；**不删除**（删除无收益且失去回退路径） |

## 十一、不做的事（YAGNI）

- 不做 `pscreen_home` 的 tab 壳 / 底部导航（决策 3）
- 不做屏保页面（决策 4，时间页充当）
- 不迁 `potatokid_screen` 的 `features/home`（IPTV 首页）与 `features/profile`（决策 2）
- 不给 `pscreen_home` 引入多语言与主题切换（决策 9）
- 不迁 `pscreen_control` 的独立发布形态（废弃）
- 不重构 `potatokid_screen` 的 4-tab 外壳与 TV 交互
- 不做 `packages/` 之外的第三个宿主 App
