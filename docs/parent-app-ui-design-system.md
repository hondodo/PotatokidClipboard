# 薯仔家长 · UI 设计系统 v4

> Design System & Developer Handoff Spec · 2026-11-13 · UI Designer 交付
> 适用：`pscreen_home` / flavor `parent`
> **功能语义基线**：`docs/parent-app-redesign-prototype-v3.html`（S1–S6 + CR-01 + CR-02 已定稿）
> **视觉与交互基线**：本文 + `docs/parent-app-redesign-prototype-v4.html`
> **2026-11-13 12:17 评审增补（CR-02）**：解锁方式由「家庭规则区」移入「电视设置 · 本台设置」，按 `deviceId` 独立保存；v3 / v4 与本文已同步。

---

## 0. 定位与边界

| 文件 | 职责 | 是否可替代 |
| --- | --- | --- |
| `prototype-v3.html` | 功能、信息架构、产品语义（家庭主档案 / 分配 / 题库副本 / 解绑 / 冲突 / 只读代管） | **语义单一事实源** |
| `prototype-v4.html` | 视觉语言、组件规格、交互习惯、无障碍、深浅主题 | 不替代 v3 语义 |
| 本文 | token、组件、页面规格、验收清单、Flutter 交付映射 | handoff 规格 |

**本轮只做视觉与交互重设计，不改信息架构与产品语义。** v4 沿用 v3 的三 Tab（今天 / 孩子 / 电视）、八个页面、九个弹层与四个场景；S1–S6、CR-01、CR-02、D-01/D-02/D-03 的结论全部保留。若需调整 Tab 结构或页面归属，另走变更评估，不得在视觉重设计里顺手改掉。

---

## 1. V3 评审结论（问题与定量证据）

### 1.1 没有真正的设计系统

- `:root` 只有 12 个颜色变量；其余十几个灰阶（`#f7f9f8`、`#edf1ef`、`#cfdad5`、`#d7e1dc`、`#52635d`、`#8ba097`、`#e8eeeb`、`#cbd6d1`…）全部硬编码在规则里。
- 字号无字阶：`10 / 11 / 12 / 13 / 15 / 17 / 21px` 七个值按需散落；`.tiny` 仅 **10px**。
- 间距无栅格：`3 / 7 / 9 / 10 / 11 / 13 / 14 / 15 / 17 / 22 / 24 / 44px` 混用，不是 4pt / 8pt 体系。
- 圆角七种：`5 / 6 / 7 / 8 / 14 / 32 / 999px`；阴影只有一个硬编码 `box-shadow`。
- 无动效 token、无 z-index 层级定义、无状态规范（hover / focus / disabled / loading 各写各的）。

### 1.2 无障碍不达标（WCAG 2.1 AA）

实测对比度（脚本计算，见 v4「无障碍」视图）：

| 组合 | v3 实测 | 判定 |
| --- | --- | --- |
| `--muted #6c7b76` / 白卡（11–12px 正文） | **4.44:1** | ❌ < 4.5:1 |
| `--muted #6c7b76` / 内容底 `#f7f9f8`（`.tiny` 10px） | **4.20:1** | ❌ < 4.5:1 |
| `--green #0f6e56` / 白 | 6.20:1 | ✅ |
| 白 / `--green` 主按钮 | 6.20:1 | ✅ |

其余问题：

- 无统一 `:focus-visible`，键盘用户看不到焦点；只有输入框有一条 `box-shadow`。
- 交互元素是裸 `div`：`.card.click`、`.switch`、`[data-act]` 均无 `role` / `tabindex` / `aria-label` / `aria-checked`，键盘与读屏不可达。
- `.modal` 无 `role="dialog"` / `aria-modal`，无焦点陷阱、无 Esc 关闭、关闭后不回焦。
- `.toast` 无 `role="status"` / `aria-live`，反馈读屏不可感知。
- Tab 图标是 Unicode 字符 `⌂ ♙ ▣`（♙ 是国际象棋兵），返回/关闭用 `‹ × ›`，读屏会念成符号，跨平台字形不一致。
- 无 `prefers-reduced-motion`、无深色主题、无 200% 文字缩放保证、无 `env(safe-area-inset-*)`。

### 1.3 触控目标过小

| 元素 | v3 尺寸 | 要求 |
| --- | --- | --- |
| `.iconbtn`（返回 / 头像） | 32×32 | ≥ 44×44 |
| `.btn.sm`（批准 / 分享设置） | 约 25px 高 | ≥ 44×44 命中区 |
| `.btn` 常规 | 约 35px 高 | ≥ 44×44 |
| `.switch` | 38×22 | ≥ 44×44 命中区 |
| `.tab` | 59px 高 | ✅（唯一达标） |

