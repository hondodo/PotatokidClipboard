# TV / Home 双端直播录制方案与实施清单

> 目标：在两端加入「录制」按钮，录制家长**当前正在观看**的直播频道。
> 前提：纯 Dart 实现、不依赖 relay、不引入 ffmpeg 插件、不影响遥控与触屏现有链路。
> 归属原则（用户 2026-11-17 定稿）：**核心逻辑进共享包，UI 各自实现**；TV + home 两端都接入。
> 状态：已实施（2026-11-17）。核心逻辑 + 两端 UI 已接线，analyze 通过，录制单测 20/20、共享包全量 328/328。

---

## 1. 目标与边界（本期）

### 支持

- 家长手动点「开始录制 / 停止录制」，录当前频道原始源（relay 改写前）。
- **两端接入**：
  - TV 端（`potatokid_screen`）：胶囊菜单里的录制按钮（遥控 OK / 触屏点按）。
  - Home 端（`pscreen_home`）：直播页底部控制区的录制按钮（触屏点按）。
- 边看边录：录制期间可正常切页 / 切台。
- 切台、离页 / 退出时**自动停止并保存**已录部分。
- 产物为 `.ts` 文件，落在各自 app 私有目录，可用播放器本地回放。

### 明确不支持（本期不做）

- 后台录制：App 退后台 / 锁屏即停止（不做前台 Service，TV 上常驻通知体验差）。
- 回看 / 预录 / 定时录制：只能从点「开始」那一刻起的直播流。
- 多频道同时录制：全局同时只有一路（两端共享同一个单例 controller，一端录制时另一端不可再启）。
- 加密 HLS（`#EXT-X-KEY` AES-128）：检测到即提示「该频道不支持录制」并停止。
- 转码与 MP4 封装：不重编码，不做 remux，产物就是拼接后的 `.ts`。

---

## 2. 关键决策

| 编号 | 决策 | 理由 |
|---|---|---|
| D-1 | 用 dio 新开一路下载 HLS 分片，**不复用播放器数据** | 播放在 libmpv native 层，Dart 拿不到已下载分片 |
| D-2 | 分片顺序二进制追加写入 `.ts`，不 remux | 零 CPU 开销，TS 分片可直接拼接播放 |
| D-3 | 录制原始源 URL（`channel.sources[idx]`），非 relay 改写地址 | 录制与 relay 解耦；relay 是低码率播放链路 |
| D-4 | 录制按钮家长可见、儿童模式隐藏；controller 二次校验 | 避免儿童误录 |
| D-5 | 写 `getApplicationDocumentsDirectory()` 私有目录 | 无需存储权限，两端 AndroidManifest 都不改 |
| D-6 | 切台检测以「频道名 + 源列表 + **源索引**」为身份，非单次 URL | 防动态 token 误判；**源索引必须纳入**，否则切源后录制源与播放源分叉 |
| D-7 | 单例桥接 `RecordingSourceProvider` 上报当前源 | 沿用 `TouchBackController` / `HomeNowPlayingController` 模式 |
| D-8 | 核心逻辑进共享包，UI 各自实现 | 共享包无 UI 层；两端都拉 m3u8，逻辑只需一份 |
| D-9 | controller 不发 SnackBar / 不持有 BuildContext | 共享包不能依赖宿主 UI；通过状态 + 事件回调通知 |
| D-10 | 两端不新增依赖 | 共享包已有 dio / path_provider / media_kit |
| D-11 | **手动切源（左/右键）录制中一律拦截 + 提示** | 用户 2026-11-17 定稿：录制中理论上不能换源；保录制完整性优先 |
| D-12 | **一级看门狗原地重载照常放行，不视作换源** | 原地重载仍打开同一个 URL（signature 不变），录制可继续跟踪同一条流；拦截它会导致卡死时无法自愈 |
| D-13 | **二级看门狗/失败重试的真实换源不拦截，而是停录保播放** | 换源后 URL 变化，录制源与播放源必然分叉；此时停录保存、让播放恢复，录制让位于播放 |

