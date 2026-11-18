# ESP 设备

本目录存放 Potatokid 自研 ESP32 小屏的设备固件与操作文档。后续新增的 ESP 设备统一放在 `firmware/<设备名>/` 下。

```
esp_devices/
├── README.md                       # 本文档
├── .gitignore                      # 排除 secrets.h / 构建产物
└── firmware/
    └── potatokid_esp/              # ESP32-S3 + 1.3" OLED 小屏
        ├── potatokid_esp.ino       # 固件（Arduino）
        ├── secrets.h.example       # 私密配置模板
        └── secrets.h               # 本地私密配置（不入库）
```

## 1. 硬件

| 项目 | 型号 / 参数 |
|---|---|
| 主控 | ESP32-S3（QFN56 rev0.2，16MB Flash，8MB PSRAM） |
| 串口 | CH343 USB-UART，Linux 下为 `/dev/ttyACM0` |
| 屏幕 | 1.3 寸 OLED，**SH1106** 128x64，I2C，地址 `0x3C` |
| 按键 | 可选 1~3 个轻触按键或干接点，接 GPIO4/5/6 对地 |
| 人体感应 | 可选，输出高电平的人体感应模块（VCC 2.7–12V），OUT 接 GPIO7 |

## 2. 接线

### 2.1 屏幕

四根杜邦线，**接线前先断开 USB**：

| OLED 模块 | 接到开发板 |
|---|---|
| VCC | **3V3**（不要接 5V） |
| GND | GND |
| SCL | GPIO9 |
| SDA | GPIO8 |

注意事项：

- 按模块丝印接，不同厂家 4 针顺序不一定是 VCC/GND/SCL/SDA；
- ESP32-S3 没有 GPIO22~25，别照抄 ESP32 老教程；GPIO33~37 被 PSRAM 占用，GPIO19/20 是 USB，都要避开；
- 换引脚只改固件顶部的 `PIN_SDA` / `PIN_SCL` 两个常量；
- 模块自带 4.7k 上拉，杜邦线尽量短。

### 2.2 按键（测试期用杜邦线即可）

| 槽位 | 开发板引脚 | 触发方式 |
|---|---|---|
| 按钮1 | GPIO4 | 与 GND 短接 |
| 按钮2 | GPIO5 | 与 GND 短接 |
| 按钮3 | GPIO6 | 与 GND 短接 |

固件把三个引脚都配置为 `INPUT_PULLUP`，**按下 = 低电平**。没有按键时，一根杜邦线一头插 GPIO4、另一头碰 GND 就是一次「按下」。

> GPIO 只做信号输入，**不要**把负载（灯、继电器线圈）直接串在 GPIO 上，也不要给 GPIO 灌 5V。

### 2.3 人体感应（可选，熄屏用）

| 模块 | 接到开发板 |
|---|---|
| VCC | **3V3**（模块支持 2.7–12V；接 3.3V 供电时 OUT 高电平就是 3.3V，不会超压） |
| GND | GND（必须与开发板共地） |
| OUT | GPIO7（可在设备设置页改，`-1` = 未接） |

- 模块「有人输出高电平」；固件读到高电平就亮屏，并把计时重置，人持续在就一直亮，人走后才开始倒计时。
- 熄屏时长在 Admin → ESP 设备 →「④ 翻页与安全 → 熄屏（人体感应）」里选（默认常亮）；改完设备下次心跳生效。
- 熄屏是给面板发 power save（关显示，约省 18mA），不是断 WiFi；屏灭期间只保留 60 秒心跳、不拉页面，有人时立刻唤醒并刷新。
- 模块上电通常要几十秒预热，期间输出可能乱跳，属正常现象。
- 不要接 5V 再把 OUT 直接进 GPIO：ESP32-S3 的 IO 不耐 5V。

## 3. 开发环境

本机已装好 `arduino-cli 1.6.0` + ESP32 core `3.3.12` + `U8g2 2.36.19`，正常的编译烧录不需要联网。

国内网络直连 GitHub 基本不可用（工具链下载会超时）。重装环境时用代理索引 + 只装 S3 需要的工具：

