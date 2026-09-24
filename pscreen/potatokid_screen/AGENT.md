# potatokid_screen 项目架构大纲（AGENT.md）

> 本文件供 AI 工具自动读取，用于理解本项目的架构约定。
> 任何新功能开发、重构、修改，请严格遵循本文档描述的分层、命名与代码组织方式。

---

## 0. 架构来源与总原则

本项目为全新 Flutter 项目，架构由两个成熟项目的能力组合而来：

| 能力 | 来源 | 说明 |
| --- | --- | --- |
| 路由（Routing） | **BetterLove** | GoRouter + `AppRouter` + `RouteNames` + 类型安全 `RouteParams` + `StatefulShellRoute` |
| 状态机（State Machine） | **BetterLove** | `flutter_bloc` 的 Event / State / Bloc 三段式 |
| 依赖注入（DI） | **BetterLove** | `get_it` + 手写 Module 注册（`Injection` 门面） |
| 网络访问（Network） | **mystic_app / myStar** | `DioManager` 单例 + `HttpBaseRequest` 网络访问基类 + 自定义异常体系 |

**核心组合方式：**

- 状态管理统一使用 **BLoC**（不使用 GetX 作为状态管理）。
- 网络层统一使用 **myStar 的 `DioManager` + `HttpBaseRequest`**（不使用 BetterLove 的 `DioClient` + 多拦截器方案）。
- 二者衔接点在 **Repository**：Repository 内构造并调用 `HttpBaseRequest` 子类，捕获网络异常并转换为领域结果，再交由 Bloc 更新 State。

**分层原则（Clean Architecture，按 feature 纵向切分）：**

```
Presentation  →  Application(Bloc)  →  Domain(Repository 接口)  →  Data(Repository 实现 + API Request + Model)
```

依赖方向永远单向向内，禁止反向依赖（如 data 里 import presentation）。

---

## 1. 技术栈与依赖

`pubspec.yaml` 需引入以下依赖（当前为空白模板，需补齐）：

```yaml
dependencies:
  flutter:
    sdk: flutter
  # 路由
  go_router: ^13.0.0
  # 状态机
  flutter_bloc: ^8.1.3
  bloc_concurrency: ^0.2.5
  # 依赖注入
  get_it: ^7.6.4
  # 网络
  dio: ^5.4.0
  dio_cookie_manager: ^3.1.1
  cookie_jar: ^4.0.8
  connectivity_plus: ^6.0.0
  flutter_dotenv: ^5.1.0
  path_provider: ^2.1.0
  # 数据模型 / 序列化
  freezed_annotation: ^2.4.1
  json_annotation: ^4.9.0
  # 国际化
  easy_localization: ^3.0.3
  intl: ^0.19.0

dev_dependencies:
  build_runner: ^2.4.9
  freezed: ^2.5.2
  json_serializable: ^6.8.0
  mockito: ^5.4.4
  flutter_lints: ^6.0.0
```

**代码生成命令：**

```bash
dart run build_runner build --delete-conflicting-outputs   # 生成 .freezed.dart / .g.dart
dart run build_runner watch --delete-conflicting-outputs    # 开发期监听
```

---

## 2. 目录结构