---

## 3. 架构与数据流

```
TV  LivePlayerWidget._playCurrentSource()   ─┐
                                             ├─ report{channel,url,sourceIndex,signature,origin} → RecordingSourceProvider（共享包）
Home LivePlayerView._openSource()            ─┘                                      │
                                                                    source 变化 → autoStop

RecordingController（共享包，单例）
  ├─ state: ValueNotifier<RecordingState>（idle/recording/error + 时长/字节/频道名）
  ├─ events: 完成 / 失败 / 不支持 / 切源拒绝 → 宿主监听后弹提示（D-9）
  ├─ trySwitchSource() → 录制中返回 false（手动切源拦截，D-11）
  ├─ Timer 轮询 m3u8（targetDuration）
  └─ dio 下载新分片 → File.append → .ts（私有目录）

UI（各自端）→ controller.start/stop；监听 state 刷新按钮/角标
```

- **状态源**：`RecordingController.instance.state` 为唯一真源，两端按钮与角标都监听它。
- **互斥**：controller 全局单例，`start()` 时若已在 recording 直接返回（两端不会同时录）。
- **源身份**：`signature = 频道名 + 源URL列表 + 当前源索引`（D-6）。切台、切源都会改变它，触发 `autoStop`。
- **origin 字段**：上报时带三种来源，用于区分策略：
  - `manual` — 用户按左/右键（两端 `_switchSource()`）
  - `reload` — 一级看门狗原地重载（同一 URL，`_playCurrentSource(isReload: true)`）
  - `auto` — 二级看门狗卡死 / 失败重试真实换源（`PlaybackRetryController` 的 `onSourceChanged`）；首次起播也算 `auto`
- **切台自动停**：任何 origin 的频道变化 → `stop(save: true)`。
- **切源分三条**：
  - `manual` + recording → **拦截**（不换源、不切台），发 `switch_blocked` 事件，宿主提示「录制中不能切换信号源，请先停止录制」
  - `reload` + recording → **放行**，URL 未变 signature 不变，录制继续跟踪同一条流（D-12）。卡死时能自愈，且不打断录制
  - `auto` + recording → **不拦截**，播放器照常换源自愈；`provider` 检测到 signature 变化 → `stop(save: true)`，发 `saved` 事件提示「信号源已自动切换，录制已保存」（D-13）

> **为什么不禁用看门狗**：看门狗是播放自愈的最后防线，录制中若禁用，源卡死时播放器会永久停在缓冲界面，反而毁掉"边看边录"的体验。三级划分的取舍是：能用同一 URL 重试就继续录（reload），必须换源才牺牲录制（auto），用户主动换源则优先保护录制（manual 拦截）。

---

## 4. 文件改动清单

### A. 共享包 `packages/pscreen_screen/lib/features/iptv/application/recording/`（新增 3 文件）

- [x] **`hls_playlist.dart`** — 纯解析函数，无 IO，便于单测
  - `HlsPlaylist parsePlaylist(String text, Uri base)` → `isMaster`, `variants`, `segments`, `mediaSequence`, `targetDuration`, `encrypted`
  - master：取 `#EXT-X-STREAM-INF` 后一行 URL，选带宽最低的 variant（省带宽）
  - media：解析 `EXT-X-MEDIA-SEQUENCE` / `EXTINF` / 分片行，相对 URL 用 `base.resolve()`
  - 检测 `#EXT-X-KEY` → `encrypted=true`
