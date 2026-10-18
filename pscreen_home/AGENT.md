# pscreen_home 项目架构大纲（AGENT.md）

> 本文件供 AI 工具自动读取，用于理解本项目的架构约定。
> 任何新功能开发、重构、修改，请严格遵循本文档描述的分层、命名与代码组织方式。
> 架构与 `potatokid_screen` 同源（见其 AGENT.md），网络层按 Home Assistant 场景替换为 WebSocket。

---

## 0. 架构来源与总原则

本项目为「链接 Home Assistant 的中控屏」：主页快捷控件点按控制设备，后续扩展房间/设备树浏览。

| 能力 | 来源 | 说明 |
| --- | --- | --- |
| 路由（Routing） | **potatokid_screen** | GoRouter + `AppRouter` + `RouteNames` |
| 状态机（State Machine） | **potatokid_screen** | `flutter_bloc` 的 Event / State / Bloc 三段式 |
| 依赖注入（DI） | **potatokid_screen** | `get_it` + 手写 Module 注册（`Injection` 门面） |
| 网络访问（Network） | **本项目自研** | `HaWsClient`（core/network）：HA WebSocket 唯一网络入口 |

**核心组合方式：**

- 状态管理统一使用 **BLoC**（Event → Bloc → State，禁用 GetX）。
- 网络层统一使用 **`HaWsClient`**：Home Assistant 是 WebSocket 优先（认证、请求、事件订阅、服务调用全走 WS），
  不引入 Dio；REST 备用通道暂不需要。
- 衔接点在 **Repository**：Repository 构造并调用 `HaWsClient`，捕获网络异常并转换为领域模型/结果，再交由 Bloc 更新 State。

**分层原则（Clean Architecture，按 feature 纵向切分）：**

```
Presentation  →  Application(Bloc)  →  Domain(Repository 接口 + 领域模型)  →  Data(Repository 实现)
```

依赖方向永远单向向内，禁止反向依赖（如 data 里 import presentation）。

---

## 1. 技术栈与依赖

```yaml
dependencies:
  go_router: ^17.5.0            # 路由
  flutter_bloc: ^9.1.1          # 状态机
  get_it: ^9.3.0                # 依赖注入
  flutter_dotenv: ^6.0.1        # .env（AS_HOST / AS_KEY）
  web_socket_channel: ^3.0.0    # Home Assistant WebSocket
  shared_preferences: ^2.3.0    # 手动 HA 地址 / 令牌持久化（优先于 .env）

dev_dependencies:
  flutter_lints: ^6.0.0
```

**关于 freezed：** potatokid_screen 约定复杂模型用 freezed 生成，但 freezed 3.2.5 在 Dart 3.13 下
对「含集合字段的模型」生成非法的 `final` 构造参数（`extraneous_modifier` 错误）。
因此本项目模型**暂手写**（不可变 + `copyWith` + `fromJson`，见 `weather_models` 风格）；
升级 freezed 4.x 验证通过后再恢复代码生成。

**Dart 3.13 约定：** 构造函数依赖注入统一用**私有命名参数**（`required this._repository`，调用方仍传
`repository:`），避免 `prefer_initializing_formals` / `type_init_formals` lint。

---

## 2. 目录结构

