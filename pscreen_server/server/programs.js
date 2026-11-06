// 节目编辑（频道 / 源列表 + 规则文件）管理接口。
//
// 设计约束（与用户对齐）：
// - 只编辑频道/源列表与规则，不做 EPG；
// - 全局一份（不区分家庭/设备），只有 admin 可读写；
// - `result.m3u` 由人工维护，不存在外部脚本覆盖，因此可直接落盘；
// - 保存时先备份上一版（保留最近 10 份），tmp + rename 原子写；
// - 保存后刷新 programsUpdatedAt，并通过 config 帧给在线设备一次轻量通知
//   （只带时间戳/版本号，不把大文件塞进 WS 帧）。
//
// 另外提供只读的「最终效果」预览：用服务端本地文件按客户端同一套规则合成
// collect + result.m3u + audio 的最终顺序，便于运维在保存前后核对。
// 预览不包含设备本地才知道的两项：失效源清理（ChannelFailureGuard）与
// 家长模式过滤，页面会显式标注。

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const MAX_M3U_BYTES = 2 * 1024 * 1024;
const MAX_TEXT_BYTES = 256 * 1024;
const MAX_BACKUPS = 10;
const MAX_WARNINGS = 20;
const MAX_PREVIEW_CHANNELS = 4000;

// 白名单顺序即页面展示顺序。editable=false 的文件只能查看。
const PROGRAM_FILES = {
    'result.m3u': { label: '接口频道 result.m3u', kind: 'm3u', editable: true, maxBytes: MAX_M3U_BYTES },
    'collect.m3u': { label: '自建精选 collect.m3u', kind: 'm3u', editable: true, maxBytes: MAX_M3U_BYTES },
    'audio.m3u': { label: '广播电台 audio.m3u', kind: 'm3u', editable: true, maxBytes: MAX_M3U_BYTES },
    'guovin-api.m3u': { label: '默认快照 guovin-api.m3u', kind: 'm3u', editable: true, maxBytes: MAX_M3U_BYTES },
    'tv_name_hide.txt': { label: '隐藏频道 tv_name_hide.txt', kind: 'rules', ruleStyle: 'list', editable: true, maxBytes: MAX_TEXT_BYTES },
    'tv_name_order.txt': { label: '置顶顺序 tv_name_order.txt', kind: 'rules', ruleStyle: 'list', editable: true, maxBytes: MAX_TEXT_BYTES },
    'remove_source.txt': { label: '强制移除源 remove_source.txt', kind: 'rules', editable: true, maxBytes: MAX_TEXT_BYTES },
    'remove_source_contains.txt': { label: '移除片段 remove_source_contains.txt', kind: 'rules', editable: true, maxBytes: MAX_TEXT_BYTES },
    'not_remove_source.txt': { label: '强制保留源 not_remove_source.txt', kind: 'rules', editable: true, maxBytes: MAX_TEXT_BYTES },
    'source.txt': { label: '接口地址 source.txt', kind: 'readonly', editable: false },
    'git_source.txt': { label: '上游地址 git_source.txt', kind: 'readonly', editable: false },
    'weather_cities.txt': { label: '天气城市 weather_cities.txt', kind: 'readonly', editable: false },
};

function pad(value, width = 2) {
    return String(value).padStart(width, '0');
}

