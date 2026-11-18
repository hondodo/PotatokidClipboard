# TV 端（potatokid_screen）触屏交互完整方案

> **文档版本**：v1.3 ｜ **日期**：2026-11-18 ｜ **状态**：P0/P1 已实现（代码落地完成，待真机调校与打包装机）
> **目标一句话**：在不改动遥控链路、不影响遥控任何功能的前提下，补齐 TV 端触屏对「选台、设置等核心功能」的完整支持。
>
> **v1.1 变更（2026-11-17 14:03 用户拍板）**：① 上下滑方向定为「上滑=上一台、下滑=下一台」（沿用遥控语义）；② 呼出频道列表定为「长按」（防误触）；③ 设置页整行触屏改造纳入本期（完整改造：步进行/开关行/动作行全覆盖）；④ 不增加任何常驻可点按钮，直播页保持纯手势；⑤ 明确「设置-遥控」开关定位（见下方边界澄清），它属于遥控调试能力，与触屏方案无关、保持原样。
>
> **v1.2 变更（2026-11-17 14:30 代码落地）**：P0/P1 已实现，见「十、实施落地记录」。新增 `touch_gesture_layer.dart`（纯 pointer 手势层）+ 9 项单元测试全通过；`live_player_widget.dart` 接入手势层与双门控；`profile_page.dart` 完成设置页三类行整行触屏改造。**全量 `flutter analyze` No issues；未改动任何遥控分发代码。**
>
> **v1.3 变更（2026-11-18 17:32 用户拍板）：关闭四向滑动换台/换源。** 触屏下滑是查看系统栏的系统手势，接了换台回调会在下拉系统栏时误切频道，严重影响使用。`live_player_widget.dart` 直播间接线处四个 `onSwipe*` 回调统一改为 `_touchNoop`；`TouchGestureLayer` 组件本身保留滑动识别能力（识别为 swipe 后不动作、也不误触发单击 OSD），宿主不再绑定业务动作。**单击 OSD、长按呼出频道列表、全部遥控链路均不受影响。** 下方正文描述的滑动手势（第 135/136/148/149 行等）为历史方案记录，v1.3 起在直播页不再生效；遥控上/下切台、左/右切源保持原样。
> **适用端**：`pscreen/potatokid_screen`（TV 端）。**不涉及** `pscreen_home`（home 端）、`pscreen_server`、ESP 固件。
> **关键词**：双输入共存、平行输入适配、逻辑焦点同步、遥控零影响。

---

## 一、背景、问题与目标

### 1.1 背景

TV 端设备带触屏，但当前软件是按**「遥控单输入」范式**设计的：几乎所有交互都汇聚到 `MainApp._handleLogical`（`main_app.dart:258`），由根焦点节点的 `onKeyEvent` 分发方向键/OK/返回。触屏只是零散存在于个别 widget 的 `onTap`，没有形成一套完整、可用的触屏交互。结果是用户在触屏上「选台等功能都不能用」。

> **重要边界澄清（避免混淆）**：现有「设置 → 悬浮遥控 / 遥控」开关（`showFloatingRemote`，`profile_page.dart:317-320`）**只是 Windows 无遥控时用来模拟遥控的调试功能，不是触屏功能**。它在本方案中保持原样、不改动、也不作为触屏能力的一部分。本方案所说的"触屏"，指的是用户用手指直接触摸屏幕完成的交互，与该模拟遥控开关是两回事。二者共用同一套控制器 API，互不冲突。

### 1.2 问题陈述（三类根因，均有代码级证据）

| 编号 | 根因 | 代码锚点 | 用户可感知的现象 |
|---|---|---|---|
| C-1 | **无手势入口**：全屏视频区是 `Video(controls: NoVideoControls)`，没有任何点击/滑动手势 | `live_player_widget.dart:1122-1131` | 触屏点/划画面毫无反应，无法切台、切源、呼出频道列表 |
| C-2 | **交互层门控**：频道项虽有 `InkWell.onTap`，但被 `IgnorePointer(ignoring: !interactive)` 挡住；只有进入 `channelList` 层才可点，而"进入"这一步只有遥控 OK 能做 | `live_player_widget.dart:1172-1179`、`app_state.dart:56`、`channel_bar.dart:295` | 触屏用户打不开频道列表，或打开后点选无效 |
| C-3 | **点击只聚焦不执行**：设置页绝大多数整行 `onTap` 只调 `c.select(row)`（移动自研焦点），改值必须点 `<`/`>` 小图标或按遥控左右键 | `profile_page.dart:1107-1110` 及各 `_build*Row` | 触屏"点了没变化"，以为功能坏了 |

