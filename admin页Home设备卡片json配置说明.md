# admin 页 Home 设备卡片 JSON 配置说明

这份文档解决两个反复出现的痛点：

1. **该填什么值**——所有占位符、内联规则、节点字段、动作通道、枚举值都列出来，不用猜。
2. **哪个能生效**——后台保存会做白名单过滤，Dart 渲染器只认已实现的字段；这里标出真实生效范围、值域和优先级。

> 带 `<!-- AUTO:xxx -->` 的区块由脚本从源码自动生成，**不要手改**。更新方法见第 10 节。
> 改 JSON 布局后保存即热更新到 App；**新增 Dart 解析能力必须重新编译安装 App** 才生效（后台预览只是近似模拟）。

---

## 0. 动手之前先看这 8 条

1. 后台保存会白名单过滤：**未知 `type`、未知字段直接丢弃**，保存后不生效先查第 4 节。
2. `{title}` 在渲染层自动拼房间名（多房间时显示「客厅 设备名」），**不要写 `{room} {title}`**。
3. 一行里不同实体各自的 on/off 文案，用**占位符内联规则** `{s:后缀|on=…,off=…}`；节点级 `map` 会作用于整行所有占位符，会串味。
4. HA 的 `brightness` 是 **0-255**，显示百分比要写 `|pct`；`pct` 对 >255 的值不再换算。
5. `map` 是**整值精确匹配**，`replace` 是**子串替换**（新串留空即删除）；先 `replace` 后 `map`。
6. `visibleWhen` / `enabledWhen` 判断的是**原始值**：节点级 `map` / `replace` 不参与（内联规则会参与）。
7. `mainAlign:spaceBetween` 要贴底：父节点写 `fill:true`，且子节点**不要有吃掉剩余空间的 `expand:true`**；横向撑满的 `expand` 可以保留。
8. 未知动作字符串不会猜实体；`toggle` / `press` 只作用于主实体，指定实体请用 `toggle@{id:后缀}` / `press@{id:后缀}`。

---

## 1. 一分钟定位：我想做 X，该填什么

| 需求 | 写法示例 |
| --- | --- |
| 显示设备标题 | `"value": "{title}"` |
| 显示主实体状态并改中文 | `"value": "{state\|on=已开机,off=待机中}"` |
| 按 entity_id 后缀取状态 | `"value": "{s:_on_p_2_2}"` |
| 按后缀取属性（亮度等） | `"value": "{s:_light.brightness\|pct}%"` |
| 取完整 entity_id 给动作用 | `"onClick": "toggle@{id:_on_p_2_1}"` |
| 一行两个实体各用各的文案 | `"value": "{s:_a\|on=开,off=关} · {s:_b\|on=运行中,off=已停止}"` |
| 状态变化时变色 / 变图标 | `"colorMap": "on=#FF7043,off=#4dd4ac"`，`"iconMap": "on=power_off,off=power_on"` |
| 状态变化时改按钮文案 | `"labelMap": "on=关闭,off=开启"` |
| 删除friendly_name里的型号前缀 | `"replace": "米家智能香氛机="`（新串留空即删） |
| 只在开机时显示 | `"visibleWhen": "{s:_on_p_2_2}=on"` |
| 关机时按钮仍显示但不可点 | `"enabledWhen": "{s:_on_p_2_2}=on"` + `colorMap` 做暗色 |
| 时间按 Flutter 格式显示 | `"value": "{s:click_e_3_1012\|date:yyyy-MM-dd HH:mm}"` |
| 时间显示成相对时间 | `"value": "{s:click_e_3_1012\|ago}"` |
| 取接入/断开中较晚的时间 | `"value": "{s:_connect\|maxWith=s:_disconnect,ago}"` |
| 标题超长滚动 | `"marquee": true, "marqueeMode": "pingpong", "marqueeDirection": "left", "marqueePause": 3` |
| 文本 / label 换行 | `"value": "第一行\n第二行"`（JSON 里用 `\n` 转义）；未写 `maxLines` 时自动按行数放开，最多 6 行 |
| 多个同类实体重复渲染 | `"type": "repeat", "source": "gangs", "item": "gang", "template": {...}`，模板里用 `{gang.label}` / `toggle@{gang.entityId}` |
| 贴底分布 | 父节点 `"fill": true, "mainAlign": "spaceBetween"` |