```
lib/
├── main.dart                          # 应用入口（启动顺序见第 8 节）
├── app/
│   ├── app.dart                       # MaterialApp.router 根组件（中控屏固定暗色主题）
│   └── config/app_config.dart         # AS_HOST / AS_KEY / haWsUrl 规范化
├── core/
│   ├── router/
│   │   ├── app_router.dart            # GoRouter 封装（initialize 必须在 runApp 前）
│   │   └── route_names.dart           # 路由路径常量，禁止硬编码
│   ├── storage/
│   │   └── settings_store.dart        # 本地持久化：手动 HA 地址 / 令牌（覆盖 .env）
│   ├── di/
│   │   ├── get_it.dart                # 全局 getIt 实例
│   │   ├── injection.dart             # 门面：按序编排 Module 注册/注销
│   │   └── modules/
│   │       ├── network_module.dart    # LogService + HaWsClient
│   │       ├── storage_module.dart    # SettingsStore（依赖 LogService，需在其后）
│   │       ├── router_module.dart     # AppRouter
│   │       ├── connection_module.dart # 连接 feature
│   │       └── home_module.dart       # 主页 feature
│   ├── logging/log_service.dart       # 统一日志：Injection.get<LogService>()
│   ├── network/
│   │   ├── ha_ws_client.dart          # ★ HA WebSocket 客户端（协议层，唯一网络入口）
│   │   └── net_exceptions.dart        # HaXxx 异常 + NetErrorType 映射
│   └── utils/
│       ├── bloc_event.dart            # completeBlocEvent（事件回传 Completer）
│       └── error_message.dart         # 异常 → 可展示文案
├── features/                          # 业务功能，按 feature 纵向切分
│   ├── connection/                    # 连接状态机（连接阶段 + 重试）
│   │   ├── application/bloc/          # connection_{bloc,event,state}.dart
│   │   ├── domain/repositories/       # ConnectionRepository（纯抽象）
│   │   └── data/repositories/         # ConnectionRepositoryImpl
│   └── home/                          # 主页（中控台）
│       ├── presentation/
│       │   ├── pages/
│       │   │   ├── home_controll_board.dart    # 主页（家庭 ▸ 房间筛选 + 设备网格）
│       │   │   └── device_detail_page.dart     # 设备详情页（逐实体控制）
│       │   └── components/            # light/climate_widget、device_widget、value_widget、*_control_panel
│       ├── application/bloc/          # home_{bloc,event,state}.dart
│       ├── domain/
│       │   ├── models/ha_entity_state_model.dart   # 实体状态模型（手写不可变）
│       │   ├── models/ha_registry_model.dart       # 注册表模型（家庭/房间/设备/实体归属）
│       │   ├── models/ha_device_group.dart         # 设备分组模型（同设备实体合并成卡）
│       │   ├── models/home_climate_summary.dart    # 家庭温湿度概览（来自 climate 传感器）
│       │   ├── models/washer_summary.dart          # 洗衣机摘要（switch/select/sensor/button 组合）
│       │   ├── models/kettle_summary.dart          # 电热水瓶摘要（select/number/switch/notify 组合）
│       │   ├── models/fan_summary.dart             # 风扇摘要（fan + 关机延时 number）
│       │   ├── models/projector_summary.dart       # 投影仪摘要（button/number/select/notify）
│       │   ├── models/fridge_summary.dart          # 冰箱摘要（三舱温度 + 模式）
│       │   ├── models/water_heater_summary.dart    # 热水器摘要（water_heater + 预热/状态实体）
│       │   ├── models/water_heater_schedule.dart   # 定时预热 5 槽位编码/解析
│       │   ├── models/water_usage_record.dart      # 单次用水记录（event 历史）
│       │   └── repositories/          # HomeRepository（纯抽象）
│       └── data/repositories/         # HomeRepositoryImpl
│   └── settings/                       # 设置（HA 连接配置）
│       └── presentation/pages/settings_page.dart   # 地址 / 令牌表单（复用 ConnectionBloc）
└── shared/                            # 跨 feature 公共组件（暂空，按需创建）
```

---

## 3. 路由架构

- 所有路径集中在 `RouteNames`，业务代码禁止硬编码路径。
- `AppRouter.initialize()` 异步初始化，**必须在 `runApp` 前 await**；未初始化访问 `router` 抛 `StateError`。
- 当前路由：`home = '/'`（HomeControllBoard）、`home` 子路由 `device/:deviceId`
  （DeviceDetailPage，完整路径经 `RouteNames.deviceDetailPath(id)` 拼接）、
  `home` 子路由 `settings`（SettingsPage，`RouteNames.settingsPath`）。
  新增页面时在 `RouteNames` 加常量 → `AppRouter._buildRoutes()` 注册 `GoRoute` → 页面入 `presentation/pages/`。
