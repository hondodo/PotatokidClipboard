# app_server（Potatokid 应用分发 / 更新服务）

部署在 yuntu（Debian 12，`143.203.52.132`）的独立服务：公网业务端口 **47292**（客户端查询/下载/健康检查），管理端口 **47293**（管理页与 `/api/admin/*`）。完整方案见 [PLAN.md](./PLAN.md)。

当前进度：**阶段 0（骨架与数据模型）+ 阶段 1（管理登录与应用 CRUD）已完成**；阶段 2 的分片上传、版本发布/强更/回滚、空间自适应清理尚未实现（接口占位返回 `implemented=false`）。

## 1. 目录结构

仓库（`PotatokidClipboard/app_server/`）：

```text
app_server/
├── PLAN.md
├── README.md
├── .gitignore
├── server/                 # 源码（部署到线上 server/，含 node_modules）
│   ├── server.js           # 启动：47292 业务 + 47293 管理，健康检查
│   ├── config.js           # 读取 datas/app_update/server.config.json
│   ├── store.js            # JSON 原子写 + 串行锁 + applications/releases/latest
│   ├── security.js         # scrypt、Cookie 签名、密码策略、登录限流
│   ├── audit.js            # datas/app_update/audit.jsonl
│   ├── apps.js             # 应用 CRUD 路由
│   ├── admin.js            # 登录/会话/改密/下线/维护占位 + 管理页路由
│   ├── apiutil.js          # 响应封装、错误处理、CSRF、磁盘工具
│   └── package.json        # express@5 + cookie-parser
├── web/admin.html          # 单文件管理页（暗色，相对路径 fetch）
└── deploy/
    ├── deploy.sh           # rsync 部署 + 远端 npm install + pm2 reload
    ├── ecosystem.config.js # pm2 进程配置（app-server，384MB 堆上限）
    └── server.config.example.json
```

线上（`/home/honghao/services/app_server/`）：

```text
server/           源码 + node_modules（由 deploy.sh 同步）
build/web/        admin.html
deploy/           server.config.example.json
datas/
└── app_update/
    ├── db.json                 0600  应用/版本/最新指针/管理员
    ├── server.config.json      0600  运行期配置
    ├── secret.key              0600  Cookie 与下载签名密钥
    ├── audit.jsonl             0600  审计日志
    └── initial_admin_password.txt  0600（仅首启生成，改密后自动删除）
uploads/{packages,tmp}           安装包与分片临时目录
logs/{out,error}.log             pm2 日志
backups/                         预留
```

## 2. 部署（先改源码再部署）

规则：**只改仓库源码，再执行 `deploy.sh`；不要在线上手改 `server/` 或 `build/web/`。** 唯一允许线上直接修改的是 `datas/app_update/server.config.json`（运行期配置，不入 git，部署脚本也排除）。

```bash
# 在仓库 app_server/ 下
chmod +x deploy/deploy.sh
./deploy/deploy.sh
# 可覆盖目标：REMOTE=honghao@1.2.3.4 REMOTE_DIR=/path ./deploy/deploy.sh
```

脚本行为：

1. 远端创建 `server/ deploy/ build/web/ datas/app_update/ uploads/{tmp,packages} logs/ backups/`；
2. `rsync -az --delete` 同步 `server/`（排除 `node_modules`、`datas/`、`uploads/`、`logs/`、`backups/`、`*.bak-*`）；
3. 同步 `admin.html`、`ecosystem.config.js`、`deploy.sh`、`server.config.example.json`；
4. 远端 `cd server && npm install --omit=dev`（有 `package-lock.json` 时用 `npm ci`）；
5. `pm2 startOrReload ecosystem.config.js --update-env && pm2 save`；
6. 远端 `curl 127.0.0.1:47292/healthz` 轮询确认 200。

前置条件：本地能 `ssh honghao@143.203.52.132` 免密登录（该用户已加入 root 的 `authorized_keys`），远端已装 Node 22 + pm2。

首次部署后，在 yuntu 以 honghao 用户注册 pm2 开机自启（只需一次）：