```
lib/
├── main.dart                          # 应用入口
├── app/
│   ├── app.dart                       # MaterialApp.router 根组件
│   ├── hosts/app_hosts.dart           # 域名/环境配置（来自 myStar）
│   └── config/                        # EnvConfig、AppConstants
├── core/
│   ├── router/                        # ← BetterLove 路由
│   │   ├── app_router.dart
│   │   ├── route_names.dart
│   │   └── route_params.dart
│   ├── di/                            # ← BetterLove 依赖注入
│   │   ├── get_it.dart
│   │   ├── injection.dart
│   │   └── modules/
│   │       ├── network_module.dart
│   │       ├── router_module.dart
│   │       └── <feature>_module.dart
│   ├── network/                       # ← myStar 网络层
│   │   ├── dio_manager.dart           # 单例网络访问入口
│   │   ├── http_base_request.dart     # 网络访问基类
│   │   ├── net_exceptions.dart        # 自定义异常
│   │   ├── dio_helper.dart            # 代理 / Charles 抓包
│   │   └── dot_env_util.dart          # 环境开关
│   └── utils/                         # 通用工具（日志、扩展等）
├── features/                          # 业务功能，按 feature 纵向切分
│   └── <feature>/
│       ├── presentation/
│       │   ├── pages/                 # 页面（对应一个路由）
│       │   └── components/            # 该 feature 私有组件
│       ├── application/
│       │   └── bloc/
│       │       ├── <feature>_bloc.dart
│       │       ├── <feature>_event.dart
│       │       └── <feature>_state.dart
│       ├── domain/
│       │   └── repositories/          # 抽象接口（只定义方法签名）
│       └── data/
│           ├── models/                # freezed 数据模型
│           ├── repositories/          # 接口实现（Impl）
│           └── datasources/remote/    # HttpBaseRequest 子类（接口定义）
└── shared/
    ├── themes/                        # 主题
    └── widgets/                       # 跨 feature 公共组件
```

---

## 3. 路由架构（来自 BetterLove）

### 3.1 路由名称常量 — `core/router/route_names.dart`

所有路由路径统一在 `RouteNames` 中集中管理，禁止在业务代码中硬编码路径字符串。

```dart
class RouteNames {
  static const String splash = '/splash';
  static const String home = '/';
  static const String messages = '/messages';
  static const String profile = '/profile';
  static const String profileEdit = '/profile/edit';
  // ... 其余路由
}
```

### 3.2 类型安全路由参数 — `core/router/route_params.dart`

路由参数继承抽象基类 `RouteParams`，每个参数类实现 `toMap()`，并提供 `factory XxxParams.fromMap(Map<String, dynamic>)`。

```dart
abstract class RouteParams {
  const RouteParams();
  Map<String, dynamic> toMap();
}

class ProfileEditParams extends RouteParams {
  final String? userId;
  const ProfileEditParams({this.userId});

  @override
  Map<String, dynamic> toMap() => {'userId': userId};

  factory ProfileEditParams.fromMap(Map<String, dynamic> map) =>
      ProfileEditParams(userId: map['userId'] as String?);
}
```

**参数传递约定：** 通过 `GoRouter` 的 `state.extra` 传递。页面构建时做类型兼容解析：

```dart
final params = state.extra is ProfileEditParams
    ? state.extra as ProfileEditParams
    : ProfileEditParams.fromMap(state.extra as Map<String, dynamic>);
```

### 3.3 路由核心 — `core/router/app_router.dart`

`AppRouter` 封装 `GoRouter`，提供：

- `Future<void> initialize()`：异步初始化（自动登录 / 引导判断 → 决定 `initialLocation`），**必须在 `runApp` 前 `await`**。
- `GoRouter get router`：未初始化时访问抛 `StateError`。
- 全局 `navigatorKey` 与 `RouteObserver`。
- 导航封装方法：`go / goNamed / push / pushNamed / pop / refresh / canPop / isCurrentRouteName`。
- **类型安全导航方法**：为需要传参的页面提供强类型方法，如 `pushProfileEdit(ProfileEditParams params)`。

```dart
class AppRouter {
  GoRouter? _router;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  Future<void> initialize() async {
    if (_router != null) return;
    bool couldAutoLogin = /* 自动登录判断 */ false;
    _router = _createRouter(couldAutoLogin);
  }

  GoRouter get router {
    if (_router == null) {
      throw StateError('AppRouter has not been initialized. Call initialize() first.');
    }
    return _router!;
  }

  void pushNamed(String name, {Object? extra}) =>
      router.pushNamed(name, extra: extra);

  void pushProfileEdit(ProfileEditParams params) =>
      pushNamed(RouteNames.profileEdit, extra: params);
}
```