- [x] **`recording_source_provider.dart`** — 单例桥接（两端各上报一次）
  - `report(RecordingSource s)` / `attach(void Function(RecordingSource) onChanged)` / `detach()`
  - `RecordingSource {channelName, originalUrl, signature}`；缓存 `current` 供 UI 读
  - `RecordingSource` 字段：`channelName` / `originalUrl` / `sourceIndex` / `signature` / `origin`（`manual` / `reload` / `auto`）
  - `signature = '$channelName|$sourceIndex|${sources.join('|')}'` 的哈希（D-6，含源索引）
  - `report(s)`：先调 `controller.onSourceReport(s)` 让 controller 按 origin 决策（拦截/放行/停录）；signature 变化时再通知 autoStop
  - **拦截失败要回滚**：`manual` 被拒时 controller 返回 `false`，播放器**不执行** `_retry.setSource()`，UI 保持原源高亮
- [x] **`recording_controller.dart`** — 单例，`ValueNotifier<RecordingState>` + 事件回调
  - `RecordingState {idle, recording, error}` + `elapsed` / `bytes` / `channelName` / `error`
  - `Function(RecordingEvent)? onEvent`（`saved` / `unsupported` / `failed` / `switch_blocked`），宿主编排 SnackBar（D-9）
  - `bool onSourceReport(RecordingSource s)`：录制中且 `origin == manual` 且 signature 将变化 → 发 `switch_blocked` 事件，返回 `false`（拦截，D-11）；其余返回 `true`（放行）
  - `Future<void> start(RecordingSource source)`：非 recording → 校验 parent 模式 → 建目录/文件 → 首拉 m3u8 → 记录初始 sequence → 起轮询 Timer
  - `Future<void> stop({bool save = true})`：取消 Timer → flush/close → 发 `saved` 事件 → 回 idle
  - `void onSourceChanged(RecordingSource s)`：recording 中且 signature 变（`origin == auto`/频道变化）→ `stop(save: true)`
  - `_poll()`：按 targetDuration 重拉 m3u8，用 sequence + URL 判断新分片，下载追加
  - 单分片失败重试 2 次；连续 3 个失败 → `error` + `failed` 事件，保留已录部分
  - 文件软上限 2GB，到限自动 stop

### B. TV 端 `pscreen/potatokid_screen`（改 4 文件 + 新增 1）

- [x] **新增 `lib/features/iptv/presentation/components/recording_indicator.dart`**
  - 播放器上「录制中 ● mm:ss」角标，`IgnorePointer`，不拦手势/不进焦点链（参照 `_TouchHintBanner`）
- [x] **`lib/features/iptv/presentation/components/live_player_widget.dart`**
  - `_playCurrentSource()` 中 `String source = channel.sources[idx];`（约 954 行）之后、relay 改写**之前**插入 `RecordingSourceProvider.instance.report(...)`，origin 按调用来源传：`isReload == true` → `reload`，其余 → `auto`
  - **`_switchSource(int delta)`（约 1060 行）开头加拦截**（D-11）：上报 `origin: manual` 的新源信息给 controller，返回 `false` 则直接 `return`（不换源、不 `_playCurrentSource()`、不弹频道Toast），宿主已收到 `switch_blocked` 事件提示
  - `_appExiting` 分支（约 925 / 963 行）调 `RecordingController.instance.stopOnExit()`
  - 在播放器 Stack 挂 `RecordingIndicator`
- [x] **`lib/features/update/presentation/update_pill.dart`**
  - `allActions` 加录制按钮（parentOnly）：label 用 `capsule_record_start` / `capsule_recording_stop`（含时长），icon 用 `Icons.fiber_manual_record` / `Icons.stop_circle_outlined`，`active: recording`
  - `build` 外层包 `ValueListenableBuilder<RecordingState>` 让 label 实时刷新
  - 监听 `controller.onEvent` → 吐 SnackBar（儿童模式走 `kidSnackBar`）
- [x] **`assets/translations/{zh-CN,zh-TW,en-US,ja-JP}.json`**
  - 加 6 个 key：`capsule_record_start` / `capsule_recording_stop` / `record_started` / `record_saved` / `record_unsupported` / `record_failed`
