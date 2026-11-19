// ESP 小屏「系统状态」变量支持模块（sys.* / 天气 / 农历 / 时间 / 城市映射表）。
//
// 设计稿：docs/esp-status-page-config-design.md（v0.4）
// 职责边界：只负责「取数 + 缓存 + 降级 + 农历换算」，不碰 Express 路由、不碰 machines.json。
// 路由与渲染接线在 admin.js；本模块被 require 后以工厂方式注入配置路径。
//
// 变量来源：
// - {sys.time/date}       服务端按设备时区算好下发（设备本地走秒由固件负责）。
// - {sys.lunar}           服务端移植农历算法，零第三方 API。
// - {sys.weather.auto}    服务端出口公网 IP 反查 → 心知 V3，TTL 缓存。
// - {sys.weather.<id>}    按城市映射表 location → 心知 V3，按 id 独立缓存。
// - {sys.online/wifi/rssi/present/occupied/ip/page/total/pageOf} 由固件在绘制时取本机值，
//   服务端不下发（见 design.md 3.2；这些 token 在 actions 渲染时原样留给固件识别）。

'use strict';

// ---------- 农历（移植自 packages/pscreen_screen/lib/features/time/domain/lunar_calendar.dart）----------

const LUNAR_MONTH_CN = ['正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '冬', '腊'];
const CN_DIGIT = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

// 1900–2099 农历信息编码（下标 = year - 1900），与原 Dart 表逐字一致。
const LUNAR_DATA = [
  0x04bd8,
  0x00752, 0x00ea5, 0x0ab2a, 0x0064b, 0x00a9b, 0x09aa6, 0x0056a, 0x00b59, 0x04baa, 0x00752,
  0x0cda5, 0x00b25, 0x00a4b, 0x0ba4b, 0x002ad, 0x0056b, 0x045b5, 0x00da9, 0x0fe92, 0x00e92,
  0x00d25, 0x0ad2d, 0x00a56, 0x002b6, 0x09ad5, 0x006d4, 0x00ea9, 0x04f4a, 0x00e92, 0x0c6a6,
  0x0052b, 0x00a57, 0x0b956, 0x00b5a, 0x006d4, 0x07761, 0x00749, 0x0fb13, 0x00a93, 0x0052b,
  0x0d51b, 0x00aad, 0x0056a, 0x09da5, 0x00ba4, 0x00b49, 0x04d4b, 0x00a95, 0x0eaad, 0x00536,
  0x00aad, 0x0baca, 0x005b2, 0x00da5, 0x07ea2, 0x00d4a, 0x10595, 0x00a97, 0x00556, 0x0c575,
  0x00ad5, 0x006d2, 0x08755, 0x00ea5, 0x0064a, 0x0664f, 0x00a9b, 0x0eada, 0x0056a, 0x00b69,
  0x0abb2, 0x00b52, 0x00b25, 0x08b2b, 0x00a4b, 0x10aab, 0x002ad, 0x0056d, 0x0d5a9, 0x00da9,
  0x00d92, 0x08e95, 0x00d25, 0x14e4d, 0x00a56, 0x002b6, 0x0c2f5, 0x006d5, 0x00ea9, 0x0af52,
  0x00e92, 0x00d26, 0x0652e, 0x00a57, 0x10ad6, 0x0035a, 0x006d5, 0x0ab69, 0x00749, 0x00693,
  0x08a9b, 0x0052b, 0x00a5b, 0x04aae, 0x0056a, 0x0edd5, 0x00ba4, 0x00b49, 0x0ad53, 0x00a95,
  0x0052d, 0x0855d, 0x00ab5, 0x12baa, 0x005d2, 0x00da5, 0x0de8a, 0x00d4a, 0x00c95, 0x08a9e,
  0x00556, 0x00ab5, 0x04ada, 0x006d2, 0x0c765, 0x00725, 0x0064b, 0x0a657, 0x00cab, 0x0055a,
  0x0656e, 0x00b69, 0x16f52, 0x00b52, 0x00b25, 0x0dd0b, 0x00a4b, 0x004ab, 0x0a2bb, 0x005ad,
  0x00b6a, 0x04daa, 0x00d92, 0x0eea5, 0x00d25, 0x00a55, 0x0ba4d, 0x004b6, 0x005b5, 0x076d2,
  0x00ec9, 0x10f92, 0x00e92, 0x00d26, 0x0d516, 0x00a57, 0x00556, 0x09365, 0x00755, 0x00749,
  0x0674b, 0x00693, 0x0eaab, 0x0052b, 0x00a5b, 0x0aaba, 0x0056a, 0x00b65, 0x08baa, 0x00b4a,
  0x10d95, 0x00a95, 0x0052d, 0x0c56d, 0x00ab5, 0x005aa, 0x085d5, 0x00da5, 0x00d4a, 0x06e4d,
  0x00c96, 0x0ecce, 0x00556, 0x00ab5, 0x0bad2, 0x006d2, 0x00ea5, 0x0872a, 0x0068b, 0x10697,
  0x004ab, 0x0055b, 0x0d556, 0x00b6a, 0x00752, 0x08b95, 0x00b45, 0x00a8b, 0x04a4f,
];

function lunarLeapMonth(year) { return (LUNAR_DATA[year - 1900] >> 13) & 0xf; }
function lunarLeapDays(year) {
  const leap = lunarLeapMonth(year);
  if (!leap) return 0;
  return ((LUNAR_DATA[year - 1900] >> 12) & 1) === 1 ? 30 : 29;
}
function lunarMonthDays(year, month) {
  return ((LUNAR_DATA[year - 1900] >> (month - 1)) & 1) === 1 ? 30 : 29;
}
function lunarYearDays(year) {
  let total = 0;
  for (let m = 1; m <= 12; m += 1) total += lunarMonthDays(year, m);
  return total + lunarLeapDays(year);
}
function lunarDayCn(day) {
  if (day === 10) return '初十';
  if (day < 10) return `初${CN_DIGIT[day]}`;
  if (day < 20) return `十${CN_DIGIT[day - 10]}`;
  if (day === 20) return '二十';
  if (day < 30) return `廿${CN_DIGIT[day - 20]}`;
  return '三十';
}

/** 公历 Date → 农历中文短串（如「十月初十」），超出 1900-01-31~2099-12-31 返回 ''。 */
function lunarText(date) {
  const d = date instanceof Date ? date : new Date(date);
  if (Number.isNaN(d.getTime())) return '';
  const base = Date.UTC(1900, 0, 31);
  const cur = Date.UTC(d.getFullYear(), d.getMonth(), d.getDate());
  if (cur < base) return '';
  let offset = Math.round((cur - base) / 86400000);
  let lunarYear = 1900;
  while (lunarYear < 2100) {
    const days = lunarYearDays(lunarYear);
    if (offset < days) break;
    offset -= days;
    lunarYear += 1;
  }
  if (lunarYear >= 2100) return '';
  const leap = lunarLeapMonth(lunarYear);
  let month = 1;
  let isLeap = false;
  for (let m = 1; m <= 12; m += 1) {
    if (offset < lunarMonthDays(lunarYear, m)) { month = m; isLeap = false; break; }
    offset -= lunarMonthDays(lunarYear, m);
    if (leap === m) {
      const ld = lunarLeapDays(lunarYear);
      if (offset < ld) { month = m; isLeap = true; break; }
      offset -= ld;
    }
  }
  return `${isLeap ? '闰' : ''}${LUNAR_MONTH_CN[month - 1]}月${lunarDayCn(offset + 1)}`;
}

module.exports = { lunarText };

// ---------- 以下工厂函数在 createEspSys 中导出（需要注入路径/取数配置）----------

/**
 * 创建 ESP 系统变量服务。
 * @param {object} opts
 *   - adminDir: 配置目录（绝对路径），weatherCities.json 落这里
 *   - readJson(file, fallback) / writeJson(file, value): 复用 admin.js 的原子读写
 *   - log(msg): 可选日志回调
 */
function createEspSys(opts) {
  const adminDir = opts.adminDir;
  const readJson = opts.readJson;
  const writeJson = opts.writeJson;
  const log = typeof opts.log === 'function' ? opts.log : () => {};
  const citiesFile = require('path').join(adminDir, 'weatherCities.json');

  // key / host / 默认城市：环境变量优先（与客户端 .env 同名），无 key 时天气变量降级为空。
  const WEATHER_KEY = (process.env.SENIVERSE_V3_KEY || process.env.SENIVERSE_SECRET_KEY || '').trim();
  const WEATHER_HOST = (process.env.SENIVERSE_WEATHER_HOST_V3 || 'https://api.seniverse.com/v3').trim();
  const DEFAULT_CITY = (process.env.SENIVERSE_DEFAULT_LOCATION || '湛江').trim();
  const IP_GEO_HOSTS = [
    (process.env.SENIVERSE_IP_GEO_HOST || 'https://ipwho.is/').trim(),
    (process.env.SENIVERSE_IP_GEO_HOST_B || 'https://ipapi.co/json/').trim(),
  ];
  const TTL_MS = 30 * 60 * 1000;      // 天气缓存 30 分钟（每 id 独立）
  const IP_TTL_MS = 24 * 60 * 60 * 1000; // IP 反查缓存 24 小时

  // 进程内缓存：id -> { value, source, at }；geo -> { lat, lon, at }
  const weatherCache = new Map();
  let geoCache = null;

  // ---------- 城市映射表 ----------

  const DEFAULT_CITIES = [
    { id: 'auto', name: '自动', location: '' },
    { id: 'gz', name: '广州', location: '广州' },
    { id: 'zj', name: '湛江', location: '湛江' },
    { id: 'fs', name: '佛山', location: '佛山' },
  ];

  function readCities() {
    const raw = readJson(citiesFile, null);
    if (Array.isArray(raw) && raw.length) return normalizeCities(raw);
    return DEFAULT_CITIES.map((c) => Object.assign({}, c));
  }

  function normalizeCities(list) {
    const out = [];
    const seen = new Set(['auto']);
    out.push({ id: 'auto', name: '自动', location: '' });
    for (const item of Array.isArray(list) ? list : []) {
      if (!item || typeof item !== 'object') continue;
      let id = String(item.id || '').trim().toLowerCase();
      if (!/^[a-z0-9]{1,24}$/.test(id) || id === 'auto' || seen.has(id)) continue;
      const name = String(item.name || '').trim().slice(0, 20) || id;
      const location = String(item.location || '').trim().slice(0, 40) || name;
      out.push({ id, name, location });
      seen.add(id);
    }
    return out;
  }

  function saveCities(list) {
    const normalized = normalizeCities(list);
    writeJson(citiesFile, normalized);
    return normalized;
  }

  /** 被模板引用的 id 集合（供删除前检查），由 admin.js 注入扫描函数。 */
  let referencedIdsOf = () => new Set();
  function setReferencedIdsScanner(fn) {
    if (typeof fn === 'function') referencedIdsOf = fn;
  }

  // 拼音首字母（极简：仅覆盖常用城市单字首音；用户可手动覆盖 id）。
  // 冲突消歧规则：首字母 → 全拼 → 加序号，见 design.md 3.6.2。
  function pinyinInitial(name) {
    const map = {
      广: 'g', 州: 'z', 湛: 'z', 江: 'j', 佛: 'f', 山: 's', 镇: 'z', 赣: 'g',
      中: 'z', 舟: 'z', 南: 'n', 京: 'j', 宁: 'n', 北: 'b', 上: 's', 海: 'h',
      深: 's', 圳: 'z', 杭: 'h', 苏: 's', 成: 'c', 都: 'd', 武: 'w', 汉: 'h',
      西: 'x', 安: 'a', 重: 'c', 庆: 'q', 天: 't', 津: 'j', 长: 'c', 沙: 's',
      郑: 'z', 济: 'j', 青: 'q', 大: 'd', 连: 'l', 厦: 'x', 门: 'm', 福: 'f',
      哈: 'h', 尔: 'e', 滨: 'b', 沈: 's', 阳: 'y', 太: 't', 原: 'y', 石: 's',
      家: 'j', 庄: 'z', 合: 'h', 肥: 'f', 济: 'j', 徐: 'x', 昆: 'k', 明: 'm',
    };
    const chars = String(name || '').replace(/\s/g, '');
    let s = '';
    for (const ch of chars) s += map[ch] || '';
    return s.slice(0, 4);
  }
  function pinyinFull(name) {
    const map = {
      广: 'guang', 州: 'zhou', 湛: 'zhan', 江: 'jiang', 佛: 'fo', 山: 'shan', 镇: 'zhen',
      赣: 'gan', 中: 'zhong', 舟: 'zhou', 南: 'nan', 京: 'jing', 宁: 'ning', 北: 'bei',
      上: 'shang', 海: 'hai', 深: 'shen', 圳: 'zhen', 杭: 'hang', 苏: 'su', 成: 'cheng',
      都: 'du', 武: 'wu', 汉: 'han', 西: 'xi', 安: 'an', 重: 'chong', 庆: 'qing',
      天: 'tian', 津: 'jin', 长: 'chang', 沙: 'sha', 郑: 'zheng', 济: 'ji', 青: 'qing',
      大: 'da', 连: 'lian', 厦: 'xia', 门: 'men', 福: 'fu', 哈: 'ha', 尔: 'er',
      滨: 'bin', 沈: 'shen', 阳: 'yang', 太: 'tai', 原: 'yuan', 石: 'shi', 家: 'jia',
      庄: 'zhuang', 合: 'he', 肥: 'fei', 徐: 'xu', 昆: 'kun', 明: 'ming',
    };
    const chars = String(name || '').replace(/\s/g, '');
    let s = '';
    for (const ch of chars) s += map[ch] || '';
    return s.slice(0, 24);
  }

  /** 为城市名生成全局唯一 id：首字母 → 全拼 → 全拼+序号。返回 {id, note}。 */
  function generateCityId(name, existingCities) {
    const taken = new Set((existingCities || []).map((c) => String(c.id || '').toLowerCase()));
    const refs = referencedIdsOf();
    const isTaken = (id) => taken.has(id) || refs.has(id);
    const initial = pinyinInitial(name);
    if (initial && !isTaken(initial)) return { id: initial, note: '' };
    const full = pinyinFull(name);
    if (full && !isTaken(full)) {
      return { id: full, note: initial ? `「${initial}」已被占用，已降级全拼「${full}」` : `已生成全拼「${full}」` };
    }
    let n = 2;
    while (isTaken(`${full}${n}`)) n += 1;
    return { id: `${full}${n}`, note: `全拼也重复，已追加序号「${full}${n}」` };
  }

  // ---------- HTTP 取数 ----------

  async function fetchJson(url, timeoutMs = 6000) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const resp = await fetch(url, { signal: controller.signal, headers: { Accept: 'application/json' } });
      const text = await resp.text();
      let body = null;
      try { body = JSON.parse(text); } catch (_) { body = null; }
      return { status: resp.status, text, body };
    } finally {
      clearTimeout(timer);
    }
  }

  /** 服务端出口 IP 反查经纬度（城市级足够），缓存 24h。 */
  async function resolveGeo() {
    if (geoCache && Date.now() - geoCache.at < IP_TTL_MS) return geoCache;
    for (const host of IP_GEO_HOSTS) {
      try {
        const sep = host.includes('?') ? '&' : '?';
        const { status, body } = await fetchJson(`${host}${sep}_=${Date.now()}`);
        if (status !== 200 || !body || typeof body !== 'object') continue;
        const lat = Number(body.latitude);
        const lon = Number(body.longitude);
        if (Number.isFinite(lat) && Number.isFinite(lon) && (lat !== 0 || lon !== 0)) {
          geoCache = { lat, lon, at: Date.now() };
          return geoCache;
        }
      } catch (e) {
        log(`[esp-sys] IP 反查失败 ${host}: ${e.message}`);
      }
    }
    return null;
  }

  function shortWeather(text, temperature) {
    const t = String(text || '').trim();
    const temp = Number(temperature);
    const deg = Number.isFinite(temp) ? `${Math.round(temp)}°` : '';
    return `${t}${deg}`.trim();
  }

  /** 单个 id 取天气，带缓存与四级降级。返回 {value, source} 或 null。 */
  async function fetchWeatherFor(city) {
    if (!WEATHER_KEY) return null; // 无 key：静默降级，屏上不显示
    const id = city.id;
    const cached = weatherCache.get(id);
    if (cached && Date.now() - cached.at < TTL_MS) return cached;

    let location = city.location || city.name;
    if (id === 'auto') {
      const geo = await resolveGeo();
      if (geo) location = `${geo.lat.toFixed(4)}:${geo.lon.toFixed(4)}`;
      else location = DEFAULT_CITY; // 无定位时 auto 回退默认城市
    }
    if (!location) return null;

    try {
      const url = `${WEATHER_HOST.replace(/\/+$/, '')}/weather/now.json?key=${encodeURIComponent(WEATHER_KEY)}`
        + `&language=zh-Hans&unit=c&location=${encodeURIComponent(location)}`;
      const { status, text, body } = await fetchJson(url);
      if (status === 200 && body && Array.isArray(body.results) && body.results[0] && body.results[0].now) {
        const now = body.results[0].now;
        const value = shortWeather(now.text, now.temperature);
        if (value) {
          const hit = { value, source: 'live', at: Date.now() };
          weatherCache.set(id, hit);
          return hit;
        }
      }
      log(`[esp-sys] 天气取数失败 ${id}/${location}: HTTP ${status} ${String(text || '').slice(0, 80)}`);
    } catch (e) {
      log(`[esp-sys] 天气取数异常 ${id}: ${e.message}`);
    }
    // 降级 2：上次成功缓存（即便过期）
    if (cached && cached.value) return { value: cached.value, source: 'stale', at: cached.at };
    // 降级 3：仅 auto 回退默认城市（指定城市绝不跨城回退）
    if (id === 'auto' && location !== DEFAULT_CITY) {
      const fallback = Object.assign({}, city, { location: DEFAULT_CITY });
      const retried = await fetchWeatherByIdOnly(fallback);
      if (retried) return { value: retried.value, source: 'fallback', at: retried.at };
    }
    return null;
  }

  /** 默认城市兜底专用（不再递归回退）。 */
  async function fetchWeatherByIdOnly(city) {
    try {
      const url = `${WEATHER_HOST.replace(/\/+$/, '')}/weather/now.json?key=${encodeURIComponent(WEATHER_KEY)}`
        + `&language=zh-Hans&unit=c&location=${encodeURIComponent(city.location || city.name)}`;
      const { status, body } = await fetchJson(url);
      if (status === 200 && body && body.results && body.results[0] && body.results[0].now) {
        const value = shortWeather(body.results[0].now.text, body.results[0].now.temperature);
        if (value) {
          const hit = { value, source: 'fallback', at: Date.now() };
          weatherCache.set('auto', hit);
          return hit;
        }
      }
    } catch (_) { /* 兜底失败即输出空 */ }
    return null;
  }

  /**
   * 给一批被引用的 id 取天气，返回字典 { auto:'晴 26°', gz:'多云 29°', ... }。
   * 只取 ids 里的，未引用不请求。并发取数以缩短设备拉取延迟。
   */
  async function buildWeatherDict(ids) {
    const cities = readCities();
    const byId = new Map(cities.map((c) => [c.id, c]));
    const wanted = [...new Set((ids || []).filter((x) => x === 'auto' || byId.has(x)))];
    const dict = {};
    const meta = {};
    if (!wanted.length || !WEATHER_KEY) return { dict, meta, hasKey: !!WEATHER_KEY };
    const settled = await Promise.all(wanted.map(async (id) => {
      try {
        const hit = await fetchWeatherFor(byId.get(id));
        return { id, hit };
      } catch (e) {
        log(`[esp-sys] ${id} 取数异常: ${e.message}`);
        return { id, hit: null };
      }
    }));
    for (const { id, hit } of settled) {
      if (hit && hit.value) { dict[id] = hit.value; meta[id] = hit.source; }
    }
    return { dict, meta, hasKey: true };
  }

  /** admin 状态行用：各 id 的来源/时间/下次刷新倒计时。 */
  function cacheStatus() {
    const out = [];
    for (const [id, hit] of weatherCache.entries()) {
      out.push({
        id,
        value: hit.value,
        source: hit.source,
        updatedAt: hit.at,
        nextRefreshAt: hit.at + TTL_MS,
      });
    }
    return { hasKey: !!WEATHER_KEY, defaultCity: DEFAULT_CITY, items: out };
  }

  return {
    lunarText,
    readCities,
    saveCities,
    normalizeCities,
    generateCityId,
    setReferencedIdsScanner,
    buildWeatherDict,
    cacheStatus,
    cityById: (id) => readCities().find((c) => c.id === id) || null,
  };
}

module.exports.createEspSys = createEspSys;