> 辅助问题：`DirectionWidget`（画面上的上/下切台、左/右切源提示图标）是纯视觉控件，无任何手势，点了没反应（`direction_widget.dart` 全文件）；`_LiveUpdateIndicator`、数字回显等纯展示层明确 `IgnorePointer`，符合预期，无需改。

### 1.3 目标与成功指标

**产品目标**：触屏用户能独立完成"选台/切源/呼出频道列表/设置调整/Tab 切换"等核心任务，路径不依赖遥控器。

**成功指标（建议口径，数值待真机验证后定稿）**：

| 指标 | 定义 | 目标 | 口径来源 |
|---|---|---|---|
| 触屏选台可达性 | 仅用触屏、≤3 次操作内成功切换频道 | 100% 核心频道可切换 | 建议，待定稿 |
| 遥控回归通过率 | 既有遥控用例（切台/切源/OK/返回/锁屏吞键/Tab）全通过 | 100%（零回归） | 硬约束 |
| 触屏误触率 | 正常观看中无意图的滑动导致的误切台 | 待真机采集后设阈值 | 建议，需实测 |
| 手势识别成功率 | 有效手势被正确识别（滑动方向/点击/长按） | 待真机调校后定 | 建议，需实测 |

> 说明：以上百分比是本方案建议口径，**非实测数据**；阈值类数值（手势距离/时长/节流）均为**建议初值，须真机调校**。

### 1.4 硬约束（不可协商）

1. **遥控零影响**：不修改 `MainApp._handleLogical`、`_handleRootKey`、`_pressOk`、`RemoteKeyDispatcher`、任何现有 widget 的 `onKeyEvent`。
2. **不引入输入模式互斥**：不做"触屏模式/遥控模式"切换开关，避免状态漂移与误判（见 2.5）。
3. **覆盖层优先级不变**：锁屏、家长选人/答题、确认弹窗、消息浮层的吞键/吞触摸行为保持原样。
4. **悬浮遥控层级不变**：`FloatingRemote` 仍绘制在 Navigator/DialogRoute 之上（`app.dart:106-108`，有测试保护）。

---

## 二、核心设计原则（方案的地基）

### 2.1 原则一：平行输入适配器，绝不改遥控链路

把触屏实现为**与遥控并列的第二条输入通道**，它调用的是与遥控**完全相同的业务控制器方法**：

```
遥控按键 → _handleLogical → LiveChannelController.next()/select() ...  ┐
                                                                        ├→ 同一状态真值源 → UI
触屏手势 → TouchGestureLayer → LiveChannelController.next()/select() ...┘
```

`LiveChannelController.next()/previous()/select()`、`HomeNowPlayingController.switchSource()`、`showChannelPanel()`（`packages/pscreen_screen/lib/features/iptv/application/`）都是现成的单例 API，遥控链路已经在用。触屏直接调用它们，天然共享同一状态、同一节流（如切台 400ms `commitDelay`）、同一记忆逻辑，**不可能与遥控产生两套状态**。

### 2.2 原则二：单一真值源 + 触屏主动同步逻辑焦点

TV 端的"焦点"是**逻辑焦点**（自研索引 `ProfileFocusController` / `HomeRemoteLayer` / 胶囊二维索引 + Flutter `FocusNode`），它与视觉高亮、OK 动作目标绑定。触屏点击若不先同步焦点，会造成"高亮/焦点/动作目标"三者错位，遥控用户随后接管就会跳错位置。

**落地规则**：任何触屏"聚焦型"动作，必须先调用对应焦点控制器的 `select(...)` 同步焦点，再执行业务动作。项目已有成熟范本——选人页卡片 `onTapDown` 里 `setState(_cursor = index)`（`parental_select_overlay.dart:384-391`）、`ProfileFocusController.select(row)`（`profile_focus_controller.dart:63-67` 注释明确"点击/触摸用"）。

### 2.3 原则三：覆盖层优先，手势层可被禁用

新增的触屏手势层必须带 `enabled` 开关，由"当前是否有更高优先级覆盖层"控制。覆盖层（锁屏/家长/弹窗/消息）显示时或频道列表交互态时，手势层自动失效，把触摸让给覆盖层/列表，避免穿透误操作。

### 2.4 原则四：手势只吃 pointer，不碰 KeyEvent 链

已确认：根 `Focus(onKeyEvent)`（`main_app.dart:579-583`）**只处理键盘/遥控 KeyEvent，不触达 pointer**。因此新增 `GestureDetector` 不会破坏遥控按键分发；反之遥控也不依赖 widget 的 `onTap`（OK 例外，走 `ActivateIntent`），新增手势不会改变遥控语义。这是"零影响"的技术保证。

### 2.5 原则五：无状态共存（不做输入模式检测）

