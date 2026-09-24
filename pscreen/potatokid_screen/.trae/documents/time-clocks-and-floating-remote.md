# 时间页多样式时钟 + 悬浮遥控器蒙层

## Context（背景）

电视 App 的「时间」Tab 目前是占位页。用户希望它实现一个**多显示样式的数字/模拟时钟**，并支持上下切换样式；同时为**手机调试**提供一个可开关的**悬浮遥控器蒙层**，用来 1:1 模拟电视遥控器按键。

效果图（第一屏）：超大 `HH:MM:SS` 数字时间 + 下方「日期 / 农历 / 星期」，配**彩色缓慢流动的背景 + 20% 黑色蒙层**；**文字/表盘用白色**（因背景已被蒙层压暗）。

已确认的方案：
1. **手机调试**：悬浮迷你遥控器 D-pad 蒙层（可拖动），底层用 `KeyEventSimulator` 派发与真实遥控器相同的按键事件，复用现有焦点 / OK 处理逻辑——不做"屏幕九宫格分区"。
2. **农历**：自写 1900–2100 农历换算，**零新增依赖**。
3. **三屏背景统一**：转盘时钟（第 3 屏）与前两屏相同流动背景。
4. **悬浮遥控器显隐**：在首页「设置」里加开关控制，默认显示，运行时切换；不绑定 debug 判断。

---

## 一、全局状态与设置开关

### 1.1 `lib/features/app/application/bloc/app_state.dart`
- 新增字段 `final bool showFloatingRemote;`（默认 `true`，便于手机预览发现）。
- 更新 `AppState._`、`AppState.initial()`、`copyWith({... bool? showFloatingRemote})`。

### 1.2 `lib/features/app/application/bloc/app_event.dart`
- 新增 `class SetFloatingRemote extends AppEvent { final bool show; const SetFloatingRemote(this.show); }`。

### 1.3 `lib/features/app/application/bloc/app_bloc.dart`
- 注册 `on<SetFloatingRemote>` → `emit(state.copyWith(showFloatingRemote: event.show))`。

### 1.4 「我的」页加开关 `lib/features/profile/presentation/pages/profile_page.dart`
- 「悬浮遥控器」开关放到「我的」页（首页右上角设置按钮在电视上几乎无法触达，故改为放这里）。
- 在现有 `ListView` 末尾加一个 `SwitchListTile`：`BlocBuilder<AppBloc, AppState>` 读取 `showFloatingRemote`，`onChanged` → `context.read<AppBloc>().add(SetFloatingRemote(v))`。
- 加文案 key：`settings_floating_remote`（四个语言文件 `zh-CN/zh-TW/en-US/ja-JP` 均新增）。

### 1.5 移除顶部导航栏的设置入口 `lib/features/app/presentation/pages/main_app.dart`
- 删除 `_TopNavBar` 里右上角的设置 `IconButton`（及 `action_settings`/`SettingsSheetParams`/`AppRouter`/`Injection` 相关引用），因为电视遥控难以触达；设置功能由「我的」页承载。

---

## 二、悬浮遥控器蒙层（shared 组件）

### 2.1 `lib/shared/widgets/floating_remote.dart`（新建）
- `FloatingRemote`（StatefulWidget）：用 `BlocBuilder<AppBloc, AppState>` 依据 `showFloatingRemote` 决定显隐；**放在 MainApp 的 Stack 最上层**，可拖动。
- 用 `VariableSizePolicy/Overlay` 或直接在 MainApp 里用 `Stack` + `Positioned` 承载；拖动用 `GestureDetector.onPanUpdate` 更新 `Offset`（存 State 内）。
- 按键布局：方向键十字（↑↓←→）+ 中心 **OK** + 两个小键 **菜单**(contextMenu) / **返回**(escape)。
- 按键触发统一走 `flutter/services` 的 `KeyEventSimulator`：
  ```dart
  Future<void> _press(LogicalKeyboardKey key) async {
    await KeyEventSimulator.simulateKeyDownEvent(key);
    await KeyEventSimulator.simulateKeyUpEvent(key);
  }
  ```
  映射：上下左右 → `arrowUp/Down/Left/Right`；OK → `enter`（即 `select/激活`，会到 MainApp 根 OK 处理器）；菜单 → `contextMenu`；返回 → `escape`。
- 样式：半透明深底圆角面板 + 白色图标，可拖动，避免遮挡过多。