/** 备份名：本地时间 YYYYmmdd-HHMMSS-mmm，可排序且同一秒内多次保存不冲突。 */
function stampName(date = new Date()) {
    return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}` +
        `-${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}` +
        `-${pad(date.getMilliseconds(), 3)}`;
}

function readTextFile(file) {
    try {
        return fs.readFileSync(file, 'utf8');
    } catch (_) {
        return '';
    }
}

function statOf(file) {
    try {
        const stat = fs.statSync(file);
        if (!stat.isFile()) return null;
        return { size: stat.size, mtime: Math.round(stat.mtimeMs) };
    } catch (_) {
        return null;
    }
}

function lineCount(text) {
    if (!text) return 0;
    const normalized = text.replace(/\r\n?/g, '\n');
    return normalized.endsWith('\n')
        ? normalized.slice(0, -1).split('\n').length
        : normalized.split('\n').length;
}

/** UTF-8 / 控制字符校验：拒绝 NUL 与非法代理项（JSON 里可以塞进孤立代理项）。 */
function assertTextSafe(text) {
    if (text.includes('\u0000')) {
        throw new Error('内容包含 NUL 字符');
    }
    const loneSurrogate = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/;
    if (loneSurrogate.test(text)) {
        throw new Error('内容包含非法 UTF-16 字符，请检查编码');
    }
}

/** 去掉 BOM、统一换行，避免把 Windows 换行写进 m3u 让客户端逐行判断出错。 */
function normalizeText(raw) {
    return String(raw == null ? '' : raw)
        .replace(/^\uFEFF/, '')
        .replace(/\r\n?/g, '\n');
}

/** 规则文件：每行一个条目，`#` 注释与空行忽略。 */
function parseLineSet(text) {
    const out = new Set();
    for (const line of String(text || '').split('\n')) {
        const item = line.trim();
        if (!item || item.startsWith('#')) continue;
        out.add(item);
    }
    return out;
}

/**
 * 频道名清单（tv_name_hide / tv_name_order）：逗号分隔，换行与逗号等价
 * （与 Flutter 端 DataFiles.parseList 一致）。
 */
function parseCommaList(text) {
    const parts = [];
    for (const line of String(text || '').split('\n')) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;
        parts.push(trimmed);
    }
    return parts
        .join(',')
        .split(',')
        .map((item) => item.trim())
        .filter((item) => item);
}

/** m3u 属性提取（与 Flutter 端 IptvM3uParser 一致，大小写不敏感）。 */
function m3uAttribute(attrPart, key) {
    const match = new RegExp(`${key}="([^"]*)"`, 'i').exec(attrPart);
    return match && match[1] ? match[1] : null;
}

function m3uChannelName(attrPart) {
    const comma = attrPart.lastIndexOf(',');
    if (comma < 0 || comma === attrPart.length - 1) return '';
    return attrPart.slice(comma + 1).trim();
}

/** 解析 m3u：同名频道聚合 sources，保持首次出现顺序（镜像 Flutter 端实现）。 */
function parseM3u(content) {
    const lines = String(content || '').split('\n').map((line) => line.trim());
    const byName = new Map();
    const order = [];
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (!line.startsWith('#EXTINF:')) continue;
        const attrPart = line.slice('#EXTINF:'.length).trim();
        const name = m3uChannelName(attrPart);
        if (!name) continue;
        const logo = m3uAttribute(attrPart, 'tvg-logo');
        const group = m3uAttribute(attrPart, 'group-title');
        // Guovin 的「更新时间」条目是元信息，不是频道。
        if (group && group.includes('更新时间')) continue;
        let url = '';
        for (let j = i + 1; j < lines.length; j++) {
            const candidate = lines[j];
            if (!candidate) continue;
            if (candidate.startsWith('#')) break;
            url = candidate;
            break;
        }
        if (!url) continue;
        const existing = byName.get(name);
        if (existing) {
            if (!existing.sources.includes(url)) existing.sources.push(url);
        } else {
            byName.set(name, { name, logo: logo || null, group: group || null, sources: [url] });
            order.push(name);
        }
    }
    return order.map((name) => byName.get(name));
}

/** `CCTV1` → `CCTV-1`（与 Flutter 端 normalizeChannelName 一致）。 */
function normalizeChannelName(raw) {
    const name = String(raw == null ? '' : raw).trim();
    for (const prefix of ['CCTV', 'CETV']) {
        if (name.length <= prefix.length) continue;
        if (name.slice(0, prefix.length).toUpperCase() !== prefix) continue;
        const rest = name.slice(prefix.length).replace(/^\s+/, '');
        return rest.startsWith('-') ? `${prefix}${rest}` : `${prefix}-${rest}`;
    }
    return name;
}

