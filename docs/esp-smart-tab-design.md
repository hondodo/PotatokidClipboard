# 后台「智能」Tab 设计说明 v1.3

> 状态：**P1 + 触发规则卡片已实现并部署**（2026-11-19 20:18）。服务端 `server/scenes.js` + `server/admin.js` 挂载，前端 `web/admin_js/12-smart.js`。
> 配套原型：`docs/esp-smart-tab-prototype.html`（原型为 P1 单触发版，v1.3 规则卡片以线上 admin 为准）
> 日期：2026-11-19　范围：pscreen_server 后台 + ESP 固件感应上报链路
>
> **v1.2 变更（触发条件组）**：触发从「单个 trigger」升级为「条件组 `{logic:'and'|'or', conditions:[...]}`」；
> 新增 `ha_state`（HA 实体 / 遥控状态，15 秒可配轮询）与 `window`（允许触发时间窗）两类条件。
>
> **v1.3 变更（规则卡片，本次）**：条件组再升级为 `{ rules:[{ conditions:[...] }] }`——
> 一张规则卡片内的条件是 **AND**，规则卡片之间是 **OR**，两种关系可以同时表达，不再二选一。
> 编辑弹层去掉全局 AND/OR 下拉，改为「+ 添加规则」「+ 添加条件」两个按钮；
> 新增规则/条件后自动滚动到新卡片。触发时机**不变**（满足条件即触发 + 冷却防重复），不做边沿/状态保持。
> 旧单 trigger 与旧 AND/OR 条件组在读配置时自动迁移为 rules（AND 组→1 条规则，OR 组→每条条件 1 条规则）。

## 零、已拍板的三个决策（2026-11-19 确认）

| 编号 | 决策 | 影响 |
|---|---|---|
| D-01 | 人体感应**只做服务内的模拟实体**，不注册成 HA 里的 `binary_sensor` | 不做 MQTT/HA 实体注入；消费方式限定为「自动化触发 + 后台展示 + 开放接口」 |
| D-02 | `occupied` 窗口默认 **90 秒**（可在感应实体面板里改） | 存在 `scenes.json` 的 `settings.occupiedWindowSec`，改完立即生效，不用重启 |
| D-03 | 动作失败默认 **「失败即停」**（`onError: stop`） | 单个动作可勾「失败也继续」覆盖；符合「灯没开就不该切台」的顺序语义 |
| D-04 | **不改固件** | `esp_page`（强制小屏跳页）不进本期；触发源与动作都不依赖新固件指令 |

## 一、要解决的三个问题

| 编号 | 现象 | 本质 |
|---|---|---|
| R-01 | 现在只能靠小屏物理按键一次做一个动作，「回家开灯 + 中控切首页 + 开夜灯」要按三次 | 缺「一组动作」的可复用封装 |
| R-02 | 人在屏前 / 离开，除了熄屏没有别的联动，灯、中控、电视都不响应 | 缺触发-动作引擎 |
| R-03 | 人体感应只用于后台展示和熄屏计时，不能被别的功能引用 | 数据没有实体化，不可被消费 |

## 二、页面结构

「智能」Tab 位于「ESP 设备分类」之后，一屏三段：

```
智能                                    [人体感应实体] [+ 手动控制] [+ 自动化]
──────────────────────────────────────────────────────────────
手动控制   点卡片就执行 · 悬停右上角可编辑
[回家模式] [离家模式] [观影模式]        ← 卡片网格，自动换行
──────────────────────────────────────────────────────────────
自动化     满足条件自动执行，关掉开关立即停用
[回家自动开灯        感应触发   ●]
[人走 5 分钟熄屏     感应触发   ●]
[门锁打开→玄关灯亮   HA·15 秒   ○]     ← 暂停态整卡降透明度
```

设计取舍：

1. **手动控制和自动化同屏**，不拆两个子 Tab。理由：用户的心智是「我要它做事」，先分「我点它」和「它自己动」，两段一屏能互相对照；拆 Tab 会让「为什么这个不会自动跑」变成常见疑问。
2. **不用底栏 Tab**（米家是移动端底栏）。admin 是桌面宽屏，沿用现有顶栏，零学习成本。
3. **自动化卡片只显示「一句话人话」**：`当 X = Y，持续 Z → 做 A、B`。不显示 JSON、不显示内部 ID，ID 只在编辑页的动作副标题里出现（方便排障）。

## 三、人体感应实体化（R-03）

### 3.1 为什么必须两个状态

HC-SR501 只对红外热源**位移**敏感，输出保持约 2 秒。人坐下看书，传感器 2 秒后就没信号了。如果只有一个 `presence`，「家里有没有人」这个判断永远错。