---

## 2. 占位符速查

`{xxx}` 里的 `xxx` 在渲染层求值；找不到时替换为空串。

<!-- AUTO:placeholders -->
| 写法 | 取值 |
| --- | --- |
| `{title}` | 卡片标题；渲染层在多房间时自动拼房间名，不要再写 {room} |
| `{room}` | 房间名 |
| `{icon}` | 类型图标 |
| `{color}` | 类型主题色 |
| `{label}` | 类型标签（如「当前温度」） |
| `{main}` | 按 mainAttr / mainFmt 算出的主数值 |
| `{sub}` | 按 subTpl 算出的副文案 |
| `{state}` | 主实体 state |
| `{s1}` | 组内第 2 个实体的 state |
| `{s2}` | 组内第 3 个实体的 state |
| `{status}` | 分组状态文案 |
| `{gangCount}` | 可开关路数 |
| `{gangOnCount}` | 已开启路数 |
| `{primary.entityId}` | 主实体完整 entity_id |
| `{primary.switchable}` | 主实体是否可切换（常用于 visibleWhen） |
| `{brightnessPercent}` | 亮度百分比 0-100 |
| `{brightness}` | 亮度原始值 0-255 |
| `{attr.xxx}` | 主实体任意属性（如 {attr.friendly_name}） |
| `{entity.N.state}` | 组内第 N 个实体 state（N 从 0 起，最多 16） |
| `{entity.N.id}` | 组内第 N 个实体 entity_id |
| `{entity.N.name}` | 组内第 N 个实体显示名 |
| `{gang.xxx}` | repeat/source=gangs 时每路的字段（label/state/stateLabel/style/entityId/index） |
| `{item.xxx}` | repeat 模板项字段（等价于 gang.xxx 的通用写法） |
| `{s:后缀}` | 按 entity_id 子串匹配组内实体，取 state；支持 {s:后缀.属性} 读属性 |
| `{a:后缀.属性}` | 按后缀匹配实体，取指定 attribute |
| `{id:后缀}` | 按后缀匹配实体，取完整 entity_id（动作通道常用） |
<!-- AUTO:END -->

### 2.1 按实体后缀取值（最常用）

同一设备有多个同类实体（开关 / 模式 / 温度 / 电量…）时，下标不稳定，**用 entity_id 的子串定位**：

| 写法 | 含义 | 示例 |
| --- | --- | --- |
| `{s:后缀}` | 匹配到的第一个实体 `state` | `{s:_battery_level_p_5_1}` → `82` |
| `{s:后缀.属性}` | 该实体的属性，等价于 `a:` | `{s:_s_3_ambient_light.brightness}` |
| `{a:后缀.属性}` | 同上，显式属性写法 | `{a:_p_2_1.friendly_name}` |
| `{id:后缀}` | 完整 entity_id，主要给动作通道用 | `toggle@{id:_on_p_2_2}` |

- 匹配规则：对组内每个实体的 `entity_id` 做**不区分大小写的子串包含**，取第一个命中的。
- 后缀必须足够独特，否则会命中同设备里另一个实体。
- HA 的 `unknown` / `unavailable` 不会自动变成 `—`，要用映射兜底：`{s:xxx|unknown=—,unavailable=—}`。

### 2.2 三元表达式（兜底能力）

`{gang.isOn ? '开' : '关'}` 形式可用，但渲染层更常用预求值字段（如 `{gang.stateLabel}`），优先用后者。

---

## 3. 内联规则 `|...`