/** 频道名规则匹配：精确全等 + `*` 通配（与 Flutter 端 ChannelNameMatcher 一致）。 */
class ChannelNameMatcher {
    constructor(patterns) {
        this.exact = new Set();
        this.globs = [];
        for (const raw of patterns || []) {
            const pattern = String(raw == null ? '' : raw).trim();
            if (!pattern) continue;
            if (!pattern.includes('*')) {
                this.exact.add(normalizeChannelName(pattern));
                continue;
            }
            const segments = pattern.split('*').map((part) => normalizeChannelName(part).toLowerCase());
            if (segments.every((segment) => !segment)) continue;
            this.globs.push(segments);
        }
    }

    matches(rawName) {
        const name = normalizeChannelName(rawName);
        if (!name) return false;
        if (this.exact.has(name)) return true;
        if (!this.globs.length) return false;
        const lower = name.toLowerCase();
        return this.globs.some((segments) => ChannelNameMatcher.matchesGlob(lower, segments));
    }

    static matchesGlob(name, segments) {
        const anchorEnd = segments[segments.length - 1] !== '';
        let from = 0;
        for (let i = 0; i < segments.length; i++) {
            const segment = segments[i];
            if (!segment) continue;
            if (i === segments.length - 1 && anchorEnd) {
                return name.endsWith(segment) && name.length - segment.length >= from;
            }
            const at = name.indexOf(segment, from);
            if (at < 0) return false;
            if (i === 0 && at !== 0) return false;
            from = at + segment.length;
        }
        return true;
    }
}

/** 同名合并：源按出现顺序去重，台标/分组取首个非空。 */
function mergeChannel(first, second) {
    const sources = first.sources.slice();
    for (const url of second.sources) {
        if (!sources.includes(url)) sources.push(url);
    }
    return {
        name: first.name,
        sources,
        logo: first.logo || second.logo,
        group: first.group || second.group,
    };
}

/**
 * 合成最终列表：collect + remote + audio → 名称归一/合并 → 隐藏 → 置顶
 * → 强制移除源（remove_source 整行相等、remove_source_contains 片段包含）。
 * not_remove_source 只对「失效源自动清理」生效，服务端无法知道设备本地黑名单，
 * 因此预览里不消费它。
 */
function composePreview({ collect, remote, audio, hidePatterns, orderPatterns, removed, removedContains }) {
    const byName = new Map();
    const order = [];
    for (const channel of [...collect, ...remote, ...audio]) {
        const name = normalizeChannelName(channel.name);
        if (!name) continue;
        const normalized = name === channel.name ? channel : { ...channel, name };
        const existing = byName.get(name);
        if (existing) {
            byName.set(name, mergeChannel(existing, normalized));
        } else {
            byName.set(name, { ...normalized, sources: normalized.sources.slice() });
            order.push(name);
        }
    }
    const merged = order.map((name) => byName.get(name));

    const hide = new ChannelNameMatcher(hidePatterns);
    const visible = [];
    const hidden = [];
    for (const channel of merged) {
        if (hide.matches(channel.name)) hidden.push(channel.name);
        else visible.push(channel);
    }

    // 置顶：规则条目也做归一化，列表里不存在的忽略。
    const head = [];
    const used = new Set();
    for (const raw of orderPatterns) {
        const name = normalizeChannelName(raw);
        if (used.has(name)) continue;
        used.add(name);
        const item = visible.find((channel) => channel.name === name);
        if (item) head.push(item);
    }
    const headNames = new Set(head.map((channel) => channel.name));
    const ordered = head.length
        ? [...head, ...visible.filter((channel) => !headNames.has(channel.name))]
        : visible;

    const finalChannels = [];
    const removedChannels = [];
    const containsPatterns = Array.from(removedContains || []);
    let removedSourceCount = 0;
    for (const channel of ordered) {
        const sources = channel.sources.filter((url) => {
            if (removed.has(url)) return false;
            return !containsPatterns.some((pattern) => url.includes(pattern));
        });
        removedSourceCount += channel.sources.length - sources.length;
        if (sources.length === 0) {
            removedChannels.push(channel.name);
            continue;
        }
        finalChannels.push({ ...channel, sources });
    }

    return {
        mergedCount: merged.length,
        hiddenCount: hidden.length,
        hidden: hidden,
        orderedCount: head.length,
        removedChannels,
        removedSourceCount,
        finalChannels,
    };
}