### 1.4 视觉层级与认知负荷

- 标题层级塌陷：`.app-title` 17px、`.title` 15px、`<h2>` 17px 几乎同级，页面缺少视觉锚点；没有 24px 以上的数据或标题。
- 所有卡片同权重（白底 + 1px 边框 + 8px 圆角），「孩子今日剩余时长」这一最重要信息被埋在同款卡片堆里。
- **解释性文案混入产品界面**：`.card.tint` / `.card.warn` 里写着「规则只有一份」「时长只记在家庭自己的账上」「跨家庭统计口径」等 PM 注释。这些是评审说明，不是用户要看的 UI，直接造成信息过载。v4 全部移到原型右侧规格栏。
- 绿色语义过载：`--green` 同时表示品牌、在线、已登录、可编辑、家庭主档案、实时同步，`.chip.green` 满屏出现，失去信号价值。
- 提示样式重复：`.card.tint`（绿）、`.card.warn`（黄）、`.banner`（黄）三种并存，语义不清。

### 1.5 习惯与状态缺口

- 底部 Tab 图标非通用符号；无选中指示条。
- 解绑四条后果是纯 `<ol>` 文字，最关键的「儿童模式关闭、孩子不再受管控」没有视觉强调，用户易划过后直接点确认。
- 保存冲突三选一三个同权重小按钮并排，「以我的版本覆盖」这一破坏性动作与「放弃」同级，无默认安全项。
- 保存按钮藏在滚动内容末尾；分配开关点击即写却无任何「已保存 / 保存中」反馈。
- 只有 Toast 一种反馈，无加载骨架、无错误态、无离线态；`state.saving` 有布尔量但无 UI 表现。
- 无浏览器后退（`popstate`）处理；`render()` 全量重建 `innerHTML`。

---

## 2. Design Foundations

### 2.1 色彩系统

设计原则：**中性色承载信息，品牌色承载动作与选中，语义色只在真正需要警示时出现**。所有文字组合按 WCAG AA ≥ 4.5:1 反推，UI 组件边界 ≥ 3:1。

**浅色（默认）**

| Token | 值 | 用途 | 对比度（对白/底） |
| --- | --- | --- | --- |
| `--bg` | `#F5F8F6` | 页面画布 | — |
| `--surface` | `#FFFFFF` | 卡片 / 弹层 / Tab Bar | — |
| `--surface-2` | `#EDF3EF` | 次级填充 / 骨架 | — |
| `--ink` | `#16211D` | 主文字 | 16.54:1 |
| `--ink-2` | `#4A5A53` | 次要文字 | 7.30:1 |
| `--ink-3` | `#5B6B63` | 辅助文字 / 标签（≥12px） | 5.63:1 |
| `--line` | `#DCE5E0` | 分隔线 | — |
| `--line-strong` | `#B9C9C0` | 输入 / 控件边界 | 1.86:1（仅作边界，非文字） |
| `--brand` | `#0F7A5F` | 主按钮 / 选中 / 图标 | 5.29:1（白字 5.29:1） |
| `--brand-strong` | `#0B6249` | 强调文字 / 按下态 | 7.35:1 |
| `--brand-soft` | `#E8F5EF` | 浅色填充 | brand-strong 6.56:1 |
| `--brand-on` | `#FFFFFF` | 主按钮文字 | — |
| `--warn` | `#8A5200` | 警示文字 | 5.81:1（on `--warn-soft`） |
| `--warn-soft` | `#FFF3DC` | 警示底 | — |
| `--danger` | `#B3261E` | 危险文字 / 按钮 | 5.76:1（on `--danger-soft`） |
| `--danger-soft` | `#FDEDEC` | 危险底 | — |
| `--info` | `#1B5E8A` | 信息文字 | 6.08:1（on `--info-soft`） |
| `--info-soft` | `#E7F1F8` | 信息底 | — |

**深色 `data-theme="dark"`**

| Token | 值 | 对比度 |
| --- | --- | --- |
| `--bg` / `--surface` / `--surface-2` | `#0F1714` / `#17231E` / `#1E2E27` | — |
| `--ink` / `--ink-2` / `--ink-3` | `#EAF2EE` / `#A9BDB4` / `#8EA39A` | 15.99:1 / 8.20:1 / ≥6:1 |
| `--line` / `--line-strong` | `#2C3B34` / `#40564B` | — |
| `--brand` / `--brand-soft` / `--brand-on` | `#5FD3A6` / `#17382C` / `#06251B` | 8.76:1（on surface） |
| `--warn` / `--danger` / `--info` | `#F0B866` / `#FF9E94` / `#8CC7EC` | ≥5:1（on 对应深底） |