写在**占位符内部**、紧跟 key：

```json
"{s:_on_p_2_2|on=已开机,off=待机中}"
"{s:_s_3_ambient_light.brightness|pct}"
"{s:click_e_3_1012|date:yyyy-MM-dd HH:mm,unknown=—}"
```

<!-- AUTO:inlineRules -->
| 规则 | 作用 |
| --- | --- |
| `|pct` | HA light 的 0-255 → 0-100 百分比；>255 视为已是百分比，不再换算 |
| `|date[:pattern]` | ISO 时间按 Flutter DateFormat 格式化；支持 `zh:` / `en_US:` 前缀，省略 pattern 用 yMd |
| `|maxWith=<占位符 key>` | 当前值与另一个占位符都是 ISO 时间时取较晚者；非时间值以可解析的一方为准 |
| `|ago` | ISO 时间 → 相对时间（刚刚 / N分钟前 / N小时前 / N天前）；非时间值原样返回 |
| `|when=<key>:<期望值>=<文案>` | 另一个占位符当前值等于期望值时，把本占位符输出替换为文案（key 含冒号，如 s:_charging_state_p_5_2；如充电中覆盖开机文案） |
| `|key=值` | 通用整值映射：值可用单/双引号包住以保护逗号；多条用逗号 / 中文逗号 / 分号分隔 |
<!-- AUTO:END -->

要点：

- 多条规则用**逗号 / 中文逗号 / 分号 / 换行**分隔；值里要带逗号时用单/双引号包住，例如 `|on='开着,正在用',off=关`。
- 规则**从左到右依次作用**，所以 `date` / `ago` 这类转换要放在 `unknown=—` 映射前面。
- `pct` 只处理数值；已是 0-100 的百分比不会二次换算。
- `maxWith=<占位符 key>` 的 key 也是完整占位符写法（如 `s:_device_disconnect_e_2_2`）。
- `date` / `ago` / `maxWith` 是较新增的解析能力，**旧版 App 不认识，需重编安装**；后台预览只是近似实现，以 App 实际显示为准。

---

## 4. 节点类型与字段白名单

布局 JSON 写在 `card.layout`；`card` 本身还有下面这些字段（后台「卡片布局」区可编辑）：

<!-- AUTO:cardFields -->
| card 字段 | 说明 |
| --- | --- |
| `label` | 类型标签 / 主数值说明 |
| `mainAttr` | 主数值取自主实体的哪个属性 |
| `mainFmt` | 主数值格式模板，{v} 为原始值 |
| `subTpl` | 副文案模板，支持 {main}/{state}/{s1}/{s2} |
| `icon` | 卡片图标，布局里用 {icon} 引用 |
| `color` | 主题色，布局里用 {color} 引用 |
| `mainEntity` | 主实体匹配串（entity_id 或名称子串） |
| `bg` | 卡片正常背景色：#RRGGBB / #RRGGBBAA / {color}26；留空跟随主题 |
| `disabledBg` | 设备不可用 / 断线时的卡片背景色；留空跟随主题 |
| `buttons` | 旧版按钮定义（新布局一般用 layout 里的 button / chip） |
| `genericEnabled` | 是否启用通用卡片渲染 |
| `span` | 跨格尺寸 {col,row}，各 1~4 |
| `layout` | JSON 布局树，见第 4 节 |
<!-- AUTO:END -->

`bg` / `disabledBg` 是**卡片容器背景**（正常 / 设备离线），支持 `#RRGGBB`、`#RRGGBBAA`、`{color}26` 这类带透明度的写法；留空沿用 App 主题色。注意这两个字段改的是整张卡片，不是某个节点；节点的强调色仍用 `color`。

### 4.1 节点类型