```bash
# 1) 安装 arduino-cli
mkdir -p ~/.local/bin
curl -fsSL https://downloads.arduino.cc/arduino-cli/arduino-cli_latest_Linux_64bit.tar.gz \
  -o /tmp/arduino-cli.tgz
tar -xzf /tmp/arduino-cli.tgz -C ~/.local/bin arduino-cli

# 2) 安装核心与库
~/.local/bin/arduino-cli core install esp32:esp32
~/.local/bin/arduino-cli lib install U8g2
```

> 如果 `core install` 卡在 github.com 下载工具链：把索引里的 `https://github.com/` 换成
> `https://ghfast.top/https://github.com/`，并删掉 riscv 工具链、其它芯片 libs 等 S3 用不到的
> 依赖，用 `--config-file` 指向改造后的本地索引再安装。

## 4. 编译与烧录

```bash
~/.local/bin/arduino-cli compile --upload -p /dev/ttyACM0 \
  --fqbn esp32:esp32:esp32s3:FlashSize=16M,PSRAM=opi,CDCOnBoot=default,UploadSpeed=921600,PartitionScheme=no_fs \
  /home/honghao/codes/PotatokidClipboard/esp_devices/firmware/potatokid_esp
```

板卡选项说明：

| 选项 | 值 | 原因 |
|---|---|---|
| `FlashSize` | `16M` | 模组 16MB |
| `PSRAM` | `opi` | WROOM-2 系列 8MB PSRAM |
| `CDCOnBoot` | `default`（关闭） | 走 CH343 串口，Serial 输出到 UART0 |
| `UploadSpeed` | `921600` | CH343 稳定档位 |
| `PartitionScheme` | `no_fs` | app0/app1 各 2MB（双 OTA 槽）。默认分区只有 1.25MB，装不下中文字库；`huge_app` 有 3MB 但没有 OTA 槽 |

`no_fs` 没有文件系统分区，本项目不用；NVS 起始地址不变，换分区后 WiFi / 控制端地址等配置都保留。
**首次从其它分区方案切换时仍需 USB 烧录一次**，之后即可远程 OTA。

串口日志：

```bash
~/.local/bin/arduino-cli monitor -p /dev/ttyACM0 -c baudrate=115200
```

## 5. 私密配置

```bash
cp firmware/potatokid_esp/secrets.h.example firmware/potatokid_esp/secrets.h
# 编辑 secrets.h 填 WiFi 名称/密码、局域网设置页口令
```

`secrets.h` 已在 `.gitignore` 中排除，**不要提交真实密码**。缺失该文件时编译会直接报错，属预期行为。

## 6. 运行行为

1. 上电读取 NVS 中保存的 WiFi 与控制端地址，首次运行用 `secrets.h` 与固件默认值；
2. 15 秒内连上：OLED 显示 `IP / srv ok / 信号`，向服务端注册并拉取已放行的控制项；
3. 连不上：自动开热点 `Potatokid-Screen-Setup`（无密码），手机连上后浏览器打开
   `http://192.168.4.1` 配网，配置写入 NVS 后自动重启；
4. 联网期间每 60 秒心跳一次，并顺带刷新控制项列表、检查服务端是否发布了新固件；掉线超过 60 秒转配网热点；
5. 局域网内访问 `http://<设备IP>/` 可改 WiFi，`/settings` 是设置页，都需要口令（`secrets.h` 的网页账号/密码）。

> ⚠️ **状态栏 IP 必须是真实值，禁止写死假 IP**
>
> 屏幕顶部状态栏中间显示的设备 IP，**必须取自 `WiFi.localIP()` 的真实 station IP**。
> 在 WiFi 连上、拿到 IP **之前该位置留空**，绝不显示任何占位/示例地址。
>
> 规划原型 `docs/esp-screen-admin-prototype.html` 与 `docs/esp-screen-display-prototype.html`
> 里写的 `192.168.1.123` **只是演示用的假值**，落地固件时**不要照抄**。
> 断网态画 ✗、配网态画 AP，这两种状态同样不显示 IP。

### 6.1 屏幕四行显示与设备类型字典（oled-2.0+）