- 多 Tab 外壳需要时再引入 `StatefulShellRoute.indexedStack`（参考 potatokid_screen 第 3.4 节）。

---

## 4. 状态机 / 状态管理（BLoC 三段式）

### 4.1 Event — `application/bloc/<feature>_event.dart`

- 所有事件继承抽象基类 `<Feature>Event`。
- 需要「等待事件完成」的事件，携带 `final Completer<bool>? completer;`，
  处理器末尾用 `completeBlocEvent(event.completer, success: ...)` 回传。

### 4.2 State — `application/bloc/<feature>_state.dart`

- 不可变状态类：私有构造 + 命名工厂（`initial()` / `fromInfo()` 等）+ `copyWith`。
- 集合字段默认 `const <K, V>{}`，所有字段给默认值。
- 错误字段：`errorMessage` + `errorType`（`NetErrorType`），`copyWith(clearError: true)` 清除。

### 4.3 Bloc — `application/bloc/<feature>_bloc.dart`

- 构造函数注入 Repository（DI 提供，禁止在 Widget 里 new）：`HomeBloc({required this._repository})`。
- `on<Event>(_handler)` 注册处理器，签名为 `Future<void> _onXxx(Event e, Emitter<State> emit)`。
- 订阅仓库流的 Bloc 必须在 `close()` 中取消订阅。
- 捕获异常：写日志 `Injection.get<LogService>().error(...)`，
  `mapErrorToMessage(e)` 写入 `errorMessage`，`e.toNetErrorType()` 写入 `errorType`。

### 4.4 UI 消费

- `BlocBuilder` 渲染、`BlocListener` 副作用（SnackBar、加载数据）、
  `listenWhen` 过滤重复触发（示例见 HomeControllBoard：连接从非就绪→就绪时 `LoadHome`）。

### 本项目两个状态机

| 状态机 | 职责 | 关键事件 |
| --- | --- | --- |
| `ConnectionBloc` | 连接阶段（连接中/认证中/就绪/失败/重连中） | `StartConnection` / `RetryConnection` / `Reconnect`（配置变更：先断开再连） / `ConnectionInfoChanged` |
| `HomeBloc` | 实体状态缓存 + 快捷控件操作 + 家庭/房间筛选 | `LoadHome` / `EntityStateChanged` / `ToggleEntity` / `SetLightBrightness` / `SetLightColorTemperature` / `SetLightEffect` / `SetClimateTemperature` / `SetClimateHvacMode` / `SetClimateFanMode` / `SetClimateSwingMode` / `PressEntityButton` / `SelectEntityOption` / `SetWaterHeaterTemperature` / `SetWaterHeaterOperationMode` / `SetTextEntityValue` / `SetNumberEntityValue` / `PressNotifyAction` / `HomeSelected` / `AreaSelected` / `ClearHomeError` |

---

## 5. 依赖注入（get_it + 手写 Module）

- 全局入口 `core/di/get_it.dart` 的 `getIt`；业务统一 `Injection.get<T>()`。
- 每个 feature 一个 Module（`register()` / `unregister()` 成对），
  注册顺序 **Repository → Bloc**；`Injection.init()` 顺序：
  `NetworkModule → RouterModule → ConnectionModule → HomeModule`（reset 逆序）。
- 全局 Bloc 在 `main.dart` 的 `MultiBlocProvider` 中通过 `Injection.get<Bloc>()` 提供；
  局部 Bloc 用 `BlocProvider.value`。

---

## 6. 网络访问架构（Home Assistant WebSocket）

**`core/network/ha_ws_client.dart` 是整个应用唯一的网络入口**，职责：

1. **连接 + 认证**：连 `ws(s)://<AS_HOST>/api/websocket` → 收 `auth_required` → 发
   `{"type":"auth","access_token":AS_KEY}` → 等 `auth_ok`。
