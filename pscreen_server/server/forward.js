// 上传文件镜像转发：本地落盘成功后再异步转发到公网 yuntu 文件服务
// （POST /api/files/mirror），供外部直接下载，绕开 Tailscale/路由侠的带宽限制。
//
// 设计要点：
// - 转发 fire-and-forget：任何异常都不影响原上传接口的响应；
// - 配置每次转发时重新读取 ../datas/forward_config.json（改地址/端口/令牌免重启）；
// - 记录写 ../datas/forward_log.jsonl，按 10MiB 或 2 万行滚动；
// - 不新增第三方依赖：multipart 用 Node 内置 http/https 手工流式拼装。

const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');
const crypto = require('crypto');
const os = require('os');

const CONFIG_FILE = 'forward_config.json';
const LOG_FILE = 'forward_log.jsonl';
const LOG_MAX_BYTES = 10 * 1024 * 1024;
const LOG_MAX_LINES = 20000;
const STATUS_RECENT_LIMIT = 100;
const RESPONSE_MAX_BYTES = 256 * 1024;

const DEFAULT_CONFIG = {
    enabled: true,
    baseUrl: 'http://143.203.52.132:47292',
    serviceToken: '',
    timeoutMs: 30000,
    retries: 2,
    excludePatterns: [],
    originServer: '',
};

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

/** 通配符（* / ?）转正则；无通配符时按整段路径匹配。 */
function globToRegExp(pattern) {
    let source = '';
    for (const ch of String(pattern || '')) {
        if (ch === '*') source += '.*';
        else if (ch === '?') source += '.';
        else source += ch.replace(/[.+^${}()|[\]\\]/g, '\\$&');
    }
    return new RegExp(`^${source}$`);
}

/** 头里放相对路径：保留 / 分隔，逐段 URL 编码，保证纯 ASCII。 */
function encodeHeaderPath(value) {
    return String(value || '')
        .split('/')
        .map((segment) => encodeURIComponent(segment))
        .join('/');
}

