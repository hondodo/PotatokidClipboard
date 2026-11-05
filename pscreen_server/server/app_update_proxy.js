// 应用更新查询代理（本地 pscreen_server → yuntu app_server）。
//
// 职责边界：
// - 只代理「元数据查询」，不转发安装包字节；客户端拿到 yuntu 签名直链后
//   直连下载，本地 server 不消耗大文件流量。
// - yuntu 的地址/端口/API Key 全部放在运行期配置 datas/app_update/config.json，
//   改完不需要重启 pm2（≤5s 内 mtime 热加载生效）。
// - 查询失败一律「放行」：App 收到任何非 0 的业务码都只记录日志并进入主页。
//
// 路由（必须注册在 SPA 兜底之前）：
//   GET /api/app_update/check?app=&platform=&version=&build=&deviceId=
//   GET /api/app_update/download/:releaseId[?app=&platform=]
//   GET /api/app_update/health[?probe=1]

'use strict';

const fs = require('fs');
const path = require('path');

const DEFAULT_TIMEOUT_MS = 3000;
const DEFAULT_CACHE_TTL_MS = 60 * 1000;
const DEFAULT_STALE_TTL_MS = 24 * 60 * 60 * 1000;
const DEFAULT_RATE_LIMIT_PER_MINUTE = 60;
// mtime 热加载的节流窗口：避免每次请求都 stat 一次配置。
const CONFIG_RECHECK_MS = 5000;

/** 本地业务码（与 yuntu 错误码表一致，见 app_server/PLAN.md §4.1）。 */
const CODE_OK = 0;
const CODE_NOT_CONFIGURED = 100100;
const CODE_UPSTREAM_UNAVAILABLE = 100101;
const CODE_RATE_LIMITED = 400002;
const CODE_MISSING_APP = 400005;
const CODE_UNSUPPORTED_PLATFORM = 300005;
const CODE_RELEASE_NOT_FOUND = 300001;

const PLATFORMS = ['windows', 'apk', 'ios', 'macos', 'linux'];

function positiveInt(value, fallback) {
    const n = Number(value);
    return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
}

function trimSlash(url) {
    return String(url || '').trim().replace(/\/+$/, '');
}

/** 解析配置文件；任何非法字段都退化为「未配置/默认值」，不抛异常。 */
function parseConfig(raw) {
    const src = raw && typeof raw === 'object' ? raw : {};
    const baseUrl = trimSlash(src.baseUrl);
    let validUrl = false;
    if (baseUrl) {
        try {
            const parsed = new URL(baseUrl);
            validUrl = parsed.protocol === 'http:' || parsed.protocol === 'https:';
        } catch (_) {
            validUrl = false;
        }
    }
    const apiKey = typeof src.apiKey === 'string' ? src.apiKey.trim() : '';
    return {
        // enabled=false 或地址/密钥缺失时统一按「未配置」处理：不发上游请求。
        configured: validUrl && apiKey.length > 0 && src.enabled !== false,
        enabled: src.enabled !== false,
        baseUrl: validUrl ? baseUrl : '',
        apiKey,
        timeoutMs: positiveInt(src.timeoutMs, DEFAULT_TIMEOUT_MS),
        cacheTtlMs: positiveInt(src.cacheTtlMs, DEFAULT_CACHE_TTL_MS),
        staleTtlMs: positiveInt(src.staleTtlMs, DEFAULT_STALE_TTL_MS),
        // 固定 open：查询失败只记录，不阻断客户端进入主页。
        failMode: src.failMode === 'closed' ? 'closed' : 'open',
        allowDirectDownload: src.allowDirectDownload !== false,
        rateLimitPerMinute: positiveInt(src.rateLimitPerMinute, DEFAULT_RATE_LIMIT_PER_MINUTE),
        raw: src,
    };
}

function loadConfigFile(configPath, logger) {
    try {
        const text = fs.readFileSync(configPath, 'utf8');
        return parseConfig(JSON.parse(text));
    } catch (error) {
        if (error && error.code === 'ENOENT') {
            return parseConfig({});
        }
        if (logger) logger.warn(`[app_update] 读取配置失败 ${configPath}: ${error.message}`);
        return parseConfig({});
    }
}