固件保持「哑巴」：不认识任何设备类型，只显示服务端下发的**四行纯文本**。设备在 Admin 页
显式声明 `deviceType` + 显示实体绑定，服务端按共享字典（`pscreen_server/server/deviceTypes.js`，
与 home 端共用）把 HA 状态解析成四行下发，新设备类型接入**不用重烧固件**。

- `GET /api/device/esp/actions?format=text&deviceId=...&page=N` 的返回：
  - 第一行固定 `DISPLAY|标题|主状态|副状态|按键提示`（服务端解析好的纯文本）；
  - 其后每行 `button|name|entityId|action|id` 是放行的控制项（旧固件忽略 DISPLAY 行，仍可读按键行）。
- 屏幕布局：顶部状态栏固定「页码 + 真实 IP + WiFi 信号格」，下面依次标题 / 主状态 /
  副状态 / 按键提示四行。主状态异常时用**反白块**（亮底黑字）强调——单色屏唯一的重点手段。
- **单色三色通用**：实物有蓝光 / 白光 / 黄光三种屏，但每像素只有亮/灭两级，没有灰阶。
  绘制只用单一亮色，层次靠字号 + 留白 + 反白；不画灰阶、不画虚线。`screenColor`（NVS, 0蓝/1白/2黄）
  仅记录色别，三色 firmware 绘制逻辑一致。
- **跑马灯**：文字放得下就静止，放不下才无缝循环滚动；四行独立相位、速度
  标题 0.45× → 主状态 0.75× → 副状态 1.1× → 按键提示 1.6×（基准 15px/s），各行不同步。
  以 ~10fps 推进相位，仅超长时重绘，不整屏高频刷新（避免拖慢 I2C / 心跳 / 按键轮询）。
- **翻页**：按键绑 `next_page` / `prev_page` / `home_page` 系统动作时，服务端回执 `sys`，
  固件维护 `currentPage` 并重新拉取该页四行文本与按键定义。按键硬件可扩展（当前 3 键）。
- **中文字库**：主屏用 `wqy12_t_gb2312` + `drawUTF8`；缺字可按 README 前文换 `chinese2/3` 字库。

## 7. 设置页（设备本地）

`http://<设备IP>/settings`：

| 项 | 说明 |
|---|---|
| 控制端地址 | 默认 `http://ptool.w1.luyouxia.net`，存 NVS，改完自动重启。换域名 / 换服务端只改这里，不用重新烧录；留空保存恢复默认 |
| 可控设备列表 | 从服务端读取**已放行**的控制项（名称 / HA 实体 / 动作 / 按钮），每行可点「测试」直接执行一次 |
| 物理按键 | GPIO4/5/6 对应按钮1/2/3，短接 GND 即触发 |
| 固件升级 | 显示当前版本；服务端发布新版本时显示新版本号、大小、更新说明和「立即升级」按钮 |
| 自动更新 | 勾选后设备检测到新版本会自行下载安装（约 20 秒），完成后自动重启；开关存 NVS，不重启生效 |

屏幕上会短暂显示按键结果（`sent ok` / `failed, see serial`），失败原因看串口日志。

## 8. 用按键控制 HA（白名单在服务端）

固件本身不存 HA 地址和令牌，按键只发请求给 pscreen_server，由服务端按白名单代调 HA：

1. 管理页 `/admin` → **设备状态** → 找到这台 ESP（类型为空、型号 `ESP32-S3 1.3 OLED`）→「ESP 控制」；
2. 添加控制项：显示名、实体 id（如 `light.living_room`）、动作（切换/开/关/执行）、绑定的按钮槽位；
3. 勾选「放行」——**只有勾选的项才会下发到设备**，没勾的设备看不到、也调不动；
4. 右上角「HA 连接」填 HA 地址与长期访问令牌（HA：用户资料 → 长期访问令牌）。令牌只存在服务端，不下发到 ESP。

服务端接口（设备侧无需鉴权，白名单是唯一门禁）：

| 用途 | 接口 | 返回 |
|---|---|---|
| 拉取放行项 | `GET /api/device/esp/actions?deviceId=<id>&format=text` | `button\|name\|entityId\|action\|id` 每行一项 |
| 按键触发 | `POST /api/device/esp/press`，body `{deviceId, button}` 或 `{deviceId, actionId}` | HA 执行结果 |