**决策**：不引入 `inputMode`/`isTouch`/`lastInput` 之类的状态，不做"上次用了遥控就屏蔽触屏"这类互斥逻辑。理由：
- 当前无任何输入检测基建，新增会扩大改动面与回归风险；
- 互斥判断本身易误判（如用户手摸了一下屏幕又拿遥控），反而制造 bug；
- "两者随时都能操作 + 共享同一焦点真值源"已足够保证一致性。

> 该决策为**关键产品假设**，评审可被推翻；若推翻，需评估其对改动面与遥控回归的影响。

---

## 三、方案总体设计

### 3.1 分层触屏映射总览

| 层 | 区域 | 触屏设计 | 对应遥控 | 改动性质 |
|---|---|---|---|---|
| L1 直播手势层 | 全屏视频区 | 新增透明手势层：点击/上下滑/左右滑/长按 | OK / 上下键 / 左右键 / OK 进列表 | **新增** |
| L2 频道列表 | 频道列表面板 | 复用现有 `InkWell.onTap`；新增触屏进入入口 | 列表点选 | **修复门控 + 加入口** |
| L3 设置页 | 「我的」设置行 | 整行 `onTap` 升级为"聚焦 + 执行等价动作" | 左右键改值 / OK 执行 | **补齐语义** |
| L4 Tab 与覆盖层 | 胶囊 Tab、悬浮遥控、锁屏、家长层 | 保持现状（已可用） | — | **不改**（仅回归保护） |

### 3.2 整体交互链路

```
                       ┌─────────────────────────────────────────┐
                       │        业务控制器（唯一真值源）           │
                       │ LiveChannelController / NowPlaying / ... │
                       └───────▲──────────────────────▲──────────┘
                               │ 同一套 API            │
  遥控 KeyEvent ──► root Focus ─┘                      └── 触屏手势层 ──► 先同步逻辑焦点
        │                                                              （select(row)/_cursor）
        └─► _handleLogical（原样不动）                                        ▲
                                                                             │
                              覆盖层状态 / showChannels ──► enabled 门控 ─────┘
```

---

## 四、功能需求清单（FR）

> 状态词约定：**必须**（must）/ **应该**（should）/ **可以**（may）/ **禁止**（must not）。
> 每条需求均给出 Given/When/Then 验收标准，可直接转为测试用例。

### FR-01 全屏直播触屏手势（P0，核心）

在直播全屏视频层之上叠加透明手势层，`HitTestBehavior.translucent`（不阻断下层命中），支持四种手势：

| 手势 | 映射动作 | 对应遥控 | 优先级 |
|---|---|---|---|
| 单击画面 | 切换 频道信息 OSD（fullscreen ↔ channelInfo） | OK 呼出信息 | 1 |
| 垂直滑动 | **上滑 `previous()`（上一台）/ 下滑 `next()`（下一台）**（已定稿，沿用遥控"上=上一条"语义） | 上/下键切台 | 2 |
| 水平滑动 | 左滑 / 右滑 `switchSource(±1)`（方向真机调校） | 左/右键切源 | 2 |
| **长按（建议 500ms）** | 呼出频道列表 `showChannelPanel()`（**已定稿：长按，防误触；不采用双击**） | OK 进入 channelList | 3 |

**业务规则**：
- 手势层 `enabled` 条件：直播页在前台 && 无更高优先级覆盖层（锁屏/家长/弹窗/消息未显示）&& `showChannels == false`。
- 方向判定：以主导轴为准，建议 `|dy| >= |dx| * 1.4` 判为垂直滑动，否则水平。
- 点击 vs 滑动：位移超过 `touchSlop`（建议 24 逻辑 dp）判为滑动，否则判为点击。
- 节流：连续滑动切台需节流（建议 ≥250ms），与 `commitDelay=400ms` 配合，防止一滑切多台。
- 必须复用 `LiveChannelController.next()/previous()` 与 `HomeNowPlayingController.switchSource()`，**禁止**自行维护频道索引。

**验收标准**：
- Given 直播全屏、无覆盖层；When 用户单击画面；Then 频道信息 OSD 显示/收起，且不切台。
- Given 直播全屏；When 用户上滑；Then 切到上一个频道（previous）；When 用户下滑；Then 切到下一个频道（next），频道名 Toast 与画面同步，播放源随之切换。
- Given 直播全屏；When 用户水平滑动；Then 视频源切换一次，频道不变。
- Given 直播全屏；When 用户长按画面；Then 频道列表面板展开并进入交互态。
- Given 锁屏/家长层/确认弹窗显示中；When 用户在原画面区域滑动；Then 手势层不响应，覆盖层行为不受影响。

### FR-02 频道列表触屏点选与进入（P0）

