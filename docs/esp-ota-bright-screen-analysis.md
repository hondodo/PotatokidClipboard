# ESP 升级时亮屏问题分析

> 日期：2026-11-19　范围：`esp_devices/firmware/potatokid_esp/potatokid_esp.ino`
> 状态：**方案 B 已实施并发布 `oled-4.3`**（2026-11-19 21:26）；设备 autoUpdate 默认关闭，需在小屏本地设置页手动升级生效
> 背景：服务端原发布 `oled-4.2`，用户希望升级过程中屏幕亮起并显示进度。

## 一、结论先行

升级时"看不到进度"不是单个问题，而是**两个独立缺陷叠加**，必须一起修：

| # | 问题 | 直接原因 | 后果 |
|---|------|----------|------|
| 1 | 升级时屏幕是灭的 | `drawScreen()` 首行 `if (!oledOk \|\| screenOff) return;`，而 OTA 触发时人往往已离开、`screenOff=true` | 所有 `oledShow()` 升级提示被吞，全程黑屏 |
| 2 | 亮屏后进度被页面内容盖掉 | `drawScreen()` 里 `if (!abnormal && scrRowCount > 0)` 用页面缓存 ROWS 覆盖传入文案；`oledShow()` 传 `abnormal=false` | 屏幕亮着，但显示的是当前页正常内容，"Updating / 进度%" 看不到 |

问题 2 是上一轮加 ROWS 时引入的回归：加 ROWS 之前 `drawScreen()` 直接用传入参数画，加之后非异常提示被页面缓存劫持。按键反馈走 `oledToast()`（`abnormal=true`）没受影响，所以只有升级/系统提示中招。

## 二、链路拆解

### 2.1 熄屏怎么来的

```
loop → pollPir() → 人离开 → lastPresenceAt 不再刷新
     → (millis() - lastPresenceAt) > screenOnSec*1000
     → sleepScreen() → screenOff=true + u8g2.setPowerSave(1)
```

服务端 `SCREEN` 行下发 `screenOnSec`（0 = 常亮）。只要配了熄屏秒数，人一走屏幕就断电。

### 2.2 升级怎么触发的

| 入口 | 路径 | 用户在场? |
|------|------|-----------|
| 本地设置页「立即升级」 | `POST /update` → `runOta()` | 不确定（手机浏览器操作，PIR 未必测到) |
| 自动更新 | 后台 5 分钟查版本 → `fwAvailable` → 排队 8 秒 → loop 调 `runOta()` | 基本没人盯着 |

自动更新场景**几乎必然熄屏**：没人盯着设备，PIR 早就超时了。这正是"升级时亮屏"诉求的核心场景。

### 2.3 提示怎么被吞的

`runOta()` 里三处提示：

```cpp
oledShow("Updating", "connecting...");              // 开始前
httpUpdate.onProgress([]{ oledShow("Updating", pct%, ...); });  // 进度
oledShow("Update done", "rebooting...");            // 成功
oledShow("Update failed", code, err);               // 失败
```

全部走 `oledShow()` → `drawScreen(..., abnormal=false)`：

- 第一关 `if (screenOff) return` —— 熄屏时直接不画（问题 1）
- 第二关 `if (!abnormal && scrRowCount > 0)` —— 页面有 ROWS 缓存时用页面内容覆盖（问题 2）

同理 `drawMain()` 里的 `"Update ready"` 提示也是 `abnormal=false`，同样被 ROWS 覆盖。

## 三、方案对比

| 方案 | 做法 | 解决熄屏 | 解决覆盖 | 复杂度 | 结论 |
|------|------|----------|----------|--------|------|
| A 最小改动 | `runOta()` 开头加 `wakeScreen()` | 仅点亮一瞬 | 否 | 1 行 | 不够：PIR 超时会再熄屏，进度仍被盖 |
| **B 全程强制亮屏** | `otaInProgress` 标志贯穿 + 提示强制用传入参数 | 是 | 是 | 6 处 | **推荐**，覆盖自动/手动两种入口 |
| C 关闭熄屏功能 | 把 `screenOnSec` 设 0 | 是 | 否 | 0 行 | 牺牲平时省电，且没解决覆盖，不可取 |
| D 后台开关 | 加「升级时亮屏」配置项下发 | 是 | 是 | 高 | 单设备过度设计，固件本地逻辑足够 |

### 推荐方案 B 的设计要点

1. **加全局标志** `volatile bool otaInProgress = false;`
2. **`runOta()` 开头**：`otaInProgress = true; wakeScreen();` —— 立刻点亮并清 `screenOff`
3. **堵住再次熄屏**：
   - `sleepScreen()` 开头 `if (otaInProgress) return;`
   - loop 里 PIR 超时熄屏条件追加 `&& !otaInProgress`
