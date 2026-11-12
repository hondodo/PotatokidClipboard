# 项目长期记忆（potatokid_clipboard）

完整约定见项目根目录 `rules.md`，每次涉及部署前应先确认这些规则。

## 术语对照（用户口径，勿自行替换）

- home端 / 中控端 = `pscreen_home`
- tv端 = `potatokid_screen`（源码路径 `pscreen/potatokid_screen`）
- 本地服务 / 数据服务 = `pscreen_server/server`
- 应用服务 = `app_server`
- 本地部署 = `ssh 100.83.142.107`，部署在 `services/tools/`
- 远程部署 / yuntu部署 = `ssh yuntu`

## 部署铁律

- 所有服务用 **pm2** 管理进程。
- **必须先改源码，再部署到目标机器；绝不能直接修改部署机器里的文件**，否则源码与线上不同步、导致功能缺失或后续部署把改动覆盖掉。
- 查看线上代码可以 ssh 到目标机，但只用于排查，不作为修改入口。
- 环境差异：Windows 开发机上 `app_server` 在 yuntu、`pscreen_server` 在 100.83.142.107；Ubuntu 开发机上 `pscreen_server` 就在本机。

## app_server 部署到 yuntu 的实操要点（2026-11-12 踩坑）

- yuntu = `root@143.203.52.132`（SSH 配置里写的是 root，不是 honghao）。`honghao@143.203.52.132` 直连会被对端 reset，**不能直登**；部署必须 root 登录后再切 honghao。
- 正确姿势：`ssh yuntu`（root）→ 操作 pm2 用 `sudo -u honghao pm2 ...`（例如 `sudo -u honghao pm2 reload app-server`）。
- ⚠️ 坑：`pm2 -u honghao`（从 root 跑）会连到 **root 启动的那个指向 `/home/honghao/.pm2` 的空守护**，list 显示空、reload 不到真进程。真正管理 app-server 的是 **honghao 用户自己启动的 pm2 守护**（进程 ppid 是 honghao 的 God Daemon）。所以一定要用 `sudo -u honghao`，不是 `pm2 -u honghao`。
- 部署目录：`/home/honghao/services/app_server`，前端静态由 `web/` → 远程 `build/web/`（`webDir()` 优先读 build/web）。线上进程 app-server 以 honghao 身份运行。
- 本机（Windows Git Bash）**没有 rsync**，但有 ssh/scp。仅改静态文件时可直接 `scp` 两文件到 `/tmp`，再 `install -o honghao -g honghao -m 644` 落到 `build/web/`，属主保持 honghao，避免root 写入导致权限错位。
- 健康检查：业务端口 `127.0.0.1:47292/healthz`。

## pscreen_server 部署到 100.83.142.107（本地部署机）的实操要点（2026-11-12 踩坑）

