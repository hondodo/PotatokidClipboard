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
   （Flutter **不会**把依赖包的资产自动打进宿主 bundle）

   ```yaml
   flutter:
     assets:
       - packages/pscreen_screen/assets/datas/
   ```

3. **在任何资产读取之前配置根前缀**

   ```dart
   ScreenAssets.configure(root: 'packages/pscreen_screen/');
   ```

   忘记这一步 → 资产读取 404 且被上层 `catch` 吞掉，表现为「频道规则为空、
   城市列表为空」这类**静默故障**。共享包内的唯一资产读取点会调
   `ScreenAssets.requireConfigured()` 把这种失败变成显式异常。

4. **不要与宿主自己的 `core/di/get_it.dart` 同时 import 包的同名文件**
   —— 两边都有 `getIt` / `GetItConfig`，同时 import 会产生歧义引用错误。
   共享包内部只用包内那份；宿主侧继续用自己的那份。

5. **注册依赖**

   ```dart
   await ScreenModules.register(getIt);
   ```
