# 儿童模式实施进度

依据文档：`packages/pscreen_screen/docs/children_mode.md`

## ✅ 已完成

### 接入点核对
- 核对文档标注的全部关键文件（sleep_timer、reporting_service、message_command_executor、envelope_builder、realtime_channel、iptv_bloc、channel_name_matcher、app_settings、服务端 admin.js、宿主 UI），行号与文档 100% 吻合，方案可行。

### 阶段 1 核心代码（`flutter analyze` 无问题）

新建文件：
- `packages/pscreen_screen/lib/core/parental/parental_config.dart` — `QuietHour` / `ChildProfile` / `ParentalConfig`，生效判定式 `mode == 'on' && children.isNotEmpty`、悬空 id 过滤、quietHours 并集
- `packages/pscreen_screen/lib/core/media/kid_watch_timer_controller.dart` — 第二层双计时熔断核心：session/daily 按孩子分账、逐人阈值判定、换人仅新加入者起算、退后台 5 分钟重置 session、daily 解锁 10 分钟放行窗口、5 秒节流落盘、可注入时钟
- `packages/pscreen_screen/lib/core/parental/parental_state_controller.dart` — 唯一持有者，阶段 1 用本地临时配置（key `parental_local_config_v1`）
- `packages/pscreen_screen/lib/core/di/modules/parental_module.dart` — DI 注册（timer 先加载、controller 后加载，controller 为唯一权威）
- `packages/pscreen_screen/test/core/media/kid_watch_timer_controller_test.dart` — 18 个验收测试

修改文件：
- `packages/pscreen_screen/lib/features/msg/application/reporting_service.dart` — 心跳追加 `parental_watch` 上报（childIds + 双计时 + 日期）
- `packages/pscreen_screen/lib/core/di/screen_modules.dart` — 注册/注销 ParentalModule
- `packages/pscreen_screen/lib/core/utils/app_settings.dart` — `clearAllPersisted()` 显式豁免 `kid_watch_*` / `parental_*` 键（修复文档盲区：否则孩子可经「我的→重置」清零计时）

测试状态（2026-11-03 复验）：18 个全部通过；DEBUG print 已删除；`flutter analyze` 通过。

### 阶段 1 收尾（2026-11-03 完成）
- 原「持久化：重启后 session/daily 不归零」红灯已修复，18/18 通过。
- 到期动作接锁屏 UI：`kid_watch_timer_controller._fireThreshold` → `onThresholdReached` → `parental_lock_overlay.dart` 真实消费（initState 注册回调关消息浮层+重建，build 读 `locked` 双路兜底）；`parental_lock_overlay_test` 2/2（到阈值进锁屏 → PIN / 算术兜底解锁）。
- 本地临时配置调试入口：`parental_local_config_editor.dart` 挂载于设置面板（`settings_sheet_page`），勾选「当前观看」即设置 `activeChildIds`（模拟换人），保存经 `setActiveChildren` 生效。代码链路核对通过；UI 级操作未运行时验证。

### 阶段 0：链路验证（2026-11-03 完成）
- 隔离副本：`pscreen_server/server` 复制到 `/tmp/pscreen_stage0`，独立数据目录 + 隔离端口 3399 起服，全程未触碰线上 pm2。
- 端到端 6/6 通过（STAGE0_ALL_PASS）：HTTP 登录自动开通账号（MD5 口令）+ `deviceId` 自动建档（`machines.json` 可见 stage0-tv-001）；admin 登录；WS 握手 `ready`；`PUT /api/admin/machines/:id` 写 parental 配置 → 设备实时收到 `t:'config'` 帧（含 parental）。副本已清理。
- 备注：`/api/login` 的 `password` 字段须传 MD5（客户端先调 `/api/password_md5`）。

