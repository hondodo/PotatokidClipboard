# pscreen_screen

屏幕能力共享包：IPTV / 天气 / 时钟 / 消息协议 / 网络基础设施。

## 边界

- **包含**：`data` / `domain` / `application` 三层 + `core` 基础设施。
- **不包含**：任何 `presentation`（UI）。UI 由各宿主按自己的交互范式实现
  （电视端用遥控焦点，中控屏用触屏）。
- **不包含**：路由树、DI 根、主题、本地化资源。

## 依赖方向

宿主 App → `pscreen_screen`。共享包不依赖任何宿主。

## 宿主接入清单（漏任何一条都会静默出错）

1. **加 path 依赖**

   ```yaml
   dependencies:
     pscreen_screen:
       path: ../packages/pscreen_screen
   ```

2. **资产由共享包自己声明，宿主无需再声明**

   共享包的 `pubspec.yaml` 里已经声明了 `assets: - assets/datas/`。当它作为依赖被
   引入时，flutter_tools 会把该目录展开，并给资产键加上 `packages/pscreen_screen/`
   前缀——也就是 `packages/pscreen_screen/assets/datas/<文件名>`，正好对应宿主
   启动时设置的 `ScreenAssets.configure(root: 'packages/pscreen_screen/')`。

   **宿主不要在自己的 pubspec 里声明这份资产**：pubspec 里的目录通配是相对
   **声明方自己的目录**解析的，写 `- packages/pscreen_screen/assets/datas/` 会被
   解析成 `<宿主目录>/packages/pscreen_screen/assets/datas/`，构建时报
   `Error: unable to find directory entry in pubspec.yaml`。

3. **启动时配置根前缀并做接入自检**

   ```dart
   ScreenAssets.configure(root: 'packages/pscreen_screen/');
   ScreenAssets.requireHostConfigured();   // 未配置就抛异常
   ```

   忘记这一步 → 资产读取 404 且被上层 `catch` 吞掉，表现为「频道规则为空、
   城市列表为空」这类**静默故障**。自检放在启动期，让它立刻失败而不是等到
   第一次读资产。

   注意：共享包自己跑测试时根前缀是空串（资产就在包内 `assets/datas/`），
   这是合法的；`requireHostConfigured()` 只用于宿主。

4. **不要与宿主自己的 `core/di/get_it.dart` 同时 import 包的同名文件**
   —— 两边都有 `getIt` / `GetItConfig`，同时 import 会产生歧义引用错误。
   共享包内部只有 `core/di/screen_injection.dart` 仍用包内那份；
   各 Module 一律用 `ScreenModules.register(it)` 传进来的**宿主容器**。
   宿主侧继续用自己的那份。

5. **注册依赖**

   ```dart
   await ScreenModules.register(getIt);
   ```

   `it` 就是真正被写入的容器——包内 6 个 Module 全部用它，不再隐式依赖包内
   的全局 `getIt`。两个宿主传的都是自己的 `getIt`（= `GetIt.instance`）。

## 发送端 / 接收端（本包两端都有，宿主务必知情）

共享包**同时**提供两种能力：

| 方向 | 组成 | 位置 |
| --- | --- | --- |
| **发送端** | 协议构造器（`buildPlainText` / `buildTextCommand` / `buildVolumeCommand` / `buildChannelCommand` / `buildCommandEnvelope`） | `features/msg/protocol/envelope_builder.dart` |
| **接收端** | 协议解析 + 路由 + 执行 + 上报（`MessageRouter` / `MessageCommandExecutor` / `MessageOverlayController` / `ReportingService`） | `features/msg/application/` |

接收端由 `MsgModule` 拉起：`MsgModule.register(it)` 会订阅
`NimManager.onReceiveMessages`，把收到的文本信封交给 `MessageRouter`，
再由 `MessageCommandExecutor` 执行（音量 / 切台），文本命令走浮层。

**因此：任何调用 `ScreenModules.register(getIt)` 的宿主，也会「执行」发往自己
NIM 账号的 `cmd` 指令信封。**

### 中控屏的具体情况

`pscreen_home`（中控屏）**既是发送端也是接收端**：

- 发送端：遥控面板用宿主自己的 `NimClient`（`NimClient.autoLogin` / `sendText`）
  给电视端下发 `cmd` 信封。
- 接收端：`pscreen_home` 也调用了 `ScreenModules.register(getIt)`，因此同样会
  执行**发给中控屏自己 NIM 账号**的 `cmd` 信封。

中控屏的 Android 原生侧实现了 `potatokid/volume` 通道
（`pscreen_home/android/app/src/main/kotlin/potatokid/tools/homecontroller/MainActivity.kt`：
`volumeUp` / `volumeDown` / `toggleMute`），而共享包的 `PlatformChannelService`
正是通过这条通道控制音量。于是**一条发给中控屏的音量命令，会改中控屏自己的
系统音量**。

这是**当前设计的已知行为，不是 bug 修复项**——是「接收端随 DI 一起开箱」带来的
语义重叠，需要产品侧确认中控屏是否应当被遥控。

### 只做发送端的宿主如何退出

接收端目前**没有**独立的开关：开启它的唯一入口是 `MsgModule.register(it)`，
而它总是被 `ScreenModules.register(it)` 调用。因此，只做发送端的宿主应当：

1. **不调用** `ScreenModules.register(getIt)`；
2. 改为只注册自己需要的发送端依赖，例如
   `await CoreModule.register(getIt);`（拿 `NimManager`），
   或者像 `pscreen_home` 那样用宿主自己的 NIM 封装（`NimClient`）发消息；
3. 自己实现并注册 `CurrentSceneProvider`（只有 `MsgModule` 需要它）。

注意：不注册 `ScreenModules` 就没有 `LogService` / `DioManager` /
`IptvBloc` / `WeatherBloc` / `RemoteLoginBloc`，宿主需自行补齐。
