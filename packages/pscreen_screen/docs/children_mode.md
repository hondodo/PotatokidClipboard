# 儿童模式方案设计（电视端 IPTV）

> 状态：待评审
> 范围：电视端（Flutter Android TV，`packages/pscreen_screen` 共享包 + `pscreen/potatokid_screen` 宿主）、服务端（`pscreen_server`）、手机中控（`pscreen_home`）
> 依据：腾讯/优酷/芒果四层机制（内容准入 / 时间熔断 / 解锁验证 / 功能收敛）在本产品形态下的重新映射，及全仓代码落地点调研

---

## 0. 背景与结论

本产品没有片库、没有内容分级体系，管控对象是**电视频道**而非 VOD。因此四层机制映射为：

| 竞品机制 | 本产品映射 | 一句话方案 |
|---|---|---|
| 内容准入（分级片库） | 频道分组白名单 | 温和档做减法（`hideGroups`+`hideChannels` 黑名单）/ 严格档做加法（`allowGroups`+`allowChannels` 白名单交集），服务端 `device/config` 下发 |
| 时间熔断（单集时长） | 双计时熔断 | 单次连续 + 单日累计两个维度，本地持久化 + 心跳上报 |
| 解锁验证（扫码/人脸） | 手机中控远程解锁 | 自家 WS 链路 TV 发事件 → 手机确认 → 下发命令；PIN/算术题离线兜底 |
| 功能收敛（搜索/付费/账户） | 设置页收敛 | 儿童模式下「我的」整页替换为只读页，危险行（重置/远程账号/刷新频道等）不可达 |

**全仓现状**：grep `parental|kidMode|childLock|儿童` 在 Dart 代码中零命中——目前没有任何儿童模式实现，本方案是从零新增。

**前置事实（评审基线）**：

1. **设备注册已随登录自动完成**——新版服务端在登录时自动生成设备记录，电视端已能自动注册并登录，不存在"设备表缺电视导致 config 空转"的问题；**本方案不包含任何注册相关改动**。
2. **服务端权威副本已确定**——仅使用 `E:\Code\potatokid_clipboard\pscreen_server\server`（本方案行号均以此为准；仓库根 `server/` 为旧副本，不使用）。
3. **家长端承载已确定**——不新增独立"家长 App"，由现有手机中控 `pscreen_home` 承载，**新增 `parent` 角色**（`role` 从 `admin | user` 两级扩为 `admin | parent | user` 三级，第一版开发、无存量账号、无迁移逻辑）：`parent` 登录进**家长视图**（儿童档案/观看者/时长/解锁记录/遥控快捷入口），`admin` 默认进 admin 视图、家长能力作为入口之一，`user` 进现有中控台且无家长入口。电视端与 WS 协议零改动（见 4.2）。

---

## 1. 现状接入点地图

### 1.1 电视端已有能力

| 能力 | 位置 | 对本方案的意义 |
|---|---|---|
| 定时关闭倒计时 | `packages/pscreen_screen/lib/core/media/sleep_timer_controller.dart` | 第二层骨架；`setMinutes` L69、`onExpire` 宿主注入 L49、到期默认退出 L112-116。**L13-14 明确"不做持久化"**，且语义刻意为"一次性会话定时器" |
| 5 分钟心跳 + 结构化事件上报 | `packages/pscreen_screen/lib/features/msg/application/reporting_service.dart` | `adminAccount = '1000001'` L41、`heartbeatInterval = 5min` L44、`reportEvent` L298（→ `sendEvent(to: adminAccount)`）——观看时长上报直接复用 |
| 命令执行器 | `packages/pscreen_screen/lib/features/msg/application/message_command_executor.dart` | `switch(name)` L63，已有 10 个命令（`sleep_timer` L88 等），未知命令返回 false——**解锁命令在此加 case** |
| 下行信封构造 | `packages/pscreen_screen/lib/features/msg/protocol/envelope_builder.dart` | `buildCommandEnvelope(name, args)` L28 通用入口，手机端发解锁命令直接复用 |
| WS 事件上行 | `packages/pscreen_screen/lib/core/network/realtime_channel.dart` | `sendEvent({event, data, to})` L452——TV 发解锁请求；`deviceConfigs` 流 L342 + `_handleFrame case 'config'` L843-847——收管控配置 |
| 设备注册/上报 | `realtime_channel.dart` `sendReport` L629、`kindOfApp` L124 | 报告帧会带 `config` 回包，是配置的兜底获取路径 |
| 频道过滤管线 | `packages/pscreen_screen/lib/features/iptv/data/repositories/iptv_repository_impl.dart` `_compose` L42（`tvNameHide` 黑名单 L60 + `tvNameOrder` 置顶 L69）；`.../application/bloc/iptv_bloc.dart` `_viewOf` L72、`_applySourceRules` L102 | 第一层注入点。**L57/173/189/207 全部经 `_viewOf` 计算展示列表**，是唯一收敛点 |
| 通配匹配器 | `packages/pscreen_screen/lib/features/iptv/domain/channel_name_matcher.dart` | 精确全等 + `*` 通配，不退化为正则——白名单频道名匹配直接复用 |
| 频道分组字段 | `packages/pscreen_screen/lib/features/iptv/domain/models/iptv_channel.dart` `group` | m3u `group-title`，采样 1216 条 EXTINF 全部带分组（如 `📺央视频道`）——分组白名单天然可用 |
| 远程配置文件同步 | `packages/pscreen_screen/lib/app/config/data_files.dart`（8 个同步文件）+ `app_constants.dart` `githubDataBaseUrl` | 全局下发通道（无设备粒度），备选 |
| SharedPreferences 范式 | `packages/pscreen_screen/lib/core/utils/app_settings.dart` | key 带 `_v1` 后缀、`ensureLoaded()`、`clearAllPersisted()` L272——双计时持久化参照。**注意：`clearAllPersisted()` 清空全部键** |

### 1.2 服务端已有能力（`pscreen_server`）

| 能力 | 位置 | 对本方案的意义 |
|---|---|---|
| 设备配置解析 | `server/admin.js` `resolveMachineConfig` L337（机器 > 用户 > none，返回 `{homes, source, owner, ownerName, layoutKey}`） | **parental 字段挂在这里下发** |
| 配置响应/推送 | `deviceConfigResponse` L768、`pushConfigToMachine` L853（WS `config` 帧） | 改配置实时推电视端 |
| 设备 HTTP 接口 | `POST /api/device/register` L876、`/heartbeat` L884、`GET /config` L893、`GET|PUT /layout` L906/L925 | 中控屏 `pscreen_home` 的 `DeviceReporter` 对接目标；电视端经登录自动注册，无需调用 |
| WS 事件通道 | `server/realtime.js` `case 'event'` L807：`EVENT_NAME_PATTERN = /^[A-Za-z0-9_.:-]{1,64}$/` L19、数据上限 16KB L13、定向投递 + `persistEvent` 落 `events.jsonl` L854 | 远程解锁的事件往返**全部在此协议内，服务端零改动** |
| 历史事件查询 | `realtime.js` `case 'events'` | 家长端查当日观看时长 |
| 管理后台 | `web/admin.html` + `PUT /api/admin/machines/:id` L664 | 管控配置编辑入口落点 |

### 1.3 手机中控已有能力（`pscreen_home`）