### 3.4 Tab 外壳 — `StatefulShellRoute.indexedStack`

底部导航的多个 Tab 使用 `StatefulShellRoute.indexedStack` + 每 Tab 一个 `StatefulShellBranch`，配合 `IndexedStack` 保持各 Tab 页面状态与滚动位置（与 Bloc TTL 缓存配合）。

```dart
StatefulShellRoute.indexedStack(
  builder: (context, state, navigationShell) =>
      MainApp(navigationShell: navigationShell),
  branches: [
    StatefulShellBranch(routes: [
      GoRoute(
        path: RouteNames.home,
        name: RouteNames.home,
        pageBuilder: (context, state) =>
            _buildShellTabPage(state: state, child: const HomePage()),
      ),
    ]),
    // ... 其余 Tab branch
  ],
)
```

### 3.5 转场约定

- **普通页面**：`MaterialPage`。
- **Tab 页面**：`NoTransitionPage`（避免切换时页面重建）。
- **底部 Sheet 式页面**：`CustomTransitionPage`，配置 `fullscreenDialog: true`、`barrierColor: Colors.black54`、`opaque: false`，`transitionsBuilder` 使用自底向上的 `SlideTransition`。

```dart
CustomTransitionPage(
  fullscreenDialog: true,
  barrierColor: Colors.black54,
  opaque: false,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final offset = Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeOut),
    );
    return SlideTransition(position: offset, child: child);
  },
  child: const SomeSheetPage(),
)
```

---

## 4. 状态机 / 状态管理（来自 BetterLove）

状态管理统一使用 **BLoC 三段式**：`Event` → `Bloc` → `State`。

### 4.1 Event — `application/bloc/<feature>_event.dart`

- 所有事件继承抽象基类 `<Feature>Event`。
- 需要「等待事件完成」的事件，携带 `final Completer<bool>? completer;`。

```dart
abstract class ProfileEvent {
  const ProfileEvent();
}

class LoadProfile extends ProfileEvent {
  final Completer<bool>? completer;
  final bool forceRefresh;
  const LoadProfile({this.completer, this.forceRefresh = false});
}
```

### 4.2 State — `application/bloc/<feature>_state.dart`

- 不可变状态类，私有构造 + 命名工厂（`initial()` / `loaded()` 等）+ `copyWith`。
- 集合字段默认用 `const <String, X>{}`，所有字段给出默认值。

```dart
class ProfileState {
  final bool isLoading;
  final String? errorMessage;
  final ProfileModel? profile;

  const ProfileState._({
    required this.isLoading,
    required this.errorMessage,
    required this.profile,
  });

  factory ProfileState.initial() =>
      const ProfileState._(isLoading: false, errorMessage: null, profile: null);

  ProfileState copyWith({/* ... */}) => ProfileState._(/* ... */);
}
```

> 复杂数据模型（接口返回体）使用 **freezed + json_serializable** 生成，文件形如 `xxx_model.dart` / `xxx_model.freezed.dart` / `xxx_model.g.dart`。

### 4.3 Bloc — `application/bloc/<feature>_bloc.dart`

- 继承 `Bloc<XxxEvent, XxxState>`。
- 构造函数中通过 `on<Event>(_handler)` 注册处理器；处理器签名为 `Future<void> _onXxx(Event event, Emitter<XxxState> emit)`。
- Repository 通过构造函数注入（由 DI 提供），不直接 new。
- 需要等待的异步事件用 `completeBlocEvent(event.completer, success: ...)` 回传结果。
- 捕获异常并写日志（通过 `Injection.get<LogService>().error(...)`），转为错误 State。

```dart
class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final ProfileRepository _repository;

  ProfileBloc({required ProfileRepository repository})
      : _repository = repository,
        super(ProfileState.initial()) {
    on<LoadProfile>(_onLoadProfile);
  }

  Future<void> _onLoadProfile(LoadProfile event, Emitter<ProfileState> emit) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      final data = await _repository.getProfile();
      emit(state.copyWith(isLoading: false, profile: data));
      completeBlocEvent(event.completer, success: true);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: mapErrorToMessage(e)));
      completeBlocEvent(event.completer, success: false);
    }
  }
}
```

