# 项目术语与部署约定

## 术语对照

| 日常称呼 | 实际指向 |
| --- | --- |
| home端 / 中控端 | `pscreen_home` |
| tv端 | `potatokid_screen`（源码在 `pscreen/potatokid_screen`） |
| 本地服务 / 数据服务 | `pscreen_server/server` |
| 应用服务 | `app_server` |
| 本地部署 | `ssh 100.83.142.107` 这台机，部署目录 `services/tools/` |
| 远程部署 / yuntu部署 | `ssh yuntu` 这台机 |

## 部署规则

- 进程管理统一使用 **pm2**。
- **必须先改源码，再部署到目标机器**。禁止直接修改部署机器里的文件，否则源码与部署代码不同步，会导致功能缺失。

## ⚠️ yuntu / honghao 连接与 pm2 操作注意（极易踩坑，先读这段）

**背景**：app_server 部署在 yuntu（`root@143.203.52.132`）。SSH 配置里 `Host yuntu` 的 `User` 是 **root**，不是 honghao。

- **`honghao@143.203.52.132` 不能直接 SSH 登录**（对端会 `Connection reset by peer`）。所有操作必须先 `ssh yuntu`（root 登录），再切到 honghao。
- **pm2 最坑的一点**：远程 `/home/honghao/.pm2` 下其实并存**两个**守护进程——
  1. 由 **root** 启动的（执行 `pm2 -u honghao` 从 root 跑时连到的就是它）——它是**空的**，list 显示空、reload 不到任何进程；
  2. 由 **honghao 用户**自己启动的——这才是真正在管 `app-server`（pid 属主 honghao）的那个。
  - 所以：**不要用 `pm2 -u honghao`（root 下执行）**，那样连错守护、白忙活一天都查不出原因。正确写法是 **`sudo -u honghao pm2 <命令>`**（例如 `sudo -u honghao pm2 reload app-server` / `sudo -u honghao pm2 list`）。
- 部署目录：`/home/honghao/services/app_server`；前端静态由源码 `web/` → 远程 `build/web/`（`webDir()` 优先读 build/web），文件属主必须是 honghao。
- 本机（Windows Git Bash）**没有 rsync**，但有 `ssh` / `scp`。仅改静态文件时可：`scp` 到 `/tmp` → `install -o honghao -g honghao -m 644` 落到 `build/web/`，保持属主为 honghao，避免 root 写入导致权限错位。
- 健康检查：业务端口 `127.0.0.1:47292/healthz`（返回 200 即通过）。
- `deploy/deploy.sh` 默认 `REMOTE=honghao@143.203.52.132` 直连，在本机直连不通；如需用它，要先改成经 root 跳板再切 honghao，或手动按上面的方式同步。

## 环境相关的部署位置（原有记录）

如果当前在windows这台机：
app_server 在ssh yuntu  ；pscreen_server 服务在 ssh 100.83.142.107 (honghao@honghao-MacBookPro12-1:~/services/tools$) 如果需要查看可在这两台机看，但必须保证在源代码里修改再部署，不能直接在部署目录修改导致代码不同步。它们都是pm2
如果当前在ubuntu这台机：
app_server 在ssh yuntu  ；pscreen_server 服务在当前ubuntu这台机 (honghao@honghao-MacBookPro12-1:~/services/tools$) 如果需要查看可在这两台机看，但必须保证在源代码里修改再部署，不能直接在部署目录修改导致代码不同步。它们都是pm2