- **必须**保证触屏用户有进入 `channelList` 交互态的入口（由 FR-01 长按提供；不加常驻可点按钮，已定稿）。
- **必须**保证进入交互态后，频道项 `InkWell.onTap → _activateChannelFromPanel → select(index) + hideChannelPanel()` 可用（`live_player_widget.dart:623-626` 已实现，仅需确保不再被 `IgnorePointer` 误挡）。
- 点选后**必须**同步逻辑焦点至被选频道，保证遥控随后接管时高亮接续。
- 列表交互态下，L1 手势层**必须**禁用（`enabled=false`），避免手势与点选冲突。
- 全屏预览态（`_listPeek`，`live_player_widget.dart:1172-1178`）**保持**不可交互，符合现状设计。

**验收标准**：
- Given 全屏；When 长按呼出列表；Then 列表展开、当前频道高亮居中（`_scrollToSelected` 已实现）。
- Given 列表交互态；When 点击任一频道项；Then 切换到该频道、列表收起、焦点同步到该项。
- Given 列表交互态；When 在列表区域滑动；Then 不触发 L1 切台手势（列表自身滚动优先）。

### FR-03 设置页整行触屏执行（P1，本期确定做完整改造）

> **已定稿**：设置页整行触屏改造**纳入本期、完整改造**，覆盖下列全部三类行（不是降级版、不延后）。
> 注意：这里改造的是"真机触屏手指点击设置行"，与「设置 → 悬浮遥控」这个 Windows 模拟遥控调试开关无关；那个开关保持原样。

设置页 `_SettingRow` 的 `onTap` 从"仅聚焦"升级为"聚焦 + 执行与遥控等价的动作"，分三类处理：

| 行类型 | 现状 | 目标触屏行为 | 复用回调 |
|---|---|---|---|
| 步进型（主题/语言/画质等） | 点击只 `select` | 点击直接 stepping 到下一选项（或弹出选项供选） | `onStepRight` |
| 动作型（刷新/重置/复制/远程/版本） | 点击只 `select` | 点击直接执行动作 | `onActivateRow` / 对应动作方法 |
| 开关型（悬浮遥控/硬解/后台播放等） | 点击只 `select` | 点击直接切换开关值 | `onStepRight`（等价于翻转） |

**业务规则**：
- **禁止**改动遥控的 `step()`/`activate()` 逻辑与 `_onActivateRow`（`profile_page.dart:225-232`）的现有行为。
- 触屏点击**必须**先 `c.select(row)` 同步焦点，再执行等价动作，使高亮与动作一致。
- 步进型行选项 >2 时**必须**提供轻量选项面板（完整改造口径），避免"点一下跳一格"需要多次点击；单击步进仅作为选项面板内的快捷补充，不作为整行唯一行为。

**验收标准**：
- Given 设置页；When 点击"主题"整行；Then 焦点落到该行并弹出选项面板，选中某项后值切换到位。
- Given 设置页；When 点击"刷新频道"整行；Then 焦点落到该行且触发刷新（与遥控 OK 行为一致）。
- Given 设置页；When 用遥控左右键/OK 操作同一行；Then 行为与改造前完全一致（零回归）。

### FR-04 Tab 切换触屏（P1，确认保持）

- 胶囊 Tab 的 `InkWell(onTap: onActivate)`（`update_pill.dart:559-561`）已支持触屏，**保持不改**。
- 需补充：触屏用户进入胶囊 Mask 的入口——由 L1 单击/长按手势触发 `showCapsule()`（等价于遥控 OK 呼出）。
- **已定稿：不增加任何常驻可点按钮**（画面上不放"菜单/频道列表"图标按钮），直播页保持纯手势交互，视觉与现状一致。

**验收标准**：
- Given 胶囊 Mask 展开；When 触屏点击任一 Tab 胶囊；Then 切换到对应 Tab，行为与遥控 OK 一致。
- Given 直播全屏；When 触屏触发菜单入口；Then 胶囊 Mask 展开。

### FR-05 焦点同步机制（P1，横切关注点）

- 所有触屏"聚焦型"动作**必须**先同步逻辑焦点：`ProfileFocusController.select(row)`、`ParentalSelectOverlay._cursor`、`CapsuleControlsController` 当前行列等。
- 采用与选人页 `onTapDown` 同步 `_cursor` 相同的成熟模式，禁止新增第二套焦点状态。

**验收标准**：
- Given 用户用触屏选中设置页某行；When 立即用遥控按 OK/左右键；Then 动作作用于触屏刚选中的同一行，无跳位。

### FR-06 覆盖层与互斥处理（P0，横切关注点）