### 4.4 UI 消费

页面用 `BlocBuilder` / `BlocListener` / `BlocSelector` 消费状态：

```dart
BlocBuilder<ProfileBloc, ProfileState>(
  builder: (context, state) {
    if (state.isLoading) return const LoadingView();
    return ProfileView(profile: state.profile);
  },
)
```

---

## 5. 依赖注入（来自 BetterLove）

使用 `get_it` + **手写 Module 注册**（**不使用** injectable 代码生成）。

### 5.1 全局入口 — `core/di/get_it.dart`

```dart
final GetIt getIt = GetIt.instance;

class GetItConfig {
  static Future<void> init() async => getIt.reset();
  static Future<void> reset() async => getIt.reset();
}
```

### 5.2 门面 — `core/di/injection.dart`

`Injection` 按固定顺序编排各 Module 的注册/注销，业务统一通过 `Injection.get<T>()` 取实例。

```dart
class Injection {
  static Future<void> init() async {
    await GetItConfig.init();
    await NetworkModule.register();
    await RouterModule.register();
    await AuthModule.register();
    await ProfileModule.register();
    // ... 其余模块
  }

  static Future<void> reset() async {
    // 按注册的逆序注销
    ProfileModule.unregister();
    AuthModule.unregister();
    RouterModule.unregister();
    NetworkModule.unregister();
    await GetItConfig.reset();
  }

  static T get<T extends Object>() => getIt<T>();
}
```

### 5.3 Module 注册约定 — `core/di/modules/<feature>_module.dart`

每个 feature 一个 Module，提供成对的 `register()` / `unregister()`。注册顺序：Repository → Bloc（Bloc 依赖 Repository，必须后注册）。

```dart
class ProfileModule {
  static void register() {
    getIt.registerLazySingleton<ProfileRepository>(
      () => ProfileRepositoryImpl(api: ProfileApiService()),
    );
    getIt.registerLazySingleton<ProfileBloc>(
      () => ProfileBloc(repository: getIt<ProfileRepository>()),
    );
  }

  static void unregister() {
    getIt.unregister<ProfileBloc>();
    getIt.unregister<ProfileRepository>();
  }
}
```

### 5.4 页面注入 Bloc

- 全局 Bloc：在 `main.dart` 的 `MultiBlocProvider` 中通过 `Injection.get<XxxBloc>()` 提供。
- 路由局部 Bloc：在 `GoRoute.builder` 中用 `BlocProvider.value(value: Injection.get<XxxBloc>(), child: Page())`。

---

## 6. 网络访问架构（来自 myStar / mystic_app）

网络层统一使用 **`DioManager` 单例 + `HttpBaseRequest` 基类**，替换 BetterLove 的 `DioClient` + 多拦截器方案。

### 6.1 网络访问入口 — `core/network/dio_manager.dart`

单例，内部持有唯一 `Dio`，负责：连通性检查、重试、Cookie 持久化、代理适配、错误提示、会话级取消。

核心方法签名：

```dart
class DioManager {
  static final DioManager _instance = DioManager._internal();
  factory DioManager() => _instance;

  Dio get dio => _dio;
  PersistCookieJar cookieJar = PersistCookieJar();

  Future send({
    required String url,
    HttpMethod method = HttpMethod.GET,
    Map<String, dynamic> params = const {},
    Map<String, dynamic> headers = const {},
    CancelToken? cancelToken,
    int maxRetry = 3,
    ResponseType? responseType,
    bool tipError = true,
    bool notTipNetError = false,
    String? contentType,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
  }) async { /* 连通性检查 → 请求 → 重试 → 状态码校验 → 返回 data */ }

  /// 登录/登出时取消会话内所有进行中的请求
  void cancelSessionRequestsOnLogout() { /* ... */ }

  /// 切换域名（登录后切 apiHost，未登录切 baseHost）
  static Future<void> changeHost({bool? isLogin}) async { /* ... */ }
}
```

