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
- `packages/pscreen_screen/test/core/media/kid_watch_timer_controller_test.dart` — 19 个验收测试

修改文件：
- `packages/pscreen_screen/lib/features/msg/application/reporting_service.dart` — 心跳追加 `parental_watch` 上报（childIds + 双计时 + 日期）
- `packages/pscreen_screen/lib/core/di/screen_modules.dart` — 注册/注销 ParentalModule
- `packages/pscreen_screen/lib/core/utils/app_settings.dart` — `clearAllPersisted()` 显式豁免 `kid_watch_*` / `parental_*` 键（修复文档盲区：否则孩子可经「我的→重置」清零计时）

测试状态：19 个中 **18 个通过**；全量测试改动前基线 174 通过。

## ❌ 未完成

### 1. 阶段 1 收尾（当前卡点）— 1 个测试失败
- 「持久化：重启后 session/daily 不归零」：内存值 30 正确，落盘值 26。`_save` 异步链在 `fakeAsync` 内未完全排空（`elapse(Duration.zero)` 仍为 26），原因未定位，怀疑最后一次 30 秒处的 `_save` 未执行或被更早的写覆盖。
- 测试文件留有 `print('DEBUG raw=$raw')` 调试代码，**需删除**。

### 2. 阶段 1 剩余功能项
- 到期动作接锁屏 UI（`onThresholdReached` 目前无人消费，锁屏页可先用占位页）
- 本地临时配置调试入口（须能设置 `activeChildIds` 或「模拟换人」按钮，否则换人语义无从验收）

### 3. 阶段 0：链路验证（未开始）
- 服务端副本 `pscreen_server/server` 起服、登录自动生成设备记录、改配置收 `config` 帧

### 4. 阶段 2：远程解锁（未开始）
- `parental_unlock_request` 双发 `to: ownerAccount` + `to: '1000001'`
- `message_command_executor` 加 `case 'parental_unlock'`
- 手机端三级角色分流 + 家长视图、`ParentalVerificationSheet`、PIN/算术离线兜底

### 5. 阶段 3：白名单 + 配置来源切换（未开始）
- `ParentalConfig` 从本地临时配置切服务端 config
- `IptvBloc._viewOf` 注入温和档/严格档过滤
- 服务端 3 处小改（`normalizeMachine` 保留 parental 字段等）
- 开机选人页

### 6. 阶段 4：功能收敛（未开始）
- 「我的」Tab 整页替换为只读页 + `_handleRootKey` 拦截

## 建议下一步

先定位持久化测试 26 vs 30 的落盘差异（阶段 1 唯一红灯），删掉 DEBUG 打印，跑全量测试确认绿灯；再做锁屏占位 + 调试入口，阶段 1 即可验收。