- `lib/core/server/device_reporter.dart`：设备上报 / 60s WS report / 5min HTTP 兜底 / `channel.deviceConfigs.listen(_applyServerConfig)`——config 监听与上报的参考实现（注册已随登录自动完成，电视端无需新增注册代码）。
- `lib/features/remote_control/presentation/chat_page.dart`：`_channel.events.listen(_handleEvent)` L51——手机端收事件的先例；且会话已做线程订阅 `watchThread(peer, also: ['1000001'])` L68-73，`_belongs` L82-87 放行"TV ↔ 管理员"往来——**TV 发给 `1000001` 的消息/事件在绑定的 TV 会话里天然可见**（实时转发 + 历史快照），家长不换登录账号也能在会话时间线看到 TV→admin 的事件。
- 账号模型：单"实时账号"登录（默认 `home` + 本机设备号，设置页可改），WS 连接声明 `role: 'controller'`（客户端角色，与账号角色无关）；服务端账号 info JSON 的 `role` 字段**本方案从 `admin | user` 扩为 `admin | parent | user` 三级**（`admin.js` L5 枚举、L214 判定、admin 页 L741 下拉；第一版开发，无存量账号、无迁移回填），`/api/login` 响应 `user.role` 下发给客户端。**家长身份 = `role == 'parent'`（`admin` 兜底代管，见 4.2）**。
- **事件投递目标可单独指定（已核实），解锁请求双发**：现有 `reportEvent`（`reporting_service.dart` L298）固定走 `toAccount: adminAccount`（1000001）；**新增解锁事件不走 `reportEvent`，直接 `sendEvent` 单独指定 `to`——同一解锁请求（同一 `code`）双发两条：① `to: ownerAccount`（owner 直投）+ ② `to: '1000001'`（补 admin/成员的会话线程可见性，否则单发 ownerAccount 时别人开着会话页也收不到，见 4.2）**。`realtime_channel.dart` L452 `sendEvent({event, data, to})` 的 `to` 即任意账号（`MessageSender.sendEvent` 抽象层同样显式传 `toAccount`），服务端 `realtime.js` case `'event'` L807 按 `ACCOUNT_PATTERN` 校验 `to` 并定向投递 + 落库，**服务端零改动**；两条事件 `data` 带同一解锁短码，**手机端按短码去重**（同短码已有活动弹层则忽略后到的一条，见 4.2）。
- **向指定 TV 发命令的能力已确认（评审 P1-10）**：`live_remote_panel.dart` L45-153 已用 `buildCommandEnvelope('channel_next'/'volume_up'/...) + panel.onCommand` 向当前绑定 TV 发送 10+ 命令——`parental_unlock` 走同一投递通道，无需新增能力；**家长视图的遥控快捷入口直接复用该面板**（只开遥控面板，不打开完整中控台）。

### 1.4 电视宿主 UI 现状（`pscreen/potatokid_screen`）

- 「我的」页共 **17 行**（`profile_focus_controller.dart` L23 `rowCount = 17`），行索引：0 主题 / 1 语言 / 2 悬浮遥控器 / 3 硬解 / 4 画面 / 5 天气城市 / **6 定时关闭** / 7 后台播放 / **8 刷新频道** / 9 清理失效源 / 10 复制失效源 / 11 代理重试 / **12 重置** / **13 远程账号** / 14 版本 / 15 天气来源 / 16 免责声明。
- 危险行：**12 重置**（清空全部持久化缓存并重启，`profile_page.dart` L360）、**13 远程账号**（改 WS 账号，L363）、**8 刷新频道**（L348）。
- `main_app.dart`：4 Tab（直播/时间/屏保/我的）+ 根按键分发 `_handleRootKey`；`ConfirmDialog.isShowing` 是"弹窗期间让位"的既有先例。
- `settings_sheet_page.dart` 目前是**占位实现**（标题 + 关闭）；**当前 TV 端并未暴露 m3u 源地址编辑**（源来自服务端 `source.txt` 两跳拉取）——原调研中"Settings Sheet 里的 m3u 源地址、来源切换"需校正为上述危险行。
- `tv_scene_provider.dart` 场景 kind：`live / clock / screensaver / settings`——禁看时段与锁屏的场景挂载点。

---

## 2. 第一层：频道白名单准入

### 2.1 现状 → 缺口

- 现状：只有**黑名单**（`tvNameHide`）与**排序**（`tvNameOrder`），无白名单、无分组级开关、无服务端管控下发。
- 缺口：
  1. `resolveMachineConfig` 无 parental 字段；
  2. admin 页无编辑入口。

（设备注册已随登录自动完成，无注册类前置工作。）

### 2.2 设计

#### 配置数据结构（服务端 config 帧新增 `parental` 字段：多儿童档案）

```json
{
  "parental": {
    "mode": "off | on",
    "activeChildIds": ["c1"],
    "children": [
      {
        "id": "c1",
        "name": "小宝",
        "age": 6,
        "profileMode": "strict",
        "allowGroups": ["📺央视频道", "📺少儿频道"],
        "allowChannels": ["*少儿*"],
        "sessionLimitMin": 30,
        "dailyLimitMin": 120,
        "quietHours": ["22:00-06:00"]
      },
      {
        "id": "c2",
        "name": "姐姐",
        "age": 11,
        "profileMode": "mild",
        "locked": true,
        "hideGroups": ["📺购物频道"],
        "hideChannels": [],
        "sessionLimitMin": 60,
        "dailyLimitMin": 180
      }
    ],
    "unlockMode": "remote | pin | arith",
    "pin": "1234",
    "ownerAccount": "1000001"
  }
}
```

- `mode` 是**全局总开关**，取值 `off | on`（`off` = 整层关闭、全部字段忽略，存量设备零影响）；**档位唯一来源是各档案的 `profileMode`**——全局 mode 不再设 mild/strict 取值，避免"全局档位 vs 档案档位"双源冲突（评审 P0-3 定稿）。**观看规则全部下沉到 `children[]` 每个儿童档案**——家长在后台（admin/手机管理页）**添加孩子名称**与各自规则：可见/隐藏规则（mild: `hideGroups`/`hideChannels`；strict: `allowGroups`/`allowChannels`——按档位生效，见两档语义）、限额（`sessionLimitMin`/`dailyLimitMin`）、禁看时段（`quietHours`），`profileMode` 是该档案的档位（两档语义见下），`locked`（默认 false）标记该档案是否受验证保护。
- `activeChildIds` = **当前观看的孩子（可多位）**，电视端持久化（重启保持为默认预选），随 `parental_watch` 周期上报；开机确认/换人时另发 `parental_child_active` 事件——家长手机/admin 能看到"现在是谁在看"。
- **生效判定式（全文统一）**：`parental?.mode === 'on' && (children?.length ?? 0) > 0`。**不用"≠ off"**——老配置无 parental 字段时 `mode` 为 `undefined`，`undefined !== 'off'` 为 true 会误判；统一正向判定，缺省即未启用，也避免后续加字段时把短路条件改坏（评审收尾 #1）。`mode !== 'on'` 或 `children` 为空 = 该层不启用。
- `hideChannels` / `allowChannels` 沿用 `ChannelNameMatcher` 语义（精确 + `*` 通配），与既有 `tvNameHide` 一致，不引入正则；`hideChannels` 与 `tvNameHide` 完全同构，实现可直接复用。
- `ownerAccount` = **该 TV 的家长账号（`parent` 角色）**，缺省回退 `machine.owner`（`resolveMachineConfig` 已返回），再缺省回退 `ReportingService.adminAccount`（`1000001`）——解锁请求的投递目标，也是家长视图过滤"我管哪台 TV"的依据。家长视图按此过滤：`parent` 登录只看 `config.owner == 本账号`（或 `parental.ownerAccount == 本账号`）的电视档案；`admin` 不受限（看全部，用于代管）。

#### 选人流程（App 打开时弹出）