2. **请求-响应**：`request(type, params)` 自增 `id` 与 `Completer` 配对，
   15s 超时抛 `HaRequestException`；返回**完整结果消息**（`success` / `result` / `error`），
   调用方自行取 `result`。
3. **事件推送**：连接就绪后自动 `subscribe_events(state_changed)`，原始 `new_state` JSON
   经 `stateChanged` 流下发，由 feature 的 data 层反序列化为领域模型。
4. **自动重连**：断线指数退避（1s → 2s → 4s → 8s → 16s → 30s 封顶）；
   `authFailed`（令牌无效/未配置）**不重试**，由页面提供手动重试。
   连接代次（`_generation`）保证旧连接回调失效，杜绝竞态。
5. **服务调用**：`callService(domain, service, entityId?, serviceData?)` →
   WS `call_service`，实体通过 `target: {entity_id}` 指定（已验证可用）。

**异常体系**（`net_exceptions.dart`）：

| 异常 | 含义 | NetErrorType |
| --- | --- | --- |
| `HaDisconnectException` | 断网 / 连接关闭 | disconnect |
| `HaAuthException` | 令牌无效 | authError |
| `HaRequestException` | 请求失败 / 超时（含 HA 业务错误） | requestError |
| `HaDataException` | 响应结构异常 | dataError |

**错误 → 状态**：Bloc 统一 `catch` → `mapErrorToMessage(e)` + `e.toNetErrorType()` → State → 页面渲染。

---

## 7. 数据流转全链路（点击快捷控件）

```
[UI] LightWidget.onTap
   │ context.read<HomeBloc>().add(ToggleEntity(entityId))
   ▼
[Bloc] HomeBloc._onToggleEntity
   │ 乐观更新：state.entities[id].state 翻转 + togglingIds 加入
   │ await _repository.setEntityPower(entityId, turnOn)
   ▼
[Domain] abstract HomeRepository.setEntityPower()
   ▲ (DI 注入实现)
   ▼
[Data] HomeRepositoryImpl → domain = entityId 前缀（light/switch）
   │ await _client.callService(domain, turn_on/turn_off, entityId)
   ▼
[Network] HaWsClient.callService → request('call_service', {...})
   │ 成功：移除 togglingIds
   │ 失败：回滚乐观状态 + errorMessage（页面 SnackBar）
   ▼
[事件回流] HA 推送 state_changed → HaWsClient.stateChanged
   → HomeRepositoryImpl.watchStateChanges() → HomeBloc._onEntityStateChanged
   → 实体状态被真实值校准 → UI 自动刷新
```

---

## 8. 应用启动流程 — `main.dart`

```dart
void main() {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppConfig.initialize();        // 1. 加载 .env 默认值（AS_HOST / AS_KEY）
    await Injection.init();              // 2. 依赖注入（网络、存储、路由、业务模块）
    AppConfig.applyOverrides(            // 3. 应用持久化的手动配置（空则回落 .env）
      host: Injection.get<SettingsStore>().hostOverride,
      token: Injection.get<SettingsStore>().tokenOverride,
    );
    await Injection.get<AppRouter>().initialize();  // 4. 路由（必须在 runApp 前）
    runApp(                              // 5. 启动
      MultiBlocProvider(
        providers: [
          BlocProvider<ConnectionBloc>(
            create: (_) => Injection.get<ConnectionBloc>()..add(const StartConnection()),
          ),
          BlocProvider<HomeBloc>(create: (_) => Injection.get<HomeBloc>()),
        ],
        child: const App(),
      ),
    );
  }, (error, stack) { FlutterError.presentError(...); });
}
```

**顺序不可颠倒：** `Injection.init()` → `AppConfig.applyOverrides()` → `AppRouter.initialize()` → `runApp`。
连接由 `StartConnection` 触发；连接就绪后页面（BlocListener）派发 `LoadHome`，
**重连成功会再次触发 `LoadHome`** 自动恢复数据。

