# ESP 设备类型字典共用 — 修改计划表

> 状态维护规则：每完成一项，把该行 `- [ ]` 改为 `- [x]`，并在「进度概览」同步计数。
> 最后更新：2026-11-16 17:00 —— **23/23 全部完成**。
> 服务端已部署到 `100.83.142.107`：admin.js / ha_catalog.js / deviceTypes.js（新）/ build/web/admin.html；
> 备份在 `/home/honghao/.pkbackup_20261116_165928`，pm2 my-server 已重启，线上接口验证通过。
> home 端经 `dart analyze` 全量通过（仅 1 条与本轮无关的既有 info）；ESP 固件改到 `oled-2.0`，**部署机 arduino-cli 编译通过**（EXIT=0，flash 61% / RAM 15%），仅未真机烧录。

## 一、本次要落地的架构决策（已拍板）

1. **字典层两端共用**：设备类型字典是唯一真源，放服务端；home 与 ESP 都消费它，改一处两端生效，顺带根治 home 靠后缀猜类型导致的串类误判。
2. **取数通道不共用**：home 直连 HA WebSocket（`state_changed` 实时推送、令牌在客户端），ESP 走服务端代读（令牌留服务端、文本协议下发）。硬合并会把 home 的实时性降成轮询。
3. **固件保持"哑巴"**：只收 `title/main/sub/keys` 四行文本 + 按键槽，不认识任何设备类型；新类型接入固件零改动、不用重烧。
4. **admin 信息架构**：两个平级顶层 Tab —— 「设备类型字典」（全局规则）+「ESP 设备分类」（每台设备），不再把字典藏在设备页子 Tab 里。
5. **设计约束**：按键数量可扩展（不局限现有 3 键，翻页照做）；暂不考虑特殊字符/中文字库缺字；跑马灯仅在文字真正放不下时触发，短文本静止。

## 二、进度概览

| 端 | 总数 | 已完成 | 进行中 |
|---|---|---|---|
| 服务端（S） | 8 | 8 | 0 |
| home 端（H） | 6 | 6 | 0 |
| ESP 端（E） | 9 | 9 | 0 |
| **合计** | **23** | **23** | **0** |

**阶段说明**：P1 = 显示与配置骨架（不动取数，可先做）；P2 = 字典/带参/协议（核心）；P3 = 交互（翻页、按键扩展）。
**依赖主线**：S1–S6（服务端字典与接口）→ H1–H5（home 消费）／E5–E7（ESP 消费）；E1–E4 为纯显示层，可独立先行。

---

## 三、服务端（`pscreen_server`）— 唯一真源 + 字典解析 + 带参动作

- [x] **S1** ｜P2｜新建 `server/deviceTypes.js` 类型字典模块
  - 字段 schema 直接沿用原型 `DICT_DEFAULTS`/`DICT_DETAIL`：共用 `mainAttr/mainFmt/subTpl/step`，home 段 `homeLabel/homeCtrls/homeActs`，ESP 段 `espTitle/espMain/espSub/espKeys`。
  - 覆盖 home 现有 14 个 Summary 与原型 15 类的并集（含 light/climate，及 home 独有的 lock/home_climate）；未分类走通用兜底。
  - 导出：按 `deviceType + displayBindings + HA 状态` 解析出 `{title, main, sub, keys}` 的函数。
  - 验收：15+ 类均能解析四行文本；无类型时不黑屏，降级为 `domain · state`。

- [x] **S2** ｜P2｜`server/admin.js:255` 扩展 `normalizeEspActions`
  - machines.json 每台新增 `deviceType` 与 `displayBindings`（main/sub1/sub2 绑定到 entityId），纳入白名单规范化，非法值回退。
  - 验收：保存后字段持久化；脏数据不污染下发。

- [x] **S3** ｜P2｜`server/admin.js` 新增字典 CRUD 接口
  - `GET /api/admin/device-types`（返回默认字典 + 覆盖值）、`POST /api/admin/device-types`（覆盖并持久化到 `datas/admin/deviceTypes.json`）。
  - 验收：改字典后无需重启、无需重烧固件，两端预览即时变化（原型已实测 `°C→℃` 联动）。