- [x] **`docs/tv-touch-control-plan.md`**
  - 追加「与录制功能的边界」一节

### C. Home 端 `pscreen_home`（改 3 文件）

- [x] **`lib/features/screen/presentation/components/live_player_view.dart`**
  - `_openSource()` 中 `String url = channel.sources[idx];`（约 360 行）之后、relay 改写**之前**插入 `RecordingSourceProvider.instance.report(...)`，origin：`isReload == true` → `reload`，其余 → `auto`
  - **`_switchSource(int delta)`（约 404 行）开头加拦截**（D-11）：上报 `origin: manual`，返回 `false` 则直接 `return`（不 `setSource`、不 `_openSource`）；host 已收到 `switch_blocked` 提示
  - `dispose()` 调 `RecordingController.instance.stopOnExit()`（home 端退出是「返回主页」，播放器 dispose 即离页）
- [x] **`lib/features/screen/presentation/pages/live_page.dart`**
  - 在 `_ChannelSwitchControls`（约 263-276 行）所在底部控制区加录制按钮：监听 `RecordingController.state` 切换图标/文字，点击 start/stop
  - 接收 `controller.onEvent` 并用 `ScaffoldMessenger` 提示
  - 悬浮小窗（`widget.floating == true`）不显示录制按钮（空间小）
  - 左上角挂 `RecordingIndicator`（TV 端角标组件可提进共享包供两端复用）
- [x] **`lib/features/screen/presentation/components/live_stage_host.dart`**（如悬浮小窗宿主需要）
  - 确认悬浮 ⇄ 全屏切换不重建播放器 State，录制不中断

> Home 端文案是**硬编码中文**（无 easy_localization，见 `live_page.dart:138` 的 `Text('直播')`），按钮与提示直接用中文字符串，不改 i18n 体系。

---

## 5. 关键实现细节

### 分片下载与拼接

- 首启：master → 最低码率 variant → media playlist → 从**最后一个分片**开始下载（"正在观看"从当前时刻起）
- 轮询：每 `targetDuration` 重拉 media playlist；用 `EXT-X-MEDIA-SEQUENCE` + URL 判断新增，跳过已下载
- 写入：`File.openWrite(mode: FileMode.append)`，分片首尾相接，不做任何处理
- 文件名：`recordings/<频道名>_<yyyyMMdd_HHmmss>.ts`，频道名过滤非法字符
- 路径：TV 端 `getApplicationDocumentsDirectory()`；home 端同（各 app 私有目录，互不可见——这是期望行为）

### 切台 / 离页 / 退出

- `RecordingSourceProvider.report()` 比对 signature：不同 → controller `stop(save: true)` + `saved` 事件
- TV 退出：LivePlayerWidget `_appExiting` → `stopOnExit()`
- Home 离页：LivePlayerView `dispose()` → `stopOnExit()`
- 两端共用单例：一端在录，另一端 start 会被拒（返回 `false` + 提示「正在其他端录制」）

### 权限与依赖

- 无需新权限（私有目录）；两端 AndroidManifest 不改
- TV main manifest 已确认 `usesCleartextTraffic="true"`，HTTP 分片可下载；home 端实施时同样确认
- pubspec 三处都不改

### 与 relay 的关系

- 录制 URL 取 relay 改写**之前**的 `channel.sources[idx]`，与 `REPLY_SOURCE` / `RelayPolicy` 完全解耦
- 原始源不可直连时录制失败 → `error` 状态 + 提示，不影响播放

---

## 6. 文案

TV 端（i18n，zh-CN 示例，另三语同步）：

| key | 文案 |
|---|---|
| `capsule_record_start` | 开始录制 |
| `capsule_recording_stop` | 停止录制（{__T__}） |
| `record_started` | 正在录制 {__NAME__} |
| `record_saved` | 已保存 {__NAME__} 的录制 |
| `record_unsupported` | 该频道加密，无法录制 |
| `record_failed` | 录制失败，已保存部分内容 |
| `record_switch_blocked` | 录制中不能切换信号源，请先停止录制 |
| `record_source_switched` | 信号源已自动切换，录制已保存 |