<!-- AUTO:nodeTypes -->
| type | 主要字段 |
| --- | --- |
| `row` | 横向排列；gap / crossAlign / mainAlign |
| `column` | 纵向排列；fill:true 撑满高度，配合 mainAlign:spaceBetween 贴底 |
| `wrap` | 横向自动换行 |
| `stack` | 层叠；子节点用 stackAlign / position 定位 |
| `text` | 文本；value / size / weight / color / maxLines / align / marquee* |
| `icon` | 图标；value / size / color / box(size/radius/bg/color) |
| `button` | 按钮；label / icon / value / style / onClick / round / height |
| `chip` | 小按钮；字段同 button，常用作快捷操作 |
| `progress` | 进度条；value / min / max / color / height / interactive / onClick |
| `sparkline` | 功率曲线；metric(power/temperature/humidity) / window / height / showLabels |
| `repeat` | 重复模板；source / item / columns / gap / template |
| `divider` | 分割线；color / thickness |
<!-- AUTO:END -->

### 4.2 保存时真正保留的字段

后台 `sanitizeLayout()` 只保留下表字段；写错名字、写错类型、超范围的值会被**丢弃或夹到边界**。

<!-- AUTO:fields -->
| 字段 | 类型 / 值域 | 适用节点 |
| --- | --- | --- |
| `box` | 对象 {size 16~96, radius 0~32, bg, color} | icon |
| `children` | 子节点数组（最多 24 个） | 通用 |
| `color` | 字符串 ≤400；字符串 ≤40 | text / icon / button / chip / progress / sparkline / divider |
| `colorMap` | 字符串 ≤240 | 通用 |
| `columns` | 数值 1~4（默认 2） | repeat |
| `confirm` | 字符串 ≤60 | button / chip |
| `enabledWhen` | 字符串 ≤120 | 通用 |
| `expand` | 布尔（true 才保留） | 通用 / sparkline |
| `fill` | 布尔（true 才保留） | 通用 |
| `gap` | 数值 0~64（默认 8）；数值 0~32（默认 8） | 通用 / repeat |
| `height` | 数值 24~72（默认 30）；数值 2~24（默认 6）；数值 24~180（默认 60） | button / chip / progress / sparkline |
| `icon` | 字符串 ≤400 | button / chip |
| `iconMap` | 字符串 ≤240 | 通用 |
| `interactive` | 布尔（true 才保留） | progress |
| `label` | 字符串 ≤400 | button / chip |
| `labelColor` | 字符串 ≤40 | sparkline |
| `labelMap` | 字符串 ≤240 | 通用 |
| `mainAlign` | 枚举：start / center / end / spaceBetween / spaceAround / spaceEvenly | 通用 |
| `map` | 字符串 ≤240 | 通用 |
| `marquee` | 布尔（true 才保留） | 通用 |
| `marqueePause` | 数值 0~30（默认 2） | 通用 |
| `marqueeSpeed` | 数值 5~300（默认 40） | 通用 |
| `max` | 字符串 ≤40 | progress |
| `maxLines` | 数值 1~6（默认 1） | text |
| `metric` | 枚举：power / temperature / humidity | sparkline |
| `min` | 字符串 ≤40 | progress |
| `onClick` | 字符串 ≤120 | button / chip / progress |
| `padding` | 数组 [垂直, 水平]，各 0~48 | 通用 |
| `position` | 对象 {left/top/right/bottom/width/height}，像素 -2000~2000 | 通用 |
| `replace` | 字符串 ≤360 | 通用 |
| `round` | 布尔（true 才保留） | button / chip |
| `showLabels` | 布尔（true 才保留） | sparkline |
| `size` | 数值 8~48（默认 14）；数值 8~64（默认 24）；数值 16~96（默认 52） | text / icon / button / chip |
| `stackAlign` | 枚举：topLeft / topCenter / topRight / centerLeft / center / centerRight / bottomLeft / bottomCenter / bottomRight | 通用 |
| `style` | 字符串 ≤40 | button / chip |
| `subLabel` | 字符串 ≤400 | button / chip |
| `template` | 节点对象（repeat 模板） | repeat |
| `thickness` | 数值 1~8（默认 1） | divider |
| `value` | 字符串 ≤400；字符串 ≤40 | text / icon / button / chip / progress |
| `visibleWhen` | 字符串 ≤120 | 通用 / button / chip / progress |
| `weight` | 数值 100~900（默认 400） | text |
| `window` | 字符串 ≤20 | sparkline |
<!-- AUTO:END -->