1. **触发（以家长下发生效状态为准）**：儿童模式的生效/取消由家长在后台控制，电视端**启动登录后查询当前正在生效的模式**——登录成功的 config 下发（WS `config` 帧 / report 回包的 `parental`）满足**生效判定式** `parental?.mode === 'on' && (children?.length ?? 0) > 0`（见上，缺省 undefined 不误判）→ 弹选人页，列出家长在后台添加的孩子名称；运行中不重复弹，下次打开再确认。
   - **时序兜底**：config 到达前先读本地缓存的上次 parental 状态立即判定（与频道缓存同策略），避免每次开机等网络；config 到达后以服务端为准校正（缓存说生效、服务端判定式不成立 → 关闭选人页/解除管控；反之则补弹）。
   - **家长取消即时生效**：运行中收到 config 且判定式不再成立（`mode !== 'on'` 或 `children` 被清空）→ 停计时、复原白名单/黑名单、**清空 `activeChildIds`、作废进行中的解锁短码、若正锁屏直接解除关闭**；若正停在选人页 → 直接进入直播，无需再选。
2. **选择**：勾选**一位或多位**（兄弟姐妹一起看），按遥控「确定」进入直播；**未确定前不进入直播**（停在选人页）；上次选择作为默认预选。
3. **验证闸门**：勾选包含 `locked: true` 的档案时，该次选择需家长验证（复用第三层解锁链路：远程确认或 PIN/算术）。验证 UI 统一抽 **`ParentalVerificationSheet`**（宿主共享组件），选人页与锁屏解锁共用同一套验证流程与防爆破计数，避免两套实现（评审 P1-8 定稿）。**家长应把更宽松的档案设为 `locked`**——否则孩子可每次开机自选宽松档案；不锁 = 信任型配置，由家长取舍。
4. **多选合并语义（取最严）**：
   - 频道列表：**每个选中档案都放行才显示**（strict 在白名单交集内 ∩ mild 在黑名单并集外）；
   - 限额：**逐人比较各自档案阈值**——任一选中孩子到**自己的** `sessionLimitMin` / `dailyLimitMin` 即锁屏（效果等价组合取最小，见 3.2）；
   - `quietHours` 取**并集**（任一档案的禁看时段命中即禁）；
   - 时长分账：session 与当日累计**同时计入每位选中孩子**。

#### 状态归属与数据流（评审 P1-5/6/7 一并定稿）

**新增 `ParentalStateController`（共享包，DI 注册，唯一持有者）**，持有 parental config、`activeChildIds` 与 `KidWatchTimerController`；订阅者：开机选人页、`IptvBloc`、锁屏页、`ReportingService`。

```
服务端 machines.json(parental) ── PUT /resolveMachineConfig ──▶ WS config 帧 / report 回包
                                                                  │ realtime_channel
                                                                  ▼
                                                    ParentalStateController（唯一持有者）
                                                     ├─▶ IptvBloc：config/换人变化 → 重放 _viewOf
                                                     ├─▶ 开机选人页：读 children + 默认预选；
                                                     │    确认 → setActiveChildren(ids)
                                                     ├─▶ KidWatchTimer：读限额/quietHours，写分账时长
                                                     └─▶ ReportingService：心跳取 childIds + 分账时长
```

- **config 到达**：`deviceConfigs`（L342）/ `sendReport` 回包（L629）→ controller 更新并写缓存 → 广播：IptvBloc 重放、选人页校正（生效/取消的权威信号）。
- **选人确认的驱动链路（此前只写了 config 重放，评审 P1-6 补齐）**：选人页 → `setActiveChildren(ids)` → ①IptvBloc 立即重放 `_viewOf`（频道列表随新组合切换）②`KidWatchTimerController` 按分账规则换人 ③发 `parental_child_active` 上报。
- **无效档案 id（评审 P2）**：controller 解析时过滤 `activeChildIds` 中已不在 `children` 里的 id（家长删档案后的悬空引用）；**部分悬空 → 过滤后继续用剩余 id；全部悬空 → 视为未选，回退选人页**。
- **`_viewOf` 签名已核实（评审 P1-5）**：现有即 `Future<List<IptvChannel>>`（`iptv_bloc.dart` L72），四个调用点（L57/173/189/207）均已在 `await`——注入过滤**无需改签名、无调用点改动**，澄清为非问题。
- **服务端存储已核实（评审 P1-7）**：parental 挂**机器记录**（`machines.json` 按 deviceId，与 `resolveMachineConfig` 的"机器 > 用户"层级一致）。当前 `PUT /api/admin/machines/:id` body 只白名单 `name/owner/homes`（admin.js L648-660），且 `normalizeMachine`（L283）按白名单重建记录会**丢弃未知字段**——需 **3 处小改**：PUT 新增 parental body 分支（校验后落盘）、`normalizeMachine` 保留 parental、`resolveMachineConfig`（L337）透传。"服务端零改动"仅指 WS 事件/命令协议层，不含 config 存储链路。

#### 过滤注入点（电视端）

统一注入 **`IptvBloc._viewOf()`**（`iptv_bloc.dart` L72），不改 `_compose`：

- `_viewOf` 是展示列表的唯一计算点（L57/173/189/207 全部经过它），config 推送到达时重放一次 `emit(state.copyWith(channels: await _viewOf(_fullChannels)))` 即可生效，与既有"缓存优先 + 后台替换"策略同构。
- `_compose` 属 repository 层，合并多源后的全局黑名单/排序语义保持不动，避免两层过滤互相掩盖。
- **必须遵守 L59 防黑屏保护**：白名单计算结果为空（配置错误、分组名拼错）时不应用，保持现状列表 + 打日志，否则整份列表被清掉会导致黑屏。

#### 生效时机（家长后台下发，非本地开关）

1. 启动：登录后先读 SharedPreferences 缓存里的 parental 配置立即生效（与频道缓存同策略）——保证离线/未联网时管控不空窗；
2. WS `config` 帧（`realtime_channel.dart` L843）或 `sendReport` 回包（L629）到达 → 更新缓存 → 重放 `_viewOf`；**这是生效/取消的权威信号**（家长在后台改配置即实时推送）；
3. 频道列表刷新（m3u 拉取完成）→ `_viewOf` 天然重新过滤。

#### 两档语义（唯一按档案 `profileMode` 生效；字段按档位显隐；减法档/加法档对照）

字段名即语义，每个字段**要么生效、要么忽略**，没有模糊地带；admin 表单按档案档位显隐对应字段，杜绝"家长填了不生效的字段"（评审定稿）：

- **温和档（`profileMode = mild`）＝减法**：`hideGroups` 分组黑名单 + `hideChannels` 频道名黑名单，**两者取并集隐藏**（`hideChannels` 与既有 `tvNameHide` 完全同构，复用 `ChannelNameMatcher` 精确/`*` 通配语义，实现成本≈零）；**`allowGroups` / `allowChannels` 忽略**。
- **严格档（`profileMode = strict`）＝加法**：`allowGroups` 分组白名单 + `allowChannels` 频道名白名单，**两字段取交集**（只展示命中分组且命中频道名的频道）；**`hideGroups` / `hideChannels` 忽略**。严格档下频道条即白名单本身，配合第四层收敛后孩子无法改配置。
- **跨档案合并（多孩选中）**：一个频道可见 ⇔ **每个选中档案都放行**——strict 档看"是否在其白名单交集内"，mild 档看"是否在其黑名单并集外"；即各档案规则的交集，语义仍归 2.2 多选合并。
- 空值 = 该字段不限制；严格档 `allowGroups` 为空 = 无分组约束、等于没生效，admin 侧校验必填。

> 分组名即 m3u `group-title` 原文（如 `📺央视频道`），admin 页编辑时提供当前机器最近一次上报的分组列表做下拉选择，避免手输拼错（拼错的后果由 2.2 防黑屏保护兜底，但白名单拼错会退化为"全部不显示"→ 触发保护 → 等于没生效，需在 admin 侧校验）。

### 2.3 改动清单