> 深色模式不是把浅色取反：品牌绿提亮以维持 8.76:1，危险色改为低饱和亮红避免刺眼。原型右上角可实时切换。

### 2.2 排版系统（1.25 比例，基于 16px）

| 级别 | 字号 / 行高 | 字重 | 用途 |
| --- | --- | --- | --- |
| `display` | 32 / 40 | 700 | 关键数据（剩余分钟） |
| `h1` | 26 / 34 | 700 | 页面大标题（「早上好，爸爸」） |
| `h2` | 22 / 30 | 650 | 弹层标题 / 区块主标题 |
| `h3` | 18 / 26 | 650 | 卡片主标题 / 姓名 |
| `body-lg` | 16 / 24 | 400 | 正文重点 |
| `body` | 14 / 22 | 400 | 正文（**最小正文**） |
| `label` | 13 / 18 | 500 | 表单标签 / 区块标题 |
| `caption` | 12 / 16 | 500 | 仅辅助标签，不承载关键信息 |

- 字体栈：`-apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif`；数字启用 `font-variant-numeric: tabular-nums` 保证时长不跳动。
- **删除 v3 的 10px `.tiny`**：所有辅助信息最低 12px 且用 `--ink-3`（5.63:1）。
- Flutter 映射：逻辑像素 dp，跟随系统字体缩放（`MediaQuery.textScaler`），布局用弹性高度而非固定 px，保证 200% 缩放下不截断。

### 2.3 间距系统（4pt base / 8pt rhythm）

`--s1:4` `--s2:8` `--s3:12` `--s4:16` `--s5:20` `--s6:24` `--s8:32` `--s10:40` `--s12:48` `--s16:64`

| 场景 | 值 |
| --- | --- |
| 页面水平边距 | 20 |
| 卡片内边距 | 16 |
| 卡片间距 | 12 |
| 区块（Section）上间距 | 24 |
| 弹层内边距 | 20（底部含安全区） |
| 图标与文字间距 | 8 |

### 2.4 形状、高度与动效

| Token | 值 | 用途 |
| --- | --- | --- |
| `--r-sm` / `--r-md` / `--r-lg` / `--r-xl` / `--r-pill` | 8 / 12 / 16 / 20 / 999 | 按钮输入 / 卡片 / 大卡 / 底部弹层 / chip 头像 |
| `--e1` / `--e2` / `--e3` | `0 1px 2px` / `0 4px 12px` / `0 12px 32px` rgba(16,40,30,.06/.08/.14) | 卡片 / 浮起 / 弹层 |
| `--m-fast` / `--m-base` / `--m-slow` | 150 / 240 / 400 ms | 状态 / 页面 / 弹层 |
| `--ease` | `cubic-bezier(.2,.8,.2,1)` | 统一缓动 |
| z-index | 10 sticky / 20 tabbar / 30 scrim / 40 sheet / 50 toast | 层级 |

`@media (prefers-reduced-motion: reduce)` 下所有 transition / animation 归零。

---

## 3. 组件库规格

所有交互组件最小命中区 **44×44**；焦点样式统一 `outline: 2px solid var(--brand); outline-offset: 2px`（`:focus-visible`）。

| 组件 | 变体 | 尺寸 / 状态 | ARIA |
| --- | --- | --- | --- |
| **Button** | primary / secondary(outline) / tonal / danger / text | 高 48（主）或 44；default · hover · active · **focus-visible** · disabled(opacity .5 + `cursor:not-allowed`) · loading(spinner + 文案) | `<button>` 原生；图标按钮需 `aria-label` |
| **Input** | 文本 / 数字 / 密码 / 选择 | 高 44，标签 13px，focus ring 2px，error 态红边 + 说明 | `label[for]` + `aria-describedby` + `aria-invalid` |
| **Card** | default / hero(品牌底) / outlined / info / warning / danger | 圆角 12，padding 16，e1；可点击态有 hover 与 focus | 可点击时用 `<button class=card>` 或 `role="button"` |
| **Chip** | neutral / brand / warn / danger / info | 高 24，圆角 pill，12px；**纯展示，不可点** | 无需 ARIA，文字须自解释 |
| **Switch** | on / off / disabled | 视觉 44×26，命中区 44×44 | `role="switch"` + `aria-checked` + `aria-label` |
| **Progress** | 线性 / 环形 | 高 8，圆角 pill | `role="progressbar"` + `aria-valuenow/min/max` + `aria-label` |
| **Avatar** |  initials / 图片 | 48px，色相按 childId 轮换，色字对比 ≥4.5 | `aria-hidden`，姓名在相邻文本 |
| **List row** | leading icon / trailing value / chevron | 高 ≥56，分隔线 1px | 可点击行为 `<button>` |
| **Tab bar** | SVG 图标 + 文字 | 高 64 + 安全区；选中：品牌色 + 顶部 3px 指示条 | `role="tablist"` / `aria-selected` / `aria-current` |
| **Bottom sheet** | 标准 / 危险确认 | 圆角 20，最大高 88%，把手 + 标题 + 内容 + sticky 操作区 | `role="dialog"` `aria-modal="true"` + 焦点陷阱 + Esc + 关闭回焦 |
| **Toast** | success / error / info | 底部，4s，`aria-live` | `role="status"` `aria-live="polite"` |
| **Empty / Skeleton / Error / Offline** | 统一插画位 + 标题 + 说明 + 主 CTA | 空态 CTA 高 48 | 空态 `aria-live="polite"`；骨架 `aria-busy` |

