# 云端 relay 运维手册（HLS 中转服务）


端口假设是 ABCD

服务端脚本：`/root/relay.py`（Python3 标准库，无需 pip）
监听端口：`ABCD`（高位随机端口，防扫描）
App 侧引用：根目录 `.env` 的 `REPLY_SOURCE`（读取见 `AppConfig.relaySource`）

---

## 1. 云端重启后启动服务

```bash
nohup python3 /root/relay.py > /var/log/relay.log 2>&1 &
```

验证已启动：

```bash
# 进程在不在
ps aux | grep relay.py | grep -v grep

# 端口在不在监听
ss -lntp | grep ABCD
```

> 注意：`nohup` 启动的进程重启机器后不会自愈，**每次云机重启都要重新执行上面的启动命令**。
> 如需开机自启，可加 systemd 服务（可选，见第 5 节）。

---

## 2. 修改 TOKEN

**2.1 编辑文件**（改第 12 行 `TOKEN` 的值）：

```bash
vi /root/relay.py
# 或 nano /root/relay.py
```

```python
TOKEN = "你的新随机串"   # 改这里
```

生成随机串的方法（本机 PowerShell 或云端 bash 均可）：

```bash
python3 -c "import secrets; print(secrets.token_hex(16))"
```

**2.2 重启服务生效**（改 TOKEN 必须重启）：

```bash
# 找到旧进程 PID 并杀掉
ps aux | grep relay.py | grep -v grep
kill <旧PID>

# 重新启动
nohup python3 /root/relay.py > /var/log/relay.log 2>&1 &
```

**2.3 App 侧同步改**：根目录 `.env` 中 `REPLY_SOURCE` 的 `t=` 参数改成同一个新值，然后**完整重跑 App**（非热重载）。

> TOKEN 不匹配时服务返回 403，App 表现为打不开该源。

---

## 3. 日常验证（云端 curl 三级检查）

```bash
# ① 主列表
curl -s "http://127.0.0.1:ABCD/play.m3u8?t=<TOKEN>&src=http%3A%2F%2Fr.jdshipin.com%2FCkuBd"
# 预期：#EXTM3U + EXT-X-STREAM-INF + 一条 http://xxx.xx.xx.xx:ABCD/fetch?... 地址

# ② 子列表（把①输出的完整 fetch 地址直接粘过来执行）
curl -s "<①输出的fetch地址>"
# 预期：#EXTM3U + 若干条已改写为 relay /fetch 的分片地址

# ③ 分片下载（把②输出的一条完整分片地址粘过来）
curl -s -o /tmp/seg.ts -w "code=%{http_code} size=%{size_download}\n" "<②里的分片地址>"
# 预期：code=200，size 为几百KB~几MB
```

实时观察访问日志：

```bash
tail -f /var/log/relay.log
```

---

## 4. 排错速查

| 现象 | 原因 | 处理 |
|---|---|---|
| curl 空输出 / Connection refused | 服务没起 | `ps aux \| grep relay`、`cat /var/log/relay.log` |
| HTTP 403 | TOKEN 不匹配 | 按第 2 节改 TOKEN 并重启，App 侧同步 |
| HTTP 502 | relay 抓上游失败（源站不通/超时） | `curl -I --max-time 8 "<原始src>"` 直连测源是否活着 |
| 日志里 `Address already in use` | 端口被占（旧进程没杀干净） | `ss -lntp \| grep ABCD` 找 PID 后 kill |
| App 播放失败 | 先确认 curl 三级验证能通过 | 通过则查 App 日志 `播放频道:...ABCD/play.m3u8` 改写是否生效 |
| 播几十秒后卡住 | 子列表/分片某层没改写或上游限速 | 看 `relay.log` 里该 IP 的 `/fetch` 是否持续、返回码 |

---

## 5.（可选）配置开机自启，重启后免手动执行

```bash
cat > /etc/systemd/system/relay.service << 'EOF'
[Unit]
Description=HLS relay
After=network.target

[Service]
ExecStart=/usr/bin/python3 /root/relay.py
Restart=always
WorkingDirectory=/root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now relay

# 之后的启停/状态：
systemctl status relay
systemctl restart relay    # 改 TOKEN 后用这条重启
journalctl -u relay -f     # 看日志（此时日志不在 /var/log/relay.log）
```

> 用 systemd 后启动方式变为 `systemctl start relay`，`nohup` 方式与 systemd 二选一，不要混用。

---

## 6. 安全建议

- **TOKEN**：使用 `secrets.token_hex(16)` 生成的 32 位随机串，不用弱口令
- **安全组**：ABCD 入站尽量限制源 IP（你的宽带出口 IP）；宽带 IP 变更时更新规则
- **测试结束后**：不需要长期开放时，安全组关掉 ABCD，或 `systemctl stop relay` / `kill <PID>` 停服务
- 端口已用 ABCD 高位端口，避免常见端口扫描；不要改回 8080 等易猜端口

---

## 7. 停用中转（App 侧改回直连）

中转走 `.env` 的 `REPLY_SOURCE` 配置（`AppConfig.relaySource`），无临时测试代码。

1. 把根目录 `.env` 里的 `REPLY_SOURCE=` 清空（留空 = 直连播放）
2. **完整重跑 App**（非热重载，`.env` 改动需重新打包资产）



复制文件
scp "E:\Code\potatokid_clipboard\pscreen\potatokid_screen\relay_upload.py" xxx@xxxxxxx:~/relay.py
关闭并重启
pkill -f "python3 relay.py"; cd ~ && nohup python3 relay.py >> relay.log 2>&1 &
查看日志
tail -f ~/relay.log

grep -E "会话创建|淘汰最旧" ~/relay.log | tail -20

查看有多少ffmpeg进程
ps -ef | grep [f]fmpeg