| 状态 | 取值 | 定义 | 用途 |
|---|---|---|---|
| `presence` | 有人 / 无人 | 传感器当前电平（原始上报值） | 「刚进门」这类**瞬时触发** |
| `occupied` | 占用中 / 空闲 | 最近 N 秒（默认 90）内出现过 `presence=有人` | 「人还在不在」这类**持续判断** |

`occupied` 由服务端按 `lastEnterAt` 推算，不需要固件改动：

```js
occupied = (Date.now() - lastEnterAt) <= OCCUPIED_WINDOW_MS   // 默认 90_000
```

> 默认 90 秒的依据：传感器 2 秒保持 + 人坐着翻页/拿东西的间隔通常小于 90 秒。这个值做成可配（`scenes.json` 的 `settings.occupiedWindowSec`），不做魔数。

### 3.2 实体身份

沿用现有 `remote.<deviceId>` 的命名习惯，新增：

```
presence.<deviceId>        例：presence.esp32s3_3030f96cd03c
```

属性（在实体详情页和模板里都可读）：

| 属性 | 类型 | 说明 |
|---|---|---|
| `presence` | 有人/无人 | 瞬时值 |
| `occupied` | 占用中/空闲 | 去抖值 |
| `lastEnterAt` | 时间戳 | 最近一次进入 |
| `lastLeaveAt` | 时间戳 | 最近一次离开 |
| `idleSec` | 秒 | 距最近一次进入的时长（occupied 为空闲时才有意义） |

### 3.3 四条消费路径

| 路径 | 落点 | 是否需要新代码 |
|---|---|---|
| 自动化触发 / 条件 | 本设计新增引擎 | 是（新模块） |
| ESP 屏幕模板显示 | 在 `tplMain/tplSub` 里支持 `{presence.state}`、`{presence.idle}` | 是（模板变量表 +1 条） |
| 首页卡片 | 现有首页布局的实体绑定，加虚拟实体类型 | 是（小改） |
| 开放接口 | `GET /api/device/presence` 返回全部感应实体 | 是（约 20 行） |

### 3.4 做不到的两件事（必须写在界面上）

1. **不能注册成 HA 里的 `binary_sensor`**（已按 D-01 确认不做）。服务端只做 HA REST 调用，没有常驻 WS，也没有 MQTT 集成，无法向 HA 注入实体。要做 HA 联动只能走「服务端 → HA webhook → HA 自动化」。
2. **`occupied` 不等于人在**。90 秒窗口是折中：太短会误判无人，太长则「走了 1 分钟灯还亮着」。想真正稳，得换毫米波雷达（LD2410 这类存在式传感），软件补不了。

## 四、数据模型

新文件 `datas/admin/scenes.json`，与 `ha.json` / `deviceTypes.json` 同级。
`settings` 放全局配置（目前只有 `occupiedWindowSec`），`scenes` 放场景本体；都用原子写（tmp + rename）。

```json
{
  "version": 1,
  "settings": { "occupiedWindowSec": 90, "haPollSec": 15 },
  "scenes": [
    {
      "id": "s_hjj_kaideng",
      "name": "回家自动开灯",
      "kind": "auto",
      "enabled": true,
      "trigger": {
        "rules": [
          {
            "conditions": [
              { "type": "presence", "deviceId": "esp32s3-3030f96cd03c", "state": "present", "holdSec": 10 },
              { "type": "ha_state", "entityId": "light.ke_ting_zhu_deng", "op": "eq", "value": "off" }
            ]
          },
          { "conditions": [{ "type": "time", "at": "07:30" }] }
        ]
      },
      "window": { "days": [], "start": "", "end": "" },
      "actions": [
        { "type": "ha", "entityId": "light.ke_ting_zhu_deng", "action": "turn_on", "param": "", "onError": "stop" },
        { "type": "remote", "target": "m_xxx", "action": "home_page", "param": "", "onError": "continue" },
        { "type": "delay", "seconds": 30, "onError": "continue" }
      ],
      "cooldownSec": 30,
      "lastRunAt": 0,
      "lastResult": "ok",
      "runCount": 6,
      "createdAt": 0,
      "updatedAt": 0
    }
  ]
}
```

手动控制复用同一结构，`kind: "manual"`、`trigger` 省略。