4. **结束复位**：成功分支在 `ESP.restart()` 前、失败分支在 `toastUntil` 设置前，都置回 `false`
5. **修覆盖**：给 `drawScreen()` 加第 6 个参数 `bool useArgs = false`，`if (!abnormal && scrRowCount > 0 && !useArgs)`；`oledShow()` 传 `useArgs=true`，让系统提示始终用传入文案画，不改现有反白行为
6. **同步修** `drawMain()` 里的 `"Update ready"`（改走 `oledShow()` 或同样传 `useArgs=true`）

## 四、具体改动点（可执行清单）

| # | 位置 | 改动 |
|---|------|------|
| 1 | 全局变量区（约 220 行） | 新增 `volatile bool otaInProgress = false;` |
| 2 | `drawScreen()` 签名（400 行） | 加 `bool useArgs = false` 参数；ROWS 分支条件追加 `&& !useArgs` |
| 3 | `oledShow()`（461 行） | 调用 `drawScreen(title, l1, l2, l3, false, true)` |
| 4 | `drawMain()` 的 `fwAvailable` 分支（948 行） | 改调 `oledShow("Update ready", ...)` 以绕过 ROWS |
| 5 | `runOta()`（842 行） | 开头置 `otaInProgress=true` + `wakeScreen()`；成功/失败分支复位 `false` |
| 6 | `sleepScreen()`（977 行）+ loop 熄屏条件（1727 行） | 加 `if (otaInProgress)` 守卫 |

改动后 `APP_VER` 从 `oled-4.2` 升到 `oled-4.3`，编译、发布、用户手动升级（autoUpdate 仍默认关闭）。

## 五、验证方式

1. **编译**：arduino-cli（部署机上，fqbn `no_fs`），确认 flash/RAM 占用无异常。
2. **手动升级 + 熄屏场景**（覆盖问题 1）：把 `screenOnSec` 临时设成 10 秒 → 人离开等屏幕熄灭 → 手机访问设备 `/settings` 点「立即升级」→ 观察屏幕应立即亮起并显示 `Updating / 进度%`，期间不再熄灭。
3. **自动更新场景**：开 `autoUpdate`，发布 `oled-4.3`，人离开后观察设备是否在升级时自动亮屏。
4. **覆盖回归验证**（覆盖问题 2）：在已配置 ROWS 的页面上触发升级，确认屏幕显示的是 "Updating / 进度%" 而不是该页正常内容。
5. **失败路径**：临时发布一个损坏固件，确认显示 "Update failed"，且 5 秒后恢复常规熄屏节奏（标志已复位）。

## 六、实施记录（2026-11-19 21:26）

方案 B 已按「四、具体改动点」全部落地，6 处改动 + 版本号 `oled-4.2 → 4.3`：

- 全局 `volatile bool otaInProgress`；`runOta()` 开头置 true + `wakeScreen()`，成功/失败分支均复位。
- `sleepScreen()` 与 loop 的 PIR 超时熄屏条件都加 `otaInProgress` 守卫。
- `drawScreen()` 加第 6 参数 `bool useArgs = false`，ROWS 分支条件追加 `&& !useArgs`；`oledShow()` 传 true。
- `drawMain()` 的 `"Update ready"` 改走 `oledShow()`。

验证：部署机 arduino-cli 编译通过（flash 62% / RAM 22%，与 4.2 一致）；固件 `oled-4.3` 已发布到 `100.83.142.107`，sha256 `bcb06ec40cc15113385c8d1792396b7e4064a67523a8efec4152ad24575d4bf2`，`latest` 接口回读一致。服务端/admin/协议均无需改动。

**待真机验收**：设备 autoUpdate 默认 false，需在小屏本地设置页点升级到 `oled-4.3` 后，按「五、验证方式」实测亮屏与进度显示（本轮仅完成代码与发布，未连真机）。

## 七、风险与注意

- **功耗**：OTA 下载期间屏幕常亮，单色 OLED 约十几 mA，持续几十秒到几分钟，可接受；升级完成自动重启后恢复原逻辑。
- **`wakeScreen()` 有副作用**：它会调 `drawMain()` 并重置 `netRefreshAt`。在 `runOta()` 开头调用时会先闪一帧页面内容，紧接着被 `oledShow("Updating")` 覆盖，肉眼基本无感；如需纯净可改为直接 `screenOff=false; u8g2.setPowerSave(0);` 两行手写点亮。
- **升级进度回调频率**：`onProgress` 里已做 300ms 节流，亮屏后不会因频繁 I2C 写入拖慢下载。
- **范围**：只改固件，服务端/admin/协议均不用动；无需改数据结构。

> 合规声明：本方案为产品设计参考，原创撰写；具体实施请结合公司合规与法务要求确认。