管理页接口（需登录）：`GET/PUT /api/admin/machines/:id/esp`、`GET/PUT /api/admin/ha`。

> 动作与 HA 服务的对应：`toggle → <domain>.toggle`、`turn_on → <domain>.turn_on`、`turn_off → <domain>.turn_off`、
> `run → <domain>.turn_on`（用于 script / scene）。窗帘这类需要 `open_cover/close_cover` 的实体，建议在 HA 里建 script 后用「执行」。

### 显示模板占位符

「ESP 设备分类 → 页面 → 主状态/副状态模板」里可写以下令牌，前端预览与服务端下发用同一套解析：

| 令牌 | 取值 |
|---|---|
| `{main}` / `{s1}` / `{s2}` | 三个绑定实体（按设备类型字典的属性） |
| `{title}` / `{名称}` | 页面名 |
| `{domain.entity_id}` | 该实体的 state，如 `{switch.bedroom}` |
| `{domain.entity_id.attr}` | 该实体的指定属性，缺失时回落 state，如 `{climate.bed.temperature}` |

属性段让 128×64 屏能同时显示当前值与目标值，例如空调：

```
{climate.xiaomi_cn_735376016_m9} 当前{climate.xiaomi_cn_735376016_m9.current_temperature}° 目标{climate.xiaomi_cn_735376016_m9.temperature}°
```

超宽由固件按各行节拍走马灯滚动；预览只显示首屏。遥控设备的三段令牌 `{remote.<设备id>.<字段>}` 仍走本地实时状态，不查 HA。

## 9. 控制真实设备（继电器）

GPIO 只有 3.3V / 几 mA，只能给信号，不能直接带负载。常规做法：

| 继电器模块 | 接到 |
|---|---|
| VCC | 开发板 5V（或外部 5V，与开发板共地） |
| GND | GND（必须与开发板共地） |
| IN | GPIO4（对应按钮1） |
| COM / NO | 串在被控设备的火线或信号线上 |

- 模块分「高电平触发 / 低电平触发」两种，固件按键是低电平有效；若模块是高电平触发，接 `IN` 后行为会相反，换低电平触发模块或把按键改成上拉对 VCC（改固件 `INPUT_PULLDOWN` + 高电平判断）；
- 强烈建议被控设备的强电部分由**成品继电器/智能插座**承担，ESP 只做触发，避免市电接线风险；
- 不想接继电器时，直接用「ESP 按键 + HA 控制」的方式验证链路：HA 里操作灯/插座，设备只负责发按键请求。

## 10. 远程升级（OTA）

设备每 60 秒心跳时会顺带问服务端「有没有新固件」。检测到版本不同 → 屏幕标题变成
`Update ready`（显示当前/新版本并提示 `open web page`），用户打开设备的
`http://<设备IP>/settings` → 「固件升级」→「立即升级」即可，升级时屏幕显示百分比，
完成后自动重启，WiFi 与控制端地址配置都保留。

**发布流程**：

1. 改代码，并把 `APP_VER` 改成新版本号（如 `oled-1.4`）；
2. 编译导出 bin（OTA 只需要 app 镜像，不要 `merged.bin`）：

   ```bash
   ~/.local/bin/arduino-cli compile \
     --fqbn esp32:esp32:esp32s3:FlashSize=16M,PSRAM=opi,CDCOnBoot=default,UploadSpeed=921600,PartitionScheme=no_fs \
     --output-dir /tmp/fw_out \
     /home/honghao/codes/PotatokidClipboard/esp_devices/firmware/potatokid_esp
   # 产物：/tmp/fw_out/potatokid_esp.ino.bin
   ```

3. 管理页 `/admin` → **设备状态** → 「固件升级」→ 选 `potatokid_esp.ino.bin`，
   填与 `APP_VER` **完全一致**的版本号 →「上传并发布」；
4. 设备下一次心跳（≤60 秒）就会提示可更新；「撤回发布」可让设备停止提示。