Home 端（硬编码中文）：「录制 / 停止录制 mm:ss」「正在录制 X」「已保存 X 的录制」「该频道加密，无法录制」「录制失败，已保存部分内容」「录制中不能切换信号源，请先停止录制」「信号源已自动切换，录制已保存」。

---

## 7. 测试清单

- [x] 共享包 `test/features/iptv/application/recording/hls_playlist_test.dart`
  - master 选最低码率、media 分片解析、相对 URL resolve、加密检测、sequence 解析
- [x] 共享包 `test/features/iptv/application/recording/recording_source_provider_test.dart`
  - 同 signature 不触发、不同 signature 触发 autoStop、detach 后不回调
- [x] 共享包 `test/features/iptv/application/recording/recording_controller_test.dart`
  - start/stop 状态流转、互斥、切台停、失败保留部分
  - **切源三级**：`manual` 被拦截（返回 false + `switch_blocked`）、`reload` 放行不打断、`auto` 换源停录保存
  - **signature 含源索引**：同频道切源会触发变化（防分叉）
- [x] TV 端既有 15 个触屏测试不回归；home 端 `flutter test` 不回归
- [x] 两端 `flutter analyze lib test` 无 issue
- [x] 真机：TV（tv + phone flavor 各一次）、home（phone/board）走查
  - 录制中按左/右 → 不换源 + 提示；看门狗原地重载 → 录制不中断；人为卡流触发自动换源 → 录制保存、播放恢复

---

## 8. 风险与限制

- **带宽 ×2**：播放 + 录制各拉一路；弱 WiFi 下可能挤占播放缓冲。缓解：只录最低码率 variant、限制单路时长
- **动态 token URL**：signature 用「频道名 + 源列表」规避；若服务端每次下发列表都变，需再调整
- **直播滑动窗口**：靠 sequence 增量下载；分片过期太快可能漏片
- **加密流**：本期直接拒绝
- **双端互斥**：全局单例意味着同账号下两端不能同时录，需在 UI 提示清楚
- **版权合规**：仅家长手动、单次录制，不做后台批量；上线前确认内容授权范围

---

## 9. 验收标准

1. 两端直播页出现「开始录制」，儿童模式 / 悬浮小窗不出现。
2. 点开始 → 提示 + 红点角标 + 按钮变「停止录制（mm:ss）」；两端按钮状态同步。
3. 录制中切台 → 两端都自动保存并停止；切页（TV 设置页 / home 主控页）不中断。
4. 停止 / 离页 → 各自私有目录生成 `.ts`，可本地回放。
5. 一端录制中，另一端点开始 → 被拒并提示。
6. 两端 `flutter analyze` 与既有测试通过，遥控/触屏分层链无回归。

---

## 10. 建议实施顺序

1. **阶段一（共享包解析 + 单测）**：`hls_playlist.dart` + 测试 — 无副作用，先验证解析
2. **阶段二（共享包状态机 + 桥接 + 单测）**：`recording_controller.dart`、`recording_source_provider.dart` + 测试
3. **阶段三（TV 接线）**：LivePlayerWidget 上报 + 退出停止 + 角标；胶囊按钮 + 状态监听 + 四语文案
4. **阶段四（Home 接线）**：LivePlayerView 上报 + dispose 停止；live_page 控制区按钮 + 中文提示
5. **阶段五（验证）**：两端 analyze + 全量测试 + 真机走查


## 附录 E：存储位置 / 空间检测 / USB 与设置入口（2026-11-17 第二轮增强）

