# 设备类型判定规则引擎 —— 落地进度记录

> 设计稿：`docs/device-type-rule-engine-prototype.html`
> 开始：2026-11-16　状态：**首版已实现并部署服务端；home 待真机验证**
>
> 核心决策（用户拍板）：纯规则自动判定 + 通用配置卡片；判定统一在服务端算，
> home 拿结果渲染、ESP 保持哑巴显示；类型可动态新建、字段/动作开放输入；
> **Home 可随 App 发版更新，ESP 固件永久不动**。

---

## 一、完成项 ✅

### 服务端
- [x] **S1 `server/deviceTypes.js` 规则引擎**
  - 保留原 17 类字典 + 覆盖层兼容（旧扁平 dict / 新 `{dict,rules,card,priority,meta}` 双格式）
  - 新增 `rules[]`（规则 OR、条件 AND）、`card`（通用卡片配置）、`priority`
  - 6 个类型内置默认规则从设计稿迁移（空调/插座/热水瓶/热水器/洗衣机/风扇）
  - 判定函数 `classify(entities, types)`：具体度优先 → 再按优先级
  - 条件字段支持 `domain`/`entity_id`/`name`/`state`/`attr.xxx`/**`device.model`**/`device.name`/`device.manufacturer`
  - 操作符 `startsWith` 自动忽略 `button.`/`switch.` 域前缀（解决"按设备标识前缀分类"）
  - 动态新建类型 `create()`、灰度列表 `genericCardTypes()`
  - 验证：node 单测通过；"空调插座"判为插座（具体度 2 > 空调 1）；`xiaomi.tv.v1` 判为电视

- [x] **S2 `server/ha_catalog.js` 字段补全**
  - 目录实体输出新增 `deviceId` / `deviceModel` / `manufacturer` / `attributes`
  - 实拉验证：51/52 台设备有 model；`xiaomi.tv.v1` / `xiaomi.light.cfan01` / `xiaomi.light.ceil02`

- [x] **S3 `server/admin.js` 接口**
  - `POST /api/admin/device-types` 支持 rules/card/priority/meta 整体保存
  - `POST /api/admin/device-types/create` 新建类型
  - `POST /api/admin/device-types/classify` 命中测试（单一真源）
  - `GET /api/device/device-types` 下发 `types`(含 rules/card) + `classification` + `autoClassification` + `manualClassification` + `genericCardTypes` + `ruleEngineEnabled`
  - 自动判定失败时降级：不影响显式分类、不阻塞 home 启动

### Admin
- [x] **S4 `web/admin.html` 新增顶层 Tab「设备判定规则」**
  - 三栏：类型列表（可＋新建）/ 规则编辑器 + 通用卡片配置 / 命中测试 + 双端预览
  - 规则编辑器：规则增删启停、条件增删、字段/操作符/动作开放输入 + datalist 推荐
  - 通用卡片配置：大字标签、主属性/格式、副文案、主实体、图标/色、按钮列表
  - 灰度开关：每个类型独立 `genericEnabled`，逐个打开验证
  - 命中测试：取真实 HA 实体（含 device.model/attributes）走服务端 `/classify`
  - 权限/刷新/激活逻辑已接入（adminOnly、activateTab）
  - 验证：JS 语法通过、24 个新增 DOM id 齐全

### Home（灰度，默认关闭）
- [x] **S5 规则模型扩展 `device_type_dictionary.dart`**
  - 新增 `DeviceRuleCondition` / `DeviceRule` / `DeviceCardConfig` / `DeviceCardButton`
  - `DeviceTypeRule` 增加 rules/card/icon/color/priority
  - `DeviceTypeDictionary` 增加 `classifiedTypeOf` / `useGenericCard` / `classifyLocally`
  - 解析服务端 `autoClassification` / `manualClassification` / `genericCardTypes`
  - 保持 `DeviceTypeDictionary.active` 全局赋值语义不变（13 Summary 消歧继续可用）

- [x] **S6 通用卡片 `generic_rule_card.dart`（新建）**
  - 按 card 配置渲染：标题/大字标签/主数值/副文案/图标色/按钮/电源键
  - 占位符 `{v}/{main}/{state}/{s1}/{s2}` 填充
  - 简单动作（toggle/turn_on/turn_off/press/notify）本地下发，带参动作跳详情页