### 2.2 `lib/features/app/presentation/pages/main_app.dart`
- 在 `Scaffold.builder`/`body` 的 Stack 末尾追加 `const FloatingRemote()`（置于导航条之上，浮在所有 tab 之上），并 import 组件。

---

## 三、时间页多样式时钟

### 3.1 农历换算 `lib/features/time/domain/lunar_calendar.dart`（新建，零依赖）
- 经典 1900–2100 农历信息表（`List<num>`，每 16bit 编码每月天数/闰月）+ 转换函数。
- API：`LunarDate.from(DateTime)` → `{ int year; int month; int day; bool isLeap; }`。
- 输出农历字符串：月份用中文数字（如一/二…十一/十二，闰月前缀「闰」），日同样中文（初一…廿九、三十），组装如「八月十四」。
- 顶部中文常量数组供 `cnNumber(int)` 使用。

### 3.2 流动彩色背景 `lib/features/time/presentation/components/flowing_gradient_background.dart`（新建）
- `FlowingGradientBackground`（StatefulWidget）：持 `AnimationController(repeat, 时长约 8-12s)`。
- 用 `CustomPainter` 绘制一条随控制器 value 缓慢平移/旋转的多色 `LinearGradient`（若干亮色 stop），形成"彩色慢慢流动"。
- 叠一层 `Container(color: Colors.black.withValues(alpha: .2))`（20% 黑蒙层）。
- 三屏共用。

### 3.3 数字时间 + 农历日期子视图（`time_page.dart` 内）
- 通过 `Timer.periodic(1s)` 更新 `DateTime now`，并 `setState`，用 `intl` `DateFormat('HH:mm:ss', 'zh_CN')`。
- 日期行：公历 `DateFormat('y年M月d日', 'locale')` + 农历 `LunarDate` 中文 + 星期 `DateFormat('EEEE', locale)`，拼接如「2026年9月24日 八月十四 星期四」。
- 文字用白色（已叠加黑蒙层保证对比度）。

### 3.4 转盘（模拟）时钟 `lib/features/time/presentation/components/analog_dial_clock.dart`（新建）
- `AnalogDialClock`（StatefulWidget）+ `Timer.periodic(1s)`；用 `CustomPainter` 画 12 刻度、时/分/秒三针（白描边/白色指针），随 `DateTime` 旋转。

### 3.5 `lib/features/time/presentation/pages/time_page.dart`（重写）
- `enum TimeStyle { full, timeOnly, dial }`，用 `_styleIndex` 表示当前屏。
- 结构：
  - `Stack`：底层 `FlowingGradientBackground`（全屏）→ 内容层（按 style 渲染 3 种）。
  - 包一层全屏可聚焦的 `Focus(focusNode, autofocus: true, onKeyEvent: ...)`：
    - `arrowUp`/`arrowDown` → 循环切换 `_styleIndex`（`full→timeOnly→dial→full`），返回 `handled`；
    - 其它键（含 OK）返回 `ignored`，使 OK 继续冒泡到 MainApp 根处理器（显隐导航条）。
  - style 含义：
    - `full`：HH:MM:SS + 日期+农历+星期（同效果图，居中）。
    - `timeOnly`：仅超大 HH:MM:SS。
    - `dial`：居中 `AnalogDialClock`。
- 完成后替换原占位 `Center(Icon + Text(time_title))` 结构。

---

## 四、国际化补充

`assets/translations/{zh-CN,zh-TW,en-US,ja-JP}.json` 各新增：
- `settings_floating_remote`（悬浮遥控器开关文案）。

---

## 五、验证方式

1. `flutter analyze` 无错误。
2. 手机运行（横屏）：
   - 「时间」Tab：默认完整样式；按遥控器/悬浮蒙层的 **上/下** 在三屏间循环；三屏背景一致（流动彩色 + 20% 黑蒙 + 白色文字/表盘）。
   - 开启悬浮遥控后：拖动位置；点 ↑↓ 切换时间样式、点 ←→ 移动焦点切换顶部 tab、点 **OK** 显隐导航条+频道条、菜单/返回生效。
   - 「我的」页「悬浮遥控器」开关：能即时显示/隐藏悬浮遥控。
   - 顶部 tab 与频道条仍按之前逻辑工作；视频全屏不受影响。
   - 顶部导航栏不再有设置按钮；「我的」页可开关悬浮遥控器。