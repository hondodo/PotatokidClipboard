// 本地 pscreen_server「应用更新代理」核心逻辑测试（不依赖 express）。
// 运行：node test/app_update_proxy_test.js（在 pscreen_server 目录下）。
//
// 覆盖：配置解析/热加载、查询透传与缓存、上游故障降级（100101 / stale / 300008）、
// 下载直链 302、限流、以及「查询串不进 path」的 URL 构造。
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const {
    createAppUpdateProxy,
    parseConfig,
    parseCheckParams,
    buildUpstreamUrl,
} = require(path.join(__dirname, '..', 'server', 'app_update_proxy.js'));

let passed = 0;
function ok(name, fn) {
    return Promise.resolve(fn()).then(() => {
        passed += 1;
        console.log(`  ✓ ${name}`);
    });
}

const silentLogger = { log() {}, warn() {}, error() {} };

function makeFetch(routes) {
    const calls = [];
    const impl = async (url, options) => {
        calls.push({ url, options });
        const handler = routes(url, options);
        return {
            status: handler.status,
            text: async () => (handler.body === undefined ? '' : JSON.stringify(handler.body)),
        };
    };
    impl.calls = calls;
    return impl;
}

function okBody(overrides) {
    return {
        code: 0,
        msg: 'ok',
        data: {
            app: 'potatokid-screen',
            platform: 'apk',
            checkedAt: '2026-11-05T04:10:00Z',
            hasUpdate: true,
            forceUpdate: false,
            current: { version: '1.0.3', build: 8 },
            latest: {
                releaseId: 'rel_1',
                version: '1.0.4',
                build: 9,
                distribution: 'file',
                fileAvailable: true,
                externalUrl: null,
                forceUpdate: false,
            },
            download: {
                url: 'http://143.203.52.132:47292/api/download/rel_1?exp=1800000000&sig=abc',
                size: 73400320,
                sha256: '9f2c',
                filename: 'potatokid-screen-1.0.4-9.apk',
                expiresAt: new Date(1800000000000).toISOString(),
            },
            ...overrides,
        },
    };
}

function writeConfig(dir, config) {
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, 'config.json');
    fs.writeFileSync(file, JSON.stringify(config, null, 2));
    return file;
}

