#!/usr/bin/env bash
# 服务端同步脚本，与 ecosystem.config.js 配套使用。
#
# 用法：
#   ./deploy.sh pull                 # 线上 -> 开发目录（回同步，恢复被线上手工改动的文件）
#   ./deploy.sh push <目标>           # 开发目录 -> 部署目标（本地路径或 user@host:/path）
#   LIVE_DIR=其它路径 ./deploy.sh pull
#
# 同步范围：
#   - 服务端源码与依赖：本目录（*.bak-* 线上备份不带）
#   - web 资源 admin.html / realtime.html：源在仓库 pscreen_server/web，部署到目标的 ../build/web
#     （index.html 线上被改成 7 字节占位，与仓库源不同，两个方向都不碰）
#   - datas/、uploads/ 是运行时用户数据，任何方向都不同步
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # server/server（同步源）
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"               # PotatokidClipboard
WEB_SRC="$REPO_ROOT/pscreen_server/web"
LIVE_DIR="${LIVE_DIR:-/home/honghao/services/tools/server}"
WEB_FILES=(admin.html realtime.html)

sync_service() { # $1=源目录 $2=目标目录
    if [[ "$2" != *:* ]]; then mkdir -p "$2"; fi # 远程目标由 rsync 建目录
    rsync -a \
        --exclude='*.bak-*' \
        --exclude='datas/' \
        --exclude='uploads/' \
        "$1/" "$2/"
}

sync_web() { # $1=web 源目录 $2=部署目标目录（其上级的 build/web）
    local dst="$2/../build/web"
    if [[ "$dst" != *:* ]]; then mkdir -p "$dst"; fi
    for f in "${WEB_FILES[@]}"; do
        [ -f "$1/$f" ] && rsync -a "$1/$f" "$dst/$f"
    done
}

case "${1:-}" in
    pull)
        sync_service "$LIVE_DIR" "$SCRIPT_DIR"
        sync_web "$LIVE_DIR/../build/web" "$LIVE_DIR"
        echo "✓ 已回同步：线上 $LIVE_DIR -> 开发 $SCRIPT_DIR"
        ;;
    push)
        dest="${2:?用法: $0 push <目标目录|user@host:/path>}"
        sync_service "$SCRIPT_DIR" "$dest"
        sync_web "$WEB_SRC" "$dest"
        echo "✓ 已同步到 $dest"
        echo "  启动：cd $dest && pm2 start ecosystem.config.js"
        echo "  已有同名 my-server 时必须先 pm2 delete my-server，否则 pm2 会把配置"
        echo "  （含 env）套到现有 app 上并重启它"
        ;;
    *)
        sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