后台限制：

<!-- AUTO:limits -->
布局最大深度 8；单卡最大节点数 120；单节点最大子节点数 24。超限节点保存时会被丢弃。
<!-- AUTO:END -->

其他注意：

- `padding` 只取两个数：`[垂直, 水平]`；不写 `[x, y]` 之外的形式。
- 颜色可写十六进制简写后缀做透明：`{color}26` 表示主题色加 15% 不透明度。
- `style` 可写固定枚举 `filled / outlined / active / tonal / normal`，也可写占位符（如 `{gang.style}`）。
- `sparkline` 的 `metric` 只认 `power / temperature / humidity`；`window` 支持 `10min / 1h / 6h / 24h`。
- `visibleWhen` / `enabledWhen` / `map` / `replace` / `colorMap` / `labelMap` / `iconMap` / `marquee*` 是**所有节点通用**字段，不只属于 button/chip。

### 4.3 布局层级与拉伸

| 字段 | 作用 |
| --- | --- |
| `expand: true` | 占满父级**主轴剩余空间**；横向 row 里让文字列撑满，纵向 column 里会吃掉全部高度 |
| `fill: true` | column 填满可用高度，配合 `mainAlign:spaceBetween` 做上下分布 |
| `mainAlign` | `start / center / end / spaceBetween / spaceAround / spaceEvenly` |
| `crossAlign` | `start / center / end` |
| `align` | text 节点自己的对齐：`left / center / right` |
| `stackAlign` | stack 子节点九宫格对齐：`topLeft / topCenter / topRight / centerLeft / center / centerRight / bottomLeft / bottomCenter / bottomRight` |
| `position` | stack 子节点绝对定位：`left / top / right / bottom / width / height`（像素） |

---

## 5. 条件显隐与可点

两种条件写法完全相同：

```json
"visibleWhen": "{s:_on_p_2_2}=on"          // 不成立时整个节点不渲染
"enabledWhen": "{s:_on_p_2_2}=on"          // 不成立时仍显示，但按钮不可点
```

- 支持 `=` / `==` / `!=` 比较，右侧可用单/双引号包住。
- 裸占位符当真值：`resolve()` 结果非空、且不是 `false` / `0` 即为真，例如 `"visibleWhen": "{primary.switchable}"`。
- 条件判断用**原始值**：节点级 `map` / `replace` 不影响判断；占位符内联规则会参与。
- 香薰机那种「关机按钮暗色且不可点」写法：`enabledWhen` 控可点，`colorMap` 控颜色，`iconMap` 控图标。

---

## 6. 动作 onClick

`onClick` 由渲染器求值后交给上层白名单派发，**不执行脚本、不猜实体**。

<!-- AUTO:actions -->
| onClick 写法 | 行为 |
| --- | --- |
| `kettle@action` | 热水瓶专用：按实时状态选择开始 / 停止，不猜实体 |
| `toggle@` | toggle@<entityId>：控制指定实体（多路开关的每路大按钮）。 |
| `press@` | press@<entityId>：按指定实体按钮。 |
| `brightness@` | brightness@<entityId>:<percent>：卡片亮度条松手时下发。 只对明确写了支持调光的实体发指令，避免误伤纯开关灯。 |
| `fan@` | fan@<entityId>:<percent>：风扇风速条松手时下发。 与 brightness@ 对称：只对明确写了 fan 实体下发，bloc 内部 还会再校验 isFan 并 clamp 0-100，不会误伤灯/开关。 |
| `climateTemp@` | 空调目标温度 ±：climateTemp@<实体>:<增量>（如 -0.5 / +0.5） |
| `climateMode@` | 空调模式循环：climateMode@<实体>，依次切下一个 hvac_mode |
| `climateFan@` | 空调风速循环：climateFan@<实体>，依次切下一个 fan_mode |
| `toggle` | 切换主实体（未指定 entityId 时） |
| `turn_on` | 兼容旧写法，同 toggle |
| `turn_off` | 兼容旧写法，同 toggle |
| `press` | 按主实体按钮（未指定 entityId 时） |
| `notify` | 主实体发通知动作 |
<!-- AUTO:END -->