| 边界 | 文件 | 改动 |
|---|---|---|
| 服务端 | `admin.js`：`PUT /api/admin/machines/:id` L639（新增 parental body 分支，校验后落盘）+ `normalizeMachine` L283（白名单保留 parental）+ `resolveMachineConfig` L337（透传） | parental 挂机器记录的存储与下发，**3 处小改**（已核实当前 body 只收 name/owner/homes、normalize 会丢未知字段——见 2.2 状态归属小节） |
| 服务端 | `pscreen_server/web/admin.html` | parental 编辑表单：**儿童档案增删改**（名称/年龄/档位/时长/时段/`locked` 验证保护标记）+ **按档案档位显隐字段**（**mild 显 `hideGroups` + `hideChannels` 黑名单；strict 显 `allowGroups` + `allowChannels` 白名单**）+ 全局解锁方式 |
| 服务端 | `admin.js` L5/L214 + `admin.html` L741 | **`role` 枚举扩三级** `admin \| parent \| user`（家长操作允许 `parent`+`admin`、拒绝 `user`；下拉加「家长」）——协议格式不变 |
| 共享包 | 新增 `ParentalConfig` 模型 + `ParentalStateController`（`features/iptv/domain` 或 `core/config`，DI 注册） | `children[]` 与 `activeChildIds` 解析（**过滤悬空 id**）、按 id 查档案、多选合并（频道逐档案放行、限额逐人比较）、config/换人广播（见 2.2 状态归属小节）、**`mode !== 'on'` 短路** |
| 共享包 | `realtime_channel.dart` `deviceConfigs` L342 / `sendReport` L629 | 接收 parental 配置（WS `config` 帧 + report 回包）；**注册已随登录自动完成，无需新增注册代码** |
| 共享包 | `iptv_bloc.dart` `_viewOf` L72 | 按**选中档案**注入白名单/黑名单过滤（strict 白名单交集、mild 黑名单并集，跨档案逐档案放行）+ config/换人时重放 + 空结果保护 |
| 宿主 | 开机选人页（新场景/页面）+ `ParentalVerificationSheet` | 弹出条件、勾选一位或多位、遥控「确定」进入；`locked` 档案走验证闸门，与锁屏解锁共用 `ParentalVerificationSheet`（阶段 2 后接入远程确认，此前先落 PIN） |

---

## 3. 第二层：双计时熔断

### 3.1 现状 → 缺口

- 现状：`SleepTimerController` 是**单次会话**倒计时，注释 L13-14 明确"不做持久化，否则重启后会莫名其妙继续倒数并自动退出"——这个语义是刻意的，不能直接改造成儿童计时器。
- 缺口：
  1. 无"单日累计"维度（直播换台场景下尤其需要——换台不能算重新开始）；
  2. 无持久化（重启归零 = 孩子重启 App 即绕过）；
  3. 无禁看时段；
  4. 无锁屏动作（到期只有退出 App）。

### 3.2 设计

#### 新建 `KidWatchTimerController`（不改造 `SleepTimerController`）

理由：两者的状态语义相反——一个是"重启不该继续"的会话定时器，一个是"重启必须继续"的持久管控状态。混用会同时破坏两边。复用的只是 `ChangeNotifier` + 左上角剩余时间的展示模式。

**两个计时维度**：

| 维度 | 状态 | 重置时机 | 到阈值动作 |
|---|---|---|---|
| 单次连续观看 | `sessionStartMsByChild`（按孩子分账，墙钟） | 进入锁屏 / 离开观看态超 5 分钟（口径见下） / **换人：仅新加入孩子从 0 起算** | 进锁屏 |
| 单日累计 | `dateKey(yyyy-MM-dd)` + `dailySecByChild`（按孩子分账） | 日期翻转（每次 tick 校验 `dateKey` 变化即清零） | 进锁屏 |

- **换台不重置**：session 基于"观看场景（live / clock / screensaver）的连续在看时长"（见下方场景口径），与频道状态解耦——`channel_changed` 事件不打断计时。
- **场景计入口径（定稿，评审收尾 #4）**：`live` / `clock` / `screensaver` **计入** session 与 daily（"切到屏保不算离开" = 屏保照常计时且不重置 session，防"切屏保挂机"既刷新单次限额又逃过累计）；`settings` 与 `parental_lock` **不计入**（设置操作与锁屏本身不计费）；App 退到后台（进程存活但非前台）**超过 5 分钟 → 结算并重置 session，daily 不动**——"离开观看态超 5 分钟"即指此情形，`5 分钟` 的归属明确、验收照此测。
- **多孩同看（session 也按孩子分账，堵"加人续命"）**：`sessionSecByChild[childId] = now - sessionStartMsByChild[childId]`、`dailySecByChild[childId]` 各自累加；**换人时只重置新加入孩子的 session，仍在组合中的孩子保留原 `sessionStartMsByChild[childId]`（已看时长不清零，防"看 25/30 分钟后拉弟弟进来重开一轮"的绕过）**。
- **锁屏判定（直接落在分账结构上，评审收尾 #3）**：**任一选中孩子 `c` 的 `sessionSecByChild[c] >= c.sessionLimitMin`（daily 同理 `dailySecByChild[c] >= c.dailyLimitMin`）即锁屏**。该式与"组合阈值取最小"等价，但**实现时不应对所有人套同一个阈值**——每个孩子与**自己档案**的限额比较。
- **当日额度用尽后的解锁语义（定稿：方案 B，评审二次核对 #1）**：若 daily 到阈值锁屏后家长解锁，**不能直接清零 `dailySecByChild`**（否则点一次解锁 = 重置一天额度，方案 A），也不能置之不理（否则下一 tick `dailySecByChild[c] >= c.dailyLimitMin` 仍成立 → 解锁即再锁，死循环）。定稿：解锁成功时为该孩子写入 **`unlockGraceUntilMs = now + 放行窗口`**（如 10 分钟）；**窗口内跳过 daily 判锁**（session/quietHours 判锁照常），窗口结束回锁、等次日翻转。备选留档：A 解锁即豁免当日（太松）、C daily 锁不可解锁（家长无法临时加看），v1 取 B。
- 阈值来源：**各选中孩子自己档案**的 `sessionLimitMin` / `dailyLimitMin`（逐人比较，见上）；任一为 0/缺失 = 该维度不启用。
- **到期动作**：儿童模式下进锁屏场景（见第四层），而非 `SystemNavigator.pop()`。`SleepTimerController.onExpire`（L49）本身就是宿主注入点——若家长还开着普通定时关闭，两者独立工作，互不覆盖。

**持久化**：

- 独立类 + 独立 key（`kid_watch_timer_v1`），参照 `AppSettings` 范式（`ensureLoaded()`、`_v1` 后缀），**不放进 `AppSettings`**——因为 `AppSettings.clearAllPersisted()`（L272）会清空全部键。持久化内容：`{dateKey, dailySecByChild, sessionStartMsByChild, activeChildIds, unlockGraceUntilMs}`。
- **关键安全点**：`profile_page.dart` L360 的「重置」行调用的正是 `clearAllPersisted()`。若儿童状态键在其中，孩子可通过"我的 → 重置"一键清零计时。双保险：
  1. 第四层整页替换后重置行不可达（阶段 4）；
  2. 儿童状态**从设计上就不进入 `clearAllPersisted()` 的清理范围**（独立类天然满足），家长解除儿童模式时走显式的清除入口。

**上报（复用现有通道）**：

- `ReportingService` 5 分钟心跳（L111/L271）附带一条结构化事件：`reportEvent('parental_watch', {childIds, sessionSecByChild, dailySecByChild, date})`（L298）→ 服务端 `case 'event'` 原样落 `events.jsonl`（`realtime.js` L807/L854），**服务端零改动**——载荷按孩子分账，家长端可完整还原"谁看了多久"（评审 P1-4 定稿）；开机选人确认/换人时另发 `parental_child_active {childIds}` 事件——家长手机/admin 据此看到"现在是谁在看"；
- 家长端查看：`case 'events'` 历史查询已支持，手机中控按 `event=parental_watch` / `parental_child_active` 过滤当日记录即可。