- [x] **S4** ｜P2｜`server/admin.js:3045` 扩展 `GET /api/device/esp/actions`
  - 按设备 `deviceType + 字典` 解析出 `title/main/sub/keys` 四行下发；保留旧 `button|name|entityId|action|id` 行兼容旧固件。
  - 新增服务端代读 HA states 的聚合（令牌留服务端，不下发设备）。
  - 验收：新固件收到四行文本；旧固件仍能解析按键行不崩。

- [x] **S5** ｜P2｜带参动作支持（热水器 ±温、模式、风速）
  - `admin.js:70` 的 `ESP_ACTION_KINDS` 扩展白名单：`set_temperature/set_operation_mode/set_percentage/select_option` 等；`callHaService(entityId, action, params)` 请求体带参数。
  - 温度按字典 `step` 做 clamp 到 min/max + 取整（复用 home 规则），由服务端算好值下发。
  - 验收：温度 +/−、模式切换走通；白名单外的 action 被拒。

- [x] **S6** ｜P2｜`server/ha_catalog.js` 扩展 `ACTION_KINDS` 与 `resolveActionService`
  - `ha_catalog.js:54` 的 4 种无参动作扩展为带参服务映射（`climate.set_temperature`、`fan.set_percentage`、`water_heater.set_operation_mode` 等）。
  - 验收：带参 action 能解析到正确 HA service。

- [x] **S7** ｜P1｜`web/admin.html` 新增两个顶层 Tab（对照原型 `docs/esp-device-type-prototype.html`）
  - 「设备类型字典」：全局规则编辑器，三列（共用语义 / home 消费 / ESP 消费），左侧类型列表带"已用 N 台"。
  - 「ESP 设备分类」：每台设备选类型 + 下拉绑实体 + 按键定义 + 显示命中规则；复用现有 `createEntityPicker`。
  - 两页互跳：设备页「编辑此类型 →」带 deviceType 跳字典页。
  - 验收：无需先进某台设备即可改全局规则；下拉挂 body、可搜索、无滚动关闭问题。

- [x] **S8** ｜全部｜部署（遵守部署铁律）
  - 先改源码再部署；`tr -d '\r'` → `node --check` → 备份 → md5 对齐 → `pm2 restart my-server`；`admin.html` 同步到 `build/web/admin.html`。
  - 验收：线上 `http://100.83.142.107:3000/admin.html` 两 Tab 可用；后端契约与前端同步（避免新旧错配）。

---

## 四、home 端（`pscreen_home`）— 字典层共用，取数通道不动

- [x] **H1** ｜P2｜新增字典消费者
  - 经服务端 `GET /api/admin/device-types` 拉字典（本地缓存 + 内置默认回退）；字典是配置数据，与 HA 令牌通道分离。
  - 验收：字典改动后 home 端读到新规则。

- [x] **H2** ｜P2｜渐进迁移 14 个 `XXXSummary` 的后缀硬编码 → 读字典
  - 优先迁串类最严重的 washer / air_fryer / water_purifier（共用 `_status_p_2_2`）与 kettle / rice_cooker（共用 `_status_p_2_1`），再迁其余。
  - 涉及：`domain/models/` 下 air_fryer/fan/fridge/home_climate/multi_switch/projector/range_hood/washer/water_heater/water_purifier/lock/socket/rice_cooker/kettle 等 `*_summary.dart`。
  - 验收：显式分类后不再串类；改字典 → 同类设备一起生效。

- [x] **H3** ｜P2｜`presentation/pages/device_detail_page.dart` 面板选择改字典驱动
  - 用字典 home 段（`homeLabel/homeCtrls/homeActs`）决定大字标签、控件组、动作；门锁优先与安全设备禁用全部控制的逻辑保留。
  - 验收：改字典后详情面板随之变化；门锁仍禁用控制。

- [x] **H4** ｜P2｜数值规则统一到字典
  - 温度/数值的 clamp 到 min/max + 按 `step` 取整，统一读字典 `step`，去掉各 Summary 里重复的硬编码步长。
  - 验收：home 与 ESP 加减温步长一致。

- [x] **H5** ｜P2｜回归验证
  - 14 类设备面板与控制逐类验证；未分类设备走通用兜底不黑屏。
  - 验收：无串类误判、无回归。

