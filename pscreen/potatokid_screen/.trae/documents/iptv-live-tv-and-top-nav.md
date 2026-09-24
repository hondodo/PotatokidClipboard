# 首页直播（IPTV） + 顶部 Tab 导航改造

## Context（背景）

项目面向安卓电视（Android TV）。当前首页仍是「顶部 AppBar + 底部 tabs」（Request-1 的旧形态），用户明确要求 TV 化：

1. **顶部横向 Tab 导航条**，**左右按键焦点切换**，共 4 个 tab：`首页(直播) | 时间 | 屏保 | 我的`。tab 内图标+文字**横排**。
2. **OK 键**专门用于 tab 栏的显示/隐藏（配合遥控器，隐藏时获得全屏观看体验）。
3. 首页 = **全屏 IPTV 直播**：进入自动加载外部 m3u 列表并自动播放首频道；频道列表做横向频道条，**焦点移到即切台**（无需 OK）。
4. **保留「我的」页完整功能**（主题/语言/设置按钮），不得换成占位符；「时间」「屏保」保持占位页（图标+文字）。

播放方案（已与用户确认）：**`media_kit`（播放）+ 手写 M3U 解析**。`iptv_org_api` 因要求 Dart ^3.12.0（本项目 3.11.5）且为低可信新包，已排除。

依赖版本已核实：`media_kit 1.2.6`（Dart ^3.1.0，兼容）、`media_kit_video 2.0.1`、`media_kit_libs_video 1.0.7`（提供 Android/iOS/桌面原生 FFmpeg libs）。

---

## 一、依赖与配置

### 1.1 `pubspec.yaml`
`dependencies` 新增：
```yaml
media_kit: ^1.2.6
media_kit_video: ^2.0.1
media_kit_libs_video: ^1.0.7
```

### 1.2 `main.dart`（启动流程）
- 在 `runZonedGuarded` 内、`runApp` 前调用 `MediaKit.ensureInitialized();`。
- 把屏幕方向改为**锁定横屏**（仅 landscapeLeft/Right），并同步该行的中文注释。
- 在 `Injection.init()` 之后追加 `await Injection.get<IptvModule>().register()`（或直接纳入 `Injection.init()` 的模块链，见 3.4）。

### 1.3 `android/app/src/main/AndroidManifest.xml`
- 增加网络权限与明文流许可（m3u 内的直播 URL 常为 http）：
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<application ... android:usesCleartextTraffic="true" ...>
```

---

## 二、IPTV feature（新建 `lib/features/iptv/`，遵循 feature-first 四层 + BLoC 三段式 + get_it 手写 Module）

### 2.1 数据模型 — `application` 层轻量 Model（非 JSON，无需 codegen）
`lib/features/iptv/domain/models/iptv_channel.dart`
```dart
class IptvChannel {
  final String name;
  final String url;
  final String? logo;   // tvg-logo
  final String? group;  // group-title
}
```
（纯不可变类 + `==`，不引入 freezed，因来源非 JSON API。）

### 2.2 M3U 解析 — `data/datasources/remote/iptv_m3u_parser.dart`
手写解析器：逐行扫描，`#EXTINF:` 后捕获 `tvg-logo=`、`group-title=`、名称；下一非空行即频道 URL。返回 `List<IptvChannel>`。

### 2.3 数据源 — `data/datasources/remote/iptv_api_service.dart`
- 用 `DioManager().dio.get(m3uUrl, options: Options(responseType: ResponseType.plain))` 拉取原始 m3u 文本。
- m3u 地址做成常量（`lib/app/config/` 或 feature 内 `const String kIptvM3uUrl = 'https://gh-proxy.com/raw.githubusercontent.com/vbskycn/iptv/refs/heads/master/tv/iptv4.m3u';`）。

### 2.4 Repository
- `domain/repositories/iptv_repository.dart`：`Future<List<IptvChannel>> fetchChannels();`
- `data/repositories/iptv_repository_impl.dart`：调 ApiService + 解析 → 领域模型。

### 2.5 BLoC 三件套（`application/bloc/`）
- `iptv_event.dart`：`abstract IptvEvent` + `LoadIptv({Completer<bool>? completer, bool forceRefresh})`。
- `iptv_state.dart`：不可变，命名工厂 `initial()` + `copyWith`，字段 `isLoading / errorMessage / errorType / channels`。
- `iptv_bloc.dart`：构造注入 `IptvRepository`，`on<LoadIptv>` 拉取；catch → `mapErrorToMessage` + `e.toNetErrorType()`，日志走 `Injection.get<LogService>()`（完全对齐 HomeBloc，见 `home_bloc.dart`）。