**禁看时段（quietHours）**：

- 服务端下发 `["22:00-06:00"]`（支持跨午夜），电视端**本地时钟**判断——不做服务端时间校验，简单且离线可用；多孩选中时取各档案 `quietHours` 的**并集**；
- 执行点：场景切换为 `live` 时（`TvSceneProvider`）与每次 `session` tick 时校验；命中则不进直播，直接停在锁屏/待机场景；
- 已在观看中跨入时段 → 下一个 tick 触发锁屏。

### 3.3 改动清单

| 边界 | 文件 | 改动 |
|---|---|---|
| 共享包 | 新增 `core/media/kid_watch_timer_controller.dart` | 双计时分账（`sessionStartMsByChild`/`dailySecByChild`、换人仅新加入者起算、**逐人比较各自档案限额**、daily 解锁放行窗口 `unlockGraceUntilMs`、quietHours 并集、屏保照常累计）+ 持久化 + 日期翻转；到阈值回调宿主（进锁屏） |
| 共享包 | `reporting_service.dart` L271/L298 | 心跳附带 `parental_watch`（`childIds` + 分账时长）；开机/换人发 `parental_child_active` |
| 共享包 | `msg_module.dart`（DI） | 注册新控制器 |
| 宿主 | `main_app.dart` / 锁屏场景 | 接 `onExpire` → 进锁屏；左上角展示位**儿童模式下优先显示 KidWatchTimer 剩余，普通定时关闭降级为到期通知**（并存冲突的定稿口径，评审 P2） |
| 服务端 | 无 | 事件落库/查询已支持 |

---

## 4. 第三层：远程解锁 + PIN 兜底

### 4.1 现状 → 缺口

- 现状：WS 协议三件套齐全——上行事件 `sendEvent`（`realtime_channel.dart` L452）、下行命令 `buildCommandEnvelope`（`envelope_builder.dart` L28）、命令分发 `switch(name)`（`message_command_executor.dart` L63）。服务端事件通道对事件名只做 `EVENT_NAME_PATTERN` 校验（`realtime.js` L19），16KB 数据上限（L13），定向投递 + 落库。
- 缺口：无解锁命令、无锁屏 UI、无 PIN、无短码生成。**协议层零缺口，纯新增。**

### 4.2 设计

#### 主链路：自家 WS 闭环（相对竞品的差异化，优先做）

```
[电视端] 触发锁屏（计时到点 / 禁看时段）
   │  生成 6 位短码（60s 有效期，一次性）
   │  sendEvent(event: 'parental_unlock_request', data: {code, deviceId, reason}) ×2
   │     ① to: ownerAccount（owner 直投）  ② to: '1000001'（会话线程可见）——同 code 双发   ← realtime_channel.dart L452
   ▼
[服务端] case 'event' → 校验 EVENT_NAME_PATTERN → 定向投递 + 落 events.jsonl   ← realtime.js L807
   ▼
[手机中控 pscreen_home] events 监听（chat_page.dart 先例）→ 弹确认卡片
   │  家长点「解锁」
   │  buildCommandEnvelope('parental_unlock', {code})   ← envelope_builder.dart L28
   ▼
[服务端] 既有 cmd 路由（零改动）
   ▼
[电视端] MessageCommandExecutor 新增 case 'parental_unlock'
        校验 code 匹配 + 60s 未过期 + 未使用过 → 解除锁屏 → 清码
        + 写入 unlockGraceUntilMs（daily 锁的放行窗口，见 3.2 方案 B）
```

- 事件名 `parental_unlock_request`、命令名 `parental_unlock` 均满足 `EVENT_NAME_PATTERN`，**服务端零改动**。
- **双发（定稿）**：同一解锁请求（同一 `code`）发两条事件——① `to` = `parental.ownerAccount ?? machine.owner ?? '1000001'`（owner 直投）；② `to` = `'1000001'`（补会话线程可见性）。两条 `data` 完全相同（含同一短码），**手机端按短码去重**：同 `code` 已有活动弹层时忽略后到的一条（不同 event id、相同短码，故按 `code` 判重而非 event id）；短码 60s 过期或已消费后换新码自然弹新卡。
- **为什么必须双发**：单发 ① 时，`forwardThread` 的命中条件是"对方是订阅者本人 或 在 `also` 集合里"（`threadPeerOf`，`realtime.js` L402-411），而 `chat_page` 订阅固定 `also: ['1000001']`——事件 `to` 是 owner 自己账号时，admin/user 开着会话页也收不到，4.2「user 会话线程可见」那句就不成立；发 ② 才能同时覆盖。
- **两条到达路径（均为已有能力）**：
  1. **直投**：手机登录账号 == 事件 `to` 时，服务端按账号定向投递，任意页面可达、离线排队（`enqueueOffline` L778 / `flushOffline` L689）——owner 走 ①，`1000001` 登录者走 ②；
  2. **线程转发**：手机打开该 TV 的会话页（`thread_watch also=['1000001']`，`chat_page.dart` L71）时，② 的事件经 `forwardThread`（`realtime.js` L871-875）实时转发进时间线，`_belongs`（L82-87）天然放行——**普通成员/未登录 owner 账号的 admin 不换登录账号也能在会话里看到解锁请求**（会话历史快照 `threadItemsFor` 也包含）。
  - **重复场景（去重要覆盖的）**：owner 手机开着会话页 → 直投 1 条 + ② 线程转发 1 条；或 `ownerAccount` 缺省回退到 `1000001` → ①② 同账号直投 2 条。均由手机端短码去重消掉。
  - **缺口仅在**：手机账号既非 `ownerAccount` 也非 `1000001` **且** TV 会话页未打开——此时无实时路径，请求只落历史，打开会话可见但短码可能已过期，需"重新请求"或 PIN 兜底。
- 短码优先于二维码：手机中控是自家常驻 App，事件推送直达，无需扫码这一步。二维码（内容为 `parental://unlock?...` 深链）留作 v2 增强，便于"家长不在家时孩子拿遥控对着码、邻居手机扫"之类场景再评估。

#### 家长端承载：三级角色 + 家长视图（定稿）

**角色模型（第一版即三级，无存量迁移）**：`admin`（超管/运维）| `parent`（家长，**新增**）| `user`（普通家庭成员）。服务端 `admin.js` L5 枚举扩项、L214 判定扩为"家长操作允许 `parent` + `admin`、拒绝 `user`"、admin 页 L741 下拉增加「家长」；`/api/login` 的 `user.role` 自然下发新值，**协议格式零改动**。

**登录分流（pscreen_home）**：

| 角色 | 默认首页 | 家长能力 | 中控台（遥控/场景/天气/设置） | admin 后台 | 解锁弹层 |
|---|---|---|---|---|---|
| admin | admin 视图 | ✅ 作为入口之一（代管/救急） | ❌ 不默认混入 | ✅ | 注册（可代管） |
| parent | **家长视图（新增）** | ✅ 主视图 | ❌ 仅遥控快捷入口 | ❌ | 注册 |
| user | 现有中控台 | ❌ 无入口 | ✅ 原样 | ❌ | 不注册（收了也不弹） |

- **解锁弹层仅 `parent` / `admin` 注册** `events.listen`；`user` 登录即使收到 `parental_unlock_request` 也不弹卡、不可下发 `parental_unlock`，避免误操作。
- **`user` 仍可能"看得见"（有意为之，评审会点一句）**：事件会经 TV 会话线程（`_belongs` 放行）出现在会话时间线里，普通家庭成员能看到"电视在请求解锁"，但**没有操作能力**——实施时以"**能弹 = 能点**"为唯一授权口径，不要误以为 user 完全看不到。
- **投递目标与判定统一到 owner**：`parental.ownerAccount ?? machine.owner ?? '1000001'`；`parent` 登录只看自己管的 TV（`config.owner == 本账号`），`admin` 能看全部（代管）。这同时消掉原「显隐用 admin、投递用 ownerAccount」的双身份拧巴点——**收到就能点，点不了就是没权限收**。