**连接配置两层结构**（设置页见第 3 节路由）：
生效值 = `SettingsStore` 持久化覆盖 > `.env` 默认值（`AppConfig` 计算）。
设置页保存后若生效值变化 → `ConnectionBloc` 发 `Reconnect`
（**必须先 `disconnect` 再 `connect`**，`HaWsClient.connect` 在已连接时幂等返回）→
就绪后主页自动 `LoadHome` 刷新。清空输入保存 = 删除覆盖回落 `.env`。

---

## 9. 命名与编码规范

- **导入路径**：统一 `package:pscreen_home/...` 绝对导入，禁止相对导入；
  顺序 `dart:` → `package:flutter/` → 第三方 → 本项目。
- **文件命名**：`snake_case.dart`；Bloc 三件套固定 `<feature>_{bloc,event,state}.dart`。
- **类命名**：PascalCase；Event 用动词（`ToggleEntity`），State 用名词（`HomeState`），
  Repository 接口无后缀、实现加 `Impl`。
- **注释**：中文，公共类/方法写清职责；**不加无意义行内注释**。
- **不可变**：State / Model 一律不可变，通过 `copyWith` 更新。
- **禁止**：Widget 内直接 new Repository / Bloc（必须走 DI）；data 层 import presentation。
- **配置安全**：`.env` 含 HA 长期令牌，**已列入 .gitignore，禁止提交**。
- 若与 material 同时 import 产生命名冲突（如 `ConnectionState`），
  在 material 导入上 `hide ConnectionState` 解决。

---

## 10. AI 开发指引（新增一个 Feature 的标准步骤）

1. 建目录 `lib/features/<feature>/{presentation,application,domain,data}`。
2. 领域模型写 `domain/models/xxx_model.dart`（手写不可变 + `fromJson` + `copyWith`，见第 1 节 freezed 说明）。
3. 定义 Repository 接口 `domain/repositories/xxx_repository.dart`（纯抽象）。
4. 实现 `data/repositories/xxx_repository_impl.dart`：调 `HaWsClient`，捕获网络异常。
5. 写 Event（需要等待的加 `Completer<bool>?`）、State（不可变 + copyWith）、Bloc（注入 Repository）。
6. 写 DI Module `core/di/modules/<feature>_module.dart`，并在 `Injection` 中按序挂载。
7. 新增路由：`RouteNames` 加常量 → `AppRouter._buildRoutes()` 注册。
8. 写页面 `presentation/pages/xxx_page.dart`，用 `BlocBuilder`/`BlocListener` 消费。
9. 验证：`flutter analyze`（必须零问题）→ `flutter test` → `flutter run -d windows`。

---

## 11. 关键约定速查表

| 场景 | 约定 |
| --- | --- |
| 状态管理 | `flutter_bloc` 三段式，禁用 GetX |
| 路由 | GoRouter，路径常量进 `RouteNames` |
| 依赖注入 | get_it + 手写 Module，业务用 `Injection.get<T>()` |
| 网络入口 | `HaWsClient`（WS），服务调用用 `callService` + `target` |
| 状态订阅 | 连接就绪自动 `subscribe_events(state_changed)` |
| 断线重连 | 客户端内建指数退避；authFailed 不自动重试 |
| 网络异常 | `HaDisconnect/Auth/Request/DataException` → `NetErrorType` |
| 错误展示 | Bloc 捕获 → `mapErrorToMessage` → State → 页面渲染 |
| 模型 | 手写不可变（freezed 待升级后恢复） |
| 导入 | `package:pscreen_home/...` 绝对导入 |

---

## 12. 路线图（原构想注释的归档）