写法说明：

| 写法 | 适用 | 说明 |
| --- | --- | --- |
| `toggle` / `press` | button / chip | 作用于主实体 |
| `toggle@{id:后缀}` / `press@{id:后缀}` | button / chip | 明确指定实体，多路开关的每路按钮用这个 |
| `toggle@{gang.entityId}` | repeat 模板 | 每路按钮绑定自己的实体 |
| `brightness@{id:后缀}` | progress `interactive:true` | 滑条松手时渲染器自动补 `:百分比`，只对支持调光的灯生效 |
| `brightness` / `brightness@auto` | progress | 自动挑组内第一个支持调光的灯 |
| `fan@{id:后缀}` | progress `interactive:true` | 风速条，同样自动补百分比 |
| `kettle@action` | 热水瓶专用 | 按实时状态选择「开始 / 停止」，不猜实体 |
| `notify` | button / chip | 主实体发通知动作，文案写在动作里 |
| 其它（如 `set_temperature(...)`） | button / chip | 打开设备详情页由专用面板处理 |

- 滑条断线时指令失败会回滚乐观预览，不会停在用户拖过的位置。
- `confirm` 可写确认文案，点击后弹确认框再执行。

---

## 7. Label / 标题跑马灯

```json
{
  "type": "text",
  "value": "{a:_p_2_1.friendly_name}",
  "marquee": true,
  "marqueeMode": "loop",
  "marqueeDirection": "left",
  "marqueePause": 2,
  "marqueeSpeed": 40
}
```

| 想要的效果 | 配置 |
| --- | --- |
| 不启用（保留省略号） | 不写 `marquee`，或 `"marquee": false` |
| 一直向左无缝循环 | `marquee:true, marqueeMode:"loop", marqueeDirection:"left"` |
| 一直向右无缝循环 | 同上，`marqueeDirection:"right"` |
| 向左到头停 N 秒 → 往回跑到开头停 N 秒 | `marqueeMode:"pingpong", marqueeDirection:"left", marqueePause:N` |
| 向右到头停 N 秒 → 往回跑到尽头停 N 秒 | 同上，`marqueeDirection:"right"` |

两点注意：

- 只做单行（`maxLines:1`）；多行仍走原来的省略号布局。
- 文字要放在 `expand:true` 的 column 里，或给该 text 节点写 `expand:true`，否则拿不到有界宽度，会退化成静态文本。文字本身没超宽时也不滚，直接显示全文。

---

## 8. 时间格式化

直接用 Flutter `DateFormat`，写在 `|date:` 后面：

```json
"{s:click_e_3_1012|date:yyyy-MM-dd HH:mm}"   → 2026-11-23 15:11
"{s:click_e_3_1012|date:yMd}"                → 2026/11/23
"{s:click_e_3_1012|date:yMEd}"               → 2026/11/23周一
"{s:click_e_3_1012|date:Hms}"                → 15:11:06
"{s:click_e_3_1012|date:en_US:yMd}"          → 11/23/2026
```

- 不写 pattern（只写 `|date`）时默认 `yMd`，locale 默认 `zh`。
- locale 前缀形如 `zh:` / `en_US:`；`yyyy-MM-dd HH:mm` 里的冒号不会被误判为 locale。
支持的简写构造函数（脚本自动从源码提取）：