**家长视图页面模块（`parent` 登录后的首页，只含家长相关内容，不含中控台的场景/天气/设置、不含 admin 后台）**：

1. **儿童档案 CRUD**：名称（家长添加）、年龄、档位（mild/strict）、限额、时段、`locked`；按档位显隐字段（mild 显 `hideGroups`+`hideChannels`，strict 显 `allowGroups`+`allowChannels`）；分组下拉用该 TV 最近上报的分组列表；
2. **当前观看者**：`activeChildIds` 最新上报 + 分档案当日时长（来自 `parental_watch` 分账载荷）；
3. **解锁请求记录**：历史 `parental_unlock_request`，短码未过期的可点「解锁」补发 `parental_unlock`；
4. **设置**：`ownerAccount`、解锁方式（`remote/pin/arith`）、PIN 设置；
5. **遥控快捷入口**：点开只渲染遥控面板（复用 `live_remote_panel.dart`），**不打开完整中控台**——家长平时用手机遥控电视，又不把中控台整个暴露；
6. **账号一致性引导**：校验当前登录账号与 `parental.ownerAccount`/`machine.owner` 是否一致；不一致时提示"你登录的不是这台 TV 的家长账号，收不到解锁请求"（但仍可经 TV 会话线程只读看到）。

- **解锁确认 = 事件驱动的全局弹层**（保留既有设计）：任意页面收到 `parental_unlock_request` 即在上层弹确认卡，不依赖当前所在页面，家长停在别的页面也不会漏掉。
- **admin 登录**：默认进 admin 视图，家长视图作为其中一个入口（点击进入同一套页面，按 owner 过滤关闭 = 看全部，用于代管/救急）——**admin 视图直接复用家长视图代码、只放开 owner 过滤**，避免两套 CRUD 页面（风险 #13）。
- **事件投递与离线排队**：双发两条事件，① 直投的离线入队对"登录账号 == `ownerAccount`"的设备生效、② 直投的离线入队对 `1000001` 登录设备生效；线程转发只推在线且订阅中的 socket（会话页打开期间）。同一手机可能收到两条（owner 开会话页 / `ownerAccount` 即 `1000001`），**弹层按短码去重，同 `code` 只弹一张**。两条路径短码均 60s 过期，过期后电视端提示"重新请求"。
- **注意**：pscreen_home 默认账号是 `home` + 本机设备号（设置页可改）。家长需用 **`parent` 角色账号**登录才能进家长视图、收到任意页面的解锁弹层与离线排队；用 `user` 账号登录只能经 TV 会话线程只读看到解锁请求（会话页打开期间实时，短码可能已过期）。多家长 v1 不支持，后续把 `ownerAccount` 扩成数组即可，投递机制不变。

#### 离线兜底：PIN / 算术题（纯本地，WS 断线时可用）

- 按 `parental.unlockMode`：
  - `pin`：锁屏页 4 位数字输入（家长在 admin 设置）；
  - `arith`：三选一随机加法（如 `7 + 8 = ?`，固定一位数加法，对低龄是门槛、对家长零负担）；
  - `remote` 模式下仍展示算术题作为断线兜底（否则断线即死锁）。
- 防爆破：连续错 5 次本地锁定 60s（计数持久化，重启不清）。

#### 锁屏 UI 本身

- 电视宿主新增锁屏场景（复用 `tv_scene_provider.dart` 的场景机制，新增 kind 如 `parental_lock`，或作为 `settings` 场景之上的全屏覆盖层）；
- 展示：剩余时间/已看时长、6 位短码、"请在手机上确认"提示、兜底解锁入口；**多孩时"剩余"展示当前组合中按逐人判定最先触发的孩子的剩余时间**（即最早到阈值者；信息足够，不轮播）；
- 锁屏期间根按键分发（`main_app.dart` `_handleRootKey`）只放行解锁相关输入，其余吞掉；
- **系统级按键（评审 P2）**：`_handleRootKey` 只拦遥控按键，Android TV 的 Home/系统返回拦不住——**实施时确认宿主是否以 launcher 形式运行**；即便 Home 退到桌面，双计时状态持久化，孩子重进 App 时按已超阈值直接回到锁屏，锁屏在 App 内不会被绕过（可接受口径）；
- 验证 UI 复用 `ParentalVerificationSheet`（与选人页 `locked` 闸门同一实现，见 2.2）。

### 4.3 改动清单

| 边界 | 文件 | 改动 |
|---|---|---|
| 共享包 | `message_command_executor.dart` L63 switch | 新增 `case 'parental_unlock'` |
| 共享包 | `envelope_builder.dart` | 如需电视端主动请求信封可加构造器（`sendEvent` 已够用则不加） |
| 宿主 | 新增锁屏页面/场景 + `ParentalVerificationSheet` | 短码生成（**同 `code` 双发两条 `sendEvent`：`to: ownerAccount` + `to: '1000001'`**）、倒计时、PIN/算术题、防爆破；验证组件与选人页 `locked` 闸门共用 |
| 手机端 | `pscreen_home` **新增家长视图 + 三级分流 + 弹层注册**（新首页/页面组） | 登录按 `user.role` 分流（admin → admin 视图、parent → 家长视图、user → 中控台）；解锁弹层 `events.listen` **仅 `parent`/`admin` 注册**（user 不弹、不可下发），**弹层按短码去重（同 `code` 已有活动弹层则忽略后到的一条，消双发重复）**；家长视图含档案 CRUD、当前观看者、分档案时长、解锁记录、设置、**遥控快捷入口**（复用 `live_remote_panel.dart`，不开中控台）；需先让 `PtoolsUtil.login` 保留响应中的 `user.role`（当前丢弃响应体，仅校验 code）。**不新增家长 App** |
| 服务端 | `admin.js` L5/L214 + `web/admin.html` L741 | `role` 枚举扩为 `admin \| parent \| user`；家长操作允许 `parent` + `admin`、拒绝 `user`；下拉增加「家长」——协议格式不变 |

---

## 5. 第四层：功能收敛

### 5.1 现状 → 缺口

- 危险旁路盘点（校正后）：
  1. **重置行**（`profile_page.dart` L360，`_resetRow = 12`）——清空全部持久化缓存并重启，**可清零第二层计时**（3.2 已做独立 key 双保险，且整页替换后该行随原页不可达）；
  2. **远程账号行**（L363，`_remoteRow = 13`）——改 WS 账号可连到别的控制端；
  3. **刷新频道行**（L348，`_refreshRow = 8`）——重拉 m3u，若白名单配置已下发则无害，但仍属可打扰项；
  4. **「我的」Tab 整体**——17 行里大部分（主题/语言/硬解/画面/天气源/代理重试）无直接内容风险，但行多手杂；
  5. **频道条自由切台**——严格档下频道条已被白名单收窄，天然安全；温和档是否允许保留，作为 parental 可配项（v1 不做，白名单已覆盖主要风险）。
- **方案定稿（评审 P1-9 二选一 → 整页替换）**：儿童模式下「我的」Tab 整页替换为新增只读页（儿童模式状态 + 当前已看时长 + 请求解锁入口），**不做"行列表数据化"重构**——`rowCount = 17` 常量与 17 行结构全部不动，危险行随原页一并不可达，改动最小、off 模式零影响。
- **缺口（已消解）**：原缺口"动态隐藏行需先把行列表数据化（`profile_focus_controller.dart` L23 `static const`）"在整页替换定稿下**不再需要**——该重构从阶段 4 移除（风险 #1 消解）。

### 5.2 设计