- 登录用户**直接是 honghao**（与 yuntu 相反，无需 root、无需 sudo）。⚠️ 坑：非交互 ssh 的 PATH 没有 pm2，直接 `pm2` 会 command not found。正确姿势：`export PATH="$HOME/.npm-global/bin:$PATH"; export PM2_HOME=/home/honghao/.pm2` 再跑 pm2。
- 目标进程 `name=my-server`（fork 模式，cwd `/home/honghao/services/tools/server`，业务端口 `3000`）。fork 模式用 `pm2 restart my-server`（reload 等价 restart）。健康检查 `127.0.0.1:3000/healthz`。
- datas 真实目录 `/home/honghao/services/tools/datas`（server.js 内 `path.join(__dirname,'../datas')`）。账号文件在 `datas/register/users/<账号>`（存口令 MD5）与 `<账号>_info.txt`。
- `/tmp/pk_proxy_e2e` 的 node 进程（PPID=1，端口 3999）是 e2e 测试代理，**不在 pm2 管理内**，pm2 restart 不会影响它，勿误判为漏重启。
- **部署对齐**：本地 Windows 是 CRLF、部署机 Linux 是 LF，直接 `diff -u` 会显示整文件 hunk 假差异；务必用 `diff --strip-trailing-cr` 重算实质差异，避免把"换行符不同"误判成"要整文件覆盖"。
- **契约同步铁律**：改了客户端 API 契约（如 claim 从"服务端随机口令"改为"用户自设口令"）必须同步部署服务端，否则新旧错配（已两次踩坑：只修数据会被旧服务端代码再次覆盖）。家长号双凭据新服务端涉及 `admin.js`/`claims.js`/`realtime.js` 三文件（`server.js`/`accounts.js` 与线上零差异不用动）。
- **档案共享服务端已部署并端到端验证（2026-11-12，用户授权后执行，Task #41 完成）**：同步 `admin.js`（md5 765b3aeb）+ 新增 `parental_share.js`（修复后 md5 27b6a5c5）到 `/home/honghao/services/tools/server/`，`pm2 restart my-server`（pid 2746075→2760602）。备份在 `server/.deploy-backup-2026-11-12T07-31-16-51185580Z/`（旧 admin.js md5 a5dd3962 + machines.json md5 60d2f42a）。4 接口上线：`PUT /api/admin/parental/share-to`、`POST/DELETE /api/admin/parental/shared`、`GET /api/admin/parental/shared-view`；overview 每台电视注入 `parentalShareView`（线上 8 台电视命中）；题库 GET 回源主本+readOnly、PUT 护栏 403；时长按 `durationAnchorKey` 归主本。
- **档案共享 resolveRef 同账号 bug（本轮端到端抓到并修复）**：`parental_share.js` 的 `resolveRef` 展开引用时**只认 `child.sharedTo` 白名单**，漏了「同一家长号名下其它电视默认可见」，而写入(admin.js POST shared)与候选(buildShareView)都用 `source.parents.includes(viewer)` 判 same-account，三处口径不一致 → 同账号引用一落地就被误判 `broken/not-shared-to-viewer`（真机 m10s 引用糖果电视必现）。修复：`resolveRef` 可见性判定对齐——viewer 在 `source.parents`（same-account）**或**在 `child.sharedTo` 白名单，任一即 ok；补回归测试（`parental_share_test.js` 24 项）。**经验：可见性判定这类多入口逻辑，写入/候选/展开三处必须用同一函数或口径，否则端到端才暴露。**
- **端到端验证方式（可复用）**：家长端管理接口鉴权=`POST /api/admin/login {username,password}` 拿 `pk_admin` cookie（SESSION_COOKIE，HMAC 签名），再带 cookie 调。m10s 明文口令 `12345678`（存 MD5 25d55ad2）。测试写操作务必 `trap` 还原 machines.json；**注意 machines.json 会被真实设备心跳持续写 lastSeen，md5 与备份不同≠测试残留，先跑 `/tmp/verify_clean.js` 查 sharedTo/shared 是否真有残留，绝不能盲目 cp 备份覆盖回滚真实在线状态**。清理走接口（DELETE shared + PUT share-to sharedTo:[]），不要直接改文件。
- **真机验证档案共享（USB R58M349S90M）**：跨设备登录 m10s 成功→我的页显示家长号 m10s/我的电视 2 台；档案共享页四区齐全（本台主本「糖果」分享设置、引用进来「测试1」只读、同账号跨电视引用、其他家长分享给我）；真机点「+引用」把棠德304「测试1」引到红米笔记本→回显「引用自 home94755b3b2fc1b1ee·棠德304电视·只读」+toast，线上落盘确认；真机「分享设置」填 grandpa99 保存→主本卡变「已分享给 grandpa99」+线上落盘。测试数据已全部清理（CLEAN 无残留）。截图 `.workbuddy/screenshots/pk_e2e_*.png`。
- **跨设备登录返回不刷新——已修复（原体验瑕疵）**：账号卡 `onEditAccount` 走 GoRouter `context.push(claimAccountPath)`，不经 `ParentalPage._push()`（只有 `_push` 才在子页 pop 后补拉），故身份页登录 m10s 后返回仍显示"未设置/0台"。修复：`parental_page.dart` 新增 `_openIdentityAndRefresh()`——push 身份页返回后无条件 `_loadMyAccount()` + `_reload()`（`_reload` 会用新账号 ensureAdminSession 重建会话、按新号过滤电视），934 行改挂它。真机回归通过（pm clear 回未设置态→登录 m10s→直接返回不点刷新→我的页自动显示 m10s/2台，截图 pk_fix_return.png）。
- **parent APK 构建必须带两个参数**：`flutter build apk --debug --flavor parent --dart-define=APP_FLAVOR=parent`（见 `pscreen_home/FLAVORS.md`）。只给 `--flavor parent` 漏 dart-define 会产出"Android 层 parent 浅色状态栏 + Dart 层 board 黑色 HA 页"的混合包（`AppFlavorConfig.raw` 缺省 board）。flavor 判定：Android 原生层按 `packageName`（board=`potatokid.tools.homecontroller`/parent 以 `.parent` 结尾），Dart 层按 dart-define；两者必须一致。**board 中控端状态栏/底栏未受家长端浅色修复影响**：board 走沉浸全屏隐藏系统栏，浅色 styles 只在 `src/parent/res` 源集。
- **USB 机测试设备当前状态**：R58M349S90M 的家长端本地已登录 `m10s`（跨设备登录验证留下），显示 2 台电视；如需还原为干净派生号，在身份页清家长号。无线机 192.168.70.14:39475 仍无法注入点击（INJECT_EVENTS 权限），只能截图。Git Bash 下 adb 操作设备路径必须加 `MSYS_NO_PATHCONV=1`，否则 `/sdcard/...` 被误转成 Windows 本地路径。另：**adb install/pull 的本地 APK 路径必须给 Windows 反斜杠**（`E:\...`），给 `/e/...` 会 stat 失败却仍打印 "Performing Streamed Install" 装着旧包，务必读到 `Success` 才算装上。
- **「我的」页目标设备切换联动（2026-11-12）**：`parental_mine_tab.dart` 顶部按 `selected`（当前配置目标电视）组织，点「我的电视」某行**名字**即切换目标（避开右侧遥控/改名/可见性图标）。下方「档案共享」「解锁方式」都跟随 `selected` 联动——**解锁方式是外置组件 `presentation/parental_unlock_section.dart`（4 说明卡：远程确认/PIN/算术题/答题解锁，选中态浅绿+「当前」标签、点选即生效、PIN 就地展开、答题解锁空题库就地「管理题库」入口），顶部 chip + 浅绿提示卡会标注目标电视名**。因此设备名在页面上会多处出现（电视行 chip + 解锁方式 chip/提示卡），写 widget 测试断言设备名要用 `findsWidgets` 而非 `findsOneWidget`。`ParentalSettingsSection` 仍被规则页 `ParentalRulesSettingsPage` 使用，非死代码。交互变更前先同步 `docs/parent-app-redesign-prototype.html`（支持 `?page=mine&tv=<index>` 截图）。