**职责边界：**

- `send()` 只负责 HTTP 收发、重试、连通性、Cookie、错误 Toast；**不做业务判断**。
- 业务错误提示统一在 Repository / Bloc 层处理（由页面决定如何展示）。
- 未显式传入 `CancelToken` 的请求挂在会话级 `_sessionCancelToken` 上；登出时统一取消。

### 6.2 网络访问基类 — `core/network/http_base_request.dart`

所有接口请求继承 `HttpBaseRequest`，只暴露「我要什么」，公共逻辑（公共参数、公共 Header、合并、派发）由基类完成。

```dart
abstract class HttpBaseRequest {
  /// 公共参数，默认空，子类可覆盖
  Map<String, dynamic> commonParams() => {};

  /// 公共 Header（设备信息、Token 等）
  Future<Map<String, dynamic>> commonHeaders() async => {};

  // —— 以下由子类实现 ——
  String url();                                        // 请求地址（必填）
  Map<String, dynamic> params();                       // 请求参数（必填）
  Map<String, dynamic> headers() => {};                 // 私有 Header
  HttpMethod httpMethod() => HttpMethod.GET;            // 请求方法
  ResponseType responseType() => ResponseType.plain;    // 原始字符串优先，大 JSON 更快
  bool isJson() => true;                                // 响应后是否按 JSON 校验
  bool isAutoLogin() => false;                          // 是否自动登录
  CancelToken? cancelToken() => null;
  String? contentType() => null;
  Duration? connectTimeout() => null;
  Duration? receiveTimeout() => null;
  Duration? sendTimeout() => null;

  /// 统一发送：合并 params+commonParams、headers+commonHeaders，再派发给 DioManager
  Future send(int? maxRetry, {
    bool tipError = true,
    bool notTipNetError = false,
    String? contentType,
  }) async { /* ... */ }
}
```

**子类示例（接口定义层）：**

```dart
class ProfileApiService {
  Future<dynamic> getProfile() =>
      _GetProfileRequest().send(3);
}

class _GetProfileRequest extends HttpBaseRequest {
  @override
  String url() => '/api/profile';

  @override
  Map<String, dynamic> params() => {};

  @override
  HttpMethod httpMethod() => HttpMethod.POST;

  @override
  ResponseType responseType() => ResponseType.plain;
}
```

### 6.3 自定义异常体系 — `core/network/net_exceptions.dart`

所有网络异常继承 `Exception`，供 Repository / Bloc 分层捕获与转换：

| 异常 | 含义 |
| --- | --- |
| `NetDisconnectException` | 断网 / 无连通性 |
| `HttpCodeException` | HTTP 层错误（超时、状态码非 200 等） |
| `RESTCodeException` | 业务层错误（响应体 code != 成功值） |
| `ContentNotJsonException` | 响应不是合法 JSON |

### 6.4 错误 → 状态映射（与 BLoC 衔接）

myStar 原方案基于 GetX 的 `BaseGetVM` + `responseWithStatus`。**本项目改用 BLoC**，因此保留「异常 → 语义码」的映射思路，但映射结果写入 BLoC State，而不是 `StatusContent`。

约定在 `core/network/net_exceptions.dart` 或 utils 中提供扩展：

```dart
enum NetErrorType { cancelled, disconnect, httpError, businessError, dataError, unknown }

extension NetExceptionX on Object {
  NetErrorType toNetErrorType() {
    if (this is NetDisconnectException) return NetErrorType.disconnect;
    if (this is HttpCodeException) return NetErrorType.httpError;
    if (this is RESTCodeException) return NetErrorType.businessError;
    if (this is ContentNotJsonException) return NetErrorType.dataError;
    if (this is DioException && (this as DioException).type == DioExceptionType.cancel) {
      return NetErrorType.cancelled;
    }
    return NetErrorType.unknown;
  }
}
```

