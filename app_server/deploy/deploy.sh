#!/usr/bin/env bash
# app_server 部署脚本：从源码仓同步到 yuntu，并以 honghao 用户重启 pm2 进程。
# 规则：只改源码仓，不手改线上 server/；运行期配置只允许改 datas/app_update/server.config.json。
set -euo pipefail

REMOTE="${REMOTE:-honghao@143.203.52.132}"
REMOTE_DIR="${REMOTE_DIR:-/home/honghao/services/app_server}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"

echo "==> 目标 ${REMOTE}:${REMOTE_DIR}"

ssh "$REMOTE" "mkdir -p '${REMOTE_DIR}/server' '${REMOTE_DIR}/deploy' '${REMOTE_DIR}/build/web' \
  '${REMOTE_DIR}/datas/app_update' '${REMOTE_DIR}/uploads/tmp' '${REMOTE_DIR}/uploads/packages' \
  '${REMOTE_DIR}/logs' '${REMOTE_DIR}/backups' && chmod 700 '${REMOTE_DIR}/datas/app_update'"

echo "==> 同步 server/（排除运行期目录与 node_modules）"
rsync -az --delete \
  --exclude 'node_modules' \
  --exclude 'ecosystem.config.js' \
  --exclude 'deploy.sh' \
  --exclude 'datas' \
  --exclude 'uploads' \
  --exclude 'logs' \
  --exclude 'backups' \
  --exclude '*.bak-*' \
  "${SRC}/server/" "${REMOTE}:${REMOTE_DIR}/server/"

echo "==> 同步部署模板与前端"
rsync -az "${HERE}/ecosystem.config.js" "${REMOTE}:${REMOTE_DIR}/server/ecosystem.config.js"
rsync -az "${HERE}/deploy.sh" "${REMOTE}:${REMOTE_DIR}/server/deploy.sh"
rsync -az "${HERE}/server.config.example.json" "${REMOTE}:${REMOTE_DIR}/deploy/server.config.example.json"
rsync -az "${SRC}/web/admin.html" "${REMOTE}:${REMOTE_DIR}/build/web/admin.html"

echo "==> 安装依赖并重启 pm2"
ssh "$REMOTE" "cd '${REMOTE_DIR}/server' && \
  if [ -f package-lock.json ]; then npm ci --omit=dev --no-audit --no-fund; else npm install --omit=dev --no-audit --no-fund; fi && \
  (pm2 startOrReload ecosystem.config.js --update-env || pm2 start ecosystem.config.js) && pm2 save"

echo "==> 健康检查"
for i in 1 2 3 4 5 6 7 8 9 10; do
  if ssh "$REMOTE" "curl -fsS -m 3 http://127.0.0.1:47292/healthz" >/dev/null 2>&1; then
    echo "OK: /healthz 200"
    exit 0
  fi
  sleep 1
done

echo "WARN: /healthz 未在 10s 内通过，请查看 ${REMOTE_DIR}/logs/error.log" >&2
exit 1
