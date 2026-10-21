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
   共享包内部只用包内那份；宿主侧继续用自己的那份。

5. **注册依赖**

   ```dart
   await ScreenModules.register(getIt);
   ```
