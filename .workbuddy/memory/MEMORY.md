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