- **M0 ✅** 连通性：`.env` + WS 认证 + `get_states` + 注册表 + `call_service` 验证。
- **M1 ✅** 最小闭环：连接状态机 + 实体状态机 + 全部 light/switch 快捷控件网格（点击开关闭环）。
- **M2 ✅ 家庭 ▸ 房间 两级分组 + 设备合并成卡**：
  - **家庭层级**：HA 无独立家庭表（floor / label 注册表均为空），按约定
    **区域名 = `家庭名 房间名`** 解析（`HaArea.homeName / roomName`，首个空格切分，
    **家庭名不能含空格**）；顶部家庭标签行 + 房间标签行受其筛选。
  - **房间归属**：`config/{area,device,entity}_registry/list` 组装 `HaRegistry`
    （归属规则：实体自身 area_id > 所属设备 area_id）；卡片标注「状态 · 房间」
    （选中家庭时用短房间名，否则用完整区域名）。
  - 容错：注册表拉取失败降级为空、所选家庭/房间失效自动回退「全部」、
    仅展示含可控实体的家庭与房间（后缀为数量）。
  - **设备合并**（Mi Home 风格）：同 `device_id` 的可控实体合并为一张卡
    （`HaDeviceGroup.group`，234 个可控实体 → 24 张卡）；
    **外层卡片** = 设备名 + 聚合状态（`已开启 2/9 · 房间`）+ 电源快捷键
    （只切**主实体**）；**点卡片进详情页** `/device/:deviceId` 逐实体控制。
    - 主实体权重：真灯(0) > switch(1) > 指示灯/夜灯/氛围灯类 light(2)，
      同权重按显示名排序（主实体永远排组内首位）。
    - 房间/家庭角标按**设备卡数**计（同设备多实体只计一次），与网格所见一致。
    - 无设备归属（注册表降级）自成一卡且点击即开关，功能不受影响。
  剩余：区域 ▸ 设备 ▸ 实体 三级浏览页 + 名称过滤（原 `home_assistant_register.dart` 构想）。