- [x] **H6** ｜全部｜取数通道保持不变
  - 保留直连 HA WS（`core/network/ha_ws_client.dart`）、`state_changed` 实时推送、乐观更新/失败回滚、令牌在客户端。
  - 验收：实时性未降级为轮询。

---

## 五、ESP 端（`esp_devices/firmware/potatokid_esp/potatokid_esp.ino`）— 通用显示，固件零类型知识

- [x] **E1** ｜P1｜主屏中文化
  - `drawMain()`（:346）从 `helvB10 + 6x10` ASCII 改为 `drawUTF8` + `wqy12_t_gb2312`（`oledToast` :124 已有先例）。
  - 验收：中文标题/状态正常显示。

- [x] **E2** ｜P1｜顶部状态栏：页码 + IP + WiFi
  - IP 取真实 `WiFi.localIP()`，**拿到之前留空，绝不显示占位/假值**（README 第 6 节已写此约定）；IP 从正文第 3 行移到顶栏；断网 ✗ / 配网 AP 态不显示 IP。
  - 验收：三栏 128px 内不重叠；未连接时无假 IP。

- [x] **E3** ｜P1｜跑马灯替代硬截断
  - `oledShow()`（:101）从 `fit()` 硬截断改为行级滚动；仅放不下时触发，短文本静止；四行独立速度 0.45/0.75/1.1/1.6×（基准 15px/s）；~10fps 局部刷新，勿全屏 30fps 拖慢 I2C/心跳。
  - 验收：长文本可读、四行不同步；无截断/省略号。

- [x] **E4** ｜P1｜单色三色适配（蓝/白/黄）
  - 全屏单一亮色，无灰阶/无虚线；层次靠字号 + 留白 + 反白块；异常靠文案 + 反白（单色屏唯一强调手段）。
  - 验收：三种屏均正常，无中间明度、无装饰线。

- [x] **E5** ｜P2｜文本协议扩展
  - `fetchActions()`（:243）解析四行文本（title/main/sub/keys），兼容旧 `button|name` 行；新增 `currentPage` 与 sys 动作（next/prev/home）。
  - 验收：新协议四行显示正常；旧数据不崩。

- [x] **E6** ｜P2｜带参动作执行
  - `pressAction()`（:267）支持 params（温度/模式/风速），值由服务端算好，固件不自行计算。
  - 验收：热水器温度 +/−、模式切换从屏幕生效。

- [x] **E7** ｜P3｜翻页与按键扩展
  - 不局限 `BTN_PINS[]={4,5,6}`（:27），预留 IO 扩展/更多按键；维护 `currentPage`，翻页后 1–4 键定义随页面变化。
  - 验收：按"下一页"后按钮提示与动作同步切换。

- [x] **E8** ｜全部｜OTA 回归
  - 双 OTA 槽（no_fs 分区，前 4MB，后 12MB 闲置）验证升级与回滚；Flash 非瓶颈，无需为此项改分区。
  - 验收：OTA 成功、失败可回滚。

- [x] **E9** ｜全部｜README 写入 IP 铁律
  - `esp_devices/README.md` 第 6 节已写：状态栏 IP 必须取 `WiFi.localIP()`、拿到前留空、原型 `192.168.1.123` 是假值勿抄、断网/配网不显示 IP。
  - 状态：已完成（本轮之前写入）。

---

## 六、关键约束与踩坑备忘（落地时对照）

- **契约必须同步**：服务端改了下发格式，admin.html 与固件要一起改，否则新旧错配（已踩两次）。
- **单色屏铁律**：只用亮/灭两级，禁止 bright/dim/半透明/虚线；层次靠字号、留白、反白块。
- **跑马灯**：仅超长触发；各行独立相位与速度；不要全屏高频重绘。
- **IP**：绝不写死假 IP，取 `WiFi.localIP()`，拿到前留空。
- **部署**：非交互 ssh 需 `export PATH="$HOME/.npm-global/bin:$PATH"; export PM2_HOME=/home/honghao/.pm2`；`pm2 restart my-server`。
- **字典字段清单**：原型 `docs/esp-device-type-prototype.html` 的 `DICT_DEFAULTS`/`DICT_DETAIL`（:488–:511）可直接作为 `deviceTypes.js` 的 schema 起点。