- **整页替换（定稿）**：`main_app.dart` 儿童模式（**生效判定式成立**，`parental?.mode === 'on' && children` 非空，见 2.2）下，进入「我的」不渲染 `profile_page`，替换为只读页——展示"儿童模式已开启 + 当前已看时长 + 请求解锁"；重置(12)/远程账号(13)/刷新频道(8)/代理重试(11) 等危险行随原页一并不可达，无需逐行隐藏。
- **不改 `ProfileFocusController`**：`rowCount` 与各 `_xxxRow` 常量全部保持 `static const` 不动（与原"行列表数据化"方案二选一，评审 P1-9 定稿为整页替换——工作量大幅缩小）。
- **根按键拦截**：`_handleRootKey` 在锁屏场景吞掉除解锁外的输入（已在第三层覆盖）；儿童模式下进入「我的」的按键直接路由到只读页。
- 与前几层的耦合：本层的"儿童模式开关"状态即 **2.2 生效判定式**（`parental?.mode === 'on' && children` 非空，来自 config），不需要独立开关。

### 5.3 改动清单

| 边界 | 文件 | 改动 |
|---|---|---|
| 宿主 | `main_app.dart` | 「我的」Tab 儿童模式下整页替换为只读页 + `_handleRootKey` 拦截 |
| 宿主 | 新增只读页（我的-儿童模式态） | 模式状态 + 当前已看时长 + 请求解锁入口 |
| 宿主 | `profile_focus_controller.dart` / `profile_page.dart` | **无改动**（定稿为整页替换，17 行结构不动——原行列表数据化方案作废） |
| 共享包 | 无 | 本层纯 UI |

---

## 6. 协议与数据结构扩展汇总

| 类型 | 名称 | 方向 | 载荷 | 服务端改动 |
|---|---|---|---|---|
| config 字段 | `parental` | 服务端 → TV | 见 2.2 JSON | **3 处小改**：PUT parental 分支 + `normalizeMachine` 保留 + `resolveMachineConfig` 透传；admin 编辑表单 |
| WS 事件 | `parental_unlock_request` | TV → 家长 | `{code, deviceId, reason}` ≤16KB，**同 code 双发两条**（`to: ownerAccount` + `to: 1000001`，手机端按 `code` 去重） | **零**（通用 event 路由） |
| WS 事件 | `parental_watch` | TV → 服务端 | `{childIds, sessionSecByChild, dailySecByChild, date}`（按孩子分账） | **零**（落 events.jsonl） |
| WS 事件 | `parental_child_active` | TV → 服务端 | `{childIds}`（开机选人确认/换人时发） | **零**（落 events.jsonl） |
| WS 命令 | `parental_unlock` | 家长 → TV | `{code}` | **零**（通用 cmd 路由） |
| 本地持久化 | `kid_watch_timer_v1` 等 | — | 双计时分账（`sessionStartMsByChild`/`dailySecByChild`）、`activeChildIds`、**`unlockGraceUntilMs`（daily 解锁放行窗口）**、防爆破解锁计数 | — |
| HTTP | 设备注册 | TV → 服务端 | 登录时自动生成设备记录（新版服务端） | **零**（电视端已能自动注册并登录，本方案无注册类改动） |
| HTTP | 账号角色 | — | — | `role` 枚举 `admin \| parent \| user`（`admin.js` L5/L214、admin 页 L741）；**协议格式不变**，`/api/login` 的 `user.role` 自然下发新值；第一版开发无存量迁移 |

---

## 7. 分阶段实施计划

按既定优先级排序。**依赖关系（评审 P0-1 修正）**：阶段 1/2 期间后台还没有 parental 编辑表单（阶段 3 才有），阈值与开关来自**本地临时配置**过渡（见阶段 1），故阶段 1/2 可独立验收但**不是端到端**；阶段 3 落地服务端下发后替换临时配置来源，并负责端到端验收（其本身依赖阶段 0 的 config 下发链路验证）。

### 阶段 0：链路验证

1. 服务端副本已确定：仅用 `pscreen_server/server`（仓库根 `server/` 为旧副本，不改动）；
2. 验证"登录自动生成设备记录"与部署版本一致：TV 登录后 admin 设备表可见该电视，改配置能收到 WS `config` 帧（本方案无注册类代码改动，若部署版本缺失该行为则在 login 侧补自动建档）；
3. 验收：admin 页能看到电视设备，改配置后电视端收到 `config` 帧。

### 阶段 1：双计时熔断 + 本地持久化（最刚需，纯本地）

> **过渡方案（P0-1 定稿）**：本阶段后台尚无 parental 表单，引入**本地临时配置**——SharedPreferences 手写 key（配一个调试入口或默认值）承载 `children[]` 最小子集（id/name/profileMode/限额/quietHours）与 `mode` 开关；`ParentalStateController` 先按本地配置工作。阶段 3 落地服务端下发后，**同一 controller 换读 config**，本地配置降级为调试入口。阶段 1/2 的验收全部基于该临时配置，**不声称端到端**；"看满阈值进锁屏"的阈值即来自固定测试值（如 session 5min / daily 30min），端到端在阶段 3 验收。

1. `ParentalStateController`（先行版：读本地临时配置 + `activeChildIds`，接口与阶段 3 的 config 版一致）+ `KidWatchTimerController`（双计时分账、日期翻转、SharedPreferences、quietHours 校验）；**本地临时配置的调试入口除 `children[]`/`mode` 外还须能设置 `activeChildIds`（或提供"模拟换人"按钮）**——否则下述"换人仅新加入者起算"这条验收无从操作（评审收尾 #2）；
2. 到期动作接锁屏（锁屏 UI 可先用占位页，阶段 2 补解锁链路，阶段 3 换正式配置来源）；
3. `ReportingService` 心跳附带 `parental_watch`（`childIds` + 分账时长）；
4. 验收（固定测试阈值下）：看满阈值进锁屏（**逐人判定** `sessionSecByChild[c] >= c.sessionLimitMin`）；杀进程重启后剩余时长不归零；跨日自动清零；换台不重置；**场景口径——`settings`/锁屏不计时、退后台超 5 分钟重置 session 而 daily 不动、屏保照常累计**；重启不清计时（重置行此时仍可见，但独立 key 已保证清不掉）；**多孩分账生效——经调试入口"模拟换人"验证：换人仅新加入孩子从 0 起算、已在组合中的孩子 session 不清零（堵"加人续命"）**。

### 阶段 2：远程解锁 + PIN 兜底（差异化，链路已有）

1. TV 锁屏 → `sendEvent('parental_unlock_request')` **双发（同 `code`：`to: ownerAccount` + `to: '1000001'`）**（**触发源 = 阶段 1 的计时/禁看时段**，基于本地临时配置——本阶段可独立验收；阶段 3 后触发源不变，仅配置来源切换）；
2. `MessageCommandExecutor` 新增 `case 'parental_unlock'`；
3. 手机中控**三级角色分流 + 家长视图**：登录按 `user.role` 分流（admin → admin 视图、**parent → 家长视图**、user → 中控台）；解锁弹层 `events.listen` **仅 `parent`/`admin` 注册**（user 不注册）；家长视图含档案 CRUD、当前观看者、分档案时长、解锁记录、设置、遥控快捷入口（复用 `live_remote_panel.dart`，不开中控台）；服务端 role 枚举扩三级（`admin.js` L5/L214、admin 页 L741 加「家长」）（见 4.2）；
4. `ParentalVerificationSheet`（锁屏解锁与后续选人页 `locked` 闸门共用）+ PIN / 算术题本地兜底 + 错 5 次锁 60s；
5. 验收：WS 在线时 `parent` 账号一键解锁；**双发两条均到达、手机端同 `code` 只弹一张卡（owner 开会话页 / `ownerAccount` 即 `1000001` 两场景不重复弹）**；**daily 锁解锁后写入 `unlockGraceUntilMs`、窗口内不再立即回锁、窗口结束回锁等次日（无解锁死循环，也不重置当日额度）**；解锁弹层仅 `parent`/`admin` 可见可操作（`user` 不弹）；断网时算术题可解；短码 60s 过期作废、一次性；错误 code 无效；`user` 登录无家长入口。