- 锁屏/家长选人/家长答题/确认弹窗/消息浮层显示期间，L1 手势层**必须**失效（`enabled=false`）。
- 手势层禁用不得影响这些覆盖层自身的触屏能力（锁屏按钮、选人卡片、答题选项均已可点，保持）。
- 悬浮遥控层级保持最上，其覆盖区域的触摸仍由悬浮遥控接管。

**验收标准**：
- Given 家长锁屏；When 触摸原画面区域；Then 手势层不响应，锁屏验证流程不受影响。
- Given 悬浮遥控开启；When 点击悬浮遥控按键；Then 按键正常触发（与 `floating_remote_layer_test` 断言一致）。

---

## 五、关键交互设计详述（直播选台为核心）

### 5.1 直播全屏手势分区（线框思路）

```
┌───────────────────────────────────────────────┐
│  左上角：频道名/台标 OSD（展示，可随单击显隐） │
│                                               │
│              ┌─────────────┐                  │
│              │             │                  │
│   ← 左滑     │   视频画面   │   右滑 →        │  ← 左右滑切源
│              │  （手势层）  │                  │
│              └─────────────┘                  │
│   ↑ 上滑切台 / ↓ 下滑切台                      │
│   长按 → 呼出频道列表                          │
│                                               │
│  底部：方向提示图标（DirectionWidget，纯展示） │
└───────────────────────────────────────────────┘
```

### 5.2 用户故事与场景

**US-1（核心）**：作为 TV 观众，我想在触屏上直接滑动切换频道，以便不拿遥控器也能换台。
- Given 正在看直播；When 我向下滑动画面；Then 切到下一个频道并看到频道名提示。

**US-2**：作为 TV 观众，我想触屏呼出频道列表并点选，以便快速跳到想看的台。
- Given 正在看直播；When 我长按画面；Then 频道列表展开；When 我点某频道；Then 立即切到该台并收起列表。

**US-3**：作为 TV 观众，我想触屏调整设置，以便在遥控器没电时仍能改选项。
- Given 我在「我的」页；When 我点设置项整行；Then 该项被选中且值发生等价改变。

**US-4（回归）**：作为习惯遥控的用户，我希望新增触屏后遥控一切照旧。
- Given 触屏功能已开启；When 我用遥控上下键/OK/返回/锁屏；Then 行为与新增触屏前完全一致。

### 5.3 手势冲突消解策略

| 冲突场景 | 处理 |
|---|---|
| 滑动过程中触发点击 | 位移 > touchSlop 即取消点击判定 |
| 斜向滑动 | 按主导轴判定为垂直/水平之一，不同时触发两种动作 |
| 连续快速滑动 | 节流窗口内只响应一次切台/切源 |
| 列表态滑动 | L1 手势层 disabled，列表滚动优先 |
| 覆盖层出现瞬间的触摸 | enabled 状态由覆盖层可见性驱动，覆盖层出现即禁用手势层 |
| 触屏与遥控同时输入 | 共享同一控制器与焦点真值源，后到者覆盖前者，无状态互斥 |

---

## 六、遥控零影响保障

### 6.1 不改清单（红线）

以下文件/逻辑**禁止修改**，是遥控行为的骨架：
- `main_app.dart`：`_handleRootKey`、`_handleLogical`、`_handleHomeOk`、`_handleHomeArrow`、`_pressOk`、`_onRemoteButton`、`rootOkHandler`。
- `remote_key_dispatcher.dart`、`tv_navigator.dart`、`floating_remote.dart`（除必要的层级保持外不改）。
- 所有 `onKeyEvent` / `Shortcuts` / `Actions(ActivateIntent)` 实现。
- `app.dart` 中 FloatingRemote 挂载层级。

### 6.2 改动面（最小集）

| 端 | 文件 | 改动 |
|---|---|---|
| TV | `live_player_widget.dart`（+ 新建 `touch_gesture_layer.dart`） | 新增 L1 手势层并叠加到 Stack；L2 加入口与门控 |
| TV | `channel_bar.dart` | 点选后同步焦点（如未同步） |
| TV | `profile_page.dart` | L3 整行 onTap 升级（仅 P1） |
| 共享包 | 一般不改 | 复用现有控制器 API；若需新增 `showCapsule()` 等少量入口，保持向后兼容 |

> Flutter 改动是**编译进 APK**，部署需按项目铁律：改源码 → analyze → 构建 APK → 装机验证；**不是** pm2/静态文件热更。

### 6.3 回归测试矩阵（必须新增/保持）