<!-- AUTO:datePatterns -->
`y` / `M` / `d` / `E` / `EEEE` / `yM` / `yMd` / `yMEd` / `yMMM` / `yMMMd` / `yMMMEd` / `yMMMM` / `Hm` / `Hms` / `jm` / `jms`
<!-- AUTO:END -->

其它 pattern 直接按 `DateFormat(pattern, locale)` 处理。
- 非时间值（如 `off` 时的空串）会原样返回，所以常量时间卡建议加 `unknown=—,unavailable=—` 兜底。

---

## 9. 踩坑清单（按出现频率排序）

| 现象 | 原因 / 修法 |
| --- | --- |
| 保存后 JSON 里某个字段消失了 | 字段不在白名单（第 4.2 节），后台保存时被过滤 |
| 改了源码默认布局，线上没变化 | 该类型已被后台保存过，持久化配置优先；要改持久化数据，不是改源码默认值 |
| 同一行两个实体都显示成同一个状态文案 | 用了节点级 `map`；改成占位符内联 `\|on=…,off=…` |
| 亮度显示 82% 但 HA 里是 21 | 0-255 没换算；加 `\|pct` |
| 关灯后括号还留着 | 括号也要用条件包裹：`{s:_light\|on=(,off=}` 和 `{s:_light\|on=%),off=}` |
| 文字被截断成 `unknown` | 没兜底映射；加 `unknown=—,unavailable=—` |
| 长文本显示不全 | 加 `marquee`（第 7 节），并确认父级有界宽 |
| label / text 里的 `\n` 变成空格 | 旧版服务端 `clampText` 会替换换行，现已保留；确认后台脚本已更新并强刷浏览器 |
| `mainAlign:spaceBetween` 没贴底 | 父节点缺 `fill:true`，或子节点有 `expand:true` 吃掉剩余高度 |
| 点击按钮没反应 / 误动作了别的设备 | 动作没写 `@实体`，走了主实体；改成 `toggle@{id:后缀}` |
| 后台预览正常、App 不生效 | 新增 Dart 解析能力后 App 没重编；或后台 JS 改了没强刷浏览器 |
| 时间格式化成 literal | pattern 写错或值不是 ISO 时间；检查 HA 实体原始 state |

---

## 10. 自动维护：新增解析类型后怎么同步这份文档

文档里所有 `<!-- AUTO:xxx -->` 区块由脚本从源码提取，命令：

```bash
# 在仓库根目录执行，更新文档
node pscreen_server/scripts/gen-card-json-doc.mjs

# 只检查文档是否过期（过期时退出码 1，可挂 CI / pre-commit）
node pscreen_server/scripts/gen-card-json-doc.mjs --check
```

脚本的数据来源：

| 区块 | 提取自 |
| --- | --- |
| 占位符 | `card_layout.dart` 的 `_buildValues()` / `_resolveEntityToken()` |
| 内联规则 | `card_layout.dart` 的 `_applyInlineRules()` 分支 |
| 节点类型 / 字段白名单 / 限制 | `deviceTypes.js` 的 `LAYOUT_NODE_TYPES` / `sanitizeLayout()` |
| 动作通道 | `home_controll_board.dart` 的动作派发分支 |
| DateFormat 简写 | `card_layout.dart` 的 `_dateFormat()` |

所以新增解析能力时：

1. 在源码里加分支，**顺手写一行 `//` 注释说明**（脚本优先取注释；也可在脚本的 `INLINE_META` / `ACTION_META` 里覆盖描述）。
2. 运行上面的脚本，文档自动更新；`--check` 通过后再提交。
3. 新增占位符时，在脚本的 `PLACEHOLDER_DESC` 里补一条中文说明；没补的会标「说明待补」提醒你。

以后由我（助手）新增这类解析能力时，会在同一次改动里运行这个脚本并把文档一起提交；如果你希望更强的保证，可以把 `--check` 加到 pre-commit hook。