/**
 * 读取 [screenDir] 下的节目输入文件，并按客户端规则合成最终列表。
 *
 * 预览接口与设备侧 `final_channels.json` 共用这一份实现，避免两条链路
 * 出现语义漂移。
 */
function composeFromDir(screenDir) {
    const dir = path.resolve(screenDir);
    const file = (name) => path.join(dir, name);
    const collect = parseM3u(readTextFile(file('collect.m3u')));
    const audio = parseM3u(readTextFile(file('audio.m3u')));

    // source.txt 被设备两跳消费：先取它给的地址，能落到本目录就用本地文件，
    // 否则回落到 result.m3u（当前线上就是自指）。
    let remoteFile = 'result.m3u';
    const sourceText = readTextFile(file('source.txt')).trim();
    const localMatch = sourceText.match(/\/api\/screen\/([A-Za-z0-9_.-]+)/);
    const candidate = localMatch ? localMatch[1] : '';
    if (candidate && PROGRAM_FILES[candidate] && statOf(file(candidate))) {
        remoteFile = candidate;
    }
    const remote = parseM3u(readTextFile(file(remoteFile)));

    const inputs = {
        collect,
        remote,
        audio,
        remoteFile,
        hidden: parseCommaList(readTextFile(file('tv_name_hide.txt'))),
        ordered: parseCommaList(readTextFile(file('tv_name_order.txt'))),
        removed: parseLineSet(readTextFile(file('remove_source.txt'))),
        removedContains: parseLineSet(readTextFile(file('remove_source_contains.txt'))),
        protected: Array.from(parseLineSet(readTextFile(file('not_remove_source.txt')))),
    };
    const result = composePreview({
        collect,
        remote,
        audio,
        hidePatterns: inputs.hidden,
        orderPatterns: inputs.ordered,
        removed: inputs.removed,
        removedContains: inputs.removedContains,
    });
    return { inputs, result };
}

/**
 * 设备侧最终频道列表（服务端合并结果）。
 *
 * - `channels`：`name / group / logo / sources[]`，源已去重并完成强制移除；
 * - `protectedSources`：`not_remove_source.txt` 的内容，供设备保留「失效源清理」
 *   豁免（服务端无法预知设备本地的失效地址，所以这项仍由设备执行）；
 * - `updatedAt`：参与合成的所有文件的最新修改时间；
 * - `version`：内容哈希，内容不变时 ETag 稳定，设备可走 304 不重拉。
 */
function buildFinalChannels(screenDir) {
    const dir = path.resolve(screenDir);
    const { inputs, result } = composeFromDir(dir);
    const channels = result.finalChannels.map((channel) => ({
        name: channel.name,
        group: channel.group || '',
        logo: channel.logo || '',
        sources: channel.sources,
    }));

    const inputNames = [
        'collect.m3u', inputs.remoteFile, 'audio.m3u',
        'tv_name_hide.txt', 'tv_name_order.txt',
        'remove_source.txt', 'remove_source_contains.txt', 'not_remove_source.txt',
    ];
    let updatedAt = 0;
    for (const name of new Set(inputNames)) {
        const stat = statOf(path.join(dir, name));
        if (stat && stat.mtime > updatedAt) updatedAt = stat.mtime;
    }

    const payload = JSON.stringify({ channels, protectedSources: inputs.protected });
    const version = crypto.createHash('sha256').update(payload).digest('hex');

    return {
        version,
        updatedAt,
        channels,
        protectedSources: inputs.protected,
        counts: {
            collect: inputs.collect.length,
            remote: inputs.remote.length,
            audio: inputs.audio.length,
            merged: result.mergedCount,
            hidden: result.hiddenCount,
            ordered: result.orderedCount,
            removedChannels: result.removedChannels.length,
            removedSources: result.removedSourceCount,
            final: channels.length,
        },
    };
}