**图标**：全部内联 SVG（24×24 viewBox，`stroke=currentColor`，`stroke-width=1.8`，round cap/join），`aria-hidden="true"`，语义由相邻文字提供。删除 v3 的 `⌂ ♙ ▣ ‹ × › ↻` Unicode 图标。

---

## 4. 页面重设计规格

> 信息架构与产品语义沿用 v3；以下只描述**视觉层级、信息取舍与交互习惯**。

| 页面 | 重设计要点 |
| --- | --- |
| **账号恢复** | 主标题 26px「欢迎回来」；三条路径改为带 SVG 图标的选择卡；**「登录已有家长号」为主推**（符合重装用户预期），「创建新家长号」次之，「暂时使用本机账号」降为文字按钮；底部说明用 12px `--ink-3` |
| **今天** | 新增 26px 问候标题 + 日期；**Hero 卡**（品牌底）展示家庭概览；「待处理解锁请求」独立高优先级卡（警示边 + 48px 主按钮 + 倒计时）；孩子卡以 **32px 大号剩余分钟数** 为主视觉 + 进度条；说明性文案全部移入原型规格栏 |
| **孩子** | 家庭档案列表，48px 头像 + 18px 姓名 + 紧凑元数据行；「＋ 添加」为右上角 44×44 图标按钮（带 `aria-label`）；顶部取消说明卡 |
| **孩子详情** | 分组 Section（基本信息 / 规则 / 分配到电视 / 题库），Section 标题 13px 500；输入框 44px；开关带 `role=switch`；**规则区只放家庭级配额规则**（限额 / 禁看时段 / 白名单），CR-02 后不再放「解锁方式」，改为一行 12px 说明 + 「去电视设置」文字按钮；**底部固定操作栏**位于内容区与 Tab bar 之间（`flex:0 0 auto`，不用 sticky 以免遮挡滚动内容）；删除档案为独立 danger 区 |
| **题库与分享** | 「本地题库 / 引用副本」两态用分段控件区分；授权名单用 chip 行；「引用别人分享的题库」为虚线空态卡 + 主 CTA；跨家庭口径说明移入规格栏 |
| **电视** | 设备卡带在线状态点（绿 / 灰 + 文字，不靠颜色单独表意）、已分配档案数；主 CTA 明确 |
| **电视设置** | Section 标题右侧加「按台独立」chip；儿童模式开关 + **本台解锁方式行**（当前值 + 「仅本台生效」+ 44px「设置」按钮，不再是只读 chip）+ 分配勾选；**解绑放页面最底部独立 danger 区**，与「删除档案」文案明确区分；解绑不得改变家庭题库授权或已导入副本 |
| **账号与设置** | 低频项归入头像入口；身份 / 连接状态用 chip；深色主题开关放在原型工具栏（产品内对应「外观」设置） |

**弹层重设计**

| 弹层 | 关键改动 |
| --- | --- |
| 解绑确认 | 四条后果改为带图标 checklist；「儿童模式关闭、孩子不再受管控」用 danger 高亮块；明确家庭档案、题库授权、已导入副本和当日累计均保留；**「取消」为默认焦点且视觉更强**，确认解绑为 danger 实心按钮 |
| 保存冲突 | 三选一改纵向列表：**「查看差异」为默认安全项**（主按钮），「放弃本次修改」为次要，「以我的版本覆盖」标注危险并置底 |
| 删除档案 | 后果清单 + 不可恢复提示，独立于解绑 |
| 引用题库 | 选择来源 + 选择复制到哪个孩子（Q2），副本说明用 info 卡 |
| 本台解锁方式（CR-02） | 标题带电视名，说明「只对这台生效」；四种方式用选择卡 + 选中 chip（不靠颜色单独表意）；选 PIN 时展开 44px 本台 PIN 输入；答题解锁题库来源与空题库降级用 info 卡；主按钮「保存本台设置」为默认焦点，admin 只读态禁用 |
| 分享设置 / 登录 / 差异 / 草稿 | 统一 sheet 结构：把手 → 标题 → 说明 → 内容 → sticky 操作区 |