/** 配置装载器：启动读一次，之后按 mtime 热加载（最多 5s 检查一次）。 */
function createConfigStore(configPath, options) {
    const logger = (options && options.logger) || console;
    let current = loadConfigFile(configPath, logger);
    let lastMtime = -1;
    let lastCheckAt = 0;
    try {
        lastMtime = fs.statSync(configPath).mtimeMs;
    } catch (_) {
        lastMtime = -1;
    }
    if (!current.configured && !fs.existsSync(configPath)) {
        logger.warn(`[app_update] 未找到运行期配置 ${configPath}，更新查询将返回 ${CODE_NOT_CONFIGURED}`);
    }
    return {
        get() {
            const now = Date.now();
            if (now - lastCheckAt < CONFIG_RECHECK_MS) return current;
            lastCheckAt = now;
            try {
                const mtime = fs.statSync(configPath).mtimeMs;
                if (mtime === lastMtime) return current;
                lastMtime = mtime;
                const next = loadConfigFile(configPath, logger);
                const changedUrl = next.baseUrl !== current.baseUrl;
                current = next;
                logger.log(`[app_update] 运行期配置已热加载：configured=${current.configured} baseUrl=${current.baseUrl || '-'}${changedUrl ? '（地址已变更）' : ''}`);
            } catch (error) {
                if (error && error.code === 'ENOENT') {
                    if (lastMtime !== -1) {
                        lastMtime = -1;
                        current = parseConfig({});
                        logger.warn(`[app_update] 运行期配置被删除：${configPath}`);
                    }
                }
            }
            return current;
        },
        configPath,
        reload() {
            lastCheckAt = 0;
            return this.get();
        },
        isConfigured() {
            return current.configured;
        },
    };
}

function parseBuild(raw) {
    const n = Number.parseInt(String(raw === undefined || raw === null ? '0' : raw), 10);
    return Number.isFinite(n) && n >= 0 ? n : 0;
}

/** 校验并归一客户端查询参数。 */
function parseCheckParams(query) {
    const q = query && typeof query === 'object' ? query : {};
    const app = String(q.app || '').trim();
    const platform = String(q.platform || '').trim().toLowerCase();
    if (!app) return { error: { code: CODE_MISSING_APP, msg: '缺少 app 参数' } };
    if (!PLATFORMS.includes(platform)) {
        return { error: { code: CODE_UNSUPPORTED_PLATFORM, msg: `不支持的平台：${platform || '(空)'}` } };
    }
    return {
        app,
        platform,
        version: q.version === undefined ? '' : String(q.version),
        build: parseBuild(q.build),
        deviceId: q.deviceId === undefined ? '' : String(q.deviceId).slice(0, 128),
    };
}

/** 构造上游 URL：查询串交给 URLSearchParams，避免手工拼串写进 path。 */
function buildUpstreamUrl(baseUrl, params) {
    const url = new URL(`${trimSlash(baseUrl)}/api/update/check`);
    url.searchParams.set('app', params.app);
    url.searchParams.set('platform', params.platform);
    if (params.version) url.searchParams.set('version', params.version);
    url.searchParams.set('build', String(params.build));
    if (params.deviceId) url.searchParams.set('deviceId', params.deviceId);
    return url.toString();
}

function cacheKeyOf(params) {
    return `${params.app}|${params.platform}|${params.version}|${params.build}`;
}