| 字段 | 取值 | 说明 |
|---|---|---|
| `trigger.rules[]` | 最多 8 条 | 规则卡片，彼此 **OR**；旧单 trigger / 旧 AND 组迁移成 1 条规则，旧 OR 组迁移成每条条件 1 条规则 |
| `trigger.rules[].conditions[]` | 每规则最多 8 条、总计最多 16 条 | 规则内条件彼此 **AND**，每条是一张条件卡 |
| `conditions[].type` | `presence` / `button` / `time` / `ha_state` / `window` | 五类条件 |
| `conditions[].holdSec` | 0–3600 | presence 专用，持续多久才触发，默认 10；**这是防抖的关键** |
| `conditions[].state` | `present` / `absent` | presence 用 |
| `conditions[].entityId` / `attr` / `op` / `value` | HA 实体 / 遥控伪实体 | `ha_state` 用；`op` = eq/neq/contains/gt/lt/exists；选「有值」时 value 可空 |
| `conditions[].days` / `start` / `end` | 星期数组 + 时段 | `window` 用；空数组 = 每天；空时段 = 全天；支持跨零点 |
| `window`（旧字段） | `days[]` + 时段 | 兼容旧配置的全局时间闸门，新配置用 `window` 条件卡 |
| `settings.haPollSec` | 5–60，默认 15 | `ha_state` 条件读 HA / 遥控状态的轮询间隔，在「感应与状态设置」里改 |
| `actions[].type` | `ha` / `remote` / `delay` / `esp_page` | 前三项现有执行器已支持，`esp_page` 二期 |
| `actions[].onError` | `stop` / `continue` | 默认 `stop`，符合「按顺序，失败即停」 |
| `cooldownSec` | 0–3600 | 同场景重入间隔，防传感器抖动连续触发 |

## 五、接口清单

全部 `requireParentOperator`（与 `/api/admin/esp/presence` 一致）。

| 方法 | 路径 | 用途 | 备注 |
|---|---|---|---|
| GET | `/api/admin/scenes` | 列表 + settings + 感应实体 | 一次拉全量，切 Tab 只调一次 |
| PUT | `/api/admin/scenes/settings` | 改 `occupiedWindowSec` | 必须注册在 `/:id` 之前，否则被当 id 吞掉 |
| POST | `/api/admin/scenes` | 新建 | 服务端归一化，非法动作直接拒 |
| PUT | `/api/admin/scenes/:id` | 编辑 | 只改传入字段；`kind` 不允许改 |
| DELETE | `/api/admin/scenes/:id` | 删除 | 软删，留 `deletedAt`，30 天后清理 |
| PATCH | `/api/admin/scenes/:id/enabled` | 开关 | 高频操作，避免整表覆盖 |
| POST | `/api/admin/scenes/:id/run` | 手动执行 / 试运行 | force=true，忽略 enabled 与冷却 |
| GET | `/api/admin/presence/entities` | 感应实体列表 | 后台展示用 |

> `/api/device/presence`（对外只读）**未实现**：给外部系统消费需要独立鉴权，
> 复用 admin 会话会让「这个口到底是给谁调的」含糊。等真有外部消费需求再单独设计（P2）。

`POST /run` 返回结构（前端按这个渲染逐步结果）：

```json
{ "ok": true, "sceneId": "s_x", "steps": [
  { "i": 1, "type": "ha", "label": "开客厅主灯", "status": "ok", "ms": 180 },
  { "i": 2, "type": "remote", "label": "中控切到首页", "status": "failed", "error": "目标设备离线", "ms": 12 }
], "result": "partial" }
```

## 六、执行引擎

### 6.1 触发接点（都落在现有代码位置上）

| 触发类型 | 接在哪里 | 延迟 |
|---|---|---|
| `presence` | `POST /api/device/heartbeat` 里写 `espPresence` 的那段（admin.js:3399 附近），跳变时调用 `sceneEngine.onPresence()` | < 1 秒 |
| `button` | `POST /api/device/esp/press` 里执行完按键动作后，再调 `sceneEngine.onButton()` | < 1 秒 |
| `time` | 新增一个 60 秒 `setInterval`，比对「当前分钟是否等于场景时间」 | ±1 分钟 |
| `ha_state` | `tick()` 内按 `settings.haPollSec`（默认 15 秒，5–60 可配）独立节流，走注入的 `getStates`（复用 `haCatalogService.getStates`）；遥控伪实体 `remote.*` 走注入的 `readRemoteState`（与「插入实体」弹窗同源） | 15 秒级 |
| `window` | 并入轮询后的状态判定；`inWindow()` 判星期 + 时段，支持跨零点 | 15 秒级 |

