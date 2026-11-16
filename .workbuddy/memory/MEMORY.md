# 项目长期记忆（potatokid_clipboard）

完整约定见项目根目录 `rules.md`；部署前先确认。详细踩坑见 `.workbuddy/memory/2026-11-{11,12,13,16}.md`。

## 术语对照（用户口径，勿替换）
- home端/中控端 = `pscreen_home`；tv端 = `potatokid_screen`（`pscreen/potatokid_screen`）
- 本地服务/数据服务 = `pscreen_server/server`；应用服务 = `app_server`
- 本地部署 = `ssh 100.83.142.107`；远程/yuntu部署 = `ssh yuntu`

## 部署铁律
- 所有服务用 **pm2**；**先改源码再部署**，绝不在部署机上直接改文件。
- `yuntu` = root@143.203.52.132（honghao 直连被 reset）：root 登录后用 `sudo -u honghao pm2 ...`（`pm2 -u honghao` 会连错空守护）。app-server 部署 `/home/honghao/services/app_server`，静态 `web/`→`build/web/`，端口 47292。
- `100.83.142.107`：直接 honghao 登录；非交互 ssh 需 `export PATH="$HOME/.npm-global/bin:$PATH"; export PM2_HOME=/home/honghao/.pm2`；进程 `my-server`（**cluster 模式**，非 fork），端口 3000，用 `pm2 restart`。
- Windows CRLF vs Linux LF：比对用 `diff --strip-trailing-cr`；上传前 `tr -d '\r'`、`node --check`、备份、`install -m` 保权限、md5 对齐后再重启。
- `server/*.js` → `/home/honghao/services/tools/server/`；`web/admin.html` → `build/web/admin.html`（machines.json 在 `datas/admin/`）。
- 契约改动（客户端 API）必须同步部署服务端，否则新旧错配（已踩两次）。
- 家长端管理接口鉴权：`POST /api/admin/login` 拿 `pk_admin` cookie；m10s 口令 `12345678`。machines.json 会被心跳持续写，md5 不同≠残留，清理走接口。

## 关键约定
- 设备型号：WS 握手上报一次，取不到返回空串；禁止 Process.run 调 ps（闪黑框），用 FFI 注册表/sysfs；`device_info_plus ^13.3.0` + `win32_registry ^3.0.3`。
- parent APK：`flutter build apk --debug --flavor parent --dart-define=APP_FLAVOR=parent`（两个参数缺一不可）。
- 我的页目标设备联动：`parental_mine_tab.dart` / `parental_unlock_section.dart`；断言设备名用 `findsWidgets`；变更前同步 `docs/parent-app-redesign-prototype.html`。
- adb：Git Bash 加 `MSYS_NO_PATHCONV=1`；install/pull 本地路径用 Windows 反斜杠。USB R58M349S90M 当前登录 m10s。

## HA / ESP（2026-11-16）
- HA 取数铁律：WS auth token 在顶层；`/api/states` 无 area/device → 走 WS 注册表；area 无层级，家名按区域名首个空格切。
- ESP 动作动态解析 `server/ha_catalog.js`（cover/lock/button/valve/vacuum），存储仍 `toggle/turn_on/turn_off/run`。ESP 设备 `kind === ''`；按键路径 `POST /api/device/esp/press`；admin 口令 `123456`。
- admin.html 下拉挂 `document.body` + `position:fixed`；滚动时 `menu.contains(target)` 不关；blur 判定排除 `document.body`；中文用前缀剥离；表头 sticky 实体色；表格 fixed 布局 + 完整换行（禁省略号/title）；房间筛选必须带「家」。
- 设备类型识别：**admin 显式分类**（deviceType + 绑定实体）为唯一真源，服务端字典解析，home/ESP **共用字典层**；home 直连 HA WS 的实时通道不共用。home 端后缀推断有串类 bug（`_status_p_2_2` 三类共用）。
- OLED：三色单色屏，单一亮色无灰阶/无虚线；层次靠字号+留白+反白块；跑马灯仅超长触发、各行分速（0.45/0.75/1.1/1.6×，基准 15px/s）；顶栏=页码+IP(仅已连接)+WiFi。IP 必须 `WiFi.localIP()`，原型假值禁抄（已写 esp_devices/README.md）。Flash 16MB 但 `no_fs` 表只用前 4MB，后 12MB 闲置，字库空间不是瓶颈。
- 设备字典共用已落地（2026-11-16）：服务端 `server/deviceTypes.js`（唯一真源，覆盖层 `datas/admin/deviceTypes.json`）+ admin 两顶层 Tab「设备类型字典/ESP 设备分类」+ 公开读 `/api/device/device-types`。home 端 `features/home/domain/models/device_type_dictionary.dart` 的 `isExplicitlyOtherType()` 注入 13 个 Summary 的 tryBuild 消歧（首页静态 `active` 由 `DeviceTypeStore.refresh` 设置）；取数仍直连 HA WS。带参动作 `set_temperature(+0.5)` 等在 `callHaService` 算好值下发。
- 固件 `potatokid_esp.ino` 已改 `oled-2.0`：`drawScreen` 四行 + 顶栏真实 IP + 分速跑马灯 + 反白块 + DISPLAY 协议 + sys 翻页；arduino-cli 编译通过（flash 61%/RAM 15%），未真机烧录。编译命令见 README（fqbn `esp32:esp32:esp32s3:...PartitionScheme=no_fs`）。实施计划/进度 `docs/esp-device-dict-rollout-plan.md`（23/23 完成）。
- 原型：`docs/esp-screen-{admin,display}-prototype.html`、`docs/esp-device-type-prototype.html`。