function createAppUpdateProxy(options = {}) {
    const logger = options.logger || console;
    const fetchImpl = options.fetchImpl || ((...args) => fetch(...args));
    const nowMs = options.nowMs || (() => Date.now());
    const configPath =
        options.configPath ||
        process.env.APP_UPDATE_CONFIG ||
        path.join(options.datasDir || path.join(__dirname, '../datas'), 'app_update', 'config.json');

    const configStore = createConfigStore(configPath, { logger });
    const checkCache = new Map(); // key → { body, fetchedAt }
    const downloadUrls = new Map(); // releaseId → { url, expiresAtMs }
    const rateBuckets = new Map(); // ip → number[]
    let lastError = '';
    let lastCheckAt = 0;

    function rateLimited(ip, limit) {
        const key = ip || 'unknown';
        const now = nowMs();
        const arr = (rateBuckets.get(key) || []).filter((t) => now - t < 60 * 1000);
        if (arr.length >= limit) {
            rateBuckets.set(key, arr);
            return true;
        }
        arr.push(now);
        rateBuckets.set(key, arr);
        return false;
    }

    function rememberDownload(body) {
        const latest = body && body.data && body.data.latest;
        const download = body && body.data && body.data.download;
        if (!latest || !download || !download.url) return;
        const expiresAtMs = download.expiresAt ? Date.parse(download.expiresAt) : nowMs() + 600 * 1000;
        downloadUrls.set(latest.releaseId, {
            url: download.url,
            expiresAtMs: Number.isFinite(expiresAtMs) ? expiresAtMs : nowMs() + 600 * 1000,
        });
    }

    async function requestUpstream(cfg, params) {
        const startedAt = nowMs();
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), cfg.timeoutMs);
        try {
            const response = await fetchImpl(buildUpstreamUrl(cfg.baseUrl, params), {
                method: 'GET',
                headers: { 'X-API-Key': cfg.apiKey, Accept: 'application/json' },
                signal: controller.signal,
            });
            const text = await response.text();
            let body = null;
            try {
                body = text ? JSON.parse(text) : null;
            } catch (_) {
                body = null;
            }
            return { status: response.status, body, text, elapsedMs: nowMs() - startedAt };
        } catch (error) {
            return {
                status: 0,
                body: null,
                text: '',
                error: error && error.name === 'AbortError' ? '上游超时' : (error && error.message) || '上游不可达',
                elapsedMs: nowMs() - startedAt,
            };
        } finally {
            clearTimeout(timer);
        }
    }

    /**
     * 查询核心：返回 { status, headers, body }。
     * status 用 HTTP 状态码；body 一律是 code/msg/data 结构。
     */
    async function queryCheck(query, ip) {
        const cfg = configStore.get();
        if (!cfg.configured) {
            return {
                status: 200,
                headers: { 'X-App-Update-Cache': 'none' },
                body: { code: CODE_NOT_CONFIGURED, msg: '本地服务器未配置应用分发地址，请联系管理员', data: null },
            };
        }
        if (rateLimited(ip, cfg.rateLimitPerMinute)) {
            return {
                status: 200,
                headers: { 'X-App-Update-Cache': 'none' },
                body: { code: CODE_RATE_LIMITED, msg: '查询过于频繁，请稍后重试', data: null },
            };
        }
        const params = parseCheckParams(query);
        if (params.error) {
            return { status: 200, headers: { 'X-App-Update-Cache': 'none' }, body: params.error };
        }

        const key = cacheKeyOf(params);
        const cached = checkCache.get(key);
        const now = nowMs();
        if (cached && now - cached.fetchedAt < cfg.cacheTtlMs) {
            return { status: 200, headers: { 'X-App-Update-Cache': 'hit' }, body: cached.body };
        }

        const upstream = await requestUpstream(cfg, params);
        lastCheckAt = now;
        if (upstream.body && upstream.status >= 200 && upstream.status < 300) {
            checkCache.set(key, { body: upstream.body, fetchedAt: now });
            rememberDownload(upstream.body);
            lastError = '';
            return { status: upstream.status, headers: { 'X-App-Update-Cache': 'miss' }, body: upstream.body };
        }

        // 上游返回业务错误（如 401 API Key / 429 限流）：有 JSON 就原样透传，
        // 让客户端日志能定位；本地不伪造「无更新」。
        if (upstream.body && typeof upstream.body === 'object') {
            lastError = `upstream ${upstream.status}`;
            return { status: upstream.status, headers: { 'X-App-Update-Cache': 'miss' }, body: upstream.body };
        }

        lastError = upstream.error || `upstream ${upstream.status}`;
        if (cached && now - cached.fetchedAt < cfg.staleTtlMs) {
            logger.warn(`[app_update] 上游不可用（${lastError}），返回旧缓存`);
            return { status: 200, headers: { 'X-App-Update-Cache': 'stale' }, body: cached.body };
        }
        return {
            status: 200,
            headers: { 'X-App-Update-Cache': 'none' },
            body: { code: CODE_UPSTREAM_UNAVAILABLE, msg: '应用服务器暂时不可用', data: null },
        };
    }

    /** 下载跳转：只取签名地址，不代理字节。 */
    async function queryDownload(releaseId, query, ip) {
        const cfg = configStore.get();
        if (!cfg.configured) {
            return { status: 200, location: '', body: { code: CODE_NOT_CONFIGURED, msg: '本地服务器未配置应用分发地址，请联系管理员', data: null } };
        }
        if (!cfg.allowDirectDownload) {
            return { status: 200, location: '', body: { code: CODE_NOT_CONFIGURED, msg: '本地服务器未开启直链下载，请使用 check 接口返回的下载地址', data: null } };
        }
        const id = String(releaseId || '').trim();
        const hit = downloadUrls.get(id);
        if (hit && hit.url && hit.expiresAtMs > nowMs()) {
            return { status: 302, location: hit.url, body: null };
        }
        const app = String((query && query.app) || '').trim();
        const platform = String((query && query.platform) || '').trim().toLowerCase();
        if (app && platform) {
            const result = await queryCheck({ app, platform, version: '', build: '0' }, ip);
            const body = result.body || {};
            const latest = body.data && body.data.latest;
            const download = body.data && body.data.download;
            // build=0 查询会返回当前 latest；只有 releaseId 匹配才跳转，避免
            // 客户端拿着旧 releaseId 被静默升级到另一个版本。
            if (body.code === CODE_OK && latest && latest.releaseId === id && download && download.url) {
                return { status: 302, location: download.url, body: null };
            }
        }
        return { status: 200, location: '', body: { code: CODE_RELEASE_NOT_FOUND, msg: '下载链接已过期，请重新查询更新', data: null } };
    }

    function health(probe) {
        const cfg = configStore.get();
        const base = {
            configured: cfg.configured,
            enabled: cfg.enabled,
            baseUrlHost: cfg.baseUrl ? new URL(cfg.baseUrl).host : '',
            cacheEntries: checkCache.size,
            downloadEntries: downloadUrls.size,
            lastCheckAt: lastCheckAt ? new Date(lastCheckAt).toISOString() : null,
            lastError,
            configPath,
        };
        if (!probe) return { status: 200, body: { code: CODE_OK, msg: 'ok', data: base } };
        if (!cfg.configured) {
            return { status: 200, body: { code: CODE_NOT_CONFIGURED, msg: '本地服务器未配置应用分发地址', data: base } };
        }
        const startedAt = nowMs();
        return requestUpstream(cfg, { app: 'probe', platform: 'apk', version: '', build: 0 }).then((upstream) => ({
            status: 200,
            body: {
                code: CODE_OK,
                msg: 'ok',
                data: {
                    ...base,
                    upstream: {
                        reachable: upstream.status > 0,
                        httpStatus: upstream.status,
                        elapsedMs: upstream.elapsedMs,
                        // 上游对未知 app 返回 300000 也说明网络与鉴权链路正常。
                        businessCode: upstream.body ? upstream.body.code : null,
                    },
                },
            },
        }));
    }

    function send(res, result) {
        if (result.headers) {
            for (const [key, value] of Object.entries(result.headers)) res.setHeader(key, value);
        }
        if (result.status === 302) return res.redirect(302, result.location);
        res.setHeader('Cache-Control', 'no-store');
        return res.status(result.status).json(result.body);
    }

    /** 生成 express Router。express 只在真正挂载时加载，便于纯函数测试。 */
    function createRouter(express) {
        const router = express.Router();
        router.get('/api/app_update/check', async (req, res) => {
            try {
                send(res, await queryCheck(req.query, req.ip));
            } catch (error) {
                logger.error('[app_update] check 异常:', error);
                res.status(200).json({ code: CODE_UPSTREAM_UNAVAILABLE, msg: '应用服务器暂时不可用', data: null });
            }
        });
        router.get('/api/app_update/download/:releaseId', async (req, res) => {
            try {
                send(res, await queryDownload(req.params.releaseId, req.query, req.ip));
            } catch (error) {
                logger.error('[app_update] download 异常:', error);
                res.status(200).json({ code: CODE_UPSTREAM_UNAVAILABLE, msg: '应用服务器暂时不可用', data: null });
            }
        });
        router.get('/api/app_update/health', async (req, res) => {
            try {
                send(res, await health(req.query.probe === '1'));
            } catch (error) {
                logger.error('[app_update] health 异常:', error);
                res.status(200).json({ code: CODE_UPSTREAM_UNAVAILABLE, msg: '应用服务器暂时不可用', data: null });
            }
        });
        return router;
    }

    return {
        configPath,
        createRouter,
        queryCheck,
        queryDownload,
        health,
        getConfig: () => configStore.get(),
        reloadConfig: () => configStore.reload(),
    };
}

/** 挂载入口：在 server.js 的 SPA 兜底之前调用。 */
function attachAppUpdateProxy(app, options = {}) {
    const proxy = createAppUpdateProxy(options);
    app.use(proxy.createRouter(require('express')));
    const cfg = proxy.getConfig();
    const host = cfg.baseUrl ? new URL(cfg.baseUrl).host : '未配置';
    console.log(`[app_update] 代理已挂载：上游 ${host}（配置 ${proxy.configPath}，热加载 ≤${CONFIG_RECHECK_MS / 1000}s）`);
    return proxy;
}

module.exports = {
    attachAppUpdateProxy,
    createAppUpdateProxy,
    loadConfigFile,
    parseConfig,
    parseCheckParams,
    buildUpstreamUrl,
};