/** 校验 m3u：返回错误（阻断）与警告（提示）。 */
function validateM3u(text) {
    const lines = text.split('\n');
    const errors = [];
    const warnings = [];
    const urlLines = new Map();
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        if (!line.startsWith('#EXTINF:')) continue;
        let url = '';
        let urlLine = -1;
        for (let j = i + 1; j < lines.length; j++) {
            const candidate = lines[j].trim();
            if (!candidate) continue;
            if (candidate.startsWith('#')) break;
            url = candidate;
            urlLine = j;
            break;
        }
        if (!url) {
            errors.push(`第 ${i + 1} 行 #EXTINF 后缺少播放地址（下一行是空行或注释）`);
            continue;
        }
        if (urlLines.has(url)) {
            warnings.push(`第 ${urlLine + 1} 行与第 ${urlLines.get(url) + 1} 行地址重复`);
        } else {
            urlLines.set(url, urlLine);
        }
    }
    return { errors, warnings };
}

/** 规则文件重复检查：list 按逗号项，line 按整行（与客户端解析方式一致）。 */
function validateRules(text, style = 'line') {
    const seen = new Set();
    const warnings = [];
    if (style === 'list') {
        for (const item of parseCommaList(text)) {
            if (seen.has(item)) {
                warnings.push(`重复条目：${item}`);
            } else {
                seen.add(item);
            }
        }
        return warnings;
    }
    const lines = text.split('\n');
    const seenLines = new Map();
    for (let i = 0; i < lines.length; i++) {
        const item = lines[i].trim();
        if (!item || item.startsWith('#')) continue;
        if (seenLines.has(item)) {
            warnings.push(`第 ${i + 1} 行与第 ${seenLines.get(item) + 1} 行重复：${item}`);
        } else {
            seenLines.set(item, i);
        }
    }
    return warnings;
}