| 编号 | 用例 | 保护点 | 现有覆盖 |
|---|---|---|---|
| RT-01 | 悬浮遥控在弹窗之上可见可点 | 层级不破坏 | ✅ `floating_remote_layer_test.dart` |
| RT-02 | 锁屏期间按键吞掉、不切 Tab | 覆盖层优先级 | ✅ `main_app_profile_readonly_test.dart` |
| RT-03 | 上下键切台、左右键切源、OK 进列表 | 遥控主路径 | ⚠️ 需补 |
| RT-04 | OK 激活设置行、左右键改值 | L3 零回归 | ⚠️ 需补 |
| RT-05 | 触屏手势与遥控交替操作焦点不错位 | 焦点同步 | ⚠️ 需补 |
| RT-06 | 覆盖层显示时手势层不穿透 | 互斥 | ⚠️ 需补 |
| RT-07 | 触屏选台全链路（滑动/点选/长按） | 新功能 | ⚠️ 需补 |

> ⚠️ 备注：调研发现 `main_app_profile_readonly_test.dart:120-127` 有一条"未锁时左右键切 Tab"的断言与当前实现不一致（全仓 `goBranch` 仅在 `_goTab` 与 `TvNavigator`）。**建议评审前先跑一次该测试确认实际状态**，避免带着历史遗留问题做方案。

---

## 七、异常处理清单

| 场景 | 处理 |
|---|---|
| 频道列表为空/未加载 | 滑动切台无动作并给轻提示；不崩溃 |
| 播放中切台失败 | 复用现有重试/看门狗（`live_player_widget.dart:204-223`），触屏与遥控一致 |
| 快速连点/长按冲突 | 节流 + 手势竞技（GestureArena）交由 Flutter 处理，禁止自定义抢占 |
| 触屏坐标错位 | 统一用逻辑坐标（`details.delta` / `RenderBox.globalToLocal`），**禁止**用物理像素或硬编码屏幕坐标比较；视口见 `tv_design_viewport.dart`（基准 960×540，以代码为准） |
| 覆盖层突然弹出 | 手势层 enabled 由覆盖层可见性驱动，立即失效 |
| 触屏与悬浮遥控区域重叠 | 悬浮遥控层级更高，其区域触摸归悬浮遥控 |

---

## 八、分期实施计划（MVP 优先）

| 阶段 | 范围 | 交付价值 | 验收 |
|---|---|---|---|
| **P0（MVP）** | FR-01 全屏手势选台/切源 + FR-02 频道列表触屏 + FR-06 互斥 | 触屏"选台能用"，解决用户最痛点 | RT-01/02/03/06/07 通过；遥控零回归 |
| **P1（本期必做）** | FR-03 设置页整行触屏完整改造（三类行全覆盖）+ FR-04 Tab 入口 + FR-05 焦点同步 | 触屏覆盖设置与导航，形成完整方案 | RT-04/05 通过；全量回归 |
| **P2（体验）** | 手势引导提示（增强 DirectionWidget）、误触优化、真机阈值调校、无障碍 | 体验打磨 | 真机测试达标 |

**依赖主线**：L1 手势层（FR-01）依赖"覆盖层可见性"信号（FR-06）→ L2 入口（FR-02）→ P1 焦点同步（FR-05）→ 设置页（FR-03）。
**建议**：先做 P0 并在真机验证手势手感，再决定 P1/P2 的具体形态。

---

## 九、风险登记册

> 风险值 = 概率(1-5) × 影响(1-5)；≥15 高，8-14 中，≤7 低。

| 编号 | 风险描述 | 类别 | 概率 | 影响 | 等级 | 应对措施 |
|---|---|---|---|---|---|---|
| RK-01 | 手势层干扰遥控焦点链或 OK 激活 | 技术 | 2 | 5 | 10 中 | 只吃 pointer 不碰 KeyEvent；不改 `_handleLogical`；RT-03/04 回归 |
| RK-02 | 触屏/遥控交替导致焦点错位 | 技术 | 3 | 4 | 12 中 | 触屏动作前强制同步逻辑焦点（FR-05）；RT-05 |
| RK-03 | 覆盖层手势穿透造成误操作 | 技术 | 2 | 5 | 10 中 | enabled 门控 + 覆盖层自身 opaque；RT-06 |
| RK-04 | 手势阈值不合手，误触/识别失败 | 体验 | 3 | 3 | 9 中 | 建议初值 + 真机调校；节流；P2 打磨 |
| RK-05 | 设置页改动引入遥控回归 | 技术 | 3 | 4 | 12 中 | 只加 onTap 不改 step/activate；RT-04 |
| RK-06 | 不同触屏屏/尺寸坐标偏差 | 技术 | 2 | 3 | 6 低 | 用逻辑坐标；视口 FittedBox 逆变换已保证映射 |
| RK-07 | 工期压缩砍掉焦点同步，导致体验割裂 | 需求 | 2 | 3 | 6 低 | FR-05 列为 P1 必做；如砍需单独评审 |