```bash
pm2 startup systemd -u honghao --hp /home/honghao   # root 执行，按输出复制命令
systemctl enable pm2-honghao && systemctl status pm2-honghao
```

若 `systemctl start pm2-honghao` 报 `Can't open PID file .../pm2.pid`（手工启动的 pm2 daemon 已存在），按顺序执行一次即可交给 systemd：

```bash
su - honghao -c 'pm2 kill'      # 会短暂停止所有 pm2 应用
systemctl start pm2-honghao     # 由 systemd 拉起 daemon 并 resurrect 进程列表
systemctl is-active pm2-honghao
```

## 3. 首次启动与管理员密码

- 首次启动自动生成 `datas/app_update/{server.config.json,secret.key,db.json,audit.jsonl}`（0600）。
- 初始管理员用户名取 `server.config.json` 的 `adminUsername`（默认 `honghao`），初始密码随机生成，**只写入 `datas/app_update/initial_admin_password.txt`（0600）**，不入库、不入仓库。
- 首登会返回 `mustChangePassword=true`，除 `/me`、`/password`、`/logout` 外的管理接口一律 `403 / 400010`；改密成功后该文件自动删除、所有会话失效。
- 密码策略：最少 6 位、最多 64 位（`password.minLength` / `password.maxLength` 可配置，默认 6/64）；不强制字符类别，仅禁止纯空白与和用户名相同。初始密码为随机 18 位。

```bash
ssh honghao@143.203.52.132
sudo cat /home/honghao/services/app_server/datas/app_update/initial_admin_password.txt
```

## 4. 运行期配置

`datas/app_update/server.config.json`（模板：`deploy/server.config.example.json`）。关键字段：

| 字段 | 当前值 | 说明 |
|---|---|---|
| `port` / `adminPort` | 47292 / 47293 | 业务 / 管理端口 |
| `adminBind` | `0.0.0.0` | 管理端口绑定 |
| `publicBaseUrl` | `http://143.203.52.132:47292` | 生成下载 URL 的对外根地址（换 IP/端口只改这里） |
| `adminUsername` | `honghao` | 唯一管理员 |
| `admin.sessionHours` | 12 | Cookie 绝对有效期 |
| `admin.cookieSecure` | false | 上 HTTPS 后改 true |
| `admin.lockMinutes` | 30 | 登录失败锁定 |
| `admin.ipAllowlist` | `[]` | 动态 IP，不启用白名单 |
| `password.minLength` / `password.maxLength` | 6 / 64 | 密码长度范围（不强制字符类别） |
| `apiKey` | 自动生成 48 位 hex | 本地 server 调用凭证（阶段 3 使用） |
| `storageRoot` / `tmpDir` | uploads 下 | 安装包 / 分片目录 |
| `maxUploadBytes` | 1GiB | 单包上限（阶段 2 生效） |
| `retention.cleanupTargetFreeBytes` | 1.5GiB | 低于此值清理 archived（阶段 2） |
| `https.enabled` | false | 预留开关 |

本地调试：用 `APP_SERVER_ROOT=/tmp/appserver-local node server.js` 指定数据根目录，并自行准备该目录下 `datas/app_update/server.config.json`（示例中的 `/home/honghao/...` 路径仅适用于 yuntu）。

## 5. 运维命令

```bash
pm2 status
pm2 logs app-server --lines 100
pm2 restart app-server
tail -f /home/honghao/services/app_server/logs/error.log
curl -s http://127.0.0.1:47292/healthz
```

健康检查（无需鉴权，业务端口）：`GET /healthz` 与 `GET /api/health`，返回

```json
{"code":0,"msg":"ok","data":{"ok":true,"uptime":123,"diskFreeBytes":6000000000,
 "diskLow":false,"storageBytes":0,"maxStorageBytes":4294967296,
 "applications":1,"releases":0,"version":"0.1.0"}}
```

## 6. 阶段 0/1 已实现接口