### 阶段 3：儿童档案 + 开机选人页 + 频道白名单两档管控 + 配置来源切换（依赖阶段 0）

1. `ParentalConfig` 模型（`children[]` / `activeChildIds` 解析、**过滤悬空 id**、多选合并——频道逐档案放行、限额逐人判定）+ `ParentalStateController` 从本地临时配置**切换为读服务端 config** + 缓存；
2. `_viewOf` 注入温和档（`hideGroups`+`hideChannels` 黑名单并集）/严格档（`allowGroups`+`allowChannels` 白名单交集）过滤，跨档案逐档案放行 + 空结果防黑屏保护；
3. 服务端 **3 处小改**（PUT parental body 分支 / `normalizeMachine` 保留 / `resolveMachineConfig` 透传）+ **role 枚举扩三级**（`admin.js` L5/L214、admin 页 L741 加「家长」）+ admin 编辑表单（**儿童档案增删改，孩子名称家长添加**，**按档案档位显隐字段**，分组下拉用最近上报的分组列表）；
4. **开机选人页**：启动登录后按**家长下发生效状态**（config 满足**生效判定式** `mode === 'on' && children` 非空，未到达前用本地缓存兜底）弹出，勾选一位或多位、遥控「确定」进入，未确定不进直播；`locked` 档案勾选走 `ParentalVerificationSheet`（远程确认或 PIN）；选人确认/换人经 `setActiveChildren` 驱动重放与分账、并发 `parental_child_active`；运行中判定式不再成立（`mode !== 'on'`）即时解除（清 `activeChildIds`/作废短码/关锁屏）；**家长视图的档案 CRUD 与电视端 config 联动**（parent 在家长视图改档案 → `PUT /api/admin/machines/:id` → WS config 推电视 → 选人页/频道条实时更新）；
5. 验收：改 admin 配置 → 电视端频道条实时收窄；白名单配错不黑屏；判定式不成立（`mode !== 'on'`）时与现状完全一致；**未确定前停在选人页；多选逐档案放行（strict 交集 ∩ mild 黑名单外）、限额逐人判定；`locked` 档案无验证不可进入；后台开启→下次启动登录后弹选人页，后台取消→运行中即时解除（选人页直接进直播）；删档案后 activeChildId 悬空：全部悬空 → 回退选人页；部分悬空 → 过滤后继续用剩余 id；端到端计时阈值来自服务端下发**。

### 阶段 4：儿童模式设置收敛（整页替换，定稿）

1. `main_app.dart`「我的」Tab 儿童模式下整页替换为只读页（状态 + 已看时长 + 请求解锁入口）+ `_handleRootKey` 拦截；
2. **不改 `ProfileFocusController` / `profile_page`**（评审 P1-9 定稿为整页替换，原"行列表数据化"方案作废）；
3. 验收：儿童模式下无法触达重置/远程账号/刷新频道（入口即不可达）；判定式不成立（`mode !== 'on'`）时「我的」与现状完全一致。

> 原调研中"温和/严格之间按分类精调时长（动画限时/教育不限时）"在直播场景意义不大（频道即内容），**不纳入本期**，待有 VOD 能力后再评估。

---

## 8. 风险与待确认项

| # | 风险/待确认 | 影响 | 处理 |
|---|---|---|---|
| 1 | ~~`ProfileFocusController.rowCount` 为 `static const`~~ | — | **已消解**：阶段 4 定稿为整页替换（P1-9），`rowCount` 与 17 行结构不动 |
| 2 | `clearAllPersisted()` 清空全部键 | 孩子经"重置"绕过计时 | 儿童状态独立类独立 key，不进清理范围（阶段 1）；整页替换后重置行不可达（阶段 4） |
| 3 | 白名单全过滤导致黑屏 | 配置错误即黑屏 | `_viewOf` 空结果不应用 + admin 侧分组名校验（阶段 3） |
| 4 | `ChannelNumberInputController` 数字键直选的索引是否基于 `_viewOf` 过滤后列表 | 严格档下数字键可能选中白名单外频道 | 实施阶段 3 时确认；若基于原始列表则改为基于展示列表 |
| 5 | 三级角色边界：`user` 收得到 `parental_unlock_request` 但不弹（需确认不误操作、且其会话线程可见是有意的）；`parent` 登录非自己管的 TV 收不到解锁请求 | 解锁/管理功能缺失 | 解锁弹层仅 `parent`/`admin` 注册；家长视图按 `config.owner` 过滤；账号一致性引导（4.2） |
| 6 | 多家长/换绑：`ownerAccount` 单值，一个 TV 只认一个家长账号 | 多家长场景不支持 | v1 单家长（`parental.ownerAccount ?? machine.owner ?? '1000001'`），后续扩为数组；投递机制不变 |
| 7 | **本地时钟可被改**：quietHours 绕过 + 把系统时间改回昨天令 `dateKey` 翻转、当日累计清零 | 时间类管控整体可绕过 | v1 接受（改系统时间本身需要家长操作）；后续用 `parental_watch` 上报的服务端时间做审计（合并原 quietHours/日期翻转两条，评审 P2） |
| 8 | 孩子每次开机自选最宽松档案 | 家长配了多档也形同虚设 | 档案 `locked` 字段闸门：勾选含 `locked: true` 的档案需家长验证（2.2 选人流程）；家长应把宽松档案设为 `locked`，不锁 = 信任型配置 |
| 9 | **PIN 明文下发**：`parental.pin` 明文经 config 到 TV，SharedPreferences 可读 | 懂技术的孩子可提取 PIN | 家庭场景 v1 接受；后续可改哈希下发/本地校验（评审 P2） |
| 10 | `parental_watch` 5 分钟一条 + `events.jsonl` 持续增长，`events` 查询为全量扫描 | 设备量大后家长端查当日记录变慢 | v1 可接受；长期需索引/按日聚合表（评审 P2） |
| 11 | Android TV 系统 Home/返回键无法被 `_handleRootKey` 拦截；宿主是否 launcher 形态未确认 | 锁屏期间可退出 App 表面 | 已定口径（4.2）：计时持久化，重进 App 按超阈值回锁屏；实施时确认宿主形态（评审 P2） |
| 12 | 阶段 1/2 依赖本地临时配置过渡 | 若不写明，阶段 1/2 无法独立验收（P0-1） | 已在阶段 1 写明过渡方案，阶段 3 统一切换配置来源并负责端到端验收 |
| 13 | **三首页维护成本**：admin 视图 / 家长视图 / 中控台是三套页面，后续功能迭代需明确归属 | 长期维护负担 | v1 家长视图保持极简（只做儿童模式相关 + 遥控快捷入口），不演变成第二个中控台；**admin 视图复用家长视图代码、仅放开 owner 过滤**（4.2） |
| 14 | **parent 账号发放流程**：谁在 admin 页把账号改成 `parent`、家长如何获得账号 | 上线有一步人工 | 部署文档写明：admin 在 admin 页将家长账号 `role` 改为 `parent` 并设为该 TV 的 owner；第一版无存量、无自动迁移 |
| 15 | **双发重复弹层**：owner 开会话页（直投 + 线程转发）或 `ownerAccount` 即 `1000001`（①② 同账号）时同一手机收 2 条请求 | 同一解锁弹两张卡、误以为两次请求 | 手机端弹层按短码去重：同 `code` 已有活动弹层则忽略后到的一条（4.2）；短码 60s 过期/一次性，换码自然弹新卡 |