**状态与反馈**：保存中按钮锁定并显示 spinner；成功 / 失败 toast 带 `aria-live`；分配开关写入后给「已保存」反馈；加载用骨架；离线设备卡显示灰点 + 文字「离线」而非仅颜色。

---

## 5. 无障碍验收清单（WCAG 2.1 AA）

- [ ] 所有文字组合 ≥ 4.5:1（大文字 ≥ 3:1）；深色模式同样校验
- [ ] UI 组件边界、焦点指示 ≥ 3:1
- [ ] 全功能键盘可达：Tab 顺序合理、`:focus-visible` 清晰、无键盘陷阱（弹层内有焦点陷阱且 Esc 可退出）
- [ ] 所有交互元素使用原生 `<button>` / `<input>`，或补 `role` + `tabindex` + `aria-*`
- [ ] 状态不单靠颜色表达（在线 = 圆点 + 文字；错误 = 图标 + 文字）
- [ ] 图标 `aria-hidden`，按钮有可访问名称
- [ ] 弹层 `role="dialog" aria-modal="true"`，关闭后焦点回到触发元素
- [ ] Toast `role="status" aria-live="polite"`
- [ ] 触控目标 ≥ 44×44
- [ ] `prefers-reduced-motion` 生效
- [ ] 200% 文字缩放不截断、不重叠
- [ ] 表单有 `label[for]`、错误说明 `aria-describedby`、`aria-invalid`

---

## 6. 响应式与安全区

| 断点 | 行为 |
| --- | --- |
| < 680px | 原型展示台收起左右栏，手机视图占满宽度 |
| 680–1040px | 隐藏右侧规格栏，保留左导航 + 手机 |
| ≥ 1040px | 三栏：导航 / 手机 / 规格 |

产品侧为 mobile-first：`.device` 内容区滚动、Tab Bar 与 sticky 操作区使用 `padding-bottom: env(safe-area-inset-bottom)`，顶部状态栏使用 `env(safe-area-inset-top)`；不写死 `height:740px` 作为真实布局约束。

---

## 7. 开发者交付（Handoff）

**Flutter 映射建议**

| Web token | Flutter |
| --- | --- |
| 色彩 tokens | `ThemeData.colorScheme` + `Extension<AppColors>`，深浅各一套 |
| type scale | `TextTheme` 显式定义，字号走 `textScaler` 可缩放 |
| 间距 | `EdgeInsets` 常量类 `AppSpacing`，禁止裸数字 |
| 圆角 / 阴影 / 动效 | `AppRadius` / `AppElevation` / `AppMotion` 常量 |
| 组件 | 抽 `PKButton` / `PKCard` / `PKSwitch` / `PKSheet` / `PKToast`，统一 `Semantics` |
| 图标 | 用 `Icon` + 矢量资源，不使用字符图标 |

**验收方式**

1. 原型与本文逐条对照，视觉走查按组件而非按页面。
2. Flutter 实现后按第 5 节清单逐项打勾；对比度用脚本复算，不靠肉眼。
3. 保留 v3 语义基线不变：家庭主档案 / 分配 / 题库副本 / 解绑四条 / 冲突三选一 / admin 只读代管。
4. 按项目规则：复杂交互变更前先同步原型；本次 v4 即为同步产物，评审通过后再动 Flutter。

**Design QA 顺序**：token → 组件 → 页面 → 状态（加载 / 空 / 错误 / 离线）→ 深浅主题 → 无障碍 → 200% 缩放 → 真实设备。

---

## 8. 变更边界

- 不改 Tab 结构与页面归属；不新增 / 删除产品功能；不改 S1–S6、CR-01、D-01/D-02/D-03 结论。
- 不删除 v1 / v2 / v3 原型；v4 为并列新增的视觉稿。
- 服务端、家长端、电视端契约切换仍按 `parent-app-v2-implementation-plan.md` 执行，本文不涉及。
- 涉及儿童姓名、头像、观看记录的展示与留存，界面文案需结合公司法务 / 合规意见确认。

> 本方案为产品设计参考，具体实施请结合公司合规与法务要求确认。