> 关键 1：**触发时机不变**——条件满足即触发，重复执行由 `cooldownSec` 拦；引擎不做边沿检测、不做「状态保持 N 秒」（用户明确口径）。
> 关键 2：`presence` 的 `holdSec` 不是「等 10 秒再执行」，而是「进入时记下 pendingAt，10 秒后仍在有人状态才执行」。中途变无人则取消 pending。这样不会因为人走过走廊误触发。条件组里 presence 用 `occupied` 窗口（而非瞬时电平）判定，否则 AND 组合会被 PIR 两秒掉电平反复打断。
> 关键 3：HA 轮询用独立 `lastHaPoll` 节流，**不能放在 time 判定的 30 秒节流之后**，否则配 15 秒实际变 30 秒（本次实现踩过并修掉）。

### 6.2 执行器复用

不自建一套调用逻辑，直接复用 `admin.js` 内已有的两条路径：

- HA：`callHaService(entityId, action, param)`（ha_catalog 动态解析服务名）
- 中控/电视：`pushRemoteCommand(account, frame)` + `remoteCommandArgs()`

新增的只是「按 actions 数组顺序遍历 + 记录每步结果 + 按 onError 决定继续还是中断」。

### 6.3 并发与超时

| 项 | 规则 |
|---|---|
| 同场景 | 串行。上一次未结束时新触发直接丢弃并记 `skipped`（不排队，排队会雪崩） |
| 跨场景 | 并行，上限 5，超出排队 |
| 单动作超时 | 10 秒，超时按失败处理 |
| `delay` 动作 | 最长 600 秒；期间场景被停用则中断后续 |
| 冷却 | 同场景 `cooldownSec` 内不重复触发 |

### 6.4 执行状态机

```
idle ──触发──▶ pending(holdSec 计时) ──满足──▶ running ──▶ done(ok)
                    │                            │
                    └──条件消失──▶ cancelled      └──某步失败──▶ failed(partial)
```

`done` / `failed` 都写回 `lastRunAt`、`lastResult`、`runCount`，前端卡片读这三个字段。

## 七、异常与边界

| 场景 | 表现 | 处理 |
|---|---|---|
| 目标中控/电视离线 | 动作失败 | 卡片红边 + `上次执行失败：电视离线（07:30）`，不弹窗 |
| HA 未配置或 token 失效 | 所有 ha 动作失败 | 整场景标红，编辑页顶部提示「HA 未连接」 |
| 动作引用的实体被删 | 执行时 callHaService 报错 | 编辑页保存时就校验实体存在，不存在则拒绝保存并标出哪一条 |
| 传感器每 2 秒抖动 | 频繁触发 | `holdSec` + `cooldownSec` 双重防抖；引擎侧统计 `skipped` 次数入日志 |
| 场景引用的小屏被删 | 触发永不发生 | 列表页该卡片显示「设备已不存在」并禁用开关，允许改绑定 |
| 服务重启 | `pending` 计时丢失 | 可接受（最多漏一次触发），启动时把 `running` 标为 `interrupted` |
| 时区/夏令时 | 定时错位 | 统一用服务端本地时区，界面上标注「按服务器时间」 |
| 动作数量过多 | 执行时间过长 | 单场景上限 20 个动作，超出拒绝保存 |

## 八、分期

### P1（已实现，2026-11-19 上线）

1. 智能 Tab：列表 + 手动控制执行 + 自动化开关
2. 自动化编辑：规则卡片（规则内 AND、规则间 OR）+ presence / button / time / ha_state / window 五类条件，ha / remote / delay / scene 四类动作
3. `presence` + `occupied` 双状态实体，后台实体详情页（含窗口可调）
4. `POST /run` 逐步结果 + 失败时弹步骤明细（成功只 toast，不打断）

实现落点：`server/scenes.js`（引擎 + 存储 + 感应实体）、`server/admin.js`（注入执行器、
8 个接口、心跳与按键联动、1 秒 tick）、`web/admin_js/12-smart.js`（前端）、`web/admin.css`。

### P2（已提到 P1 完成，v1.2）

1. ~~HA 实体状态触发（15 秒轮询）~~ — 已上线，`ha_state` 条件 + `settings.haPollSec`
2. ~~条件（condition）：多条件 AND/OR~~ — 已上线，v1.3 起为 `trigger.rules` 规则卡片（规则内 AND、规则间 OR）
3. `esp_page` 动作：让指定小屏跳到某页（**要固件配合加 FORCE 行，按 D-04 本期不做**）

### v1.2 验收记录（2026-11-19 19:45）