### 2.6 播放 UI（`presentation/components/`）
- `live_player_widget.dart`（StatefulWidget）：创建 `Player()` + `VideoController`，`player.open(Media(url, httpHeaders: ...))` 播流；`dispose()` 时 `player.dispose()`。暴露 `playChannel(IptvChannel)` 切换。
- `channel_bar.dart`：横向频道条，每个频道用 `FocusableActionDetector(focusNode, onFocusChange: → 切台, autofocus)`；焦点态高亮。**不注册 ActivateIntent**（这样 OK 会冒泡到壳层用于显隐导航条）。

### 2.7 HomePage 改造（`lib/features/home/presentation/pages/home_page.dart`）
- 去掉 `ImmersiveScaffold` + AppBar。
- `HomePage` 改为：`BlocProvider<IptvBloc>(create: ..add(LoadIptv()))`，body 为直播结构：
  - 加载中 → loading；出错 → `_ErrorView`（复用现有 retry 结构）；有频道 → `Stack`：全屏 `VideoWidget(controller)` + 底部/叠加 `ChannelBar`（黑底）。
  - **自动播放**：拿到 channels 后 `playChannel(channels.first)`。
- 首页原本的 `HomeBloc` 列表**不再作为首页主体**（保留 Home/HomeDetail 路由与文件不删除，避免破坏 detail 页；首页主体切换为直播）。如需让列表可用，保留右上设置入口进入即可。

---

## 三、顶部 Tab 导航改造（替换 Request-1 的底部 NavigationBar）

### 3.1 `lib/features/app/presentation/pages/main_app.dart`（重写）
- 移除 `bottomNavigationBar`；改为**顶部横向条**：4 个 tab `首页|时间|屏保|我的`，图标+文字**横排**。
- 每个 tab 用 `FocusableActionDetector`：`onFocusChange` 为真时 `navigationShell.goBranch(index, initialLocation: index == currentIndex)`（**左右焦点即切页**）；焦点态高亮（TV 风格，与频道条一致）。**不设 ActivateIntent** → OK 冒泡。
- 导航条显隐：延续 `AppState.isChromeVisible`，用 `AnimatedSlide`/`AnimatedAlign`（顶部）做收起动画；可加一个设置 IconButton（承接原 Home AppBar 的设置入口）。
- **根级 OK 切换**：在 `MainApp` 外层包 `Focus(canRequestFocus: false, onKeyEvent: ...)`，当 `event is KeyDownEvent && key ∈ {select, enter, space, gameButtonA}` 时 `context.read<AppBloc>().add(const ToggleChrome())` 并返回 `KeyEventResult.handled`。因焦点 tab/频道均不消费 OK，OK 稳定冒泡到此处——实现「OK 管显隐」。
  > 已核实 Flutter SDK：`select/enter/space/gameButtonA` → `ActivateIntent()`；仅有可聚焦且注册了 enabled action 的控件才 `handled` 并阻断冒泡；`Shortcuts` 的 `Focus.onKeyEvent` 会先行于先祖节点。故非 action 的焦点项不妨碍本壳层 OK 处理。

### 3.2 `lib/features/time/presentation/pages/time_page.dart` / `screensaver_page.dart`
- 已是占位页（图标+文字居中），**保持**。无需改。

### 3.3 `lib/features/profile/presentation/pages/profile_page.dart`
- 去掉 `ImmersiveScaffold` + AppBar → 纯内容 `ListView`（**保留 SegmentedButton 主题、ChoiceChip 语言、FilledButton 设置**全部功能）。仅改包裹层，不动内部。

### 3.4 `lib/shared/widgets/immersive_scaffold.dart` → **删除**
- 唯一的点击切显隐机制被 OK 取代，AppBar 也移出页面。删除文件并清理 import。

### 3.5 DI：新增 `lib/core/di/modules/iptv_module.dart`
- 仿 `home_module.dart`：`register()` 注册 `IptvRepository → IptvBloc`；在 `injection.dart` 的 `init()`/`reset()` 中挂载 `IptvModule`。

### 3.6 国际化（`assets/translations/*.json`）
- 如导航条/频道条需要文本，使用已有 `home_title / time_title / screensaver_title / profile_title`（均已存在）。无需新增 key（若直播页需 loading/error 文案，复用 `common_*`）。

---

## 四、验证方式

1. `flutter pub get` 确认 media_kit 三包解析成功（无 SDK 冲突）。
2. `dart run build_runner build --delete-conflicting-outputs`（本次新增为纯手写 model，非 freezed，通常无需；跑一次以防误改生成文件）。
3. `flutter analyze`：应无错误告警。
4. 真机/模拟器（横屏）验证：
   - 首页进入 → 自动拉取 m3u、显示频道条、自动播放首频道完整视频流。
   - D-pad **左右**在顶部 tab 间焦点切换即切页（首页<->时间<->屏保<->我的）。
   - 按 **OK**：tab 栏隐藏/显示切换；我的页内容完整（主题/语言/设置均在）。
   - 频道条左右焦点→即时换台。