async function main() {
    const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'pk_app_update_test_'));
    const configDir = path.join(tmpRoot, 'app_update');

    console.log('[app_update proxy] 测试');

    // ---- 配置解析 ----
    await ok('非法 baseUrl / 缺 apiKey → 视为未配置', () => {
        const cfg = parseConfig({ baseUrl: 'not-a-url', apiKey: 'k' });
        assert.strictEqual(cfg.configured, false);
        assert.strictEqual(cfg.baseUrl, '');
        const cfg2 = parseConfig({ baseUrl: 'http://127.0.0.1:9999', apiKey: '' });
        assert.strictEqual(cfg2.configured, false);
        const cfg3 = parseConfig({ baseUrl: 'http://127.0.0.1:9999', apiKey: 'k', enabled: false });
        assert.strictEqual(cfg3.configured, false);
        const cfg4 = parseConfig({});
        assert.strictEqual(cfg4.failMode, 'open');
        assert.strictEqual(cfg4.allowDirectDownload, true);
        assert.strictEqual(cfg4.timeoutMs, 3000);
    });

    // ---- 参数校验 / URL 构造 ----
    await ok('缺少 app / 平台非法 分别返回 400005 / 300005', () => {
        assert.strictEqual(parseCheckParams({ platform: 'apk' }).error.code, 400005);
        assert.strictEqual(parseCheckParams({ app: 'a', platform: 'android' }).error.code, 300005);
        const params = parseCheckParams({ app: 'a', platform: 'APK', build: 'x', version: '1.0.3' });
        assert.strictEqual(params.platform, 'apk');
        assert.strictEqual(params.build, 0);
    });

    await ok('abi 透传到上游 URL，且缓存键按 abi 隔离（不串包）', async () => {
        // 归一 + 小写化；不带 abi → 空串（上游按 universal 处理）
        assert.strictEqual(parseCheckParams({ app: 'a', platform: 'apk', abi: 'Armeabi-V7a' }).abi, 'armeabi-v7a');
        assert.strictEqual(parseCheckParams({ app: 'a', platform: 'apk' }).abi, '');
        const url = new URL(
            buildUpstreamUrl('http://127.0.0.1:9999', { app: 'a', platform: 'apk', version: '', build: 8, deviceId: '', abi: 'arm64-v8a' }),
        );
        assert.strictEqual(url.searchParams.get('abi'), 'arm64-v8a');

        // 同 app/version/build、不同 abi → 必须各自回源，不得命中对方缓存
        const configPath = writeConfig(path.join(tmpRoot, 'abi'), { baseUrl: 'http://127.0.0.1:9999', apiKey: 'k', cacheTtlMs: 60000 });
        const fetchImpl = makeFetch(() => ({ status: 200, body: okBody() }));
        const proxy = createAppUpdateProxy({ configPath, fetchImpl, logger: silentLogger });
        await proxy.queryCheck({ app: 'a', platform: 'apk', build: '8', abi: 'armeabi-v7a' }, '1.1.1.1');
        await proxy.queryCheck({ app: 'a', platform: 'apk', build: '8', abi: 'arm64-v8a' }, '1.1.1.1');
        assert.strictEqual(fetchImpl.calls.length, 2);
        assert.ok(fetchImpl.calls[0].url.includes('abi=armeabi-v7a'));
        assert.ok(fetchImpl.calls[1].url.includes('abi=arm64-v8a'));
    });

    await ok('查询串走 searchParams，不写进 path', () => {
        const url = new URL(
            buildUpstreamUrl('http://127.0.0.1:9999', { app: 'potatokid-screen', platform: 'apk', version: '1.0.3', build: 8, deviceId: 'd1' }),
        );
        assert.strictEqual(url.pathname, '/api/update/check');
        assert.strictEqual(url.searchParams.get('app'), 'potatokid-screen');
        assert.strictEqual(url.searchParams.get('platform'), 'apk');
        assert.strictEqual(url.searchParams.get('build'), '8');
        assert.ok(!url.pathname.includes('%3F'));
        assert.ok(!url.pathname.includes('?'));
    });

    // ---- 未配置：不发上游请求 ----
    await ok('未配置 → 100100 且不请求上游', async () => {
        const configPath = writeConfig(path.join(tmpRoot, 'empty'), { enabled: false });
        const fetchImpl = makeFetch(() => ({ status: 200, body: okBody() }));
        const proxy = createAppUpdateProxy({ configPath, fetchImpl, logger: silentLogger });
        const result = await proxy.queryCheck({ app: 'potatokid-screen', platform: 'apk', build: '8' }, '1.1.1.1');
        assert.strictEqual(result.body.code, 100100);
        assert.strictEqual(fetchImpl.calls.length, 0);
    });

    // ---- 正常查询 + 缓存 ----
    await ok('查询透传 + 第二次命中缓存 + X-API-Key', async () => {
        const configPath = writeConfig(configDir, {
            baseUrl: 'http://127.0.0.1:9999',
            apiKey: 'test-key',
            cacheTtlMs: 60000,
        });
        const fetchImpl = makeFetch((url) => {
            assert.ok(url.startsWith('http://127.0.0.1:9999/api/update/check?'));
            return { status: 200, body: okBody() };
        });
        const proxy = createAppUpdateProxy({ configPath, fetchImpl, logger: silentLogger });
        const first = await proxy.queryCheck({ app: 'potatokid-screen', platform: 'apk', version: '1.0.3', build: '8' }, '1.1.1.1');
        assert.strictEqual(first.status, 200);
        assert.strictEqual(first.body.code, 0);
        assert.strictEqual(first.body.data.hasUpdate, true);
        assert.strictEqual(first.headers['X-App-Update-Cache'], 'miss');
        assert.strictEqual(fetchImpl.calls[0].options.headers['X-API-Key'], 'test-key');

        const second = await proxy.queryCheck({ app: 'potatokid-screen', platform: 'apk', version: '1.0.3', build: '8' }, '1.1.1.1');
        assert.strictEqual(second.headers['X-App-Update-Cache'], 'hit');
        assert.strictEqual(fetchImpl.calls.length, 1);
    });

    // ---- 下载直链 302（不代理字节） ----
    await ok('下载：命中缓存的签名地址 → 302，本地不转发字节', async () => {
        const configPath = writeConfig(configDir, { baseUrl: 'http://127.0.0.1:9999', apiKey: 'test-key' });
        const fetchImpl = makeFetch(() => ({ status: 200, body: okBody() }));
        const proxy = createAppUpdateProxy({ configPath, fetchImpl, logger: silentLogger });
        await proxy.queryCheck({ app: 'potatokid-screen', platform: 'apk', build: '8' }, '1.1.1.1');
        const result = await proxy.queryDownload('rel_1', {}, '1.1.1.1');
        assert.strictEqual(result.status, 302);
        assert.ok(result.location.includes('/api/download/rel_1'));
    });

    await ok('下载：缓存缺失 → 带 app/platform 重新取链；releaseId 不匹配不跳转', async () => {
        const configPath = writeConfig(configDir, { baseUrl: 'http://127.0.0.1:9999', apiKey: 'test-key' });
        const fetchImpl = makeFetch(() => ({ status: 200, body: okBody() }));
        const proxy = createAppUpdateProxy({ configPath, fetchImpl, logger: silentLogger });
        const hit = await proxy.queryDownload('rel_1', { app: 'potatokid-screen', platform: 'apk' }, '1.1.1.1');
        assert.strictEqual(hit.status, 302);
        const miss = await proxy.queryDownload('rel_other', { app: 'potatokid-screen', platform: 'apk' }, '1.1.1.1');
        assert.strictEqual(miss.status, 200);
        assert.strictEqual(miss.body.code, 300001);
    });

    await ok('下载：allowDirectDownload=false 时明确拒绝', async () => {
        const configPath = writeConfig(configDir, { baseUrl: 'http://127.0.0.1:9999', apiKey: 'test-key', allowDirectDownload: false });
        const proxy = createAppUpdateProxy({ configPath, fetchImpl: makeFetch(() => ({ status: 200, body: okBody() })), logger: silentLogger });
        const result = await proxy.queryDownload('rel_1', {}, '1.1.1.1');
        assert.strictEqual(result.status, 200);
        assert.strictEqual(result.body.code, 100100);
    });

    // ---- 上游故障 ----
    await ok('上游断网且无缓存 → 100101', async () => {
        const configPath = writeConfig(configDir, { baseUrl: 'http://127.0.0.1:9998', apiKey: 'test-key' });
        const fetchImpl = async () => {
            throw new Error('connect ECONNREFUSED');
        };
        const proxy = createAppUpdateProxy({ configPath, fetchImpl, logger: silentLogger });
        const result = await proxy.queryCheck({ app: 'potatokid-screen', platform: 'apk', build: '8' }, '1.1.1.1');
        assert.strictEqual(result.body.code, 100101);
        assert.strictEqual(result.headers['X-App-Update-Cache'], 'none');
    });

    await ok('上游 5xx 且有过期缓存 → stale 缓存（不阻断）', async () => {
        let clock = 1000000;
        let fail = false;
        const configPath = writeConfig(configDir, { baseUrl: 'http://127.0.0.1:9997', apiKey: 'test-key', cacheTtlMs: 1000, staleTtlMs: 86400000 });
        const fetchImpl = makeFetch(() => (fail ? { status: 500, body: undefined } : { status: 200, body: okBody() }));
        const proxy = createAppUpdateProxy({ configPath, fetchImpl, logger: silentLogger, nowMs: () => clock });
        await proxy.queryCheck({ app: 'potatokid-screen', platform: 'apk', build: '8' }, '1.1.1.1');
        fail = true;
        clock += 5000; // 超过 cacheTtlMs，进入 stale 判定
        const result = await proxy.queryCheck({ app: 'potatokid-screen', platform: 'apk', build: '8' }, '1.1.1.1');
        assert.strictEqual(result.headers['X-App-Update-Cache'], 'stale');
        assert.strictEqual(result.body.data.hasUpdate, true);
    });

    await ok('上游 300008（安装包被清理）原样透传，交给客户端重试', async () => {
        const configPath = writeConfig(configDir, { baseUrl: 'http://127.0.0.1:9996', apiKey: 'test-key' });
        const fetchImpl = makeFetch(() => ({ status: 410, body: { code: 300008, msg: '该版本安装包已被清理，请重新上传' } }));
        const proxy = createAppUpdateProxy({ configPath, fetchImpl, logger: silentLogger });
        const result = await proxy.queryCheck({ app: 'potatokid-screen', platform: 'apk', build: '8' }, '1.1.1.1');
        assert.strictEqual(result.status, 410);
        assert.strictEqual(result.body.code, 300008);
    });

    // ---- 限流 ----
    await ok('同 IP 超过 rateLimitPerMinute → 400002', async () => {
        let clock = 2000000;
        const configPath = writeConfig(configDir, { baseUrl: 'http://127.0.0.1:9995', apiKey: 'test-key', rateLimitPerMinute: 2 });
        const proxy = createAppUpdateProxy({
            configPath,
            fetchImpl: makeFetch(() => ({ status: 200, body: okBody() })),
            logger: silentLogger,
            nowMs: () => clock,
        });
        await proxy.queryCheck({ app: 'a', platform: 'apk', build: '8' }, '9.9.9.9');
        await proxy.queryCheck({ app: 'b', platform: 'apk', build: '8' }, '9.9.9.9');
        const third = await proxy.queryCheck({ app: 'c', platform: 'apk', build: '8' }, '9.9.9.9');
        assert.strictEqual(third.body.code, 400002);
        // 另一个 IP 不受影响
        const other = await proxy.queryCheck({ app: 'a', platform: 'apk', build: '8' }, '8.8.8.8');
        assert.strictEqual(other.body.code, 0);
    });

    // ---- 配置热加载 ----
    await ok('改 baseUrl 后 reloadConfig 生效（不需要重启进程）', async () => {
        const hotDir = path.join(tmpRoot, 'hot');
        const configPath = writeConfig(hotDir, { baseUrl: 'http://127.0.0.1:9994', apiKey: 'test-key' });
        const seen = [];
        const fetchImpl = async (url) => {
            seen.push(url);
            return { status: 200, text: async () => JSON.stringify(okBody()) };
        };
        const proxy = createAppUpdateProxy({ configPath, fetchImpl, logger: silentLogger });
        await proxy.queryCheck({ app: 'potatokid-screen', platform: 'apk', build: '8' }, '1.1.1.1');
        assert.ok(seen[0].startsWith('http://127.0.0.1:9994'));

        writeConfig(hotDir, { baseUrl: 'http://127.0.0.1:9993', apiKey: 'test-key' });
        const reloaded = proxy.reloadConfig();
        assert.strictEqual(reloaded.baseUrl, 'http://127.0.0.1:9993');
        await proxy.queryCheck({ app: 'potatokid-screen', platform: 'apk', build: '7' }, '1.1.1.1');
        assert.ok(seen[1].startsWith('http://127.0.0.1:9993'));
    });

    await ok('配置被删除 → 回落到未配置（100100）', async () => {
        const cfgFile = writeConfig(path.join(tmpRoot, 'gone'), { baseUrl: 'http://127.0.0.1:9992', apiKey: 'test-key' });
        const proxy = createAppUpdateProxy({ configPath: cfgFile, fetchImpl: makeFetch(() => ({ status: 200, body: okBody() })), logger: silentLogger });
        fs.unlinkSync(cfgFile);
        proxy.reloadConfig();
        const result = await proxy.queryCheck({ app: 'potatokid-screen', platform: 'apk', build: '8' }, '1.1.1.1');
        assert.strictEqual(result.body.code, 100100);
    });

    console.log(`[app_update proxy] 全部通过：${passed} 项`);
    fs.rmSync(tmpRoot, { recursive: true, force: true });
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