### 阶段 2：远程解锁（2026-11-03 代码核对 + 测试通过）
- `parental_unlock_request` 双发：`parental_unlock_code_controller._sendDouble`（owner 直投，空则 adminAccount 兜底 + `adminAccount = '1000001'`，`Future.wait` 并发）；**服务端已对该类事件按 `machine.parents` 扇出给该设备全部绑定家长（单条记录 + `audience`），非 owner 家长也能收到**。
- `message_command_executor.dart` L95 `case 'parental_unlock'`。
- 手机端三级角色分流与家长视图：`AccountSession.roleNotifier` 上供路由/弹层，`parental_page` 角色闸门（user 拒绝、parent 按 `machine.parents` 过滤、admin 代管全部）、`parental_unlock_overlay` 收 `parental_unlock_request` 弹确认卡并回发。
- `ParentalVerificationSheet`（设备端 349 行）+ PIN / 算术离线兜底：由 `parental_lock_overlay_test`（pin 模式 / 算术兜底）覆盖。
- 测试：`parental_unlock_code_controller_test`、`parental_attempt_gate_test`、`message_command_executor_parental_test`、`parental_unlock_tracker_test` 随包全量通过。
- 手机端确认卡 UI 交互未运行时验证。

### 阶段 3：白名单 + 配置来源切换（2026-11-03 代码核对 + 测试通过）
- `ParentalConfig` 切服务端 config：`realtime_channel.applyServerConfig` 解析 config 帧 parental（`_serverConfigured` / `serverStorageKey` 缓存兜底 / `onConfigApplied` 广播）；config 帧下发已在阶段 0 实测。
- `IptvBloc._viewOf` 唯一计算点末尾叠加 `applyParentalFilter`（strict 白名单交集 / mild 黑名单并集、多档案合并、防黑屏保护），`iptv_parental_filter_test` 255 行覆盖。
- 服务端小改：`normalizeMachine` 按白名单重建时保留 `parental`（坏数据 try/catch 容错）；阶段 0 实测 PUT 后保留并随 config 帧下发。
- 开机选人页：`parental_select_overlay.dart`（全屏覆盖层、每次启动只确认一次、已选档案悬空回退、与锁屏层序处理）挂载于 `main_app` Stack（L475），按键 gate（L168）。交互未运行时验证。

### 阶段 4：功能收敛（2026-11-03 完成）
- 「我的」Tab 整页替换为只读页：`MainApp._profileReadonly` 判定式 + `IndexedStack` 翻转，原页危险行（重置/远程）不可达；`_handleRootKey` 拦截（选人 gate > 锁屏吞键 > 消息浮层 > chrome 切 Tab 分发）。
- 锁屏层按键拦截修复：`parental_lock_overlay` 吞键（焦点在锁屏按钮时按键不再冒泡触发焦点转移切 Tab）。
- `main_app_profile_readonly_test` 3/3 通过（含未锁对照、锁屏吞键断言）；修复跨测试 rootBundle 缓存污染导致的整跑失败（翻译加载改同步读盘）。

### 回归基线（2026-11-03 全绿）
- `potatokid_screen`：11/11 通过 + `flutter analyze` 通过。
- `packages/pscreen_screen`：241/241 通过 + `flutter analyze` 通过。
- `pscreen_home`：369 通过 + 1 个既有失败（`live_page_test.dart` 倒计时，非本次引入）+ `flutter analyze` 通过。

## ❌ 未完成（需真机 / 真 App 运行时验证，代码已落地）

- 阶段 1：调试入口 UI 实际操作（勾选「当前观看」模拟换人后计时表现）。
- 阶段 2：手机端收到解锁请求 → 确认卡 / 验证 → 回发 → 设备解锁的端到端交互。
- 阶段 3：开机选人页真机交互；儿童模式下 IPTV 列表真机观感（strict/mild 两档）。
- 阶段 4：真机上「我的」只读页滚动与按键拦截手感。

## 建议下一步

真机回归上述 4 项运行时验证（无需改代码）；期间发现的问题按阶段逐项修复。