- [x] **S7 接入 `home_controll_board.dart`**
  - `buildCard` 顶部灰度分支：classifiedType 命中且 `useGenericCard=true` 时走通用卡片
  - 未开启时 13 个专用 Summary 行为完全不变（零回归）

- [x] **S8 home 验证**
  - `dart analyze lib` 通过（仅 1 条既有无关 info）
  - 新增 `test/device_type_rule_engine_test.dart` 5 个用例全部通过（前缀匹配/model 匹配/具体度优先/响应解析）

### ESP
- [x] **S9 固件不动**：仍收四行文本，新类型零烧录；model/规则解析全在服务端

---

## 二、未完成 / 待验证 ⏳

| 项 | 状态 | 说明 / 下一步 |
|---|---|---|
| **服务端部署到 100.83.142.107** | ✅ 完成 | 已按铁律执行：`tr -d '\r'` → `node --check` → 备份（`backups/rule-engine-20261116-180642`）→ 上传 → md5 四文件全对齐 → `pm2 restart my-server`（cluster），进程 online |
| **admin.html 部署到 build/web/** | ✅ 完成 | 同上，`web/admin.html` → `build/web/admin.html`；curl 验证新 Tab 已上线 |
| **home 真机验证** | ⏳ 待做 | 编译 parent APK 或 debug 装 USB 设备（R58M349S90M，m10s）；在 admin 打开某类型灰度开关，观察首页卡片 |
| **规则命中端到端实测** | ✅ 完成 | 部署后 curl 实测：`/api/admin/device-types/classify` 传入"空调插座"→ 判为 socket（具体度 2）；`/api/device/device-types` 返回 17 类 + 31 条自动分类 + rules/card/genericCardTypes；新建类型 + 恢复默认 CRUD 通过，覆盖层回到 `{}` |
| **全量灰度切换后下线 13 Summary** | ⏳ 后续 | 逐个类型打开通用卡片、验证无误后，再考虑删除专用 widget；本次保留兜底 |
| **详情页/控制完全配置驱动** | ⏳ 后续 | 本次通用卡片只覆盖首页卡片；详情页仍用专用面板，带参动作跳详情页 |
| **设备型号字段接入 home 本地兜底判定** | ✅ 已做 | `device.model` 已在字段白名单；home `classifyLocally` 支持（服务端不可达时用） |

---

## 三、改动文件清单

**服务端**（`pscreen_server/`）
- `server/deviceTypes.js`（重写：规则引擎 + 动态类型 + model 字段）
- `server/ha_catalog.js`（实体输出加 deviceId/deviceModel/manufacturer/attributes）
- `server/admin.js`（3 个 admin 接口 + 公开接口下发判定结果）

**Admin**
- `web/admin.html`（新 Tab + 样式 + 规则引擎 UI 逻辑 + 灰度开关）

**Home**（`pscreen_home/`）
- `lib/features/home/domain/models/device_type_dictionary.dart`（扩展模型 + 本地引擎）
- `lib/features/home/presentation/components/generic_rule_card.dart`（新建通用卡片）
- `lib/features/home/presentation/pages/home_controll_board.dart`（灰度接入）
- `test/device_type_rule_engine_test.dart`（新建 5 用例）

**未改**
- `esp_devices/firmware/...`（固件保持哑巴显示）
- `docs/device-type-rule-engine-prototype.html`（设计稿，本轮只作为参考）

---

## 四、灰度使用方法（部署后）

1. admin 登录 → 顶层 Tab「设备判定规则」
2. 左侧选类型（如"电视"）→ 中栏「通用卡片配置」勾选「用通用卡片渲染该类型」
3. 点「保存并生效」→ 写回 `datas/admin/deviceTypes.json`，两端即时生效
4. home 重启或下拉刷新后，该类型的设备卡片改用通用卡片
5. 验证无误再开下一个类型；出问题取消勾选即回退到专用卡片

> 若要在 admin 里让某类设备按型号自动归类：选中类型 → 判定规则里加条件
> `字段=device.model` `操作符=eq/startsWith` `值=xiaomi.tv.v1` → 保存。
> 新建类型（如加湿器）点左侧「＋新建类型」，填 key/label 即可，无需改代码。

---

## 五、注意事项 ⚠️

### 5.1 分类判定规则
- **设备标识前缀 ≠ domain**：`xiaomi_cn_mitv_` / `xiaomi_cn_991270332_cfan` / `xiaomi_cn_918088698_ceil` 这类是 `entity_id` 里的设备标识，不是 `domain`。这三个实体横跨 `button`/`switch` 两个域，用 `domain=button` 分类必然串类。正确配法：`字段=entity_id` `操作符=startsWith` `值=前缀`；`startsWith` 已自动剥离 `button.`/`switch.` 域前缀再比，否则完整 ID 以域开头会匹配不到。
- **分类主字段用 `device.model`，不要用 `manufacturer`**：实拉线上 52 台设备，`device.model` 覆盖率 51/52，且 `xiaomi.tv.v1` / `xiaomi.light.cfan01` 这类值自带品类语义；`manufacturer` 有 20 种脏值（`2小米大家电冰洗-对接创维`、`深圳市火乐科技发展有限公司`、`null`），只能做「小米/非小米」粗判断，不能当判定条件。
- **多条件 + 具体度优先**：同型号多台（如 3 台电视）需用 `device.model` + `device.name`/房间条件组合区分单台。规则命中裁决是「具体度高的胜出，同分再按 priority」——「空调插座」靠 `name 含插座 + domain=climate`（2 条件）胜过普通空调的 `domain=climate`（1 条件），这就是多条件解决串类的原理，不要简化成单条件。
- **自动判定失败会降级**：服务端算不出类型时不阻塞 home 启动、不影响显式分类；home 端 `classifyLocally` 只在服务端不可达时兜底，两者逻辑保持一致即可。

### 5.2 灰度切换（home 通用卡片）
- **所有类型的 `genericEnabled` 默认关闭**，13 个专用 Summary 全部保留兜底，零回归。必须**逐个类型**打开验证，确认卡片渲染、按钮动作都正确后再开下一个，**不要一次性全开**。
- 出问题**取消勾选立刻回退**到专用卡片，无需改代码。
- 本次通用卡片只覆盖**首页卡片**；详情页/控制仍是专用面板，带参动作（如 `set_temperature(+0.5)`）会跳详情页。详情页完全配置驱动是后续项。
- 全量灰度验证无误前，**不要删除 13 个专用 Summary widget**。

### 5.3 部署铁律（100.83.142.107）
- **先改源码再部署**，绝不在部署机上直接改文件。
- 全部服务走 **pm2**，进程 `my-server` 是 **cluster 模式**（非 fork），用 `pm2 restart my-server`。
- 非交互 ssh 需先 `export PATH="$HOME/.npm-global/bin:$PATH"; export PM2_HOME=/home/honghao/.pm2`。
- Windows → Linux 部署链：`tr -d '\r'` 转 LF → `node --check` → 备份 → 上传 → md5 对齐 → `install -m` 保权限 → 重启。CRLF 比对用 `diff --strip-trailing-cr`。
- **契约改动（客户端 API）必须同步部署服务端**，否则新旧错配（已踩过两次）。
- 本次备份在 `backups/rule-engine-20261116-180642`；静态页 `web/admin.html` → `build/web/admin.html`。

### 5.4 数据与运维
- **覆盖层 `datas/admin/deviceTypes.json` 会被 admin 接口写入**：命中测试/新建类型等验证操作会改它，测完必须确认还原为 `{}`（或恢复默认），避免测试类型残留。新建类型 + reset 已验证可正常还原。
- admin 登录接口 `POST /api/admin/login` **必须同时传 `username` 和 `password`**（只传 password 会失败）；仅 `admin|parent` 角色有管理页权限，`user` 角色被拒。
- `machines.json` 会被心跳持续写，md5 不同≠残留；清理显式分类走接口，不要直接改文件。
- **ESP 固件永久不动**：固件只收 `title/main/sub/keys` 四行文本，model/规则解析全在服务端；新增类型/规则/属性零烧录，只有引入**全新动作 kind** 时才扩服务端白名单。

### 5.5 ESP 显示（既有约定，勿回退）
- 三色单色屏（蓝/白/黄），无灰阶、无虚线；层次靠字号+留白+反白块。
- 跑马灯**仅在超长放不下时触发**，各行分速（0.45/0.75/1.1/1.6×，基准约 15px/s），标题最慢、提示最快。
- 顶栏 IP 必须来自 `WiFi.localIP()`，原型假值禁止照抄。
