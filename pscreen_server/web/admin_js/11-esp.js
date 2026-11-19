'use strict';

  // 手动控制（场景）在按键里的引用：只认「智能」页建的手动控制。
  // 自动化有自己的触发条件，不该被按键当动作直接调起来。
  function espSceneOf(sceneId) {
    if (!sceneId) return null;
    return (state.scenes || []).find((item) => item.id === sceneId && item.kind === 'manual') || null;
  }

  const ESP_THEMES = {
    blue: { on: '#6cb6ff' },
    white: { on: '#ffffff' },
    yellow: { on: '#ffd23f' },
  };

  // 常用 HA 动作（带参写法与服务端白名单一致）。当前配置不在列表里时，
  // 下拉会把原值补在最前面，不会被静默改掉。
  const ESP_HA_ACTIONS = [
    ['toggle', '切换'],
    ['turn_on', '开'],
    ['turn_off', '关'],
    ['run', '执行'],
    ['set_temperature(+0.5)', '温度 +'],
    ['set_temperature(-0.5)', '温度 −'],
    ['set_percentage(+25)', '数值 +'],
    ['set_percentage(-25)', '数值 −'],
    ['next_effect', '下个效果'],
    ['press', '触发'],
  ];

  // 需要参数的动作：选了它却没填参数，HA 会直接 400，所以行内补一个参数输入框。
  const ESP_HA_PARAM_ACTIONS = new Set([
    'set_temperature', 'set_operation_mode', 'set_hvac_mode', 'set_percentage',
    'select_option', 'number_set', 'brightness', 'next_effect', 'next_option',
  ]);

  function espUid(prefix) {
    return `${prefix}${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
  }

  // 每页状态栏配置：新增项容忍旧配置缺字段，默认值与服务端 normalizeEspStatusBar 保持一致。
  function espStatusBarOf(page) {
    const raw = (page && page.statusBar) || {};
    const on = (key, def) => (raw[key] === undefined ? def : raw[key] !== false);
    return {
      enabled: on('enabled', true),
      showPage: on('showPage', true),
      showTime: on('showTime', true),
      showWifiIcon: on('showWifiIcon', true),
      showRssi: on('showRssi', false),
      showIp: on('showIp', false),
    };
  }

  /**
   * 4 个模板位与显示开关的关系（与服务端 / 固件同口径）：
   * - 主/副状态：恒定可用；
   * - 行3：页面名或按键提示隐藏一个就开放；
   * - 行4：两个都隐藏才开放。
   * 「逐个开放」是为了避免用户编辑了真机看不到的行。
   */
  function espRowVisibility(page) {
    const showTitle = !page || page.showTitle !== false;
    const showKeys = !page || page.showKeys !== false;
    return {
      showTitle,
      showKeys,
      line3: !showTitle || !showKeys,
      line4: !showTitle && !showKeys,
    };
  }

  function newEspPage(index) {
    return {
      id: espUid('p'),
      name: `页面 ${index + 1}`,
      icon: '',
      deviceType: '',
      bindings: { main: '', s1: '', s2: '' },
      // 自定义显示模板 + 值替换（留空 = 走设备类型字典）
      tplMain: '',
      tplSub: '',
      tplLine3: '',
      tplLine4: '',
      showTitle: true,
      showKeys: true,
      valueMap: '',
      entityValueMap: '',
      // 绑定的遥控设备（中控/电视主键）；空串 = 普通 HA 页面。
      remoteTarget: '',
      buttons: [],
      loop: true,
      idle: 0,
      statusBar: espStatusBarOf(null),
      image: { data: '', invert: false, enabled: false },
    };
  }

  /**
   * 上传图片 → 128×64 1-bit 行优先点阵（每行 16 字节，MSB 在前），base64 输出。
   * 与固件 drawImageBits / 服务端 IMG| 协议共用同一格式；不做灰度，阈值二值化。
   */
  function espImageToBits(file) {
    return new Promise((resolve, reject) => {
      if (!file) return reject(new Error('未选择图片'));
      if (file.size > 2 * 1024 * 1024) return reject(new Error('原图请选 2MB 以内'));
      const reader = new FileReader();
      reader.onerror = () => reject(new Error('读取图片失败'));
      reader.onload = () => {
        const img = new Image();
        img.onerror = () => reject(new Error('图片格式无法识别'));
        img.onload = () => {
          const cv = document.createElement('canvas');
          cv.width = 128;
          cv.height = 64;
          const c = cv.getContext('2d', { willReadFrequently: true });
          c.fillStyle = '#fff';
          c.fillRect(0, 0, 128, 64);
          // 透明底按白处理，避免 PNG 透明区被二值化成一片黑点。
          c.drawImage(img, 0, 0, 128, 64);
          const data = c.getImageData(0, 0, 128, 64).data;
          const bits = new Uint8Array(1024);
          for (let y = 0; y < 64; y += 1) {
            for (let x = 0; x < 128; x += 1) {
              const i = (y * 128 + x) * 4;
              // 透明像素无论 RGB 是什么都当白底。
              const a = data[i + 3] / 255;
              const gray = (0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]) * a + 255 * (1 - a);
              if (gray < 128) bits[y * 16 + (x >> 3)] |= 0x80 >> (x & 7);
            }
          }
          let bin = '';
          for (let i = 0; i < bits.length; i += 4096) {
            bin += String.fromCharCode.apply(null, bits.subarray(i, i + 4096));
          }
          resolve(btoa(bin));
        };
        img.src = reader.result;
      };
      reader.readAsDataURL(file);
    });
  }

  /** 预览解码：base64 → 1024 字节点阵，反色由预览端按位取反，与固件一致。 */
  function espDecodeImageBits(data, invert) {
    if (!data) return null;
    let bin;
    try { bin = atob(String(data).replace(/[^A-Za-z0-9+/=]/g, '')); } catch (error) { return null; }
    if (bin.length < 1024) return null;
    const bits = new Uint8Array(1024);
    for (let i = 0; i < 1024; i += 1) bits[i] = bin.charCodeAt(i) & 0xff;
    if (invert) for (let i = 0; i < 1024; i += 1) bits[i] = ~bits[i] & 0xff;
    return bits;
  }

  async function loadEspDevices(force = false) {
    if (state.espDevices && !force) return state.espDevices;
    // 复用 overview 里的机器列表，筛出 ESP 设备（platform 含 esp 或名字带小屏）。
    let machines = state.overview && state.overview.machines;
    if (!machines) {
      const data = await api('/api/admin/overview');
      state.overview = data;
      machines = data.machines || [];
    }
    state.espDevices = machines.filter((m) => {
      const p = String(m.platform || '').toLowerCase();
      return p.includes('esp') || String(m.model || '').toLowerCase().includes('oled')
        || (m.espPages && m.espPages.length > 0);
    });
    if (!state.espDevices.length && machines.length) state.espDevices = machines.slice(); // 兜底：全列出来也能配
    if (state.espDevices.length && !state.espDevEditId) state.espDevEditId = state.espDevices[0].id;
    renderEspDevices();
    return state.espDevices;
  }

  let espPresenceTimer = null;

  const espPad2 = (n) => String(n).padStart(2, '0');

  /** 感应时间：当天只显示时分秒，跨天补 MM-DD，避免把「昨天 23:57」读成今天。 */
  function espClock(ts) {
    const ms = Number(ts) || 0;
    if (!ms) return '—';
    const d = new Date(ms);
    const now = new Date();
    const sameDay = d.getFullYear() === now.getFullYear()
      && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
    const hms = `${espPad2(d.getHours())}:${espPad2(d.getMinutes())}:${espPad2(d.getSeconds())}`;
    return sameDay ? hms : `${espPad2(d.getMonth() + 1)}-${espPad2(d.getDate())} ${hms}`;
  }

  function espAgo(ts) {
    const ms = Number(ts) || 0;
    if (!ms) return '';
    const sec = Math.max(0, Math.floor((Date.now() - ms) / 1000));
    if (sec < 60) return `${sec} 秒前`;
    const min = Math.floor(sec / 60);
    if (min < 60) return `${min} 分钟前`;
    const hour = Math.floor(min / 60);
    if (hour < 24) return `${hour} 小时前`;
    return `${Math.floor(hour / 24)} 天前`;
  }

  /**
   * 人体感应摘要：有人时以「进入」为主，无人时以「离开」为主，另一个时间跟在后面。
   * 时间只在 0/1 跳变时刷新（服务端保证），所以「离开 xx」就是人走后那一刻。
   * 侧栏很窄，返回带 .pir-seg 的片段：每段时间整体不折断，换行只发生在 ` · ` 处，
   * 避免出现「离开 00:03:50（45 秒前）进…」被省略号截断的情况。
   */
  function espPresenceLine(pir) {
    if (!pir) return '';
    const enter = pir.lastEnterAt ? `进入 ${espClock(pir.lastEnterAt)}` : '';
    const leave = pir.lastLeaveAt ? `离开 ${espClock(pir.lastLeaveAt)}` : '';
    const main = pir.present ? enter : leave;
    const other = pir.present ? leave : enter;
    const ago = pir.present ? espAgo(pir.lastEnterAt) : espAgo(pir.lastLeaveAt);
    if (!main) return esc(pir.present ? '已上报有人（无进入时间）' : '还没有人进入过');
    const segs = [`${esc(main)}（${esc(ago)}）`];
    if (other) segs.push(esc(other));
    return segs.map((text) => `<span class="pir-seg">${text}</span>`).join('<span class="pir-sep">·</span>');
  }

  /** 感应行的 hover 提示：进入 / 离开 / 最近一次心跳（状态更新时间）。 */
  function espPirTitle(pir) {
    if (!pir) return '设备未接感应或还没上报过';
    return `最近进入 ${espClock(pir.lastEnterAt)} · 最近离开 ${espClock(pir.lastLeaveAt)} · 状态更新 ${espClock(pir.updatedAt)}`;
  }

  function renderEspDevices() {
    const list = $('espdev-list');
    if (!list || !state.espDevices) return;
    list.innerHTML = state.espDevices.map((dev) => {
      const active = dev.id === state.espDevEditId ? ' active' : '';
      const pages = dev.espPages || [];
      const tag = pages.length ? `${pages.length} 页` : '未配置';
      // 人体感应：固件只在 0/1 跳变时立即上报，服务端存最近一次跳变时间。
      const pir = dev.espPresence;
      // 标签常驻占位：新上报时增量更新就能显示出来，不必整列表重渲染。
      const pirTag = `<span class="tag${pir && pir.present ? ' pir-on' : ''}" data-pir${pir ? '' : ' style="display:none"'}>${pir && pir.present ? '有人' : '无人'}</span>`;
      const pirLine = espPresenceLine(pir);
      return `<div class="espdev-item${active}" data-id="${esc(dev.id)}">`
        + `<span class="espdev-name">${esc(dev.name || dev.id)}</span>`
        + `<span class="espdev-tags">${pirTag}<span class="tag">${esc(dev.role === 'slave' ? '从机' : '主机')}</span><span class="tag">${esc(tag)}</span></span>`
        + `<span class="espdev-pir" title="${esc(espPirTitle(pir))}">${pirLine || '感应未上报'}</span>`
        + '</div>';
    }).join('');
    list.querySelectorAll('.espdev-item').forEach((el) => {
      el.addEventListener('click', async () => {
        state.espDevEditId = el.dataset.id;
        renderEspDevices();
        await openEspDevEditor(state.espDevEditId);
      });
    });
    $('espdev-meta').textContent = `${state.espDevices.length} 台 ESP 设备`;
    ensureEspPresencePolling();
  }

  /**
   * 只覆盖感应那一块，不重建整个列表——高频轮询时不会打断 hover 提示和点击。
   */
  function applyEspPresence(dev) {
    const list = $('espdev-list');
    if (!list) return;
    const id = (window.CSS && CSS.escape) ? CSS.escape(dev.id) : String(dev.id);
    const item = list.querySelector(`.espdev-item[data-id="${id}"]`);
    if (!item) return;
    const pir = dev.espPresence;
    const tagEl = item.querySelector('.tag[data-pir]');
    if (tagEl) {
      tagEl.textContent = pir.present ? '有人' : '无人';
      tagEl.classList.toggle('pir-on', pir.present === true);
      tagEl.style.display = '';
    }
    const lineEl = item.querySelector('.espdev-pir');
    if (lineEl) {
      lineEl.innerHTML = espPresenceLine(pir) || '感应未上报';
      lineEl.title = espPirTitle(pir);
    }
  }

  /**
   * 感应状态轮询：只在列表可见时跑，切到别的标签页自动空转返回。
   * 固件在电平跳变时立刻上报，链路是秒级的，所以这里 4 秒一次就接近「实时」；
   * 走轻量接口 /api/admin/esp/presence（只回 id + espPresence）。
   */
  async function refreshEspPresence() {
    const list = $('espdev-list');
    if (!list || !state.espDevices || list.offsetParent === null) return;
    if (document.visibilityState === 'hidden') return;
    const data = await api('/api/admin/esp/presence');
    const rows = data.devices || [];
    for (const dev of state.espDevices) {
      const fresh = rows.find((item) => item.id === dev.id);
      if (!fresh || !fresh.espPresence) continue;
      dev.espPresence = fresh.espPresence;
      applyEspPresence(dev);
    }
  }

  function ensureEspPresencePolling() {
    if (espPresenceTimer) return;
    espPresenceTimer = setInterval(() => {
      refreshEspPresence().catch(() => {}); // 瞬时失败不打扰，下一轮再说
    }, 4000);
  }

  let espDevDraft = null;

  function espActivePage() {
    if (!espDevDraft) return null;
    return espDevDraft.pages.find((p) => p.id === espDevDraft.activePageId) || espDevDraft.pages[0] || null;
  }

  /** 遥控设备目录（中控/电视）：一设备一实体，含能力表与实时状态。 */
  // 与智能页共用 state.espRemoteDevices 这一份缓存。刷新失败时保留旧值，
  // 不要把缓存清成 []——否则选项会「第一次能看到、刷新失败后就没了」。
  async function loadEspRemoteDevices(force = false) {
    if (state.espRemoteDevices && !force) {
      state.smartRemote = state.espRemoteDevices;
      return state.espRemoteDevices;
    }
    try {
      const data = await api('/api/admin/remote/devices');
      state.espRemoteDevices = data.devices || [];
    } catch (error) {
      // 保留上一次成功加载的目录；只有从未加载过才留空，让界面给出正确提示。
    }
    state.smartRemote = state.espRemoteDevices;
    return state.espRemoteDevices;
  }

  function espRemoteDeviceOf(deviceId) {
    if (!deviceId) return null;
    return (state.espRemoteDevices || []).find((item) => item.deviceId === deviceId) || null;
  }

  /** 遥控命令的默认参数：枚举取第一项，数字取最小值（通常 0），文本留空。 */
  function espDefaultRemoteParam(cap) {
    const arg = cap && cap.args && cap.args[0];
    if (!arg) return '';
    if (arg.type === 'number') return String(arg.min == null ? 0 : arg.min);
    if (arg.type === 'text') return '';
    const first = (arg.options || [])[0];
    return first ? first.value : '';
  }

  // 遥控设备状态标签：模板快捷插入。字段与服务端 REMOTE_STATE_FIELDS 对齐。
  const ESP_REMOTE_TAGS = [
    ['page', '当前页'],
    ['channel', '当前频道'],
    ['volume', '当前音量'],
    ['sleep', '定时开关'],
    ['sleepLeft', '定时剩余'],
  ];

  /** 当前页绑定的遥控设备可用的快捷标签（带当前值）；未绑定返回 null。 */
  function espRemoteQuickTokens(page) {
    const bound = page && page.remoteTarget;
    if (!bound) return null;
    const dev = espRemoteDeviceOf(bound);
    if (!dev) return null;
    const fields = dev.fields || {};
    return {
      label: `遥控状态 · ${dev.name || bound}`,
      items: ESP_REMOTE_TAGS.map(([field, label]) => ({
        id: `${dev.entityId}.${field}`,
        name: label,
        value: fields[field] || '',
      })),
    };
  }

  /**
   * 「插入实体」弹窗的系统状态分组（v0.5）：
   * - 系统状态：内置变量，点击插入 {sys.xxx} / {image}；
   * - 天气城市：从 state.weatherCities 动态生成带参变量 {sys.weather.<id>}。
   * 与 HA 实体/遥控状态在同一弹窗混选，复用 onPick 回调。
   */
  function espSysVarGroups() {
    const SYS_VARS = [
      ['sys.time', '时间 HH:MM'], ['sys.timeSec', '时间 HH:MM:SS'], ['sys.date', '日期'],
      ['sys.lunar', '农历'], ['sys.weather.auto', '天气·自动定位'],
      ['sys.online', '是否联网'], ['sys.wifi', 'WiFi 信号'], ['sys.rssi', '信号强度 dBm'],
      ['sys.present', '人体感应'], ['sys.occupied', '占用状态'], ['sys.ip', '本机 IP'],
      ['sys.page', '当前页'], ['sys.total', '总页数'], ['sys.pageOf', '页码 4/5'],
      // 图片不再靠模板 token：在「屏幕显示内容 → 图片显示」上传并勾选即可。
    ];
    const sysItems = SYS_VARS.map(([id, name]) => ({ id, name, value: `{${id}}` }));
    const cityItems = () => (state.weatherCities || [])
      .filter((c) => c.id !== 'auto')
      .map((c) => ({ id: `sys.weather.${c.id}`, name: `天气·${c.name}`, value: `{sys.weather.${c.id}}` }));
    return [
      { label: '系统状态（新增）', isNew: true, items: sysItems },
      { label: '天气城市（映射表生成 · 一页可多城市）', items: cityItems },
    ];
  }

  /**
   * 所有遥控设备的状态字段 → 伪造成 HA 实体，供「插入实体」弹窗混选。
   * 这样遥控状态与 HA 实体在同一列表，可跨设备、可搜索、可家庭/房间筛选。
   * id 用三段式 remote.<设备id>.<字段>，与后端模板渲染的 REMOTE_TPL_TOKEN_RE 对齐。
   */
  function espRemoteStatusEntities() {
    const out = [];
    for (const dev of (state.espRemoteDevices || [])) {
      const fields = dev.fields || {};
      for (const [field, label] of ESP_REMOTE_TAGS) {
        out.push({
          id: `${dev.entityId}.${field}`,
          name: `${dev.name || dev.deviceId} · ${label}`,
          state: fields[field] || '',
          home: dev.home || '未归属家庭',
          room: dev.kind === 'home' ? '遥控 · 中控' : '遥控 · 电视',
          device: dev.name || dev.deviceId,
          __remoteBadge: '遥控',
          actions: [],
        });
      }
      // 整体摘要标签（当前场景 + 音量），对应 {remote.xxx} 两段式。
      // 必须放在字段循环外：每台设备只生成 1 个，否则会随字段数重复。
      out.push({
        id: dev.entityId,
        name: `${dev.name || dev.deviceId} · 场景与音量`,
        state: dev.state || '',
        home: dev.home || '未归属家庭',
        room: dev.kind === 'home' ? '遥控 · 中控' : '遥控 · 电视',
        device: dev.name || dev.deviceId,
        __remoteBadge: '遥控',
        actions: [],
      });
    }
    return out;
  }

  /** 实体 id → 实体（带 state/attributes），预览用；目录未加载时为空表。 */
  function espEntityIndex() {
    if (state.espEntityIndexSrc === state.haEntities && state.espEntityIndexMap) return state.espEntityIndexMap;
    const map = new Map();
    for (const entity of ((state.haEntities && state.haEntities.entities) || [])) map.set(entity.id, entity);
    state.espEntityIndexSrc = state.haEntities;
    state.espEntityIndexMap = map;
    return map;
  }

  function espTypeInfo(key) {
    const types = state.espTypes || state.deviceTypes || [];
    return types.find((t) => t.key === (key || '')) || null;
  }

  /** 空白行清洗：只由 `--` / `·` / 空白组成的行置空（与服务端 ESP 下发一致）。 */
  function espCleanLine(value) {
    const text = String(value == null ? '' : value).trim();
    if (!text) return '';
    return text.replace(/--/g, '').replace(/·/g, '').trim() ? text : '';
  }

  /** 值替换表：`on=开启, off=关闭`（逗号 / 分号 / 换行分隔）。 */
  function espParseValueMap(text) {
    const map = new Map();
    String(text || '').split(/[\n,;，；]+/).forEach((line) => {
      const m = line.match(/^\s*([^=:：]+?)\s*[=:：]\s*(.*?)\s*$/);
      if (m && m[1]) map.set(m[1], m[2]);
    });
    return map;
  }

  /**
   * 按实体的值替换表：`entity_id: on=有人, off=无人`（一行一个实体）。
   * 键允许 HA 实体两段式，也允许遥控语义字段三段式（如 remote.android_x.sleep）。
   */
  function espParseEntityValueMap(text) {
    const map = new Map();
    String(text || '').split('\n').forEach((line) => {
      const idx = line.search(/[:：]/);
      if (idx <= 0) return;
      const entityId = line.slice(0, idx).trim();
      if (!/^(?:[a-z][a-z0-9_]*\.[a-z0-9_]+|remote\.[a-z0-9_]+\.[a-z]+)$/i.test(entityId)) return;
      const rules = espParseValueMap(line.slice(idx + 1));
      if (rules.size) map.set(entityId, rules);
    });
    return map;
  }

  /** 取实体显示值：优先属性，缺失回落 state；优先按实体替换，再落到页面级。 */
  function espEntityValue(index, map, entityMaps, entityId, attr) {
    const entity = entityId ? index.get(entityId) : null;
    if (!entity) return '';
    const attrs = entity.attributes || {};
    const raw = (attr && attrs[attr] != null && attrs[attr] !== '')
      ? String(attrs[attr])
      : (entity.state != null && entity.state !== '' ? String(entity.state) : '');
    const own = entityMaps.get(entityId);
    if (own && own.has(raw)) return own.get(raw);
    return map.size && map.has(raw) ? map.get(raw) : raw;
  }

  /**
   * 抽出模板里的实体令牌，支持可选第三段属性：
   * `{climate.bed}` → baseId=climate.bed, attr=state
   * `{climate.bed.temperature}` → baseId=climate.bed, attr=temperature
   * key 是 ctx.entities 的查找键（与 {token} 原文一致）。
   * 与服务端 admin.js 的 parseEspTemplateTokens 同构。
   */
  // 本机类 sys 变量由固件绘制时替换，服务端/预览都原样保留 token（与服务端同构）。
  const ESP_FIRMWARE_SYS_KEYS = new Set([
    'sys.online', 'sys.wifi', 'sys.rssi', 'sys.present', 'sys.occupied',
    'sys.ip', 'sys.page', 'sys.total', 'sys.pageof',
  ]);

  function espTemplateTokens(text) {
    const re = /\{([a-z][a-z0-9_]*\.[a-z0-9_]+)(?:\.([a-z0-9_]+))?\}/gi;
    const out = [];
    let m;
    while ((m = re.exec(String(text || '')))) {
      if (m[1].toLowerCase() === 'sys' || m[1].toLowerCase().startsWith('sys.')) continue;
      const attr = m[2] || 'state';
      out.push({ baseId: m[1], attr, key: attr === 'state' ? m[1] : `${m[1]}.${attr}` });
    }
    return out;
  }

  /** 渲染 `{main}/{s1}/{s2}/{title}/{domain.entity[.attr]}/{sys.*}` 模板（与服务端同构）。 */
  function espRenderTemplate(tpl, ctx) {
    return String(tpl || '')
      .replace(/\{([^{}]+)\}/g, (all, rawKey) => {
        const key = rawKey.trim();
        if (key === 'main') return ctx.main;
        if (key === 's1') return ctx.s1;
        if (key === 's2') return ctx.s2;
        if (key === 'title' || key === '名称') return ctx.title;
        const lowerKey = key.toLowerCase();
        if (lowerKey.startsWith('sys.') || key === 'image') {
          // 与服务端同构：图片走独立 IMG 行，正文 {image} 永远渲染为空。
          if (key === 'image') return '';
          if (ctx.sys && Object.prototype.hasOwnProperty.call(ctx.sys, key)) return ctx.sys[key];
          return ESP_FIRMWARE_SYS_KEYS.has(lowerKey) ? `{${key}}` : '';
        }
        return ctx.entities[key] || '';
      })
      .replace(/[ \t]+/g, ' ')
      .replace(/--/g, '')
      .trim();
  }

  /** 字典副状态：缺失的段整段丢弃，避免 `亮度 80% · --`。 */
  function espRenderSub(tpl, s1, s2) {
    const MISSING = '\u0000';
    return String(tpl || '')
      .replace('{s1}', s1 || MISSING)
      .replace('{s2}', s2 || MISSING)
      .split(/\s*·\s*/)
      .map((part) => part.trim())
      .filter((part) => part && !part.includes(MISSING))
      .join(' · ')
      .replace(/--/g, '')
      .trim();
  }

  /** 预览用：按页内模板把实体解析成四行文本（模板留空即空行，无字典兜底）。 */
  function espPreviewLines(page) {
    const index = espEntityIndex();
    const map = espParseValueMap(page.valueMap);
    const entityMaps = espParseEntityValueMap(page.entityValueMap);
    // 与服务端同构：行3/行4 只在对应开关让位后参与渲染。
    const vis = espRowVisibility(page);
    const tplLine3 = vis.line3 ? (page.tplLine3 || '') : '';
    const tplLine4 = vis.line4 ? (page.tplLine4 || '') : '';
    // 模板里直写的实体 id 也从目录里取值。
    const tplAll = `${page.tplMain || ''} ${page.tplSub || ''} ${tplLine3} ${tplLine4}`;
    // 与服务端同构：「显示图片」勾选优先；旧配置按「模板只有 {image}」兼容。
    const showImageOnly = !!(page.image && page.image.enabled && page.image.data)
      || (/\{image\}/.test(tplAll) && !tplAll.replace(/\{image\}/g, ' ').trim());
    const ctx = {
      title: showImageOnly ? '' : (page.name || ''),
      entities: {},
      sys: {},
    };
    // 系统变量预览值（示例；真机由服务端/固件取实时值）。
    const sysTokens = tplAll.match(/\{(?:sys\.[a-zA-Z0-9_.]+|image)\}/g) || [];
    const nowD = new Date();
    const p2 = (n) => String(n).padStart(2, '0');
    const wk = ['日', '一', '二', '三', '四', '五', '六'][nowD.getDay()];
    const demoSys = {
      'sys.time': `${p2(nowD.getHours())}:${p2(nowD.getMinutes())}`,
      'sys.timeSec': `${p2(nowD.getHours())}:${p2(nowD.getMinutes())}:${p2(nowD.getSeconds())}`,
      'sys.date': `${p2(nowD.getMonth() + 1)}-${p2(nowD.getDate())} 周${wk}`,
      'sys.lunar': '十月十一',
      'sys.weather.auto': '晴 26°',
    };
    for (const t of sysTokens) {
      const key = t.slice(1, -1);
      // 图片不作为文字绘制；预览靠点阵块表示，不再写 "[图片]" 占位字样。
      if (key === 'image') continue;
      if (Object.prototype.hasOwnProperty.call(demoSys, key)) ctx.sys[key] = demoSys[key];
      else if (key.startsWith('sys.weather.')) {
        ctx.sys[key] = '晴 26°'; // 预览示例值；城市名由模板手写
      }
    }
    // 三段式遥控标签 `{remote.xxx.channel}` 优先单独匹配（含整体 `{remote.xxx}`）。
    const remoteTplRe = /\{(remote\.([a-z0-9_]+)(?:\.([a-z]+))?)\}/g;
    const remotes = new Map((state.espRemoteDevices || []).map((item) => [item.entityId, item]));
    let rm;
    while ((rm = remoteTplRe.exec(tplAll))) {
      const dev = remotes.get(rm[2] ? `remote.${rm[2]}` : rm[1]);
      const fields = dev && dev.fields ? dev.fields : null;
      if (rm[3] && fields) {
        // 遥控语义字段也走「按实体替换」→ 页面级兜底，键形如 remote.xxx.sleep。
        let value = fields[rm[3]] || '';
        const own = entityMaps.get(rm[1]);
        if (own && own.has(value)) value = own.get(value);
        else if (map.has(value)) value = map.get(value);
        ctx.entities[rm[1]] = value;
      } else if (!rm[3]) ctx.entities[rm[1]] = dev ? (dev.state || '') : '';
      else ctx.entities[rm[1]] = '';
    }
    // 其余 HA 实体（排除已被上面处理的 remote.*），支持可选第三段属性。
    for (const token of espTemplateTokens(tplAll)) {
      if (token.baseId.startsWith('remote.')) continue;
      ctx.entities[token.key] = espEntityValue(index, map, entityMaps, token.baseId, token.attr);
    }

    const mainTxt = page.tplMain ? espRenderTemplate(page.tplMain, ctx) : '';
    const subTxt = page.tplSub ? espRenderTemplate(page.tplSub, ctx) : '';
    const line3Txt = tplLine3 ? espRenderTemplate(tplLine3, ctx) : '';
    const line4Txt = tplLine4 ? espRenderTemplate(tplLine4, ctx) : '';
    let keys = (page.buttons || [])
      .filter((item) => item.enabled !== false && Number(item.slot) >= 1)
      .sort((a, b2) => Number(a.slot) - Number(b2.slot))
      .map((item) => {
        const slotName = (espDevDraft && espDevDraft.slotNames || {})[String(item.slot)];
        return `${slotName || item.slot}:${String(item.name || item.label || '').trim()}`;
      })
      .join('  ');
    // 纯图片页：标题/正文/按键提示全部留空，预览与真机下发保持一致。
    if (showImageOnly) {
      return { title: '', main: '', sub: '', line3: '', line4: '', keys: '', rows: [] };
    }
    const title = vis.showTitle ? (page.name || '未命名') : '';
    const keysText = vis.showKeys ? keys : '';
    // 空行不占位：与服务端 ROWS 行同构，隐藏后内容整体上移。
    const allRows = [title, mainTxt, subTxt, line3Txt, line4Txt, keysText];
    const rows = allRows.map((text) => espCleanLine(text)).filter((text) => text !== '').slice(0, 4);
    return { title, main: mainTxt, sub: subTxt, line3: line3Txt, line4: line4Txt, keys: keysText, rows };
  }

  function espClip(ctx, text, maxWidth) {
    if (ctx.measureText(text).width <= maxWidth) return text;
    let out = text;
    while (out.length && ctx.measureText(`${out}…`).width > maxWidth) out = out.slice(0, -1);
    return `${out}…`;
  }

  function drawEspPreview() {
    const canvas = $('espdev-canvas');
    const page = espActivePage();
    if (!canvas || !espDevDraft || !page) return;
    const ctx = canvas.getContext('2d');
    const theme = ESP_THEMES[$('espdev-theme').value] || ESP_THEMES.blue;
    const on = theme.on;
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, 128, 64);
    ctx.fillStyle = on;
    ctx.textBaseline = 'alphabetic';

    // 顶部状态栏：按本页 statusBar 逐项绘制（每页独立配置，v0.5）。
    const index = espDevDraft.pages.indexOf(page) + 1;
    const sb = espStatusBarOf(page);
    const dev = (state.espDevices || []).find((d) => d.id === espDevDraft.id) || {};
    const hasBar = sb.enabled !== false;
    let sx = 3;
    ctx.font = '8px monospace';
    if (hasBar) {
      if (sb.showPage !== false) { ctx.fillText(`${index}/${espDevDraft.pages.length}`, sx, 9); sx += 26; }
      if (sb.showTime !== false) {
        const d0 = new Date();
        ctx.fillText(`${String(d0.getHours()).padStart(2, '0')}:${String(d0.getMinutes()).padStart(2, '0')}`, sx, 9);
        sx += 30;
      }
      if (sb.showIp && dev.ip) { ctx.fillText(dev.ip, sx, 9); sx += dev.ip.length * 5 + 3; }
      if (sb.showRssi && dev.rssi != null) { ctx.fillText(`${dev.rssi}dBm`, sx, 9); sx += 34; }
      if (sb.showWifiIcon !== false) {
        for (let i = 0; i < 3; i += 1) ctx.fillRect(110 + i * 4, 9 - (3 + i * 2), 2, 3 + i * 2);
      }
    }
    // 四行统一字号、等距排列；隐藏行时空位被后续内容顶替（与固件 ROWS 行同构）。
    // 状态栏显示时内容区从 y=12 起、每行 13px；隐藏时从 y=2 起、每行 15px。
    const rowTop = hasBar ? 12 : 2;
    const rowStep = hasBar ? 13 : 15;

    // 图片（服务端下发的 1-bit 点阵）：预览按真实点位画，所见即真机所见。
    const hasImg = !!(page.image && page.image.data && (page.image.enabled
      || /\{image\}/.test(`${page.tplMain || ''} ${page.tplSub || ''}`)));
    if (hasImg) {
      const bits = espDecodeImageBits(page.image.data, page.image.invert);
      const imgTop = hasBar ? 12 : 0;
      if (bits) {
        ctx.fillStyle = on;
        for (let y = 0; y < 64 - imgTop; y += 1) {
          for (let xb = 0; xb < 16; xb += 1) {
            const byte = bits[y * 16 + xb];
            for (let bit = 0; bit < 8; bit += 1) {
              if (byte & (0x80 >> bit)) ctx.fillRect(xb * 8 + bit, imgTop + y, 1, 1);
            }
          }
        }
      } else {
        ctx.fillStyle = on;
        ctx.fillRect(3, imgTop + 8, 122, 40);
        ctx.fillStyle = '#000';
        ctx.font = '9px "Microsoft YaHei", sans-serif';
        ctx.fillText('点阵数据无效', 8, imgTop + 32);
      }
      ctx.fillStyle = on;
    }

    const lines = espPreviewLines(page);
    // 与真机一致：四行统一 12px 中文字号，不再「标题小 / 主状态大 / 副状态小」。
    ctx.font = '12px "Microsoft YaHei", sans-serif';
    lines.rows.forEach((text, i) => {
      const baseline = rowTop + rowStep * (i + 1) - 2;
      ctx.fillText(espClip(ctx, text, 122), 3, baseline);
    });

    const buttonCount = (page.buttons || []).filter((item) => item.enabled !== false).length;
    $('espdev-preview-meta').innerHTML =
      `页面 <b>${index}/${espDevDraft.pages.length}</b> · ${buttonCount} 个按键 · ${lines.rows.length} 行显示`
      + `<br>状态栏：${hasBar ? '显示' : '隐藏（内容上移）'} · 图片：${hasImg ? '显示' : '关闭'} · 超宽文字按节拍滚动`;
  }

  function renderEspPages() {
    const box = $('espdev-pages');
    if (!box) return;
    if (!espDevDraft) { box.innerHTML = ''; return; }
    const pages = espDevDraft.pages;
    $('espdev-pagecount').textContent = `${pages.length} 页`;
    box.innerHTML = pages.map((page, index) => `
      <div class="esp-page-chip${page.id === espDevDraft.activePageId ? ' active' : ''}" data-page="${esc(page.id)}">
        <span class="nm">${esc(page.name || '未命名')}</span>
        <span class="num">${index + 1}</span>
        <button class="x" type="button" data-del="${esc(page.id)}" title="删除这一页">×</button>
      </div>`).join('')
      + '<button class="esp-page-add" type="button" id="espdev-addpage">＋ 添加页面</button>';

    box.querySelectorAll('[data-page]').forEach((el) => {
      el.addEventListener('click', (event) => {
        if (event.target.closest('[data-del]')) return;
        espDevDraft.activePageId = el.dataset.page;
        renderEspPages();
        renderEspPageEditor();
      });
    });
    box.querySelectorAll('[data-del]').forEach((el) => {
      el.addEventListener('click', (event) => {
        event.stopPropagation();
        const page = espDevDraft.pages.find((p) => p.id === el.dataset.del);
        if (!page) return;
        if (!confirm(`删除页面「${page.name || '未命名'}」？该页的显示与按键配置会一起删除。`)) return;
        espDevDraft.pages = espDevDraft.pages.filter((p) => p.id !== page.id);
        if (!espDevDraft.pages.length) espDevDraft.pages.push(newEspPage(0));
        espDevDraft.activePageId = espDevDraft.pages[0].id;
        renderEspPages();
        renderEspPageEditor();
      });
    });
    $('espdev-addpage').addEventListener('click', addEspPage);
  }

  function addEspPage() {
    if (!espDevDraft) return;
    const page = newEspPage(espDevDraft.pages.length);
    espDevDraft.pages.push(page);
    espDevDraft.activePageId = page.id;
    renderEspPages();
    renderEspPageEditor();
  }

  function renderEspPageEditor() {
    const host = $('espdev-editor');
    const page = espActivePage();
    if (!host) return;
    if (!espDevDraft || !page) {
      host.innerHTML = '<div class="empty">请选择左侧设备</div>';
      return;
    }
    $('espdev-title').textContent = `页面配置 · ${page.name || '未命名'}`;
    const sb = espStatusBarOf(page);
    const imgData = String((page.image && page.image.data) || '');
    const imgEnabled = !!(page.image && page.image.enabled && imgData);
    // 设备本机上报的槽位→GPIO。后台只展示，不反向下发；
    // 槽位 0 显示「—」，本机没启用的槽位显示「未映射」。
    const pinMap = new Map((espDevDraft.buttons || []).map((item) => [Number(item.slot), Number(item.pin)]));
    const pinOf = (slot) => {
      const n = Number(slot);
      if (!n) return { text: '—', mapped: true };
      if (pinMap.has(n)) return { text: `GPIO${pinMap.get(n)}`, mapped: true };
      return { text: '未映射', mapped: false };
    };
    const mappingText = pinMap.size
      ? [...pinMap.entries()].sort((a, b) => a[0] - b[0]).map(([slot, pin]) => `${slot}→GPIO${pin}`).join(' · ')
      : '设备尚未上报';
    const missingSlots = [...new Set((page.buttons || [])
      .filter((item) => item.enabled !== false && Number(item.slot) >= 1 && !pinMap.has(Number(item.slot)))
      .map((item) => Number(item.slot)))].sort((a, b) => a - b);

    // 槽位显示名（设备级）：屏幕底部提示用「蓝色按钮:空调开关」代替「1:空调开关」。
    const slotNames = (espDevDraft && espDevDraft.slotNames) || {};
    // 熄屏秒数（设备级）：0 = 常亮。
    const screenOnSec = Number((espDevDraft.screen || {}).onSeconds) || 0;
    // 只列出实际用到的槽位（本机已映射 + 各页面按键），没有时给 1~4 方便先起名。
    const usedSlots = new Set();
    (espDevDraft.buttons || []).forEach((item) => {
      const slot = Number(item.slot);
      if (slot >= 1) usedSlots.add(slot);
    });
    espDevDraft.pages.forEach((item) => (item.buttons || []).forEach((button) => {
      const slot = Number(button.slot);
      if (slot >= 1) usedSlots.add(slot);
    }));
    const slotList = usedSlots.size ? [...usedSlots].sort((a, b) => a - b) : [1, 2, 3, 4];
    const slotNameFields = slotList.map((slot) => `
      <label class="esp-slotname"><span>${slot}</span>
        <input data-slotname="${slot}" maxlength="16" value="${esc(slotNames[String(slot)] || '')}" placeholder="默认 ${slot}">
      </label>`).join('');

    const buttonRow = (button, index) => {
      const isSys = button.kind === 'sys';
      const isRemote = button.kind === 'remote';
      // 手动控制：按下即执行「智能」页里那条场景的动作组。
      const isScene = button.kind === 'scene';
      const sceneObj = isScene ? espSceneOf(button.sceneId) : null;
      const pin = pinOf(button.slot);
      // 每个遥控按键各自绑定目标设备；旧配置按键没这字段时回退页面级 remoteTarget。
      const btnTarget = button.remoteTarget || page.remoteTarget || '';
      const remoteDev = isRemote ? espRemoteDeviceOf(btnTarget) : null;
      const remoteSpec = isRemote && remoteDev
        ? (remoteDev.capabilities || []).find((item) => item.cmd === button.action)
        : null;
      const actionValue = isSys || isRemote
        ? button.action
        : `${button.action}${button.param ? `(${button.param})` : ''}`;
      const actionList = isSys ? ESP_SYS_ACTION_LABELS
        : isRemote ? (remoteDev ? (remoteDev.capabilities || []).map((item) => [item.cmd, item.label]) : [])
          : ESP_HA_ACTIONS;
      let actionOpts = actionList
        .map(([value, label]) => `<option value="${value}" ${value === actionValue ? 'selected' : ''}>${label}</option>`)
        .join('');
      if (!actionList.some(([value]) => value === actionValue)) {
        actionOpts = `<option value="${esc(actionValue)}" selected>${esc(actionValue)}</option>${actionOpts}`;
      }
      // 遥控按键的「实体」列换成命令参数：枚举出下拉，数字出输入框。
      const arg = remoteSpec && remoteSpec.args && remoteSpec.args[0];
      let paramCell;
      if (isRemote) {
        if (!remoteSpec) {
          paramCell = `<span class="hint">${btnTarget ? '请选择命令' : '请先选目标设备'}</span>`;
        } else if (!arg) {
          paramCell = '<span class="hint">无需参数</span>';
        } else if (arg.type === 'enum') {
          paramCell = `<select data-f="param">${(arg.options || []).map((opt) =>
            `<option value="${esc(opt.value)}" ${opt.value === button.param ? 'selected' : ''}>${esc(opt.label)}</option>`).join('')}</select>`;
        } else if (arg.type === 'text') {
          paramCell = `<input data-f="param" type="text" value="${esc(button.param || '')}" maxlength="40" placeholder="${esc(arg.label || '参数')}">`;
        } else {
          paramCell = `<input data-f="param" type="number" value="${esc(button.param || '')}" min="${esc(arg.min == null ? '' : arg.min)}" max="${esc(arg.max == null ? '' : arg.max)}" placeholder="${esc(arg.label || '参数')}">`;
        }
      }
      // 需要参数的 HA 动作（如 set_temperature）必须显式填值，否则 HA 会 400。
      const needsHaParam = !isSys && !isRemote && ESP_HA_PARAM_ACTIONS.has(button.action);
      const slotOpts = ['<option value="0">—</option>']
        .concat(Array.from({ length: 8 }, (_, i) =>
          `<option value="${i + 1}" ${Number(button.slot) === i + 1 ? 'selected' : ''}>${i + 1}</option>`))
        .join('');
      const total = (page.buttons || []).length;
      return `<tr data-btn="${esc(button.id)}">
        <td class="slot-cell"><select data-f="slot">${slotOpts}</select>${
          slotNames[String(button.slot)] ? `<span class="esp-slot-sub">${esc(slotNames[String(button.slot)])}</span>` : ''
        }</td>
        <td><span class="pin-badge${pin.mapped ? '' : ' off'}">${esc(pin.text)}</span></td>
        <td><input data-f="name" maxlength="40" value="${esc(button.name || button.label || '')}" placeholder="屏幕显示名称"></td>
        <td><div class="esp-action-cell">
          <select data-f="kind">
            <option value="ha" ${!isSys && !isRemote && !isScene ? 'selected' : ''}>HA 动作</option>
            <option value="remote" ${isRemote ? 'selected' : ''}>设备遥控</option>
            <option value="sys" ${isSys ? 'selected' : ''}>系统动作</option>
            <option value="scene" ${isScene ? 'selected' : ''}>手动控制</option>
          </select>
          ${isRemote ? `<select class="esp-remote-target" data-f="remoteTarget" title="${esc(remoteDev ? `本按键控制：${remoteDev.name}` : '本按键要控制的中控/电视')}"><option value="">选择目标设备…</option>${remoteDevOptsFor(btnTarget)}</select>` : ''}
          ${isScene ? '<span class="esp-scene-hint" title="动作组在「智能」页维护，这里只选执行哪一个">执行所选场景</span>' : `<select data-f="action">${actionOpts}</select>`}
          ${needsHaParam ? `<input data-f="param" class="esp-ha-param" value="${esc(button.param || '')}"
            placeholder="参数：+0.5 / -0.5 / 制冷"
            title="该动作必须填参数，否则 HA 会拒绝"
            style="${button.param ? '' : 'border-color:rgba(248,113,113,.65);'}">` : ''}
        </div></td>
        <td><div class="esp-ent-cell">${isRemote ? paramCell : isScene ? espSceneCell(button, sceneObj) : isSys ? '<span class="hint">无需参数</span>' : `
          <input data-f="entity" value="${esc(button.entityId || '')}" placeholder="entity_id" autocomplete="off">
          <button class="btn small" type="button" data-pickbtn="${esc(button.id)}">选择</button>`}
        </div></td>
        <td class="ops-cell">
          <button class="move-btn" type="button" data-upbtn="${esc(button.id)}" title="上移" ${index === 0 ? 'disabled' : ''}>↑</button>
          <button class="move-btn" type="button" data-downbtn="${esc(button.id)}" title="下移" ${index >= total - 1 ? 'disabled' : ''}>↓</button>
          <button class="del-btn" type="button" data-delbtn="${esc(button.id)}" title="删除">×</button>
        </td>
      </tr>`;
    };

    /**
     * 手动控制按键的「实体」列：选一条场景，并在下面写出它会做什么。
     * 摘要很重要——按下按键前不用切回「智能」页确认这条场景到底改了哪些东西。
     */
    const espSceneCell = (button, scene) => {
      const manuals = (state.scenes || []).filter((item) => item.kind === 'manual');
      // 场景被删掉后必须留一个占位项：否则浏览器会自动选中第一条，
      // 界面上看着像绑了另一条，实际存的还是那个不存在的 id，按下去只会报错。
      const orphan = button.sceneId && !manuals.some((item) => item.id === button.sceneId);
      const head = orphan
        ? `<option value="${esc(button.sceneId)}" selected>（原场景已删除，请重选）</option>`
        : '';
      const list = manuals.length
        ? manuals.map((item) => `<option value="${esc(item.id)}" ${!orphan && item.id === button.sceneId ? 'selected' : ''}>${esc(item.name)}</option>`).join('')
        : (orphan ? '' : '<option value="">（还没有手动控制，先去「智能」页建一个）</option>');
      const opts = head + list;
      const cooldown = scene && Number(scene.cooldownSec) > 0 ? ` · 冷却 ${scene.cooldownSec} 秒` : '';
      const desc = scene
        ? `${(scene.actionTexts || []).join(' → ')}${cooldown}`
        : (button.sceneId ? '这条手动控制已被删除，请重新选择' : '请选择一条手动控制');
      return `<div class="esp-scene-cell">
        <select data-f="sceneId">${opts}</select>
        <span class="esp-scene-desc">${esc(desc)}</span>
      </div>`;
    };

    // 遥控按键各自选目标设备：下拉选项在所有中控/电视里列，供每个按键独立选择。
    // 列宽有限：名字里已经带「中控/电视」时不再重复加括号后缀。
    const remoteDevOptsFor = (current) => (state.espRemoteDevices || []).map((dev) => {
      const kindText = dev.kind === 'home' ? '中控' : '电视';
      const label = String(dev.name || '').includes(kindText) ? dev.name : `${dev.name}（${kindText}）`;
      return `<option value="${esc(dev.deviceId)}" ${dev.deviceId === current ? 'selected' : ''}>${esc(label)}${dev.online ? '' : ' · 离线'}</option>`;
    }).join('');

    const rowVis = espRowVisibility(page);
    host.innerHTML = `
      <div class="esp-section">
        <h4>① 页面属性</h4>
        <div class="esp-field-row"><label>页面名称</label><input id="esp-page-name" maxlength="20" value="${esc(page.name)}"></div>
        <div class="esp-field-row"><label>屏幕行显示</label>
          <div class="esp-field-inline">
            <label class="inline-check"><input type="checkbox" id="esp-show-title" ${rowVis.showTitle ? 'checked' : ''}> 显示页面名称</label>
            <label class="inline-check"><input type="checkbox" id="esp-show-keys" ${rowVis.showKeys ? 'checked' : ''}> 显示按键提示</label>
          </div>
        </div>
        <p class="hint">四行统一字号、等距排列。隐藏「页面名称」或「按键提示」会让出一行内容位——下方「内容行3」随之开放编辑；两个都隐藏时再开放「内容行4」。这样你编辑的每一行都能在预览/真机上看到。</p>
        <p class="hint">按键动作可独立选「HA 动作 / 设备遥控 / 系统动作 / 手动控制」（动作组在「智能」页维护）——遥控按键各自选目标中控或电视，一页可控制多台，也能与 HA 按键混用。遥控设备的状态（当前页/频道/音量/定时）可在下方模板的「插入实体」弹窗里跨设备选择。</p>
      </div>
      <div class="esp-section">
        <h4>② 屏幕显示内容 <span class="tag">按页内模板生成</span></h4>
        <div class="esp-field-row"><label>主状态模板</label>
          <div class="esp-ent-cell">
            <input id="esp-tpl-main" maxlength="120" value="${esc(page.tplMain || '')}" placeholder="例：卧室{switch.bedroom} 走廊{switch.corridor}">
            <button class="btn small" type="button" data-tpl-pick="main">插入实体</button>
          </div>
        </div>
        <div class="esp-field-row"><label>副状态模板</label>
          <div class="esp-ent-cell">
            <input id="esp-tpl-sub" maxlength="120" value="${esc(page.tplSub || '')}" placeholder="例：厨房开关：{switch.kitchen}">
            <button class="btn small" type="button" data-tpl-pick="sub">插入实体</button>
          </div>
        </div>
        <div class="esp-field-row" data-line3-row><label>内容行3</label>
          <div class="esp-ent-cell">
            <input id="esp-tpl-line3" maxlength="120" value="${esc(page.tplLine3 || '')}" placeholder="隐藏页面名称或按键提示后可编辑" ${rowVis.line3 ? '' : 'disabled'}>
            <button class="btn small" type="button" data-tpl-pick="line3" ${rowVis.line3 ? '' : 'disabled'}>插入实体</button>
          </div>
        </div>
        <div class="esp-field-row" data-line4-row><label>内容行4</label>
          <div class="esp-ent-cell">
            <input id="esp-tpl-line4" maxlength="120" value="${esc(page.tplLine4 || '')}" placeholder="页面名称与按键提示都隐藏后可编辑" ${rowVis.line4 ? '' : 'disabled'}>
            <button class="btn small" type="button" data-tpl-pick="line4" ${rowVis.line4 ? '' : 'disabled'}>插入实体</button>
          </div>
        </div>
        <p class="hint" id="esp-line-lock-hint">${!rowVis.line3 ? '内容行3/4 未开放：先到「① 页面属性」隐藏「页面名称」或「按键提示」让出屏幕行。' : !rowVis.line4 ? '内容行4 未开放：再把剩下的「页面名称 / 按键提示」也隐藏，让出第 4 行。' : '四行内容位已全部开放，可编辑内容行3、内容行4。'}</p>
        <div class="esp-field-row"><label>值替换</label>
          <input id="esp-value-map" maxlength="300" value="${esc(String(page.valueMap || '').replace(/\n/g, '，'))}" placeholder="on=开启, off=关闭">
        </div>
        <div class="esp-field-row tall"><label>按实体替换</label>
          <div class="esp-ent-cell" style="align-items:start">
            <textarea id="esp-entity-value-map" rows="2" maxlength="2000" placeholder="switch.bedroom_light: on=有人, off=无人">${esc(page.entityValueMap || '')}</textarea>
            <button class="btn small" type="button" data-entmap-pick>插入实体</button>
          </div>
        </div>
        <p class="hint">模板就是屏幕上要显示的内容：<b>直接写实体 id</b>（如 <b>{switch.bedroom}</b>，可写多个），<b>{title}</b> 是页面名；也可点「插入实体」插入 <b>系统状态</b>变量（时间/农历/天气/有人 等），与实体同框混编。主状态模板显示在加粗大字行，副状态模板显示在下方小字行；留空的那行不显示。点「插入实体」可搜家庭/房间/设备；若上方绑了遥控设备，模板框下会直接显示一排<b>遥控状态标签按钮</b>（当前页/频道/音量/定时开关/定时剩余），点一下即插入到光标处。<br>「值替换」是页面级兜底（<b>on=开启, off=关闭</b>）；「按实体替换」一行一个实体（<b>entity_id: on=有人, off=无人</b>），遥控状态字段同样适用（<b>remote.android_xxx.sleep: 关闭=未启用, 开启=关闭剩余</b>），同一状态优先用实体自己的翻译。缺值的段会自动省略，不会留下 <b>--</b> 或 <b>·</b>。</p>
        <div class="esp-image-box">
          <div class="esp-field-row"><label>图片显示</label>
            <div class="esp-ent-cell">
              <label class="inline-check"><input type="checkbox" id="esp-image-enabled" ${imgEnabled ? 'checked' : ''} ${imgData ? '' : 'disabled'}> 显示图片</label>
              <button class="btn small" type="button" id="esp-pick-image">上传图片</button>
              <input type="file" id="esp-image-file" accept="image/*" style="display:none">
              <label class="inline-check"><input type="checkbox" id="esp-image-invert" ${page.image && page.image.invert ? 'checked' : ''}> 反色</label>
              <button class="btn small" type="button" id="esp-clear-image" ${imgData ? '' : 'disabled'}>清除</button>
            </div>
          </div>
          <div class="esp-image-lock" id="esp-image-lock" ${imgEnabled ? '' : 'hidden'}>正在使用图片显示，上方内容编辑已锁定；取消勾选后可继续编辑（原内容会保留）。</div>
          <p class="hint">图片转成 <b>128×64 黑白点阵</b>（无灰度）随配置下发，<b>不烧进固件</b>。上传后会自动勾选「显示图片」：整屏只显示这张图，页面名标题和文字都不再叠加。取消勾选则恢复按上面的模板显示，模板内容会保留。单图 ≤2KB。</p>
        </div>
      </div>
      <div class="esp-section">
        <h4>②b 状态栏 <span class="tag">本页独立</span></h4>
        <div class="esp-field-row"><label>状态栏</label>
          <label class="inline-check"><input type="checkbox" id="esp-sb-enabled" ${sb.enabled ? 'checked' : ''}> 显示</label>
        </div>
        <div class="esp-sb-elements" id="esp-sb-elements">
          ${[
            ['showPage', '页码'],
            ['showTime', '时间'],
            ['showWifiIcon', 'WiFi 图标'],
            ['showRssi', '信号强度'],
            ['showIp', 'IP'],
          ].map(([k, label]) =>
            `<label class="inline-check"><input type="checkbox" data-sb="${k}" ${sb[k] ? 'checked' : ''} ${sb.enabled ? '' : 'disabled'}> ${label}</label>`).join('')}
        </div>
        <p class="hint">状态栏为本页独立配置：隐藏时正文上移占满顶部。128px 单行放不下全部元素，勾选过多会截断——预览里可实时核对。</p>
      </div>
      <div class="esp-section">
        <h4>③ 按键定义 <span class="tag">按页面切换</span></h4>
        <div class="esp-map-line">
          本机按键映射（设备上报）：<b>${esc(mappingText)}</b>
          <button class="btn small" type="button" id="esp-refresh-pins">刷新引脚</button>
        </div>
        <div class="esp-slotnames">
          <div class="esp-slotnames-label">槽位显示名（可选，屏幕提示用名字代替数字）</div>
          <div class="esp-slotnames-grid">${slotNameFields}</div>
        </div>
        ${missingSlots.length ? `<div class="esp-warn">槽位 ${missingSlots.join('、')} 在本机未启用：按下不会触发。请到设备设置页「物理按键槽位」添加或修改 GPIO，或把按键改到已映射的槽位。</div>` : ''}
        <div class="esp-btn-table-wrap">
          <table class="esp-btn-table">
            <thead><tr><th>槽位</th><th>板上 GPIO</th><th>按键名称</th><th>行为</th><th>实体</th><th></th></tr></thead>
            <tbody id="esp-btn-rows">${(page.buttons || []).map(buttonRow).join('')}</tbody>
          </table>
        </div>
        <div class="dt-actions">
          <button class="btn small" type="button" id="esp-add-btn">＋ 添加按键</button>
        </div>
        <p class="hint">「板上 GPIO」来自设备心跳上报的实际槽位映射（后台只读）。显示「未映射」说明本机没启用该槽位，按下不会触发；名称直接用完整文案，屏幕底部提示行放不下会自动滚动。上方「槽位显示名」只影响屏幕提示（数字 → 蓝色按钮），不改槽位号和 GPIO。</p>
      </div>
      <div class="esp-section">
        <h4>④ 翻页与安全</h4>
        <div class="esp-field-row"><label>循环翻页</label>
          <select id="esp-page-loop">
            <option value="1" ${page.loop !== false ? 'selected' : ''}>是（末页回到首页）</option>
            <option value="0" ${page.loop === false ? 'selected' : ''}>否（末页停住）</option>
          </select>
        </div>
        <div class="esp-field-row"><label>空闲返回</label>
          <select id="esp-page-idle">
            <option value="0" ${!page.idle ? 'selected' : ''}>不自动返回</option>
            <option value="60" ${Number(page.idle) === 60 ? 'selected' : ''}>60 秒无操作回首页</option>
            <option value="300" ${Number(page.idle) === 300 ? 'selected' : ''}>5 分钟无操作回首页</option>
          </select>
        </div>
        <div class="esp-field-row"><label>熄屏（人体感应）</label>
          <select id="esp-screen-on">
            <option value="0" ${!screenOnSec ? 'selected' : ''}>常亮（不熄屏）</option>
            <option value="30" ${screenOnSec === 30 ? 'selected' : ''}>人离开后 30 秒熄屏</option>
            <option value="60" ${screenOnSec === 60 ? 'selected' : ''}>人离开后 1 分钟熄屏</option>
            <option value="120" ${screenOnSec === 120 ? 'selected' : ''}>人离开后 2 分钟熄屏</option>
            <option value="300" ${screenOnSec === 300 ? 'selected' : ''}>人离开后 5 分钟熄屏</option>
          </select>
        </div>
        <p class="hint">翻页不需要额外硬件：把任意槽位的行为设为「下一页」即可。<br>
        熄屏需要设备本机设置页填「人体感应 OUT GPIO」：有人时亮屏，人持续在就一直亮，人离开后按这里选的秒数熄屏；熄屏期间只保心跳、不拉页面，唤醒时立刻刷新。</p>
      </div>
      <div class="dt-actions">
        <button class="btn primary small" type="button" id="esp-save">保存并下发</button>
        <span class="hint" style="align-self:center">保存后设备下次心跳自动生效</span>
      </div>`;

    $('esp-page-name').addEventListener('input', (event) => {
      page.name = event.target.value;
      $('espdev-title').textContent = `页面配置 · ${page.name || '未命名'}`;
      renderEspPages();
    });

    // 显示开关 → 逐位开放内容行3/4（与服务端 ROW 行、固件渲染同口径）。
    function applyRowVisibility() {
      const vis = espRowVisibility(page);
      const line3Input = $('esp-tpl-line3');
      const line4Input = $('esp-tpl-line4');
      const line3Pick = host.querySelector('[data-tpl-pick="line3"]');
      const line4Pick = host.querySelector('[data-tpl-pick="line4"]');
      const imgOn = !!(page.image && page.image.enabled && page.image.data);
      line3Input.disabled = !vis.line3 || imgOn;
      line4Input.disabled = !vis.line4 || imgOn;
      if (line3Pick) line3Pick.disabled = !vis.line3 || imgOn;
      if (line4Pick) line4Pick.disabled = !vis.line4 || imgOn;
      const hint = $('esp-line-lock-hint');
      if (hint) hint.textContent = !vis.line3
        ? '内容行3/4 未开放：先隐藏「页面名称」或「按键提示」让出屏幕行。'
        : !vis.line4
          ? '内容行4 未开放：再把剩下的「页面名称 / 按键提示」也隐藏，让出第 4 行。'
          : '四行内容位已全部开放，可编辑内容行3、内容行4。';
    }
    $('esp-show-title').addEventListener('change', (event) => {
      page.showTitle = event.target.checked;
      applyRowVisibility();
      drawEspPreview();
    });
    $('esp-show-keys').addEventListener('change', (event) => {
      page.showKeys = event.target.checked;
      applyRowVisibility();
      drawEspPreview();
    });
    $('esp-tpl-main').addEventListener('input', (event) => {
      page.tplMain = event.target.value;
      drawEspPreview();
    });
    $('esp-tpl-sub').addEventListener('input', (event) => {
      page.tplSub = event.target.value;
      drawEspPreview();
    });
    $('esp-tpl-line3').addEventListener('input', (event) => {
      page.tplLine3 = event.target.value;
      drawEspPreview();
    });
    $('esp-tpl-line4').addEventListener('input', (event) => {
      page.tplLine4 = event.target.value;
      drawEspPreview();
    });
    $('esp-value-map').addEventListener('input', (event) => {
      page.valueMap = event.target.value;
      drawEspPreview();
    });
    $('esp-entity-value-map').addEventListener('input', (event) => {
      page.entityValueMap = event.target.value;
      drawEspPreview();
    });
    // 状态栏：每页独立。关掉总开关时子项只读，隐藏后正文在预览里上移。
    if (!page.statusBar) page.statusBar = espStatusBarOf(null);
    $('esp-sb-enabled').addEventListener('change', (event) => {
      page.statusBar.enabled = event.target.checked;
      host.querySelectorAll('[data-sb]').forEach((box) => { box.disabled = !event.target.checked; });
      drawEspPreview();
    });
    host.querySelectorAll('[data-sb]').forEach((box) => {
      box.addEventListener('change', () => {
        page.statusBar[box.dataset.sb] = box.checked;
        drawEspPreview();
      });
    });
    // 图片：浏览器本地转 128×64 1-bit，base64 随页面配置下发，不进固件。
    if (!page.image) page.image = { data: '', invert: false, enabled: false };
    const imgFile = $('esp-image-file');
    const pickImgBtn = $('esp-pick-image');
    const clearImgBtn = $('esp-clear-image');
    const imgEnabledBox = $('esp-image-enabled');
    const imgLock = $('esp-image-lock');
    const contentFields = [$('esp-tpl-main'), $('esp-tpl-sub'), $('esp-tpl-line3'), $('esp-tpl-line4'),
      $('esp-value-map'), $('esp-entity-value-map')];
    const contentPickers = [...host.querySelectorAll('[data-tpl-pick], [data-entmap-pick]')];
    // 勾选「显示图片」后整页只出图：锁住上方四个内容框并给出明确提示，
    // 避免用户以为文字还会显示。取消勾选即解锁，已填内容原样保留。
    function applyImageLock() {
      const on = !!(page.image.enabled && page.image.data);
      imgEnabledBox.disabled = !page.image.data;
      contentFields.forEach((el) => { if (el) el.disabled = on; });
      contentPickers.forEach((el) => { el.disabled = on; });
      imgLock.hidden = !on;
      applyRowVisibility();
    }
    applyImageLock();
    imgEnabledBox.addEventListener('change', (event) => {
      page.image.enabled = event.target.checked;
      applyImageLock();
      drawEspPreview();
    });
    pickImgBtn.addEventListener('click', () => imgFile.click());
    imgFile.addEventListener('change', async () => {
      const file = imgFile.files && imgFile.files[0];
      if (!file) return;
      const restore = setBtnBusy(pickImgBtn, '转换中…');
      try {
        const data = await espImageToBits(file);
        page.image.data = data;
        // 上传即勾选「显示图片」，无需再在模板里写 {image}。
        page.image.enabled = true;
        imgEnabledBox.checked = true;
        clearImgBtn.disabled = false;
        applyImageLock();
        drawEspPreview();
        toast('图片已转成 128×64 黑白点阵并开启显示，记得点「保存并下发」', 'ok');
      } catch (error) {
        toast('图片转换失败：' + error.message, 'error');
      } finally {
        restore();
        imgFile.value = '';
      }
    });
    $('esp-image-invert').addEventListener('change', (event) => {
      page.image.invert = event.target.checked;
      drawEspPreview();
    });
    clearImgBtn.addEventListener('click', () => {
      page.image.data = '';
      page.image.enabled = false;
      imgEnabledBox.checked = false;
      clearImgBtn.disabled = true;
      applyImageLock();
      drawEspPreview();
    });
    // 槽位显示名（设备级）：立即影响预览底部提示，保存后随页面配置一起下发。
    host.querySelectorAll('[data-slotname]').forEach((el) => {
      el.addEventListener('input', () => {
        const key = el.dataset.slotname;
        if (!espDevDraft.slotNames) espDevDraft.slotNames = {};
        const value = el.value.trim();
        if (value) espDevDraft.slotNames[key] = value;
        else delete espDevDraft.slotNames[key];
        drawEspPreview();
      });
    });
    // 「插入实体」：在光标处插入 {entity_id}，绑定数量不够时可直接引用任意实体。
    host.querySelectorAll('[data-tpl-pick]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const which = btn.dataset.tplPick;
        const inputIds = {
          main: 'esp-tpl-main', sub: 'esp-tpl-sub',
          line3: 'esp-tpl-line3', line4: 'esp-tpl-line4',
        };
        const titles = {
          main: '插入实体到主状态模板', sub: '插入实体到副状态模板',
          line3: '插入实体到内容行3', line4: '插入实体到内容行4',
        };
        const keys = {
          main: 'tplMain', sub: 'tplSub', line3: 'tplLine3', line4: 'tplLine4',
        };
        const input = $(inputIds[which]);
        if (!input) return;
        openEntityPicker({
          title: titles[which] || '插入实体',
          quickTokens: espRemoteQuickTokens(page),
          groups: espSysVarGroups(),
          extraEntities: espRemoteStatusEntities(),
          // 温度、亮度这类值在 HA 里是实体的属性而不是独立实体，列表里选不到，
          // 所以这里允许选中实体后再挑一个属性，插入 `{domain.entity.attr}`。
          withAttributes: true,
          onPick: (entity) => {
            const token = entity.attr ? `{${entity.id}.${entity.attr}}` : `{${entity.id}}`;
            const start = input.selectionStart == null ? input.value.length : input.selectionStart;
            const end = input.selectionEnd == null ? input.value.length : input.selectionEnd;
            input.value = input.value.slice(0, start) + token + input.value.slice(end);
            const pos = start + token.length;
            page[keys[which]] = input.value;
            input.focus();
            input.setSelectionRange(pos, pos);
            drawEspPreview();
          },
        });
      });
    });
    // 「按实体替换」的插入按钮：插入 `entity_id: `，再补 on=…, off=…
    const entMapBtn = host.querySelector('[data-entmap-pick]');
    if (entMapBtn) {
      entMapBtn.addEventListener('click', () => {
        const input = $('esp-entity-value-map');
        openEntityPicker({
          title: '选择要单独替换值的实体',
          onPick: (entity) => {
            const token = `${entity.id}: `;
            const start = input.selectionStart == null ? input.value.length : input.selectionStart;
            const end = input.selectionEnd == null ? input.value.length : input.selectionEnd;
            input.value = input.value.slice(0, start) + token + input.value.slice(end);
            const pos = start + token.length;
            page.entityValueMap = input.value;
            input.focus();
            input.setSelectionRange(pos, pos);
            drawEspPreview();
          },
        });
      });
    }
    $('esp-page-loop').addEventListener('change', (event) => {
      page.loop = event.target.value === '1';
    });
    $('esp-page-idle').addEventListener('change', (event) => {
      page.idle = Number(event.target.value) || 0;
    });
    $('esp-screen-on').addEventListener('change', (event) => {
      // 设备级：保存在 draft 上，随页面一起提交；不随切换页面丢失。
      espDevDraft.screen = { onSeconds: Number(event.target.value) || 0 };
    });
    $('esp-add-btn').addEventListener('click', () => {
      page.buttons.push({
        id: espUid('b'), name: '', label: '',
        kind: 'ha', action: 'toggle', param: '',
        entityId: '', slot: 0, enabled: true,
      });
      renderEspPageEditor();
    });
    $('esp-refresh-pins').addEventListener('click', refreshEspPins);
    $('esp-save').addEventListener('click', saveEspPages);

    host.querySelectorAll('tr[data-btn]').forEach((tr) => {
      const button = page.buttons.find((item) => item.id === tr.dataset.btn);
      if (!button) return;
      tr.querySelectorAll('[data-f]').forEach((el) => {
        const field = el.dataset.f;
        const commit = () => {
          if (field === 'slot') button.slot = Number(el.value) || 0;
          else if (field === 'name') button.name = el.value;
          else if (field === 'remoteTarget') {
            button.remoteTarget = el.value;
            // 换设备后能力表变了：重选第一条命令，参数也跟着重置。
            const dev = espRemoteDeviceOf(button.remoteTarget);
            const cap = dev && (dev.capabilities || [])[0];
            button.action = cap ? cap.cmd : '';
            button.param = espDefaultRemoteParam(cap);
            if (!button.name && cap) button.name = cap.label;
          } else if (field === 'sceneId') {
            button.sceneId = el.value;
            button.action = 'run';
            const scene = espSceneOf(button.sceneId);
            if (!button.name && scene) button.name = scene.name;
          } else if (field === 'entity') {
            button.entityId = el.value.trim();
            // 名称留空时，选中已知实体就用它的人类可读名称自动补上。
            if (!button.name && button.entityId) {
              const entity = espEntityIndex().get(button.entityId);
              if (entity && entity.name) {
                button.name = String(entity.name).slice(0, 40);
                renderEspPageEditor();
                return;
              }
            }
          } else if (field === 'kind') {
            const kind = el.value === 'sys' ? 'sys' : el.value === 'remote' ? 'remote'
              : el.value === 'scene' ? 'scene' : 'ha';
            button.kind = kind;
            button.param = '';
            button.entityId = '';
            if (kind === 'scene') {
              // 默认选第一条手动控制，省掉「切了类型还要再选一次」的空状态。
              const first = (state.scenes || []).find((item) => item.kind === 'manual');
              button.sceneId = button.sceneId || (first ? first.id : '');
              button.action = 'run';
              if (!button.name) button.name = first ? first.name : '手动控制';
            } else if (kind === 'sys') {
              button.action = 'next_page';
              if (!button.name) button.name = '下一页';
            } else if (kind === 'remote') {
              const dev = espRemoteDeviceOf(button.remoteTarget || page.remoteTarget || '');
              const cap = dev && (dev.capabilities || [])[0];
              button.action = cap ? cap.cmd : '';
              button.param = espDefaultRemoteParam(cap);
              if (!button.name && cap) button.name = cap.label;
            } else {
              button.action = 'toggle';
              if (!button.name) button.name = '切换';
            }
          } else if (field === 'action') {
            const value = el.value;
            if (button.kind === 'remote') {
              const dev = espRemoteDeviceOf(button.remoteTarget || page.remoteTarget || '');
              const cap = dev && (dev.capabilities || []).find((item) => item.cmd === value);
              button.action = value;
              button.param = espDefaultRemoteParam(cap);
              if (!button.name && cap) button.name = cap.label;
            } else {
              const isSys = ESP_SYS_VALUES.has(value);
              const m = value.match(/^([a-z_]+)(?:\(([^)]*)\))?$/i);
              button.kind = isSys ? 'sys' : 'ha';
              button.action = m ? m[1] : value;
              button.param = !isSys && m && m[2] != null ? m[2] : '';
              if (isSys) button.entityId = '';
              if (!button.name && el.selectedIndex >= 0) button.name = el.options[el.selectedIndex].text;
            }
          } else if (field === 'param') {
            button.param = el.value;
          }
          drawEspPreview();
          // 换目标设备后命令表变了，必须重绘整行：否则命令下拉还停在选设备前的空态，
          // 看着像「没拉到数据」，其实 button.action 已经被设成第一条命令了。
          if (field === 'kind' || field === 'action' || field === 'sceneId' || field === 'remoteTarget') renderEspPageEditor();
        };
        el.addEventListener('change', commit);
        if (field === 'name' || field === 'entity' || field === 'param') el.addEventListener('input', commit);
      });
      const pick = tr.querySelector('[data-pickbtn]');
      if (pick) {
        pick.addEventListener('click', () => {
          openEntityPicker({
            title: `选择按键实体${button.name ? ` · ${button.name}` : ''}`,
            value: button.entityId || '',
            actionableOnly: true,
            onPick: (entity) => {
              button.entityId = entity.id;
              if (!button.name) button.name = String(entity.name || '').slice(0, 40);
              renderEspPageEditor();
            },
          });
        });
      }
      const del = tr.querySelector('[data-delbtn]');
      if (del) {
        del.addEventListener('click', () => {
          page.buttons = page.buttons.filter((item) => item.id !== button.id);
          renderEspPageEditor();
        });
      }
      // 上移 / 下移：直接交换数组顺序，不用删掉重填。
      const move = (offset) => {
        const from = page.buttons.indexOf(button);
        const to = from + offset;
        if (from < 0 || to < 0 || to >= page.buttons.length) return;
        page.buttons.splice(from, 1);
        page.buttons.splice(to, 0, button);
        renderEspPageEditor();
      };
      const up = tr.querySelector('[data-upbtn]');
      if (up) up.addEventListener('click', () => move(-1));
      const down = tr.querySelector('[data-downbtn]');
      if (down) down.addEventListener('click', () => move(1));
    });

    drawEspPreview();
  }

  /** 只刷新设备上报的槽位→GPIO，不丢当前页未保存的编辑。 */
  async function refreshEspPins() {
    if (!espDevDraft) return;
    try {
      const cfg = await api(`/api/admin/machines/${encodeURIComponent(espDevDraft.id)}/pages`);
      espDevDraft.buttons = Array.isArray(cfg.buttons) ? cfg.buttons : [];
      renderEspPageEditor();
      toast('已刷新本机引脚映射', 'success');
    } catch (error) {
      toast('刷新失败：' + error.message, 'error');
    }
  }

  async function openEspDevEditor(id) {
    const host = $('espdev-editor');
    host.innerHTML = '<div class="empty">加载中…</div>';
    $('espdev-pages').innerHTML = '';
    $('espdev-pagecount').textContent = '';
    // 实体目录只影响下拉候选；没加载成功也能手填 entity_id。
    if (!state.haEntities) {
      try { await loadHaEntities(); } catch (_) { /* 忽略 */ }
    }
    // 遥控设备目录（中控/电视）同理：加载失败时不显示遥控选项，不影响 HA 配置。
    try { await loadEspRemoteDevices(true); } catch (_) { /* 忽略 */ }
    let cfg;
    try {
      cfg = await api(`/api/admin/machines/${encodeURIComponent(id)}/pages`);
    } catch (error) {
      host.innerHTML = `<div class="empty">加载失败：${esc(error.message)}</div>`;
      return;
    }
    state.espTypes = cfg.types || state.deviceTypes || [];
    const dev = state.espDevices.find((d) => d.id === id) || {};
    const pages = (cfg.pages || []).map((page) => ({
      id: page.id,
      name: page.name,
      icon: page.icon || '',
      deviceType: page.deviceType || '',
      bindings: Object.assign({ main: '', s1: '', s2: '' }, page.bindings || {}),
      tplMain: page.tplMain || '',
      tplSub: page.tplSub || '',
      tplLine3: page.tplLine3 || '',
      tplLine4: page.tplLine4 || '',
      showTitle: page.showTitle !== false,
      showKeys: page.showKeys !== false,
      valueMap: page.valueMap || '',
      entityValueMap: page.entityValueMap || '',
      remoteTarget: page.remoteTarget || '',
      // 旧配置迁移：遥控按键没有自己的目标设备时，用页面级 remoteTarget 回填，
      // 这样用户保存一次后，每个按键就独立记住自己的目标设备了。
      buttons: (page.buttons || []).map((button) => ({
        ...button,
        remoteTarget: button.remoteTarget || (button.kind === 'remote' ? (page.remoteTarget || '') : ''),
      })),
      loop: page.loop !== false,
      idle: Number(page.idle) || 0,
      statusBar: espStatusBarOf(page),
      image: {
        data: String((page.image && page.image.data) || ''),
        invert: !!(page.image && page.image.invert),
        enabled: !!(page.image && page.image.enabled && page.image.data),
      },
    }));
    if (!pages.length) pages.push(newEspPage(0));
    espDevDraft = {
      id,
      name: dev.name || id,
      pages,
      activePageId: pages[0].id,
      // 设备本机上报的槽位→GPIO（read-only），用于在后台显示实际引脚。
      buttons: Array.isArray(cfg.buttons) ? cfg.buttons : [],
      // 槽位显示名（设备级）：屏幕底部提示用「蓝色按钮:空调开关」。
      slotNames: Object.assign({}, cfg.slotNames || {}),
      // 熄屏秒数（设备级）：0 = 常亮。
      screen: Object.assign({ onSeconds: 0 }, cfg.screen || {}),
    };

    // 从「HA 实体库 → 绑定到 ESP」跳过来：预填成当前页的一个按键。
    const preset = state.espPreset;
    if (preset && preset.deviceId === id) {
      pages[0].buttons.push({
        id: espUid('b'),
        name: preset.name || '',
        label: preset.name || '',
        kind: 'ha',
        action: 'toggle',
        param: '',
        entityId: preset.entityId,
        slot: 0,
        enabled: true,
      });
      state.espPreset = null;
    }

    $('espdev-title').textContent = `页面配置 · ${espDevDraft.name}`;
    renderEspPages();
    renderEspPageEditor();
  }

  async function saveEspPages() {
    if (!espDevDraft) return;
    const activeId = espDevDraft.activePageId;
    const payload = {
      // 槽位显示名是设备级配置，和页面一起保存。
      slotNames: espDevDraft.slotNames || {},
      // 熄屏秒数（设备级）：0 = 常亮。
      screen: { onSeconds: Number((espDevDraft.screen || {}).onSeconds) || 0 },
      pages: espDevDraft.pages.map((page) => ({
        id: page.id,
        name: page.name,
        icon: page.icon,
        deviceType: page.deviceType,
        bindings: page.bindings,
        tplMain: page.tplMain || '',
        tplSub: page.tplSub || '',
        tplLine3: page.tplLine3 || '',
        tplLine4: page.tplLine4 || '',
        showTitle: page.showTitle !== false,
        showKeys: page.showKeys !== false,
        valueMap: page.valueMap || '',
        entityValueMap: page.entityValueMap || '',
        remoteTarget: page.remoteTarget || '',
        loop: page.loop !== false,
        idle: Number(page.idle) || 0,
        statusBar: espStatusBarOf(page),
        image: {
          data: String((page.image && page.image.data) || ''),
          invert: !!(page.image && page.image.invert),
          enabled: !!(page.image && page.image.enabled && page.image.data),
        },
        buttons: (page.buttons || []).map((button) => ({
          id: button.id,
          name: button.name || '',
          // label 仅保留给旧固件协议，值与完整名称一致，不再截短。
          label: button.name || button.label || '',
          kind: button.kind === 'sys' ? 'sys' : button.kind === 'remote' ? 'remote'
            : button.kind === 'scene' ? 'scene' : 'ha',
          sceneId: button.kind === 'scene' ? (button.sceneId || '') : '',
          remoteTarget: button.kind === 'remote' ? (button.remoteTarget || '') : '',
          action: button.kind === 'remote' ? button.action
            : button.kind === 'sys' ? button.action
              : button.kind === 'scene' ? 'run'
                : `${button.action}${button.param ? `(${button.param})` : ''}`,
          param: button.param || '',
          entityId: button.kind === 'ha' ? (button.entityId || '') : '',
          slot: Number(button.slot) || 0,
          enabled: button.enabled !== false,
        })),
      })),
    };
    const id = espDevDraft.id;
    try {
      await api(`/api/admin/machines/${encodeURIComponent(id)}/pages`, {
        method: 'PUT',
        body: JSON.stringify(payload),
      });
      toast('页面配置已保存，设备下次心跳自动生效', 'success');
      await loadEspDevices(true);
      await openEspDevEditor(id);
      // 回到保存前选中的页，避免保存后跳回第 1 页。
      if (espDevDraft && espDevDraft.pages.some((page) => page.id === activeId)) {
        espDevDraft.activePageId = activeId;
        renderEspPages();
        renderEspPageEditor();
      }
    } catch (error) {
      toast('保存失败：' + error.message, 'error');
    }
  }

  if ($('espdev-theme')) $('espdev-theme').addEventListener('change', drawEspPreview);

  // ESP 设备分类的刷新按钮
  if ($('espdev-reload')) $('espdev-reload').addEventListener('click', () => {
    Promise.all([loadDeviceTypes(true), loadHaEntities().catch(() => {}), loadEspDevices(true)])
      .then(() => { if (state.espDevEditId) return openEspDevEditor(state.espDevEditId); })
      .catch((error) => toast('刷新失败：' + error.message, 'error'));
  });

  // ------------------------------------------------------------ 天气城市映射表

  async function loadWeatherCities(force = false) {
    if (state.weatherCities && !force) return state.weatherCities;
    const data = await api('/api/admin/weather/cities');
    state.weatherCities = data.cities || [];
    state.weatherRefCounts = data.refCounts || {};
    state.weatherCache = data.cache || null;
    state.weatherSeedNames = data.seedNames || [];
    return state.weatherCities;
  }

  function espCopyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).catch(() => {});
      return;
    }
    // admin 常跑在局域网 http 上，Clipboard API 不可用，退回 execCommand。
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.cssText = 'position:fixed;left:-9999px;top:0';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); } catch (error) { /* 复制失败不打断主流程 */ }
    ta.remove();
  }

  /**
   * 城市表只在这里维护；home/tv 运行时不读这份配置。
   * id 由服务端按「首字母 → 全拼 → 序号」生成，落库后不可改，改名不影响缓存 key。
   */
  async function openWeatherCitiesDialog() {
    let data;
    try {
      data = await api('/api/admin/weather/cities');
    } catch (error) {
      toast('城市表加载失败：' + error.message, 'error');
      return;
    }
    state.weatherCities = data.cities || [];
    state.weatherRefCounts = data.refCounts || {};
    state.weatherCache = data.cache || null;
    state.weatherSeedNames = data.seedNames || [];

    const layer = document.createElement('div');
    layer.className = 'ent-pick-layer weather-city-layer';
    layer.innerHTML = `
      <div class="overlay">
        <div class="card dialog wide" role="dialog" aria-modal="true">
          <div class="dialog-head">
            <h3>天气城市映射表</h3>
            <button class="icon-btn" type="button" data-wc-close>×</button>
          </div>
          <div class="dialog-body">
            <p class="hint">模板里写 <code>{sys.weather.gz}</code> 就会显示对应城市天气；一页可以写多个城市。<b>auto</b> 是固定项，取服务端出口 IP 定位，失败回退到默认城市。<br>
            id 由城市名自动生成（首字母冲突时改全拼，再冲突加序号），<b>创建后不可修改</b>；改名只影响显示，不影响缓存。表内改动与 home/tv 无关。</p>
            <div class="wc-add">
              <label>城市名 <input type="text" id="wc-new-name" maxlength="20" placeholder="例：镇江"></label>
              <label>查询地点（可空） <input type="text" id="wc-new-location" maxlength="40" placeholder="默认同城市名"></label>
              <button class="btn small primary" type="button" id="wc-add-btn">＋ 新增城市</button>
            </div>
            <div class="wc-table-wrap">
              <table class="wc-table">
                <thead><tr><th>id（不可改）</th><th>城市名</th><th>查询地点</th><th>引用</th><th>操作</th></tr></thead>
                <tbody id="wc-rows"></tbody>
              </table>
            </div>
            <div class="wc-foot">
              <span class="wc-cache" id="wc-cache"></span>
              <button class="btn small" type="button" id="wc-reseed">从种子文件补入</button>
              <button class="btn small primary" type="button" id="wc-save">保存修改</button>
            </div>
          </div>
          <div class="dialog-foot">
            <span class="hint">被引用的城市不能直接删，先把模板里的 <code>{sys.weather.id}</code> 换掉。</span>
            <button class="btn" type="button" data-wc-close>关闭</button>
          </div>
        </div>
      </div>`;
    $('dialog-root').appendChild(layer);
    const close = () => { layer.remove(); document.removeEventListener('keydown', onKey); };
    const onKey = (event) => { if (event.key === 'Escape') close(); };
    document.addEventListener('keydown', onKey);
    layer.querySelectorAll('[data-wc-close]').forEach((btn) => btn.addEventListener('click', close));
    layer.querySelector('.overlay').addEventListener('click', (event) => {
      if (event.target === layer.querySelector('.overlay')) close();
    });

    const rowsEl = layer.querySelector('#wc-rows');
    const cacheEl = layer.querySelector('#wc-cache');
    const renderRows = () => {
      const refCounts = state.weatherRefCounts || {};
      rowsEl.innerHTML = (state.weatherCities || []).map((c) => {
        const fixed = c.id === 'auto';
        const refs = Number(refCounts[c.id]) || 0;
        return `<tr data-city="${esc(c.id)}">
          <td><code>{sys.weather.${esc(c.id)}}</code><button class="wc-copy" type="button" data-copy="${esc(c.id)}" title="复制变量">复制</button></td>
          <td><input type="text" data-field="name" maxlength="20" value="${esc(c.name)}" ${fixed ? 'disabled' : ''}></td>
          <td><input type="text" data-field="location" maxlength="40" value="${esc(c.location || '')}" ${fixed ? 'disabled' : ''}></td>
          <td>${fixed ? '固定' : (refs ? `<b class="wc-used">${refs} 处</b>` : '—')}</td>
          <td><button class="btn small" type="button" data-del="${esc(c.id)}" ${fixed || refs ? 'disabled' : ''}>删除</button></td>
        </tr>`;
      }).join('');
      const cache = state.weatherCache || {};
      const items = cache.items || [];
      const seeds = Array.from(new Set(state.weatherSeedNames || []));
      const names = new Set((state.weatherCities || []).filter((c) => c.id !== 'auto').map((c) => c.name));
      const seedDiff = seeds.length
        ? ` · 种子 weather_cities.txt ${seeds.length} 项 · 多 ${seeds.filter((n) => !names.has(n)).length} / 少 ${[...names].filter((n) => !seeds.includes(n)).length}`
        : ' · 种子文件不存在（可用下方按钮补入）';
      cacheEl.innerHTML = `${cache.hasKey ? '天气接口已配置' : '<b class="wc-warn">未配置天气 API Key，天气变量会留空</b>'}
        · 默认城市 ${esc(cache.defaultCity || '—')} · 缓存 ${items.length} 项${esc(seedDiff)}`
        + (items.length ? `<br><span class="muted">${items.map((hit) => `${esc(hit.id)}:${esc(hit.source || '')}`).join(' · ')}</span>` : '');
      rowsEl.querySelectorAll('[data-copy]').forEach((btn) => btn.addEventListener('click', () => {
        espCopyText(`{sys.weather.${btn.dataset.copy}}`);
        toast('变量已复制，粘到主状态/副状态模板即可', 'ok');
      }));
      rowsEl.querySelectorAll('[data-del]').forEach((btn) => btn.addEventListener('click', async () => {
        if (!confirm(`删除城市「${btn.dataset.del}」？`)) return;
        const restore = setBtnBusy(btn, '删除中…');
        try {
          const result = await api(`/api/admin/weather/cities/${encodeURIComponent(btn.dataset.del)}`, { method: 'DELETE' });
          state.weatherCities = result.cities || [];
          await loadWeatherCities(true);
          renderRows();
          drawEspPreview();
          toast('城市已删除', 'ok');
        } catch (error) { toast('删除失败：' + error.message, 'error'); restore(); }
      }));
    };
    renderRows();

    layer.querySelector('#wc-add-btn').addEventListener('click', async (event) => {
      const nameInput = layer.querySelector('#wc-new-name');
      const locInput = layer.querySelector('#wc-new-location');
      const name = nameInput.value.trim();
      if (!name) { toast('请填城市名', 'error'); return; }
      const restore = setBtnBusy(event.currentTarget, '新增中…');
      try {
        const result = await api('/api/admin/weather/cities', {
          method: 'POST',
          body: JSON.stringify({ name, location: locInput.value.trim() }),
        });
        await loadWeatherCities(true);
        renderRows();
        drawEspPreview();
        nameInput.value = '';
        locInput.value = '';
        toast(`已新增 ${result.city.name} → ${result.city.id}${result.note ? `（${result.note}）` : ''}`, 'ok');
      } catch (error) { toast('新增失败：' + error.message, 'error'); }
      finally { restore(); }
    });

    layer.querySelector('#wc-save').addEventListener('click', async (event) => {
      const restore = setBtnBusy(event.currentTarget, '保存中…');
      try {
        let changed = 0;
        for (const tr of rowsEl.querySelectorAll('tr[data-city]')) {
          const id = tr.dataset.city;
          if (id === 'auto') continue;
          const original = (state.weatherCities || []).find((c) => c.id === id);
          if (!original) continue;
          const name = tr.querySelector('[data-field="name"]').value.trim();
          const location = tr.querySelector('[data-field="location"]').value.trim();
          if (name === original.name && location === (original.location || '')) continue;
          await api(`/api/admin/weather/cities/${encodeURIComponent(id)}`, {
            method: 'PUT',
            body: JSON.stringify({ name, location }),
          });
          changed += 1;
        }
        await loadWeatherCities(true);
        renderRows();
        drawEspPreview();
        toast(changed ? `已保存 ${changed} 个城市` : '没有需要保存的改动', 'ok');
      } catch (error) { toast('保存失败：' + error.message, 'error'); }
      finally { restore(); }
    });

    layer.querySelector('#wc-reseed').addEventListener('click', async (event) => {
      const restore = setBtnBusy(event.currentTarget, '补入中…');
      try {
        const result = await api('/api/admin/weather/cities/reseed', { method: 'POST' });
        await loadWeatherCities(true);
        renderRows();
        drawEspPreview();
        toast(result.msg || `已补入 ${(result.added || []).length} 个城市`, 'ok');
      } catch (error) { toast('补入失败：' + error.message, 'error'); }
      finally { restore(); }
    });
  }

  if ($('esp-weather-cities')) $('esp-weather-cities').addEventListener('click', openWeatherCitiesDialog);

  // ------------------------------------------------------------ Tab