**自动更新**（适合远程设备，不用每次回后台点按钮）：

- 设备设置页「固件升级」里勾选「自动更新」，开关存 NVS，保存即生效（不需要重启）；
- 心跳发现新版本后延迟 8 秒开始自动安装，屏幕显示 `Update ready` → `Updating xx%` → 自动重启；
- 失败保留当前固件，30 分钟后重试；同一版本不会陷入「失败-重启-再失败」的循环；
- 设备只比对版本字符串，**服务端发布什么版本就装什么**（发布旧版本等于自动回滚），发布前确认版本号；
- 自动更新依赖设备能访问「控制端地址」，离线设备不会触发，恢复在线后下一次心跳补上。

注意：

- 版本号必须与固件内 `APP_VER` 一致，否则升级后仍会提示（设备只做字符串比对）；
- OTA 依赖双 app 槽，`no_fs`/`min_spiffs` 可用，`huge_app` 不行；
- 升级中途断电不会变砖：旧固件仍在另一个槽，重新上电会回滚；
- 设备侧接口：`GET /api/device/firmware/latest?format=text` → `version|size|sha256|notes`，
  `GET /api/device/firmware/download` 下载 bin。

## 11. 常见问题

| 现象 | 排查 |
|---|---|
| 屏幕全黑 | 先看串口是否打印 `OLED ready at 0x3C`；没有则检查 SDA/SCL 是否接反、VCC 是否为 3V3 |
| 屏幕花屏/错位（左缺右乱码） | 面板是 SH1106 而驱动写成 SSD1306；用 `U8G2_SH1106_128X64_NONAME_F_HW_I2C`（当前固件已如此） |
| 亮屏后正文空白、只剩顶栏页码和 IP | ≤`oled-3.2` 的 bug：`NetSnapshot` 标量未初始化，感应心跳那条不拉页面的路径会发布「状态沿用上一轮、文本全空」的假快照，把正文刷成空白。`oled-3.3` 已修（补默认值 + 感应上报不再顺延 60 秒心跳） |
| 按键名称显示乱码 | 控制项名是中文，必须用 UTF-8 中文字库 + `drawUTF8`（当前固件用 `u8g2_font_wqy12_t_gb2312`）；生僻字不在 GB2312 内可换 `u8g2_font_wqy12_t_chinese2/3` |
| 设置页没有「立即升级」 | 服务端还没发布固件（admin →「固件升级」上传），或已发布版本与设备 `APP_VER` 相同 |
| 升级失败 | 看串口 `[ota] failed code=...`；常见是分区不是 `no_fs`/`min_spiffs`（无双槽）、服务端 bin 被撤回、设备访问不到控制端地址 |
| 串口无输出 | 确认板卡选项 `CDCOnBoot=default`，端口为 `/dev/ttyACM0` |
| 连不上 WiFi | 只支持 2.4GHz；确认热点名称密码；等 15 秒自动进配网热点 |
| 局域网设置页打不开 | 需要 Basic Auth（`secrets.h` 的口令）；确认设备和电脑在同一网段 |
| 服务端显示离线 | 检查控制端地址是否可达、心跳日志 `[srv] ... -> HTTP 200 ok` |
| 设置页控制项为空 | 管理页还没添加控制项，或没勾「放行」 |
| 按键提示 failed | 看串口：`未配置 HA` → 填 HA 连接；`调用 HA 失败` → 检查 HA 地址/令牌；`未放行` → 回管理页勾选 |

## 11. 新增 ESP 设备的约定

- 目录：`firmware/<设备名>/<设备名>.ino`，与 Arduino sketch 同名规则保持一致；
- 私密信息一律走 `secrets.h`（模板入库、真实文件不入库）；
- `deviceId` 建议 `<前缀>-<MAC 12 位>`，前缀区分设备形态（如 `esp32s3`）；
- 上线后统一调 `/api/device/register` 与 `/api/device/heartbeat`，不要另建注册接口；
- 需要 HA 控制的设备，复用 `/api/device/esp/actions` 与 `/api/device/esp/press`，白名单统一在 admin 页维护；
- 新增硬件引脚在 README 的接线表登记，避免后续换板接错。