function createForwarder(options = {}) {
    const datasDir = path.resolve(options.datasDir);
    const configPath = path.join(datasDir, CONFIG_FILE);
    const logPath = path.join(datasDir, LOG_FILE);
    const hostName = String(options.originServer || os.hostname() || 'potatokid-server').trim();

    let inflight = 0;
    let logLineCount = -1; // -1 = 尚未统计，首次用到时读文件计算

    // ------------------------------------------------------------ 配置

    function writeConfigTemplate() {
        const template = {
            enabled: DEFAULT_CONFIG.enabled,
            baseUrl: DEFAULT_CONFIG.baseUrl,
            serviceToken: DEFAULT_CONFIG.serviceToken,
            timeoutMs: DEFAULT_CONFIG.timeoutMs,
            retries: DEFAULT_CONFIG.retries,
            excludePatterns: DEFAULT_CONFIG.excludePatterns,
            originServer: hostName,
        };
        fs.mkdirSync(datasDir, { recursive: true });
        fs.writeFileSync(configPath, `${JSON.stringify(template, null, 2)}\n`, {
            encoding: 'utf8',
            mode: 0o600,
        });
        console.log(`[forward] 已生成转发配置模板: ${configPath}`);
    }

    function ensureConfigFile() {
        if (!fs.existsSync(configPath)) {
            try {
                writeConfigTemplate();
            } catch (error) {
                console.error('[forward] 生成配置文件失败:', error.message);
            }
        }
    }

    function normalizeConfig(raw) {
        const value = raw && typeof raw === 'object' ? raw : {};
        const timeout = Number(value.timeoutMs);
        const retries = Number(value.retries);
        return {
            enabled: value.enabled === undefined ? DEFAULT_CONFIG.enabled : Boolean(value.enabled),
            baseUrl: typeof value.baseUrl === 'string' && value.baseUrl.trim()
                ? value.baseUrl.trim().replace(/\/+$/, '')
                : DEFAULT_CONFIG.baseUrl,
            serviceToken: typeof value.serviceToken === 'string' ? value.serviceToken.trim() : '',
            timeoutMs: Number.isFinite(timeout)
                ? Math.min(Math.max(Math.floor(timeout), 1000), 600000)
                : DEFAULT_CONFIG.timeoutMs,
            retries: Number.isFinite(retries)
                ? Math.min(Math.max(Math.floor(retries), 0), 10)
                : DEFAULT_CONFIG.retries,
            excludePatterns: Array.isArray(value.excludePatterns)
                ? value.excludePatterns
                    .filter((item) => typeof item === 'string' && item.trim())
                    .map((item) => item.trim())
                : [],
            originServer: typeof value.originServer === 'string' && value.originServer.trim()
                ? value.originServer.trim()
                : hostName,
        };
    }

    /** 每次转发 / 查询状态都重新读取，保证地址、端口、令牌热生效。 */
    function readConfig() {
        ensureConfigFile();
        try {
            return normalizeConfig(JSON.parse(fs.readFileSync(configPath, 'utf8')));
        } catch (error) {
            console.warn('[forward] 读取配置失败，使用内置默认值:', error.message);
            return normalizeConfig({});
        }
    }

    function isExcluded(originPath, patterns) {
        if (!patterns || !patterns.length) return false;
        const value = String(originPath || '').replace(/\\/g, '/');
        const base = path.basename(value);
        return patterns.some((pattern) => {
            try {
                const reg = globToRegExp(pattern);
                return reg.test(value) || reg.test(base);
            } catch (_) {
                return false;
            }
        });
    }

    // ------------------------------------------------------------ 日志

    function countLogLines() {
        if (logLineCount >= 0) return logLineCount;
        try {
            const content = fs.readFileSync(logPath, 'utf8');
            logLineCount = content ? content.split('\n').filter((line) => line.trim()).length : 0;
        } catch (_) {
            logLineCount = 0;
        }
        return logLineCount;
    }

    function trimLogIfNeeded() {
        let needTrim = false;
        try {
            if (fs.statSync(logPath).size > LOG_MAX_BYTES) needTrim = true;
        } catch (_) {
            return;
        }
        if (logLineCount >= 0 && logLineCount > LOG_MAX_LINES) needTrim = true;
        if (!needTrim) return;
        try {
            const content = fs.readFileSync(logPath, 'utf8');
            const lines = content.split('\n').filter((line) => line.trim());
            const kept = lines.slice(-LOG_MAX_LINES);
            const tmp = `${logPath}.tmp`;
            fs.writeFileSync(tmp, kept.length ? `${kept.join('\n')}\n` : '', 'utf8');
            fs.renameSync(tmp, logPath);
            logLineCount = kept.length;
            console.log(`[forward] 转发日志已滚动，保留最近 ${kept.length} 条`);
        } catch (error) {
            console.error('[forward] 滚动转发日志失败:', error.message);
        }
    }

    function appendLog(entry) {
        try {
            fs.mkdirSync(datasDir, { recursive: true });
            fs.appendFileSync(logPath, `${JSON.stringify(entry)}\n`, 'utf8');
            if (logLineCount >= 0) logLineCount += 1;
            trimLogIfNeeded();
        } catch (error) {
            console.error('[forward] 写入转发日志失败:', error.message);
        }
    }

    function readRecentEntries(limit) {
        try {
            const content = fs.readFileSync(logPath, 'utf8');
            const lines = content.split('\n').filter((line) => line.trim());
            logLineCount = lines.length;
            const recent = lines.slice(-limit);
            return recent
                .map((line) => {
                    try {
                        return JSON.parse(line);
                    } catch (_) {
                        return null;
                    }
                })
                .filter(Boolean);
        } catch (_) {
            logLineCount = 0;
            return [];
        }
    }

    // ------------------------------------------------------------ 转发

    /**
     * 单次 multipart 上传。返回 {ok, status, id, sha256, error}，自身不抛出。
     */
    function uploadOnce(config, filePath, originPath, extraHeaders = {}) {
        return new Promise((resolve) => {
            let settled = false;
            let completedHash = null;
            const finish = (value) => {
                if (settled) return;
                settled = true;
                resolve(value);
            };

            let url;
            try {
                url = new URL(`${config.baseUrl}/api/files/mirror`);
            } catch (error) {
                return finish({ ok: false, status: null, id: null, sha256: null, error: `baseUrl 无效: ${error.message}` });
            }

            let fileSize;
            try {
                fileSize = fs.statSync(filePath).size;
            } catch (error) {
                return finish({ ok: false, status: null, id: null, sha256: null, error: `读取文件失败: ${error.message}` });
            }

            const transport = url.protocol === 'https:' ? https : http;
            const name = path.basename(filePath);
            const safeName = name.replace(/["\r\n]/g, '_');
            const boundary = `----PotatokidMirror${crypto.randomBytes(12).toString('hex')}`;
            const preamble = Buffer.from(
                `--${boundary}\r\n`
                + `Content-Disposition: form-data; name="file"; filename="${safeName}"; filename*=UTF-8''${encodeURIComponent(name)}\r\n`
                + 'Content-Type: application/octet-stream\r\n\r\n',
                'utf8'
            );
            const epilogue = Buffer.from(`\r\n--${boundary}--\r\n`, 'utf8');
            const hash = crypto.createHash('sha256');

            const requestOptions = {
                protocol: url.protocol,
                hostname: url.hostname,
                port: url.port ? Number(url.port) : (url.protocol === 'https:' ? 443 : 80),
                method: 'POST',
                path: `${url.pathname}${url.search}`,
                headers: {
                    'Content-Type': `multipart/form-data; boundary=${boundary}`,
                    'Content-Length': String(preamble.length + fileSize + epilogue.length),
                    'X-Service-Token': config.serviceToken,
                    'X-File-Name': encodeURIComponent(name),
                    'X-Origin-Server': config.originServer,
                    'X-Origin-Path': encodeHeaderPath(originPath),
                    Accept: 'application/json',
                    Connection: 'close',
                    ...extraHeaders,
                    // Host 由 Node 自动填充；显式端口已包含在内。
                },
            };

            let request;
            try {
                request = transport.request(requestOptions, onResponse);
            } catch (error) {
                return finish({ ok: false, status: null, id: null, sha256: null, error: `创建请求失败: ${error.message}` });
            }

            function onResponse(response) {
                const chunks = [];
                let received = 0;
                response.on('data', (chunk) => {
                    received += chunk.length;
                    if (received <= RESPONSE_MAX_BYTES) chunks.push(chunk);
                });
                response.on('end', () => {
                    const body = Buffer.concat(chunks).toString('utf8');
                    const localSha = completedHash;
                    if (response.statusCode < 200 || response.statusCode >= 300) {
                        return finish({
                            ok: false,
                            status: response.statusCode,
                            id: null,
                            sha256: localSha,
                            error: `HTTP ${response.statusCode}: ${body.slice(0, 200)}`,
                        });
                    }
                    let parsed = null;
                    try {
                        parsed = body ? JSON.parse(body) : null;
                    } catch (_) {
                        parsed = null;
                    }
                    if (parsed && typeof parsed.code !== 'undefined' && parsed.code !== 0) {
                        return finish({
                            ok: false,
                            status: response.statusCode,
                            id: null,
                            sha256: localSha,
                            error: `对端返回 code=${parsed.code}: ${String(parsed.msg || '').slice(0, 200)}`,
                        });
                    }
                    const data = (parsed && parsed.data) || {};
                    return finish({
                        ok: true,
                        status: response.statusCode,
                        id: data.id === undefined ? null : data.id,
                        downloadUrl: typeof data.downloadUrl === 'string' ? data.downloadUrl : null,
                        sha256: localSha || (typeof data.sha256 === 'string' ? data.sha256 : null),
                        error: null,
                    });
                });
                response.on('error', (error) => finish({
                    ok: false,
                    status: response.statusCode || null,
                    id: null,
                    sha256: completedHash,
                    error: `读取响应失败: ${error.message}`,
                }));
            }

            request.setTimeout(config.timeoutMs);
            request.on('timeout', () => request.destroy(new Error(`请求超时(${config.timeoutMs}ms)`)));
            request.on('error', (error) => finish({
                ok: false,
                status: null,
                id: null,
                sha256: completedHash,
                error: error.message,
            }));

            request.write(preamble);
            const stream = fs.createReadStream(filePath);
            stream.on('data', (chunk) => {
                // 对端提前返回（如 401）时停止继续读取大文件。
                if (settled) {
                    stream.destroy();
                    request.destroy();
                    return;
                }
                hash.update(chunk);
            });
            stream.on('error', (error) => request.destroy(error));
            stream.on('end', () => {
                completedHash = hash.digest('hex');
                request.end(epilogue);
            });
            stream.pipe(request, { end: false });
        });
    }

    async function runMirror(filePath, originPath, extraHeaders = {}) {
        const config = readConfig();
        if (!config.enabled) return; // 关闭时完全不发请求、不写日志

        const relPath = String(originPath || '').replace(/\\/g, '/');
        if (isExcluded(relPath, config.excludePatterns)) return;

        let size = 0;
        try {
            size = fs.statSync(filePath).size;
        } catch (error) {
            appendLog({
                ts: new Date().toISOString(),
                path: relPath,
                size: 0,
                ok: false,
                status: null,
                id: null,
                sha256: null,
                error: `文件不存在或不可读: ${error.message}`,
            });
            return;
        }

        if (!config.serviceToken) {
            appendLog({
                ts: new Date().toISOString(),
                path: relPath,
                size,
                ok: false,
                status: null,
                id: null,
                sha256: null,
                error: 'serviceToken 未配置，已跳过转发（请填写 datas/forward_config.json 的 serviceToken，取自 yuntu server.config.json 的 files.serviceToken）',
            });
            return;
        }

        inflight += 1;
        const startedAt = Date.now();
        const attempts = config.retries + 1;
        let result = { ok: false, status: null, id: null, downloadUrl: null, sha256: null, error: '未执行' };
        let attemptsUsed = 0;
        try {
            for (let attempt = 0; attempt < attempts; attempt += 1) {
                if (attempt > 0) {
                    await sleep(Math.min(1000 * Math.pow(2, attempt - 1), 30000));
                }
                attemptsUsed = attempt + 1;
                result = await uploadOnce(config, filePath, relPath, extraHeaders);
                if (result.ok) break;
                if (attempt < attempts - 1) {
                    console.warn(`[forward] 转发失败（第 ${attempt + 1}/${attempts} 次）: ${relPath} - ${result.error}`);
                }
            }
        } catch (error) {
            result = { ok: false, status: null, id: null, downloadUrl: null, sha256: null, error: `转发异常: ${error.message}` };
        } finally {
            inflight -= 1;
        }

        appendLog({
            ts: new Date().toISOString(),
            path: relPath,
            size,
            ok: result.ok,
            status: result.status,
            id: result.id,
            sha256: result.sha256,
            error: result.error,
            attempts: attemptsUsed,
            durationMs: Date.now() - startedAt,
        });
        if (result.ok) {
            console.log(`[forward] 转发成功: ${relPath} (${size} bytes, id=${result.id})`);
        } else {
            console.error(`[forward] 转发失败: ${relPath} - ${result.error}`);
        }
        return result;
    }

    /**
     * 等待转发完成并返回结果：成功时 resolve { ok, id, downloadUrl, sha256, status }，
     * 失败时 throw（让调用方决定是否继续；例如头像上传场景必须拿到公网 URL，
     * 转发失败直接报错给家长，避免头像存了 pscreen_server 但没同步到 app_server）。
     * 内部与 mirrorToYuntu 共用 runMirror，配置/重试/超时规则完全一致。
     */
    async function mirrorAndWait(filePath, originPath, extraHeaders = {}) {
        const result = await runMirror(filePath, originPath, extraHeaders);
        if (!result || !result.ok) {
            throw new Error(result ? result.error : '转发未执行');
        }
        return {
            ok: true,
            id: result.id,
            downloadUrl: result.downloadUrl,
            sha256: result.sha256,
            status: result.status,
        };
    }

    /**
     * fire-and-forget：调用方不需要 await，异常只记录日志，绝不影响上传响应。
     */
    function mirrorToYuntu(filePath, originPath, extraHeaders = {}) {
        let task;
        try {
            task = runMirror(filePath, originPath, extraHeaders);
        } catch (error) {
            console.error('[forward] 启动转发任务失败:', error.message);
            return Promise.resolve();
        }
        return task.catch((error) => {
            console.error('[forward] 转发任务异常:', error && error.message ? error.message : error);
        });
    }

    // ------------------------------------------------------------ 状态

    function status() {
        const config = readConfig();
        const entries = readRecentEntries(STATUS_RECENT_LIMIT);
        const success = entries.filter((entry) => entry.ok === true).length;
        const failed = entries.length - success;
        const lastError = entries.slice().reverse().find((entry) => entry.ok !== true) || null;
        return {
            enabled: config.enabled,
            baseUrl: config.baseUrl,
            originServer: config.originServer,
            timeoutMs: config.timeoutMs,
            retries: config.retries,
            excludePatterns: config.excludePatterns,
            // 只暴露是否已配置，不返回令牌明文。
            serviceTokenConfigured: Boolean(config.serviceToken),
            inflight,
            log: {
                file: `datas/${LOG_FILE}`,
                lines: countLogLines(),
                maxLines: LOG_MAX_LINES,
                maxBytes: LOG_MAX_BYTES,
            },
            recent: {
                window: STATUS_RECENT_LIMIT,
                count: entries.length,
                success,
                failed,
                lastError: lastError
                    ? {
                        ts: lastError.ts || null,
                        path: lastError.path || null,
                        status: lastError.status === undefined ? null : lastError.status,
                        error: lastError.error || null,
                    }
                    : null,
            },
        };
    }

    // 启动即生成模板，方便管理员直接填写令牌。
    ensureConfigFile();

    return { mirrorToYuntu, mirrorAndWait, status, configPath, logPath };
}

module.exports = { createForwarder };