Bloc 中统一捕获：

```dart
try {
  final data = await _repository.getProfile();
  emit(state.copyWith(isLoading: false, profile: data));
} catch (e) {
  emit(state.copyWith(isLoading: false, errorType: e.toNetErrorType()));
}
```

### 6.5 领域中间件层 — `StatusErrorCode`

如需与页面 UI 状态机对齐，可在 `application` 层定义 `StatusErrorCode { cancelled, disconnect, assectError, dataError, unknown }`，由 `NetErrorType` 映射得到，页面根据它决定展示内容。

### 6.6 辅助模块

- `core/network/dio_helper.dart`：`addCharlesAdapter(dio)` 代理/Charles 抓包适配；`checkIfEmulator()` 等。
- `core/network/dot_env_util.dart`：`isDebugMode` / `isForceOpenProxy` / `isEnableDevTools` 等环境开关，值来自 `.env`。
- `app/hosts/app_hosts.dart`：`AppHosts.baseHost / apiHost / h5Host / ...` 静态域名配置，含 `init()` 与 `_toDioBaseUrl` 规范化。

---

## 7. 数据流转全链路（整合示例）

以「加载个人资料」为例，展示 BetterLove 的 BLoC/路由 与 myStar 的网络层如何协同：

```
[UI] ProfilePage
   │ context.read<ProfileBloc>().add(LoadProfile())
   ▼
[Bloc] ProfileBloc._onLoadProfile
   │ await _repository.getProfile()
   ▼
[Domain] abstract ProfileRepository.getProfile()
   ▲  (由 DI 注入实现)
   │
[Data] ProfileRepositoryImpl.getProfile()
   │ await ProfileApiService().getProfile()
   ▼
[Data/Remote] _GetProfileRequest extends HttpBaseRequest
   │ send(3) → 合并公共参数/Header
   ▼
[Network] DioManager().send(...)
   │ 连通性 → Dio 请求 → 重试 → 校验
   │ 失败抛 NetDisconnectException / HttpCodeException / RESTCodeException / ContentNotJsonException
   ▲
   │ 异常向上冒泡
[Bloc] catch → emit(state.copyWith(errorType: e.toNetErrorType()))
   ▼
[UI] 根据 State 渲染加载 / 成功 / 失败
```

---

## 8. 应用启动流程 — `main.dart`

```dart
void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. 允许横竖屏（不锁定方向）
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // 2. 加载 .env 与环境配置
    // await dotenv.load(fileName: '.env');
    // await AppHosts.init();

    // 3. 国际化（默认中文简体）
    await EasyLocalization.ensureInitialized();
    await initializeDateFormatting('zh_CN', null);
    await initializeDateFormatting('zh_TW', null);
    await initializeDateFormatting('en_US', null);
    await initializeDateFormatting('ja_JP', null);

    // 4. 依赖注入（含网络、路由模块）
    await Injection.init();

    // 5. 初始化路由（异步，决定 initialLocation）
    await Injection.get<AppRouter>().initialize();

    // 6. 启动
    runApp(
      EasyLocalization(
        supportedLocales: const [
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
            // ... 其余全局 Bloc
          ],
          child: const App(), // 内部 MaterialApp.router(routerConfig: Injection.get<AppRouter>().router)
        ),
      ),
    );
  }, (error, stack) {
    FlutterError.presentError(FlutterErrorDetails(exception: error, stack: stack));
  });
}
```

**启动顺序不可颠倒：** `Injection.init()` 必须在 `AppRouter.initialize()` 之前，`AppRouter.initialize()` 必须在 `runApp` 之前。

**多语言：** 支持 中文简体（`zh-CN`，默认）/ 中文繁体（`zh-TW`）/ 英语 US（`en-US`）/ 日本语（`ja-JP`）四种语言，翻译文件位于 `assets/translations/<locale>.json`。新增语言需同步更新 `supportedLocales`、`fallbackLocale` 与对应 JSON 文件；运行时切换调用 `context.setLocale(locale)`。

