# 旧版卡片资料与逐类型改造须知

本目录保存旧版中控屏卡片资料，用于把后台「设备判定规则 + JSON 布局树」逐类对齐到旧版效果。

- `board-all-01.png` ~ `board-all-05.png`：旧版 App「全部」页面的卡片截图。
- `home_1204_table.csv`：27 张卡片的清单与进度。`状态` 列标记 `已完成 / 进行中 / 待配置 / 待确认`，每完成一类就更新它，**不要靠翻截图猜进度**。
- `lib/`：一份旧版 Flutter 源码（只读参考）。需要确认「卡片显示什么、按钮到底点了哪个实体、发了什么参数」时，以这里的代码为准。

## 核心原则：显示必须走后台 JSON 布局（不要硬编码本地布局）

- **所有卡片的显示（文案、图标、字号、间距、按钮尺寸、对齐）必须由后台 `CARD_LAYOUTS` / admin 下发的 JSON 布局树驱动，App 端只负责渲染，不在 Dart 里写死某类型的布局。**
- 旧版专用 Widget（如 `KettleWidget`）仅作代码兜底，正常路径一律走 `JsonCardRenderer`；新增/调整一类卡片时，改的是后台 JSON，不是新建 Dart Widget。
- **如果当前 Dart 渲染器不具备某个显示条件，就扩展 Dart 渲染器 + JSON 协议**（例如热水瓶需要「上下分布中间留白」→ 新增 `fill` 字段 + `mainAlign: spaceBetween`；需要大触点按钮 → 新增 `chip.height` / `chip.size`），但**显示数据仍来自后台配置**，扩展的是「渲染能力」，不是「把布局写死在 Dart」。
- 按钮动作同样不在 Dart 里硬编码实体：复杂设备用专用动作通道（如 `kettle@action`，onClick 不带实体 id，App 按实时状态从 `KettleSummary` 取确认过的实体和参数）。

## 后台改布局 → App 自动热更新（不用重启）

- 服务端 `deviceTypes.js` 维护持久化的 `_revision`（保存在 `datas/admin/deviceTypes.json` 顶层，不作为设备类型下发）；`update/create/reset` 都会递增。
- admin「保存并生效」成功后，服务端给所有在线 home（跳过 parent 家长端）推一帧 `{ t: 'config', config: { ..., deviceTypesUpdatedAt } }`（复用 `/ws` 现有 config 通道，与 programs 同一机制）。**只带版本号，不带字典本体**。
- App `device_reporter._applyConfig()` 收到后比对持久化版本（SharedPreferences `device_types_updated_at_v1`）：变新才 `DeviceTypeStore.refresh()`（只读 GET `/api/device/device-types`）→ 派发 `DeviceTypesReloaded` 触发 UI 重建。离线设备重连/60s 心跳也会自愈。
- 只有**改了 Dart 渲染能力**（如新增 `fill` / `chip.height` 字段、新动作通道）才需要重新打包重启 App；单纯改后台 JSON 布局、规则、图标、文案，保存后在线 App 秒内生效。
- 安全底线：热更新链路只有 GET + 解析 + 替换静态字典 + rebuild，**绝不调用任何设备控制动作**；解析失败保留旧字典；WS 离线时降级心跳同样能补齐。

## 安全约定（最重要）

这些卡片对应的是**正在运行的真实设备**。配置错误不会只影响界面，点击后会直接动作到设备。

1. **禁止猜测可操作按钮**。一个按钮接到哪个实体、用哪种动作（`ToggleEntity` / `PressEntityButton` / `PressNotifyAction`）、参数是什么，必须从旧版 `lib/` 里查到确切实现，不能因为「看起来像开关」就挂 `toggle`。
2. **不要用通用布局的按钮去试探设备**。复杂设备（电热水瓶、洗衣机、空气炸锅、电饭煲、热水器、投影仪等）优先保留旧版专用 Widget / Summary；通用 JSON 布局只做展示或明确无副作用的区域。
3. 不确定时 **先不接 onClick**，让点击落到详情页，由用户确认后再补。宁可按钮没反应，也不能误动作。
4. 改完一类先在 admin 预览和本机 App 验证文案/按钮数量，再问用户是否继续下一类；不要一次性批量切全部类型。
5. 线上改动先备份，再 scp + `node --check` + `pm2 reload`；静态 admin 文件部署在 `~/services/tools/build/web/`，服务端文件在 `~/services/tools/server/`。

## 热水瓶（kettle）已确认的正确行为

参考文件：`lib/features/home/domain/models/kettle_summary.dart` 与 `lib/features/home/presentation/components/kettle_widget.dart`。

- 卡片只有一个文字按钮：未运行显示「加热」，运行中按阶段显示「停止加热 / 停止保温」。**没有圆形电源开关**。
- 「停止」：`PressEntityButton(entityId: <..._cancel_cooking_a_2_2>)`。
- 「开始加热」：`PressNotifyAction(entityId: <..._start_cook_a_2_1>, message: [模式id, 设定温度, 保温, 保温温度, 除氯, 风冷, 纯净水保温温度, 自来水保温温度])`。参数是旧版 `KettleSummary.startMessage` 按实时状态拼出来的 8 项列表，不能简化成 `toggle`。
- 因为开始/停止动作依赖实时状态计算，App 端已让 `kettle` 继续走旧版 `KettleWidget`；后台布局只用于 admin 预览，`chip.onClick` 刻意留空。
- **显示布局要点（已改为走后台 JSON）**：`CARD_LAYOUTS.kettle` 用 `fill: true` + `mainAlign: spaceBetween` 让列占满卡片高度、头部与底部读数分开，中间留白（等价旧版 `Spacer`）；底部「当前温度 / 大字 38 / 目标 / 描边按钮」的字号与 `chip.height: 42` 全在后台 JSON 配，App 不写死。按钮 `onClick: kettle@action` 走专用安全通道，App 按 `KettleSummary.isActive` 实时选择「加热」（`PressNotifyAction` + 8 参数）或「停止」（`PressEntityButton`），与旧版行为一致。**不要再把 kettle 早退到 `KettleWidget`。**

## 后台/admin 展示注意

- 设备类型列表只显示中文标签（如「热水瓶」）。`card.icon` 可以是 Material 名（如 `water_drop`），但列表图标位必须转成字形或 `✦`，不能把长英文原文渲染进 20px 的图标位，否则会与中文重叠。
- 卡片状态/模式等分散在同一 HA 设备的多个实体里时，用 `{s:<entity_id 后缀>}` / `{a:<后缀>.<属性>}` / `{id:<后缀>}` 精确取值，不要用 `entity.10.state` 这种组内下标——实体排序会变。
- 值替换 `map` 只用于显示文案；不要拿它去拼真实控制动作。

## 当前进度

见 `home_1204_table.csv`：灯光类已完成；热水瓶（#2）配置中；下一类是风扇灯（#3），需要处理它与「风扇」类型的优先级冲突。