---

## 十、决策记录与遗留待办

### 10.1 已拍板决策（2026-11-17，用户确认）

| 编号 | 决策点 | 结论 |
|---|---|---|
| D-1 | 上下滑方向 | 上滑 = 上一台（previous）、下滑 = 下一台（next），沿用遥控语义 |
| D-2 | 呼出频道列表手势 | 长按（不用双击，防误触） |
| D-3 | 设置页触屏改造 | 本期完整改造，步进行/开关行/动作行全覆盖 |
| D-4 | 常驻可点按钮 | 不加，直播页保持纯手势，视觉与现状一致 |
| D-5 | 「设置-遥控」开关定位 | 属 Windows 无遥控时的遥控模拟调试功能，**非触屏功能**，保持原样、不纳入本方案 |

### 10.2 遗留待办（开发前核实）

1. **RT-03 遗留测试不一致 —— 已核实为基线既存问题**：跑全量测试时 `main_app_profile_readonly_test.dart`（3 项）与 `parental_lock_overlay_test.dart`（2 项）共 5 项失败；用 HEAD 原始版本对照跑，**同样的 5 项同样失败**（含 `line 126` "未锁时左右键应切换 Tab" 断言），确认与本次触屏改动无关，属仓库既有失败。本方案未修改这些测试涉及的代码。
2. **2.5 无状态共存决策**：本方案默认采用（不引入输入模式互斥）；若开发中发现共存导致冲突，再单独评审是否引入输入模式状态。
3. **手势阈值真机调校**：touchSlop=24dp、长按=500ms、节流=250ms、方向比=1.4 均为建议初值，须在真机验证后定稿。

---

## 十一、实施落地记录（2026-11-17 v1.2）

### 11.1 代码改动清单

| 文件 | 改动 | 对应需求 |
|---|---|---|
| `lib/features/iptv/presentation/components/touch_gesture_layer.dart`（**新建**） | 纯 pointer 手势层：`Listener` 手写识别 tap / 上滑 / 下滑 / 左滑 / 右滑 / 长按；`enabled` + `shouldAccept` 双门控；250ms 滑动节流、24dp touchSlop、1.4 主轴比、500ms 长按。只发回调、不持状态、不碰任何 KeyEvent。 | FR-01、FR-06 |
| `lib/features/iptv/presentation/components/live_player_widget.dart` | ① import 手势层 + 三个覆盖层信号；② 新增 `_touchEnabled()`（全屏/频道信息层 && 无 ConfirmDialog/选人/锁屏/消息覆盖层）+ `_touchShouldAccept()` 二次确认 + `_touchToggleInfo()` 单击切换 OSD；③ 在 Stack 视频之上、频道条之下叠加 `TouchGestureLayer`，四向回调复用 `LiveChannelController.previous/next`、`switchSource`、`showChannelPanel`。 | FR-01、FR-02、FR-06 |
| `lib/features/profile/presentation/pages/profile_page.dart` | `_SettingRow` 新增可选 `onTapAction`：整行点击 = 聚焦 + 等价动作。9 个步进/开关行接 `c.step(1)`，刷新/复制/重置/远程/版本接既有动作方法（与遥控 OK 同源）；2 个只读行保持"仅聚焦"。 | FR-03、FR-05 |
| `test/features/iptv/presentation/touch_gesture_layer_test.dart`（**新建**） | 9 项单元测试：单击、四向滑动、长按、enabled 门控、shouldAccept 门控、微位移判点击。 | RT-07 |

### 11.2 遥控零影响的落实证据

- **未改动任何遥控分发代码**：`main_app.dart`（`_handleLogical`/`_handleRootKey`/`_pressOk`/`_onRemoteButton`）、`remote_key_dispatcher.dart`、`floating_remote.dart`、`app.dart` 层级，全部保持原样。
- **手势层只吃 pointer**：`TouchGestureLayer` 用 `Listener` 处理 pointer 事件，不注册任何 `onKeyEvent`/`Shortcuts`/`Actions`；root `Focus.onKeyEvent` 不受影响。
- **业务动作同源**：触屏回调调用的是遥控链路本来就在用的 `LiveChannelController.previous/next`、`HomeNowPlayingController.switchSource/showChannelPanel`、`ProfileFocusController.step/onStepRow`，没有第二套改值逻辑。
- **设置页聚焦先行**：整行点击先 `c.select(row)`（同步逻辑焦点）再执行动作，保证触屏与遥控焦点不错位（FR-05）。
- **覆盖层门控**：手势层在确认弹窗/选人页/家长锁屏/消息浮层显示时自动失效；频道列表交互态（`channelList`）下也失效，频道条点选不受影响。