- **M3** 首页布局（原 `home_controll_board.dart` 构想）：第一行常用设备横向列表，
  第二行房间标签切换；`light_widget` / `button_widget` 按 domain 扩展 cover/climate/media_player 等。
  - **✅ 灯 / 空调卡片与详情面板**：首页灯卡带亮度滑条（多实体设备卡同样支持），
    空调卡带目标温度加减与电源键；详情页灯面板支持亮度 / 色温 / 灯光效果，
    空调面板支持圆形温度盘、模式、风速、摆风。参数全部来自实体属性
    （`brightness` / `color_temp_kelvin` / `effect_list` / `hvac_modes` /
    `fan_modes` / `swing_modes`），不支持的项目自动隐藏。
  - **✅ 家庭温湿度概览**：首页顶部按家庭展示温度 / 湿度（未选家庭显示全部，
    选中后只显示该家庭 + 「全部」返回）。HA 无「全屋温湿度」聚合实体，
    数据取家庭内 climate 的 `current_temperature` / `current_humidity`，
    优先选同时具备温湿度的设备；缺失项不渲染。
  - **✅ 洗衣机卡片**：按设备聚合 12kg / 10kg 洗衣机实体（状态、模式、
    剩余时间、累计水电、启动/暂停/停止），主开关强制取
    `switch.*_on`，避免选中「提示音 / 静音」。摘要按实体 id 的 MIoT 属性
    后缀（`_status_p_2_2` / `_mode_p_2_3` / `_start_wash_` …）识别，不依赖
    friendly_name；10kg 没有「运行状态」时用 `stroke`，没有水电统计时隐藏统计行。
  - **✅ 热水器卡片**：`water_heater` 主实体（目标温度 35-65℃、洗浴模式）
    + 工作状态 / 进水温度 / 水流量 / 预热 / 定时预热；首页卡支持目标温度
    加减，详情面板支持温度滑条、模式选择与预热开关。状态、故障、进水温度、
    水流量、预热、定时表、使用记录均按实体 id 后缀识别，不依赖 friendly_name。
  - **✅ 热水器使用记录 / 定时设置**：使用记录用
    `history/history_during_period` 拉 `event.*_usage_record` 历史，按周/月/年
    聚合用水、用气与次数并画柱状图；定时设置解析并写回
    `text.*_preheat_timer` 的 `类型&开始&结束&开关&id` 五槽位编码串。
    重复类型暂支持仅一次 / 每天。
  - **✅ 全实体展示**：首页网格与详情页不再只显示可控实体；同一设备下的
    sensor / binary_sensor / button / event / 不可用实体也参与分组。
    非可控实体用 `ValueWidget` 静态展示值或「暂不支持操作」，按
    `HaDomainIcons` 取图标；纯数据设备 `HaDeviceGroup.primary` 为 null，
    不显示电源键；组内全部不可用时整卡置灰。
  - **✅ 风扇卡片**：模式（直吹风 / 睡眠风 / 自然风 / 循环风）、风速、左右摆风、
    延时关闭；普通风扇按三挡（33/66/100），风扇灯按 `percentage_step=1`
    走无级调速（1-100）。延时兼容 `_off_delay_time_p_2_10`（0-480 分钟）
    和 `_delay_time_p_6_2`（0-720 分钟）。首页卡显示模式 / 档位 / 摆风与电源，
    详情页用 `fan.set_preset_mode` / `fan.set_percentage` / `fan.oscillate`。
  - **✅ 投影仪卡片**：坚果投影仪在 HA 里没有 media_player，拆成开机/关机
    button、音量/亮度 number、输入源 select、应用列表 sensor、打开应用 notify；
    卡片显示当前应用 / 输入源、音量和亮度，详情页提供应用快捷入口、输入源、
    音量、亮度、静音、播放控制。开关机状态用 devicestartup / deviceshutdown
    事件时间推断；开关机走 `button.press`，打开应用走 notify 的 YAML 包名列表。
    虚拟遥控按 MIoT `virtual-remote.press-button` 的按键类型发送
    `[0/1/2/3/4/5/6/7/8/9/10/11/12/13]`；没有数字键，无法输入数字。
    遥控面板按宽度自适应：宽屏左右分栏（左侧方向盘，右侧电源/设置/对焦/音量），
    窄屏竖排。
  - **✅ 冰箱卡片 / 详情**：冷藏、冷冻、变温三舱当前温度 + 目标温度 + 模式
    （手动/智能/速冷/速冻）；详情页支持三舱目标温度加减、模式切换、
    环境温湿度 / 运行时长 / 开门次数。冰箱没有总电源，常驻运行；食材管理
    是米家云端数据，HA 未暴露，详情页只做说明。
  - **✅ 风扇灯组合**：同一设备同时有 `light.*` 和 `fan.*` 时用组合卡
    （灯亮度 + 风扇模式/档位），卡片快捷开关和详情页第一行都用
    `switch.*_all_on_p_10_1` 总开关；详情页同时渲染总开关、风扇面板和灯光面板。
  - **✅ 电热水瓶卡片**：当前水温 / 状态 / 内置模式（自来水、纯净水、凉白开）
    / 设定温度 / 保温温度 / 除氯 / 风冷 / 童锁状态；首页卡和详情页均用文字
    按钮：未运行「加热」、加热中「停止加热」、保温/降温「停止保温」。
    开始加热走 `notify.send_message`（message 为 8 项 YAML 参数列表：模式id、设定温度、
    保温、保温温度、除氯、风冷、纯净水保温温度、自来水保温温度），
    停止走 `button.press`。模式差异：纯净水加热到纯净水保温温度（66℃）、
    显示保温；自来水加热到沸点并显示自来水保温温度（51℃）、除氯；
    凉白开加热到沸点，不显示保温 / 保温温度。米家的扩展模式定义在
    云端，HA 只有 `text.*_mode_id`，不做自定义模式管理。
- **M4** 配置持久化：~~设置页 HA 地址 / 令牌（shared_preferences，优先于 .env，清空回落）~~ **✅ 已实现**（`SettingsStore` + 设置页 + `Reconnect` 刷新）；剩余：常用实体勾选（shared_preferences）、断网横幅、乐观更新确认超时回滚。
- **M5** 部署：屏幕常亮（wakelock）、开机自启、kiosk 模式（按目标设备选型）。
