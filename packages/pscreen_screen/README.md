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

2. **在宿主自己的 pubspec 里声明共享包的资产**

   ```yaml
   flutter:
     assets:
       - packages/pscreen_screen/assets/datas/
   ```

   为什么宿主必须自己声明：flutter_tools 对**依赖包**解析资产时不展开通配目录
   （`packages/flutter_tools/lib/src/asset.dart` 里对依赖包传
   `wildcardDirectories: <Uri>[]`，注释即 "Do not track wildcard directories for
   dependencies"）。因此共享包自己声明的 `assets: - assets/datas/`（目录）在被依赖时
   不会生效，只有宿主显式声明 `packages/pscreen_screen/assets/datas/` 才会被打进
   bundle，资产键为 `packages/pscreen_screen/assets/datas/<文件名>`。

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
