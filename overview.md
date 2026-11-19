# 智能页触发规则卡片改造 — 交付概览

## 做了什么

把自动化编辑里的「全局 AND/OR 下拉 + 一叠条件卡」改成**规则卡片**结构：

- 顶部两个按钮：`+ 添加规则`、`+ 添加条件`
- **每张规则卡片内的条件是 AND**（全部满足才算这条规则满足）
- **规则卡片之间是 OR**（任意一条规则满足就触发）
- 新增规则或条件后自动滚动到新卡片，避免用户以为没加上
- 触发时机不变：条件满足即触发，重复执行仍由「冷却时间」拦住（不引入边沿触发）

## 关键改动

| 文件 | 改动 |
|---|---|
| `pscreen_server/server/scenes.js` | 触发数据改为 `{rules:[{conditions:[]}]}`；规则内 AND / 规则间 OR 求值；旧单 trigger 与旧 AND/OR 条件组读时自动迁移；轮询/心跳路径统一走规则结构 |
| `pscreen_server/web/admin_js/12-smart.js` | 去掉 AND/OR 下拉，加两个新增按钮；渲染规则卡片与「且」「或」连接词；新增后 rAF + `scrollIntoView` 滚动；保存提交 rules |
| `pscreen_server/web/admin.css` | 规则卡片、连接词、按钮布局样式 |
| `pscreen_server/test/scenes_conditions_test.js` | 重写为规则语义测试（含旧结构迁移与混合 AND/OR） |
| `docs/esp-smart-tab-design.md` | 升 v1.3，同步数据结构、字段表、验收记录 |

## 验证

- 服务端单测 `scenes_conditions_test.js` **14/14**
- 真实 admin 页无头浏览器 **36/36**（含自动滚动调用断言、规则/条件增删守卫、保存与回读）
- 回归：`esp_sys_test.js` 14/14、`esp_template_token_test.js` 7/7、`admin_alias_test.js` 6/6；改动 JS 全部 `node --check` 通过

## 部署状态（2026-11-19 20:17 已完成）

- 3 个文件已同步到 `100.83.142.107`：`server/scenes.js`、`build/web/admin_js/12-smart.js`、`build/web/admin.css`；admin.html / admin.js / 固件无需改动。
- 备份后缀 `.bak-smartrules-20261119_2017`；LF 转换 + md5 与本地完全一致；远端 `node --check` 通过；`pm2 restart my-server` 后进程在线、HTTP 200。
- 线上验证：静态资源 md5 与本地对齐；`/api/admin/scenes` 读旧自动化「回家自动开灯」已迁移成 `rules=[["presence"]]`，无残留旧 `logic` 字段。

## 追加：ESP 页面四行统一 + 显示开关让位（21:00 已上线）

先提交了上一段改动：`0212cbd`。随后按拍板完成 ESP 页面配置改造：

- 页面名称、按键提示改为**显示勾选**；隐藏一个让出一行内容，隐藏两个让出两行。
- 内容区变成 4 个模板位（主/副 + 行3/行4），**逐位开放编辑**：藏起页面名或按键才开放行3，两个都藏才开放行4；行3/行4 同样支持插入实体、值替换、按实体替换、系统变量与跑马灯。
- 取消「主状态大字体」，四行统一 wqy12 字号、等距排列；admin 预览与真机同一套坐标，所见即所得。
- 服务端下发 `ROWS|` 合并四行，保留 `DISPLAY|` 兼容旧固件；固件 `oled-4.2` 已发布。

验证：服务端 16/16、真实 admin 浏览器 18/18、固件编译通过（flash 62% / RAM 22%）。代码与固件均已部署/发布。

## 后续事项

- 线上已有自动化若仍是旧结构，读取时会自动迁移；用户重新保存后落库为 rules。
- **ESP 设备需在本地设置页手动点升级**到 `oled-4.2`（设备 autoUpdate 默认 false，服务端已发布但不会自动推），升级后新布局才在真机生效。
