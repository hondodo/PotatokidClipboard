这是部署在云途的应用管理说明：
背景：由于本地的 /pscreen_server （部署在 /home/honghao/services/tools） 使用的路由侠只有1G流量，并不适合用来做应用更新，所以接到云途，待路由侠后面需要开通流量后再接回

## 阶段 2 已实现（v0.2.0）

- 管理端（47293，需登录 + `X-Admin-Request: 1`）：
  - `POST /api/admin/uploads/init` / `GET /api/admin/uploads/:uploadId` / `PUT /api/admin/uploads/:uploadId/chunks/:index` / `POST /api/admin/uploads/:uploadId/complete` / `DELETE /api/admin/uploads/:uploadId`
  - `POST /api/admin/releases`（仅 iOS 外部链接）、`PUT /api/admin/releases/:id`、`POST /api/admin/releases/:id/publish`、`POST /api/admin/releases/:id/rollback`、`DELETE /api/admin/releases/:id`
  - `GET /api/admin/apps/:appId/releases`、`GET|POST /api/admin/maintenance/*`（cleanup 默认 `dryRun=true`）
- 业务端（47292，需 `X-API-Key`）：`GET /api/update/check`（别名 `GET /api/apps/:appId/update`）返回 `hasUpdate/forceUpdate/latest/download`；`GET|HEAD /api/download/:releaseId?exp=&sig=` 支持 Range/206。
- 空间自适应清理：每小时检查，可用 <1.5GiB 时按 archivedAt 升序清理、<1GiB 停上传；`keepPrevious=1`；日志 `logs/cleanup.log` + `audit.jsonl(action=cleanup)`。

## 阶段 3 已实现（多账号 + 三角色 + 文件镜像）

- 账号与角色：`admin`（账号/临时口令）、`apps`（应用/版本/上传/发布/回滚/清理）、`files`（镜像文件查看/下载/删除）；接口越权返回 `403 400011`。
- 页面：`/admin` 账号管理、`/apps` 应用管理、`/files` 文件管理，`/` 按角色跳转或给出三入口；登录态 Cookie `pk_app_admin`，临时口令 Cookie `pk_app_viewer`。
- 临时访问口令：scope `files:read` / `apps:read`，TTL 10 分钟～7 天（默认 24 小时），可一次性、可吊销，仅只读（写操作 `400012`）。
- 文件镜像（业务端口 47292，`X-Service-Token`）：`POST /api/files/mirror`（multipart 字段 `file` 或原始 body，`X-File-Name` / `X-Origin-Server` / `X-Origin-Path` 支持 URL 编码）；存储 `uploads/mirror/<yyyymmdd>/<id>_<name>`；总量 1GiB 按 `createdAt` 最旧优先淘汰，只作用于镜像目录；日志 `logs/files.log`，审计 `file_mirror|file_delete|file_cleanup`。
- 管理接口（`files` 角色）：`GET /api/admin/files/list`、`GET /api/admin/files/usage`、`GET|HEAD /api/admin/files/:id/download`（支持 Range）、`DELETE /api/admin/files/:id`。

## 源码与部署（重要）

- **源码唯一保存在 `100.83.142.107:/home/honghao/codes/PotatokidClipboard/app_server`（git 仓库），yuntu 上不保存源码副本。**
- 运行数据不在 git：`datas/`（db.json、server.config.json、secret.key、audit.jsonl）、`uploads/`、`logs/`、`backups/`、`node_modules/` 均已被 `.gitignore` 忽略，换机后需由服务首次启动生成或从备份恢复。
- 换机恢复步骤：
  1. `git clone git@github.com:hondodo/PotatokidClipboard.git`
  2. 在 yuntu 上准备运行目录 `/home/honghao/services/app_server`（无需源码）
  3. 执行 `bash app_server/deploy/deploy.sh`（rsync 到 yuntu 运行目录并重启 pm2）
  4. 远端 `cd /home/honghao/services/app_server/server && npm ci --omit=dev`
  5. `pm2 startOrReload ecosystem.config.js --update-env && pm2 save`
  6. `curl -fsS http://127.0.0.1:47292/healthz` 返回 200
- 部署脚本默认目标 `honghao@143.203.52.132:/home/honghao/services/app_server`，可用环境变量 `REMOTE` / `REMOTE_DIR` 覆盖；运行期只改 `datas/app_update/server.config.json`。
- 阶段 3 首次启动会把旧版单管理员迁移为 `accounts[]`（`honghao` 获得 `admin/apps/files`），并自动生成 `files.serviceToken` 写入配置（权限 0600）。