### 11.3 验证结果

| 验证项 | 结果 |
|---|---|
| 新增手势层单元测试 | **9/9 通过** |
| `flutter analyze`（P0 两文件 / P1 单文件 / 全量） | **三处均 No issues found** |
| 全量 `flutter test` | 16 通过、5 失败；5 项经 HEAD 基线对照确认为**既存失败**（导航断言 + 家长锁），与本次改动无关 |

### 11.4 未完成 / 待真机

- **真机手势阈值调校**：touchSlop、长按、节流、主轴比需在真实触屏 TV 上验证；单元测试只验证逻辑映射。
- **打包装机**：Flutter 改动编译进 APK，需按部署铁律重新 `flutter build apk`（TV flavor）并装机验证；本轮未打包、未部署。
- **RT-03 既存失败测试**：属历史遗留，建议单独排期修复（不在本方案范围）。

---

## 附录 A：术语

| 术语 | 含义 |
|---|---|
| TV 端 / potatokid_screen | 本方案目标端，路径 `pscreen/potatokid_screen` |
| 逻辑焦点 | 自研焦点索引（`ProfileFocusController`/`HomeRemoteLayer`/胶囊二维索引）+ Flutter `FocusNode`，与高亮/OK 目标绑定 |
| 交互层 `HomeRemoteLayer` | 首页交互状态机：`fullscreen`/`channelInfo`/`channelList`/`capsuleControls`（`app_state.dart:5`） |
| L1/L2/L3/L4 | 本方案对触屏改造的四层划分（见 3.1） |
| touchSlop | 判定"滑动 vs 点击"的最小位移阈值（建议 24 逻辑 dp） |
| commitDelay | 切台后延迟换源窗口（`LiveChannelController`，400ms），起防抖作用 |

## 附录 B：关键代码锚点索引

| 主题 | 文件 | 关键位置 |
|---|---|---|
| 遥控总分发 | `main_app.dart` | `_handleLogical:258`、`_handleRootKey:173`、`rootOkHandler:579` |
| 悬浮遥控链路 | `floating_remote.dart` / `remote_key_dispatcher.dart` / `main_app.dart` | `onTap→dispatch:221`、`_onRemoteButton:218` |
| 直播页与手势缺口 | `live_player_widget.dart` | 视频区 `1122-1131`、频道条门控 `1172-1179`、点选 `623-626` |
| 频道控制器 | `packages/pscreen_screen/.../live_channel_controller.dart` | `select:70`、`_step:78`、`commitDelay` |
| 频道条 tile | `channel_bar.dart` | `InkWell.onTap:295`、`_scrollToSelected:52-103` |
| 设置行 | `profile_page.dart` | `_SettingRow:1074-1151`、onTap 只 select、`_onActivateRow:225-232` |
| 焦点控制器 | `profile_focus_controller.dart` | `select:63`（点击/触摸用） |
| 视口缩放 | `tv_design_viewport.dart` | `designSize=960x540:13`、FittedBox `:46-55` |
| 覆盖层 | `update_pill.dart` / `parental_select_overlay.dart` | 胶囊 ColoredBox `408-411`、选人 opaque `385/579` |
| 回归测试 | `test/features/app/presentation/*.dart` | 悬浮遥控层级、锁屏吞键 |

## 附录 C：合规与原创声明

- 本方案为 TV 端交互改造的产品设计参考，交互模式借鉴通用遥控器/触屏惯例（触控手势、焦点管理为公共交互知识），未复刻任何特定产品的专有文案、视觉或交互细节。
- 所有代号、阈值、指标均为设计建议或待实测项，未引用未授权数据。
- 具体实施请结合真机验证、研发可行性评估与公司合规/法务要求确认。

## 附录 D：与录制功能的边界（2026-11-17）

录制核心在共享包 `packages/pscreen_screen/.../recording/`，与触屏手势层并行、互不干扰：

- **手势层不受影响**：录制角标（`RecordingIndicator`）为 `IgnorePointer` 纯展示，不进焦点链、不拦 TouchGestureLayer 的点击/长按/滑动。
- **胶囊菜单录制按钮**：「开始/停止录制」加入胶囊功能菜单（parentOnly，儿童模式隐藏），触屏点按与遥控 OK 均走同一 `_CapsuleEntry.onActivate`。
- **切源拦截**：录制中按左/右键（manual）被拦截并提示，触屏上下滑动换台不受影响——上下滑是切频道（song 级），会按「切台」停录保存，符合预期。
- **提示**：录制事件（开始/保存/切源被拒/自动换源）由 LivePlayerWidget 统一弹 SnackBar，儿童模式走 kidSnackBar，与触屏提示条（_TouchHintBanner）分属不同层，不冲突。