- 服务端单测 `test/scenes_conditions_test.js` **11/11**：旧 trigger 迁移、五类条件归一化、非法类型拦截、AND/OR 描述、HA 匹配/不匹配、AND 一假即不触发、OR 一真即触发、遥控伪实体、window 时段外不触发、haPollSec 边界。
- 真实 admin 页无头浏览器 **24/24**：AND/OR 下拉、增删条件、ha_state 参数、复用插入实体弹窗、window 七天与跨零点、保存落库为条件组、触发文本、回读一致。
- 回归：`esp_sys_test.js` 14/14、`esp_template_token_test.js` 7/7、ESP 页浏览器 26/26。
- 部署：5 文件同步到 `100.83.142.107`，备份 `.bak-smartcond-20261119_1945`，md5 对齐、远端语法校验、`pm2 restart my-server`、线上接口验证旧自动化「回家自动开灯」迁移为 `logic=and / 1 条件`。

### v1.3 验收记录（2026-11-19 20:15，本地完成）

- 服务端单测 `test/scenes_conditions_test.js` **14/14**：旧单 trigger / 旧 AND 组 / 旧 OR 组迁移、新 rules 五类条件、非法类型与空规则拦截、规则间「或」+ 规则内「且」描述、HA 匹配/不匹配、规则内一假即不触发、规则间一真即触发、全不满足不触发、旧 OR 组迁移后仍按 OR 触发、遥控伪实体、window 时段、haPollSec 边界。
- 真实 admin 页无头浏览器 **36/36**：无旧 AND/OR 下拉、两个新增按钮、默认 1 规则 1 条件、「且」/「或」连接词、加规则/加条件后确实调用滚动（含 rAF）、规则内「+ 条件」、规则与条件删除守卫、复用插入实体弹窗、保存落库为 `[2,1]` 两规则、触发文本「(A 且 B) 或 C」、回读一致。
- 回归：`esp_sys_test.js` 14/14、`esp_template_token_test.js` 7/7、`admin_alias_test.js` 6/6；改动文件 `node --check` 全通过。
- 部署（20:17 完成）：3 文件 `server/scenes.js`、`build/web/admin_js/12-smart.js`、`build/web/admin.css` 同步到 `100.83.142.107`，备份后缀 `.bak-smartrules-20261119_2017`，LF + md5 对齐（线上回读 `045dc33d…` / `b037ee6e…` / `23189192…`）、远端 `node --check` 通过、`pm2 restart my-server` 后服务在线。线上验证：静态资源 HTTP 200 且 md5 与本地一致；`/api/admin/scenes` 读旧自动化「回家自动开灯」已迁移为 `rules=[["presence"]]`，无残留 `logic` 字段。
4. 感应实体作为 ESP 模板变量（`{presence.state}`）——需要改 `resolveDisplay` 的取数上下文，
   单独一次改动更安全，不塞进本次
5. 通知动作：执行成功/失败推到家长端
6. 场景模板市场（回家/离家/观影预设）
7. `/api/device/presence` 对外只读接口（含独立鉴权）

## 九、验收标准

| 编号 | Given | When | Then |
|---|---|---|---|
| AC-01 | 已建「有人持续 10 秒 → 开灯」 | 人在屏前停留 10 秒 | 10 秒内灯亮，卡片显示「今天触发 N 次 · 最近 hh:mm」 |
| AC-02 | 同上 | 人走过（停留 3 秒离开） | 不触发，日志记 1 次 `cancelled` |
| AC-03 | 自动化已关闭 | 满足触发条件 | 不执行，`runCount` 不变 |
| AC-04 | 「开灯 + 电视切台」，电视离线 | 手动点执行 | 第 1 步成功、第 2 步失败并标红，后面不再执行 |
| AC-05 | 同一场景 30 秒内连续满足 | 第二次触发 | 直接跳过，不重复执行 |
| AC-06 | 感应实体详情页 | 人坐下不动 2 分钟 | `presence` 显示无人、`occupied` 仍显示占用中 |
| AC-07 | 服务重启后 | 打开智能 Tab | 上次 `running` 的场景显示「已中断」，可重新执行 |

## 十、决策记录

| 问题 | 结论 | 落地位置 |
|---|---|---|
| 感应实体要不要做成真 HA 实体 | **不做**，只用服务内的虚拟实体 `presence.<deviceId>` | `scenes.js` 的 `presenceEntityOf` |
| `occupied` 窗口默认值 | **90 秒**，可在「人体感应实体」面板里改 | `scenes.json` 的 `settings.occupiedWindowSec` |
| 动作失败默认策略 | **失败即停**，单条可勾「失败也继续」 | `normalizeScene` 的 `onError` 默认 `stop` |
| `esp_page` 动作（强制小屏跳页） | **本期不做**（要改固件） | 记入 P2 |

> 合规声明：本方案为产品设计参考，具体实施请结合公司合规与法务要求确认。