统一响应 `{code,msg,data}`，成功 `code=0`；管理接口要求会话 Cookie `pk_app_admin`，写操作要求 `X-Admin-Request: 1`。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/healthz`、`/api/health` | 健康检查（业务端口，无鉴权） |
| GET | `/admin` | 管理页（仅管理端口） |
| POST | `/api/admin/login` | `{username,password}`，成功后 Set-Cookie（httpOnly/SameSite=Strict/12h） |
| POST | `/api/admin/logout` | 清 Cookie |
| GET | `/api/admin/me` | 会话信息 + `mustChangePassword` |
| PUT | `/api/admin/password` | `{currentPassword,newPassword}`，改密后全部会话失效 |
| POST | `/api/admin/sessions/revoke` | 强制下线全部会话 |
| GET | `/api/admin/apps` | 应用列表 + 各平台 latest 摘要 |
| POST | `/api/admin/apps` | 创建应用 `{appId,name,description,platforms[]}` |
| GET | `/api/admin/apps/:appId` | 应用详情 + latest + 版本记录 |
| PUT | `/api/admin/apps/:appId` | 改名/说明/平台/启停 |
| DELETE | `/api/admin/apps/:appId` | 有版本记录时拒绝（返回 300011），请改用停用 |
| GET | `/api/admin/maintenance/status` | 磁盘/容量/归档统计 |
| POST | `/api/admin/maintenance/cleanup` | 占位，返回 `implemented=false` |

数据层（`store.js`）已实现 `applications`、`releases`、`latest`（`appId → platform → releaseId`）读写，以及：
`build` 正整数、同 `app+platform` 唯一（`300002`）、发布时 `build > latest.build`（`300003`，`rollback` 例外）、`version` 格式校验、**`pubspec +N == build` 必须显式确认**（`pubspecBuildConfirmed` 字段，未确认拒绝）。上传/发布路由在阶段 2 接入。

### 错误码

沿用 PLAN 4.1；本阶段新增（实现细节所需）：

| code | HTTP | 含义 |
|---|---|---|
| 400005 | 200 | 参数校验失败（appId/version/build/密码等） |
| 400010 | 403 | 首次登录未改密，其余管理接口被限制 |
| 300010 | 200 | appId 已存在 |
| 300011 | 200 | 应用已有版本记录，禁止删除 |
| 500000 | 500 | 服务器内部错误 |

## 7. 安全说明

- 管理面公网 HTTP（无域名/证书，`https.enabled=false`）：靠 ≥6 位密码 + scrypt、12h 单点会话、双维度失败限流（同 IP 5 次/15 分钟、同账号 10 次/60 分钟、锁 30 分钟）、写操作 `X-Admin-Request` + Origin 校验、二次确认与 `audit.jsonl` 审计。
- **风险说明**：管理页是公网 HTTP 明文传输入口，短密码（最低 6 位）的安全性主要依赖登录失败限流兜底，建议实际使用 **8～10 位以上**；上 HTTPS 前不要把弱口令用于该入口。
- **不启用 IP 白名单**（运营商动态 IP），`admin.ipAllowlist` 仅为预留字段。
- yuntu 上**未启用 ufw**：该机为容器化环境，且 Docker 发布端口可能绕过 ufw；端口放行以云安全组为主（需放行 47292/47293。管理端口建议在安全组按来源收窄，但动态 IP 场景下主要依赖应用层认证）。
- 未改动 yuntu 既有服务（22/12345/47291/80/443/3478）与本地 `pscreen_server`。
- 审计文件 `audit.jsonl` 记录登录成功/失败/锁定、应用创建/修改/删除、改密、强制下线、手动清理意图。

## 8. 阶段 2 待办

1. `uploads.js`：分片 init/chunk/status/complete，8MiB 分片、流式合并 + sha256、扩展名白名单、预检磁盘。
2. `releases.js`：iOS 外部链接录入、发布/强更/回滚路由，接 `store.publishRelease`。
3. `cleanup.js`：每小时磁盘检查（<1.5GiB 清理 archived、<1GiB 停上传）、保留 1 个 previous、`logs/cleanup.log` 与审计。
4. `web/admin.html`：上传表单、断点续传、版本表操作按钮、统计。