**屏幕方向：** 不锁定方向，允许横竖屏（`portraitUp/portraitDown/landscapeLeft/landscapeRight`）。

---

## 9. 命名与编码规范

- **导入路径**：统一使用 `package:potatokid_screen/...` 绝对导入，禁止相对导入。
- **导入顺序**：`dart:` → `package:flutter/` → 第三方包 → 本项目 `package:`。
- **文件命名**：`snake_case.dart`；Bloc 三件套固定为 `<feature>_bloc.dart` / `<feature>_event.dart` / `<feature>_state.dart`。
- **类命名**：`PascalCase`；Event 用动词短语（`LoadProfile`），State 用名词（`ProfileState`），Repository 接口无后缀、实现加 `Impl`。
- **注释**：使用中文注释，公共类/方法写清楚职责。**不要加无意义的行内注释。**
- **不可变**：State / Model 一律不可变，通过 `copyWith` 更新。
- **禁止**：在 Widget 内直接 `new` Repository / Bloc（必须走 DI）；在 data 层 import presentation 层。

---

## 10. AI 开发指引（新增一个 Feature 的标准步骤）

1. **建目录**：`lib/features/<feature>/{presentation,application,domain,data}` 四层。
2. **定义 Model**：`data/models/xxx_model.dart`，用 freezed + json_serializable，跑 `build_runner`。
3. **定义接口定义层**：`data/datasources/remote/xxx_api_service.dart`，每个接口一个 `HttpBaseRequest` 子类。
4. **定义 Repository 接口**：`domain/repositories/xxx_repository.dart`（纯抽象）。
5. **实现 Repository**：`data/repositories/xxx_repository_impl.dart`，调用 ApiService，捕获网络异常。
6. **写 Event**：继承 `<Feature>Event`，需要等待的加 `Completer<bool>?`。
7. **写 State**：不可变 + 命名工厂 + `copyWith`。
8. **写 Bloc**：构造函数注入 Repository，`on<Event>` 注册处理器。
9. **写 DI Module**：`core/di/modules/<feature>_module.dart`，实现 `register()` / `unregister()`，并在 `Injection` 中挂载。
10. **加路由**：`RouteNames` 增加常量；如需参数，写 `<Xxx>Params`；在 `AppRouter._buildRoutes()` 注册 `GoRoute`。
11. **写页面**：`presentation/pages/xxx_page.dart`，用 `BlocBuilder`/`BlocListener` 消费状态。
12. **验证**：`dart run build_runner build --delete-conflicting-outputs`，再执行 `flutter analyze`。

---

## 11. 关键约定速查表

| 场景 | 约定 |
| --- | --- |
| 状态管理 | `flutter_bloc`（Event/State/Bloc），禁用 GetX 做状态管理 |
| 路由 | `GoRouter`，路径常量进 `RouteNames`，参数走 `RouteParams` + `state.extra` |
| Tab 保持 | `StatefulShellRoute.indexedStack` + `NoTransitionPage` |
| 弹层页面 | `CustomTransitionPage`（fullscreenDialog + 透明 + 底部滑入） |
| 依赖注入 | `get_it` + 手写 Module，业务用 `Injection.get<T>()` |
| 网络入口 | `DioManager()` 单例的 `send()` |
| 接口定义 | 继承 `HttpBaseRequest`，实现 `url()` / `params()` |
| 网络异常 | `NetDisconnectException` / `HttpCodeException` / `RESTCodeException` / `ContentNotJsonException` |
| 错误展示 | 在 Bloc 层捕获并转为 State，由页面渲染（不改动 `DioManager` 业务语义） |
| 代码生成 | freezed / json_serializable，命令见第 1 节 |
| 导入 | `package:potatokid_screen/...` 绝对导入 |