### 背景与修复的前提缺陷
- **致命 bug**：原 `RecordingController.instance` 未注入 `documentsDir`，`_resolveDocumentsDir()` 抛「录制目录提供者未注入」——真机点录制第一步必失败。单测因各自注入目录而未暴露。
- 修复：写入抽象为 `RecordingSink`；目录由存储策略层统一解析；单测保持 `documentsDir` 注入方式兼容。

### 存储位置（回答「放 app 内还是 Download、用户看不看得见」）
- 默认仍是 app 私有目录 `getApplicationDocumentsDirectory()/recordings/*.ts`（免权限），用户在文件管理器**看不到**。
- 新增 **SAF 选目录**（`ACTION_OPEN_DOCUMENT_TREE` + `takePersistableUriPermission`），可指向 U 盘 / SD 卡 / 任意目录；用户可见且**无需存储权限**。位置持久化到 `AppSettings`。
- 三方案取舍：A 保持私有+导出（改动小但需手动搬）、B SAF 选目录（**采用**，一次解决可见性 + USB）、C 公共 Download（Android 11+ 作用域存储受限，弃用）。

### 空间检测（回答「空间少是否提示并停止」）
- 原生 `StatFs` 查可用字节：internal 查 app 文件卷，custom 把 SAF tree 的 docId（`primary:` / `XXXX-XXXX:`）解析到 `/storage/<volume>` 再查；失败返回 -1，Dart 侧跳过判断。
- 录前预检 + 每落一个分片复查：低于阈值（设置页可配，默认 512MB）发 `lowSpace` 事件 → SnackBar 提示 + 自动停录保存。保留 2GB 单文件上限。

### 原生通道（`potatokid/recording`，两端 MainActivity 各挂一个 `RecordingStorageChannel`）
- `pickDirectory` / `freeBytes` / `openOutputStream` / `appendBytes` / `closeStream` / `listFiles` / `deleteFile`
- SAF 写入用 `DocumentsContract.createDocument` + `ContentResolver.openOutputStream`；content:// 无法用 dart:io 写，故分片过 MethodChannel 传给原生 OutputStream。
- 两端 compileDebugKotlin 均编译通过（仅既有 deprecation 警告）。

### 设置与入口（回答「放设置里吗」）
- **TV**：胶囊菜单加「录制中心」入口 → 新路由 `/recording` 弹层，两个 Tab（录制设置 / 录制文件）。不占「我的」页 16 行焦点链，遥控零影响。回放走独立路由 `/recording/playback`。四语各 +17 文案。
- **Home**：设置页内嵌 `RecordingSettingsSection`（存储位置 / 可用空间 / 单文件上限 / 低空间阈值 / 文件列表）；回放用独立 `RecordingPlaybackPage`。文案硬编码中文（home 无 i18n）。

### 新增/改动文件（第二轮）
- 共享包新增：`recording_sink.dart`（LocalFileSink / SafStreamSink）、`recording_platform.dart`（RecordingPlatform + MethodChannel 实现 + RecordedFile）、`recording_storage.dart`（存储策略）、`recording_library_controller.dart`（列表数据）；`recording_controller.dart` / `app_settings.dart` 改造；单测 +3。
- 两端原生：各新增 `RecordingStorageChannel.kt`，MainActivity 挂接 + onActivityResult 转发。
- TV：`features/recording/` 两个页面 + 路由三处 + 胶囊入口 + 四语文案。
- Home：`RecordingSettingsSection` + `RecordingPlaybackPage` + settings_page 插入。

### 验证
- 录制单测 23/23、共享包全量 340/340、两端原生 Kotlin 编译通过、三端 analyze（仅基线 issue）。
- TV 基线失败 5 个（parental/profile readonly，占位页不渲染播放器）、home 基线失败 3 个（parental `saveDeviceSettings` 缺参）+ 1 个 flaky 心跳测试（单跑通过），均与录制无关。
- **待真机验证**：U 盘选目录与写入、可用空间读数、低空间自动停、录制文件回放（U 盘 content:// 回放依赖设备播放器兼容性）。