function attachPrograms(app, options = {}) {
    const screenDir = path.resolve(options.screenDir);
    const backupRoot = path.resolve(options.backupRoot);
    const stateFile = path.resolve(options.stateFile);
    const requireAdmin = options.requireAdmin;
    const jsonOk = options.jsonOk;
    const jsonFail = options.jsonFail;
    // 由 admin.js 注入：给所有在线可接收设备推完整 config 帧，返回送达数。
    const pushToOnlineDevices = typeof options.pushToOnlineDevices === 'function'
        ? options.pushToOnlineDevices
        : () => 0;

    function state() {
        try {
            const raw = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
            return {
                updatedAt: Number(raw.updatedAt) || 0,
                revision: Number(raw.revision) || 0,
            };
        } catch (_) {
            return { updatedAt: 0, revision: 0 };
        }
    }

    function saveState(next) {
        fs.mkdirSync(path.dirname(stateFile), { recursive: true });
        const tmp = `${stateFile}.tmp`;
        fs.writeFileSync(tmp, JSON.stringify(next, null, 2), 'utf8');
        fs.renameSync(tmp, stateFile);
    }

    function bumpState() {
        const current = state();
        // 时间戳必须单调递增：同一毫秒内连续保存时也要让设备看到版本变化。
        const next = {
            updatedAt: Math.max(Date.now(), current.updatedAt + 1),
            revision: current.revision + 1,
        };
        saveState(next);
        return next;
    }

    function specOf(name) {
        return Object.prototype.hasOwnProperty.call(PROGRAM_FILES, name) ? PROGRAM_FILES[name] : null;
    }

    function filePath(name) {
        return path.join(screenDir, name);
    }

    function backupDir(name) {
        return path.join(backupRoot, name);
    }

    function pruneBackups(name) {
        const dir = backupDir(name);
        let entries = [];
        try {
            entries = fs.readdirSync(dir)
                .filter((item) => item.endsWith('.bak'))
                .sort()
                .reverse();
        } catch (_) {
            return;
        }
        for (const item of entries.slice(MAX_BACKUPS)) {
            try {
                fs.unlinkSync(path.join(dir, item));
            } catch (_) {
                // 清理失败不影响本次保存
            }
        }
    }

    function backup(name) {
        const file = filePath(name);
        const stat = statOf(file);
        if (!stat) return '';
        fs.mkdirSync(backupDir(name), { recursive: true });
        let stamp = stampName();
        let dest = path.join(backupDir(name), `${stamp}.bak`);
        let seq = 1;
        while (fs.existsSync(dest)) {
            stamp = `${stampName()}-${seq}`;
            dest = path.join(backupDir(name), `${stamp}.bak`);
            seq++;
        }
        fs.copyFileSync(file, dest);
        try {
            fs.chmodSync(dest, 0o600);
        } catch (_) {
            // 权限调整失败不阻断
        }
        pruneBackups(name);
        return path.basename(dest, '.bak');
    }

    function listBackups(name) {
        const dir = backupDir(name);
        let entries = [];
        try {
            entries = fs.readdirSync(dir).filter((item) => item.endsWith('.bak'));
        } catch (_) {
            return [];
        }
        return entries
            .map((item) => {
                const file = path.join(dir, item);
                const stat = statOf(file);
                return {
                    timestamp: item.slice(0, -4),
                    size: stat ? stat.size : 0,
                    mtime: stat ? stat.mtime : 0,
                };
            })
            .filter((item) => item.timestamp)
            .sort((a, b) => (a.timestamp < b.timestamp ? 1 : -1));
    }

    function atomicWrite(file, text) {
        fs.mkdirSync(path.dirname(file), { recursive: true });
        const tmp = `${file}.tmp-${process.pid}-${crypto.randomBytes(4).toString('hex')}`;
        fs.writeFileSync(tmp, text, { encoding: 'utf8', mode: 0o600 });
        try {
            fs.chmodSync(tmp, 0o600);
        } catch (_) {
            // 权限调整失败不阻断
        }
        fs.renameSync(tmp, file);
    }

    function metaOf(name) {
        const spec = specOf(name);
        const stat = statOf(filePath(name));
        return {
            name,
            label: spec.label,
            kind: spec.kind,
            editable: spec.editable,
            exists: !!stat,
            size: stat ? stat.size : 0,
            mtime: stat ? stat.mtime : 0,
            maxBytes: spec.maxBytes || MAX_TEXT_BYTES,
            backups: listBackups(name).length,
        };
    }

    function contentOf(name) {
        const text = readTextFile(filePath(name));
        return { content: text, lines: lineCount(text) };
    }

    function validateSave(name, rawContent) {
        const spec = specOf(name);
        if (!spec.editable) throw new Error('该文件只读，不提供编辑入口');
        if (typeof rawContent !== 'string') throw new Error('content 必须是字符串');
        const content = normalizeText(rawContent);
        assertTextSafe(content);
        if (!content.trim()) {
            throw new Error('内容为空；客户端会把空内容当作无效并保留旧值，因此不允许保存空文件');
        }
        const bytes = Buffer.byteLength(content, 'utf8');
        if (bytes > spec.maxBytes) {
            throw new Error(`内容 ${bytes} 字节，超过上限 ${spec.maxBytes} 字节`);
        }
        const warnings = [];
        if (spec.kind === 'm3u') {
            const result = validateM3u(content);
            if (result.errors.length) {
                const head = result.errors.slice(0, 3).join('；');
                const more = result.errors.length > 3 ? `；另有 ${result.errors.length - 3} 处` : '';
                throw new Error(`m3u 格式检查未通过：${head}${more}`);
            }
            warnings.push(...result.warnings);
        } else {
            warnings.push(...validateRules(content, spec.ruleStyle));
        }
        return { content, bytes, warnings: warnings.slice(0, MAX_WARNINGS), lines: lineCount(content) };
    }

    // ------------------------------------------------------------ 接口

    // 注意：静态路径必须排在 /:name 之前，否则会被当成文件名。
    app.get('/api/admin/programs/preview', requireAdmin, (req, res) => {
        try {
            const { inputs, result } = composeFromDir(screenDir);
            const collect = inputs.collect;
            const remote = inputs.remote;
            const audio = inputs.audio;
            const remoteFile = inputs.remoteFile;
            const channels = result.finalChannels.slice(0, MAX_PREVIEW_CHANNELS).map((channel) => ({
                name: channel.name,
                group: channel.group || '',
                logo: channel.logo || '',
                sources: channel.sources.length,
            }));
            return jsonOk(res, {
                updatedAt: state().updatedAt,
                remoteFile,
                counts: {
                    collect: collect.length,
                    remote: remote.length,
                    audio: audio.length,
                    merged: result.mergedCount,
                    hidden: result.hiddenCount,
                    ordered: result.orderedCount,
                    removedChannels: result.removedChannels.length,
                    removedSources: result.removedSourceCount,
                    final: result.finalChannels.length,
                },
                channels,
                truncated: result.finalChannels.length > MAX_PREVIEW_CHANNELS,
                hidden: result.hidden.slice(0, 200),
                removedChannels: result.removedChannels.slice(0, 200),
                notes: [
                    '预览按客户端同一套规则合成：collect → 接口列表 → audio，名称归一/合并、隐藏、置顶、强制移除源。',
                    '「清理失效源」与家长模式过滤由设备本地决定，预览不包含。',
                ],
            });
        } catch (error) {
            console.error('[programs] 预览失败:', error);
            return jsonFail(res, error.message);
        }
    });

    app.post('/api/admin/programs/push', requireAdmin, (req, res) => {
        try {
            const current = state();
            if (!current.updatedAt) {
                return jsonFail(res, '还没有保存过任何节目文件，无需通知');
            }
            const pushed = pushToOnlineDevices();
            return jsonOk(res, {
                pushed,
                updatedAt: current.updatedAt,
                revision: current.revision,
            }, pushed > 0 ? `已通知 ${pushed} 个在线连接重新拉取` : '当前没有在线设备，设备下次上线或手动刷新时生效');
        } catch (error) {
            console.error('[programs] 通知设备失败:', error);
            return jsonFail(res, error.message);
        }
    });

    app.get('/api/admin/programs', requireAdmin, (req, res) => {
        try {
            const current = state();
            return jsonOk(res, {
                updatedAt: current.updatedAt,
                revision: current.revision,
                files: Object.keys(PROGRAM_FILES).map(metaOf),
            });
        } catch (error) {
            console.error('[programs] 读取文件列表失败:', error);
            return jsonFail(res, error.message);
        }
    });

    app.get('/api/admin/programs/:name', requireAdmin, (req, res) => {
        try {
            const name = String(req.params.name || '');
            if (!specOf(name)) return jsonFail(res, '文件不在节目编辑白名单内');
            const meta = metaOf(name);
            if (!meta.exists) return jsonFail(res, '文件不存在', undefined, 404);
            const { content, lines } = contentOf(name);
            return jsonOk(res, {
                ...meta,
                content,
                lines,
                backups: listBackups(name),
                updatedAt: state().updatedAt,
            });
        } catch (error) {
            console.error('[programs] 读取文件失败:', error);
            return jsonFail(res, error.message);
        }
    });

    app.put('/api/admin/programs/:name', requireAdmin, (req, res) => {
        try {
            const name = String(req.params.name || '');
            const spec = specOf(name);
            if (!spec) return jsonFail(res, '文件不在节目编辑白名单内');
            if (!spec.editable) return jsonFail(res, '该文件只读，不提供编辑入口', undefined, 403);
            const body = req.body || {};
            const meta = metaOf(name);
            if (!meta.exists) return jsonFail(res, '文件不存在，无法覆盖', undefined, 404);
            const expectedMtime = Number(body.expectedMtime);
            if (Number.isFinite(expectedMtime) && expectedMtime > 0 && Math.abs(meta.mtime - expectedMtime) > 1) {
                return jsonFail(res, '文件已被其他人修改，请刷新后重试', undefined, 409);
            }
            const checked = validateSave(name, body.content);
            const backupStamp = backup(name);
            atomicWrite(filePath(name), checked.content);
            const nextState = bumpState();
            let pushed = 0;
            try {
                pushed = pushToOnlineDevices();
            } catch (error) {
                console.error('[programs] 保存后通知设备失败（文件已保存）:', error.message);
            }
            const saved = metaOf(name);
            console.log(`[programs] ${name} 已保存 size=${saved.size} backup=${backupStamp || '-'} pushed=${pushed}`);
            return jsonOk(res, {
                ...saved,
                lines: checked.lines,
                warnings: checked.warnings,
                backup: backupStamp,
                updatedAt: nextState.updatedAt,
                revision: nextState.revision,
                pushed,
            }, pushed > 0
                ? `已保存，并通知 ${pushed} 个在线连接重新拉取`
                : '已保存；当前没有在线设备，下次上线或手动刷新频道时生效');
        } catch (error) {
            console.error('[programs] 保存失败:', error.message);
            return jsonFail(res, error.message);
        }
    });

    app.get('/api/admin/programs/:name/backups', requireAdmin, (req, res) => {
        try {
            const name = String(req.params.name || '');
            if (!specOf(name)) return jsonFail(res, '文件不在节目编辑白名单内');
            return jsonOk(res, { name, backups: listBackups(name) });
        } catch (error) {
            console.error('[programs] 读取备份失败:', error);
            return jsonFail(res, error.message);
        }
    });

    app.post('/api/admin/programs/:name/restore', requireAdmin, (req, res) => {
        try {
            const name = String(req.params.name || '');
            const spec = specOf(name);
            if (!spec) return jsonFail(res, '文件不在节目编辑白名单内');
            if (!spec.editable) return jsonFail(res, '该文件只读，不提供回退入口', undefined, 403);
            const timestamp = String((req.body || {}).timestamp || '').trim();
            if (!/^[0-9]{8}-[0-9]{6}-[0-9]{3}(-[0-9]+)?$/.test(timestamp)) {
                return jsonFail(res, '备份标识无效');
            }
            const backupFile = path.join(backupDir(name), `${timestamp}.bak`);
            if (!fs.existsSync(backupFile)) return jsonFail(res, '该备份不存在', undefined, 404);
            const content = readTextFile(backupFile);
            const checked = validateSave(name, content);
            // 回退前先把当前版本也备份一份，回退本身也可撤销。
            const backupStamp = backup(name);
            atomicWrite(filePath(name), checked.content);
            const nextState = bumpState();
            let pushed = 0;
            try {
                pushed = pushToOnlineDevices();
            } catch (error) {
                console.error('[programs] 回退后通知设备失败（文件已回退）:', error.message);
            }
            const saved = metaOf(name);
            console.log(`[programs] ${name} 已回退到 ${timestamp} backup=${backupStamp || '-'} pushed=${pushed}`);
            return jsonOk(res, {
                ...saved,
                lines: checked.lines,
                warnings: checked.warnings,
                backup: backupStamp,
                restoredFrom: timestamp,
                updatedAt: nextState.updatedAt,
                revision: nextState.revision,
                pushed,
            }, pushed > 0
                ? `已回退到 ${timestamp}，并通知 ${pushed} 个在线连接重新拉取`
                : `已回退到 ${timestamp}；当前没有在线设备，下次上线或手动刷新频道时生效`);
        } catch (error) {
            console.error('[programs] 回退失败:', error.message);
            return jsonFail(res, error.message);
        }
    });

    return {
        updatedAt: () => state().updatedAt,
        revision: () => state().revision,
        notifyOnlineDevices: () => pushToOnlineDevices(),
    };
}

module.exports = {
    attachPrograms,
    // 导出纯函数便于单独验证
    parseM3u,
    normalizeChannelName,
    ChannelNameMatcher,
    composePreview,
    composeFromDir,
    buildFinalChannels,
    validateM3u,
    validateRules,
};
