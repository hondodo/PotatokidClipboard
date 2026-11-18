'use strict';

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

  function espUid(prefix) {
    return `${prefix}${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
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
      valueMap: '',
      entityValueMap: '',
      // 绑定的遥控设备（中控/电视主键）；空串 = 普通 HA 页面。
      remoteTarget: '',
      buttons: [],
      loop: true,
      idle: 0,
    };
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

  function renderEspDevices() {
    const list = $('espdev-list');
    if (!list || !state.espDevices) return;
    list.innerHTML = state.espDevices.map((dev) => {
      const active = dev.id === state.espDevEditId ? ' active' : '';
      const pages = dev.espPages || [];
      const tag = pages.length ? `${pages.length} 页` : '未配置';
      return `<div class="espdev-item${active}" data-id="${esc(dev.id)}"><span>${esc(dev.name || dev.id)}</span><span class="tag">${esc(tag)}</span></div>`;
    }).join('');
    list.querySelectorAll('.espdev-item').forEach((el) => {
      el.addEventListener('click', async () => {
        state.espDevEditId = el.dataset.id;
        renderEspDevices();
        await openEspDevEditor(state.espDevEditId);
      });
    });
    $('espdev-meta').textContent = `${state.espDevices.length} 台 ESP 设备`;
  }

  let espDevDraft = null;

  function espActivePage() {
    if (!espDevDraft) return null;
    return espDevDraft.pages.find((p) => p.id === espDevDraft.activePageId) || espDevDraft.pages[0] || null;
  }

  /** 遥控设备目录（中控/电视）：一设备一实体，含能力表与实时状态。 */
  async function loadEspRemoteDevices(force = false) {
    if (state.espRemoteDevices && !force) return state.espRemoteDevices;
    try {
      const data = await api('/api/admin/remote/devices');
      state.espRemoteDevices = data.devices || [];
    } catch (error) {
      state.espRemoteDevices = [];
    }
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

  /** 按实体的值替换表：`entity_id: on=有人, off=无人`（一行一个实体）。 */
  function espParseEntityValueMap(text) {
    const map = new Map();
    String(text || '').split('\n').forEach((line) => {
      const idx = line.search(/[:：]/);
      if (idx <= 0) return;
      const entityId = line.slice(0, idx).trim();
      if (!/^[a-z][a-z0-9_]*\.[a-z0-9_]+$/i.test(entityId)) return;
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

  /** 渲染 `{main}/{s1}/{s2}/{title}/{domain.entity}` 模板（与服务端同构）。 */
  function espRenderTemplate(tpl, ctx) {
    return String(tpl || '')
      .replace(/\{([^{}]+)\}/g, (all, rawKey) => {
        const key = rawKey.trim();
        if (key === 'main') return ctx.main;
        if (key === 's1') return ctx.s1;
        if (key === 's2') return ctx.s2;
        if (key === 'title' || key === '名称') return ctx.title;
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

  /** 预览用：按设备类型字典/自定义模板把绑定实体解析成四行文本。 */
  function espPreviewLines(page) {
    const type = espTypeInfo(page.deviceType);
    const dict = (type && type.dict) || { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1}' };
    const index = espEntityIndex();
    const map = espParseValueMap(page.valueMap);
    const entityMaps = espParseEntityValueMap(page.entityValueMap);
    const b = page.bindings || {};
    const ctx = {
      main: espEntityValue(index, map, entityMaps, b.main, dict.mainAttr),
      s1: espEntityValue(index, map, entityMaps, b.s1, 'state'),
      s2: espEntityValue(index, map, entityMaps, b.s2, 'state'),
      title: page.name || '',
      entities: {},
    };
    // 模板里直写的实体 id 也从目录里取值。
    const tplAll = `${page.tplMain || ''} ${page.tplSub || ''}`;
    const re = /\{([a-z][a-z0-9_]*\.[a-z0-9_]+)\}/gi;
    const remotes = new Map((state.espRemoteDevices || []).map((item) => [item.entityId, item]));
    let m;
    while ((m = re.exec(tplAll))) {
      if (m[1].startsWith('remote.')) {
        const dev = remotes.get(m[1]);
        ctx.entities[m[1]] = dev ? (dev.state || '') : '';
        continue;
      }
      ctx.entities[m[1]] = espEntityValue(index, map, entityMaps, m[1], 'state');
    }

    const mainTxt = page.tplMain
      ? espRenderTemplate(page.tplMain, ctx)
      : (ctx.main ? espCleanLine(dict.mainFmt.replace('{v}', ctx.main)) : '');
    const subTxt = page.tplSub
      ? espRenderTemplate(page.tplSub, ctx)
      : espCleanLine(espRenderSub(dict.subTpl, ctx.s1, ctx.s2));
    let keys = (page.buttons || [])
      .filter((item) => item.enabled !== false && Number(item.slot) >= 1)
      .sort((a, b2) => Number(a.slot) - Number(b2.slot))
      .map((item) => {
        const slotName = (espDevDraft && espDevDraft.slotNames || {})[String(item.slot)];
        return `${slotName || item.slot}:${String(item.name || item.label || '').trim()}`;
      })
      .join('  ');
    return { title: page.name || '未命名', main: mainTxt, sub: subTxt, keys };
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

    // 顶部系统状态栏：页码 + IP + WiFi（固件固定绘制，不参与页面配置）。
    const index = espDevDraft.pages.indexOf(page) + 1;
    ctx.font = '8px monospace';
    ctx.fillText(`${index}/${espDevDraft.pages.length}`, 3, 9);
    const dev = (state.espDevices || []).find((d) => d.id === espDevDraft.id) || {};
    if (dev.ip) ctx.fillText(dev.ip, 34, 9);
    for (let i = 0; i < 3; i += 1) ctx.fillRect(110 + i * 4, 9 - (3 + i * 2), 2, 3 + i * 2);

    const lines = espPreviewLines(page);
    ctx.font = '10px "Microsoft YaHei", sans-serif';
    ctx.fillText(espClip(ctx, lines.title, 122), 3, 22);
    ctx.font = 'bold 12px "Microsoft YaHei", sans-serif';
    ctx.fillText(espClip(ctx, lines.main, 122), 3, 38);
    ctx.font = '8px "Microsoft YaHei", sans-serif';
    if (lines.sub) ctx.fillText(espClip(ctx, lines.sub, 122), 3, 50);
    if (lines.keys) {
      ctx.font = '8px monospace';
      ctx.fillText(espClip(ctx, lines.keys, 124), 3, 62);
    }

    const buttonCount = (page.buttons || []).filter((item) => item.enabled !== false).length;
    const displayCount = ['main', 's1', 's2'].filter((slot) => page.bindings && page.bindings[slot]).length;
    $('espdev-preview-meta').innerHTML =
      `页面 <b>${index}/${espDevDraft.pages.length}</b> · ${buttonCount} 个按键 · ${displayCount} 行显示<br>超宽文字在设备上按各行节拍滚动（预览只显示首屏）`;
  }

  function renderEspPages() {
    const box = $('espdev-pages');
    if (!box) return;
    if (!espDevDraft) { box.innerHTML = ''; return; }
    const pages = espDevDraft.pages;
    $('espdev-pagecount').textContent = `${pages.length} 页`;
    box.innerHTML = pages.map((page, index) => `
      <div class="esp-page-chip${page.id === espDevDraft.activePageId ? ' active' : ''}" data-page="${esc(page.id)}">
        <span>${esc(page.icon || '·')}</span>
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
    const types = state.espTypes || [];
    const typeOpts = ['<option value="">通用兜底（domain + state）</option>']
      .concat(types.filter((t) => t.key).map((t) =>
        `<option value="${esc(t.key)}" ${t.key === page.deviceType ? 'selected' : ''}>${esc(t.label || t.key)}</option>`))
      .join('');
    const bindInput = (slot, label) =>
      `<label>${label}<div class="esp-ent-cell">
        <input data-bind="${slot}" value="${esc((page.bindings && page.bindings[slot]) || '')}" placeholder="entity_id" autocomplete="off">
        <button class="btn small" type="button" data-bind-pick="${slot}">选择</button>
      </div></label>`;

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
      const pin = pinOf(button.slot);
      const remoteDev = isRemote ? espRemoteDeviceOf(page.remoteTarget) : null;
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
          paramCell = `<span class="hint">${page.remoteTarget ? '请选择命令' : '请先绑定遥控设备'}</span>`;
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
            <option value="ha" ${!isSys && !isRemote ? 'selected' : ''}>HA 动作</option>
            <option value="remote" ${isRemote ? 'selected' : ''} ${page.remoteTarget ? '' : 'disabled'}>设备遥控</option>
            <option value="sys" ${isSys ? 'selected' : ''}>系统动作</option>
          </select>
          <select data-f="action">${actionOpts}</select>
        </div></td>
        <td><div class="esp-ent-cell">${isRemote ? paramCell : isSys ? '<span class="hint">无需参数</span>' : `
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

    const remoteOpts = ['<option value="">不绑定（普通 HA 页面）</option>']
      .concat((state.espRemoteDevices || []).map((dev) => {
        const kindText = dev.kind === 'home' ? '中控' : '电视';
        return `<option value="${esc(dev.deviceId)}" ${dev.deviceId === page.remoteTarget ? 'selected' : ''}>${esc(dev.name)}（${kindText}${dev.online ? '' : ' · 离线'}）</option>`;
      })).join('');

    const boundRemote = espRemoteDeviceOf(page.remoteTarget);
    const remoteHint = boundRemote
      ? `当前绑定「${esc(boundRemote.name)}」，模板里可写 <b>{${esc(boundRemote.entityId)}}</b> 显示它的场景/音量。`
      : '';

    host.innerHTML = `
      <div class="esp-section">
        <h4>① 页面属性</h4>
        <div class="esp-field-row"><label>页面名称</label><input id="esp-page-name" maxlength="20" value="${esc(page.name)}"></div>
        <div class="esp-field-row"><label>图标</label><input id="esp-page-icon" maxlength="2" value="${esc(page.icon || '')}" style="width:70px"></div>
        <div class="esp-field-row"><label>遥控设备</label><select id="esp-page-remote">${remoteOpts}</select></div>
        <p class="hint">名称显示在屏幕顶部标题行；图标只用于后台列表，不占屏幕像素。选中「遥控设备」后，本页按键可选「设备遥控」，命令从该设备能力表里挑（主页/直播/音量/频道…）；不绑定就是普通 HA 页面。${remoteHint}</p>
      </div>
      <div class="esp-section">
        <h4>② 屏幕显示内容 <span class="tag">由设备类型字典生成</span></h4>
        <div class="esp-field-row"><label>设备类型</label><select id="esp-page-type">${typeOpts}</select></div>
        <div class="esp-bind-grid">${bindInput('main', '主状态')}${bindInput('s1', '副状态 1')}${bindInput('s2', '副状态 2')}</div>
        <p class="hint">点「选择」按家庭 / 房间 / 设备筛选实体，弹窗里会显示当前状态值；也可以直接手填 entity_id。四行文字由「设备类型字典」统一解析，home 端与屏幕同时生效。</p>
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
        <div class="esp-field-row"><label>值替换</label>
          <input id="esp-value-map" maxlength="300" value="${esc(String(page.valueMap || '').replace(/\n/g, '，'))}" placeholder="on=开启, off=关闭">
        </div>
        <div class="esp-field-row tall"><label>按实体替换</label>
          <div class="esp-ent-cell" style="align-items:start">
            <textarea id="esp-entity-value-map" rows="2" maxlength="2000" placeholder="switch.bedroom_light: on=有人, off=无人">${esc(page.entityValueMap || '')}</textarea>
            <button class="btn small" type="button" data-entmap-pick>插入实体</button>
          </div>
        </div>
        <p class="hint">模板留空就用设备类型字典。<b>推荐直接写实体 id</b>（如 <b>{switch.bedroom}</b>，可写多个，绑定不够时用这个）；<b>{main}</b> / <b>{s1}</b> / <b>{s2}</b> 只是三个绑定的快捷写法，<b>{title}</b> 是页面名。点「插入实体」可直接搜家庭/房间/设备。<br>「值替换」是页面级兜底（<b>on=开启, off=关闭</b>）；「按实体替换」一行一个实体（<b>entity_id: on=有人, off=无人</b>），同一状态优先用实体自己的翻译。缺值的段会自动省略，不会留下 <b>--</b> 或 <b>·</b>。</p>
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
        <p class="hint">翻页不需要额外硬件：把任意槽位的行为设为「下一页」即可。</p>
      </div>
      <div class="dt-actions">
        <button class="btn primary small" type="button" id="esp-save">保存并下发</button>
        <button class="btn small" type="button" id="esp-edit-dict">编辑此类型字典 →</button>
        <span class="hint" style="align-self:center">保存后设备下次心跳自动生效</span>
      </div>`;

    $('esp-page-name').addEventListener('input', (event) => {
      page.name = event.target.value;
      $('espdev-title').textContent = `页面配置 · ${page.name || '未命名'}`;
      renderEspPages();
    });
    $('esp-page-icon').addEventListener('input', (event) => {
      page.icon = event.target.value;
      renderEspPages();
    });
    $('esp-page-type').addEventListener('change', (event) => {
      page.deviceType = event.target.value;
      drawEspPreview();
    });
    // 页面绑定遥控设备：绑定后按键才能选「设备遥控」，已有遥控按键保持不变。
    $('esp-page-remote').addEventListener('change', (event) => {
      page.remoteTarget = event.target.value;
      renderEspPageEditor();
    });
    $('esp-tpl-main').addEventListener('input', (event) => {
      page.tplMain = event.target.value;
      drawEspPreview();
    });
    $('esp-tpl-sub').addEventListener('input', (event) => {
      page.tplSub = event.target.value;
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
        const input = which === 'main' ? $('esp-tpl-main') : $('esp-tpl-sub');
        openEntityPicker({
          title: which === 'main' ? '插入实体到主状态模板' : '插入实体到副状态模板',
          onPick: (entity) => {
            const token = `{${entity.id}}`;
            const start = input.selectionStart == null ? input.value.length : input.selectionStart;
            const end = input.selectionEnd == null ? input.value.length : input.selectionEnd;
            input.value = input.value.slice(0, start) + token + input.value.slice(end);
            const pos = start + token.length;
            if (which === 'main') page.tplMain = input.value;
            else page.tplSub = input.value;
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
    host.querySelectorAll('[data-bind]').forEach((el) => {
      el.addEventListener('input', () => {
        page.bindings[el.dataset.bind] = el.value.trim();
        drawEspPreview();
      });
    });
    // 「选择」按钮：打开实体弹窗（家庭/房间/设备筛选 + 当前状态值）。
    const bindLabels = { main: '主状态', s1: '副状态 1', s2: '副状态 2' };
    host.querySelectorAll('[data-bind-pick]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const slot = btn.dataset.bindPick;
        openEntityPicker({
          title: `选择显示实体 · ${bindLabels[slot] || slot}`,
          value: page.bindings[slot] || '',
          onPick: (entity) => {
            page.bindings[slot] = entity.id;
            renderEspPageEditor();
          },
        });
      });
    });
    $('esp-page-loop').addEventListener('change', (event) => {
      page.loop = event.target.value === '1';
    });
    $('esp-page-idle').addEventListener('change', (event) => {
      page.idle = Number(event.target.value) || 0;
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
    $('esp-edit-dict').addEventListener('click', () => {
      state.dtEditKey = page.deviceType || '';
      activateTab('device-types');
    });

    host.querySelectorAll('tr[data-btn]').forEach((tr) => {
      const button = page.buttons.find((item) => item.id === tr.dataset.btn);
      if (!button) return;
      tr.querySelectorAll('[data-f]').forEach((el) => {
        const field = el.dataset.f;
        const commit = () => {
          if (field === 'slot') button.slot = Number(el.value) || 0;
          else if (field === 'name') button.name = el.value;
          else if (field === 'entity') {
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
            const kind = el.value === 'sys' ? 'sys' : el.value === 'remote' ? 'remote' : 'ha';
            button.kind = kind;
            button.param = '';
            button.entityId = '';
            if (kind === 'sys') {
              button.action = 'next_page';
              if (!button.name) button.name = '下一页';
            } else if (kind === 'remote') {
              const dev = espRemoteDeviceOf(page.remoteTarget);
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
              const dev = espRemoteDeviceOf(page.remoteTarget);
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
          if (field === 'kind' || field === 'action') renderEspPageEditor();
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
      valueMap: page.valueMap || '',
      entityValueMap: page.entityValueMap || '',
      remoteTarget: page.remoteTarget || '',
      buttons: (page.buttons || []).map((button) => ({ ...button })),
      loop: page.loop !== false,
      idle: Number(page.idle) || 0,
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
      pages: espDevDraft.pages.map((page) => ({
        id: page.id,
        name: page.name,
        icon: page.icon,
        deviceType: page.deviceType,
        bindings: page.bindings,
        tplMain: page.tplMain || '',
        tplSub: page.tplSub || '',
        valueMap: page.valueMap || '',
        entityValueMap: page.entityValueMap || '',
        remoteTarget: page.remoteTarget || '',
        loop: page.loop !== false,
        idle: Number(page.idle) || 0,
        buttons: (page.buttons || []).map((button) => ({
          id: button.id,
          name: button.name || '',
          // label 仅保留给旧固件协议，值与完整名称一致，不再截短。
          label: button.name || button.label || '',
          kind: button.kind === 'sys' ? 'sys' : button.kind === 'remote' ? 'remote' : 'ha',
          action: button.kind === 'remote' ? button.action
            : button.kind === 'sys'
              ? button.action
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

  // 设备类型字典 / ESP 设备分类的刷新按钮
  if ($('dt-reload')) $('dt-reload').addEventListener('click', () => {
    Promise.all([loadDeviceTypes(true), loadEspDevices(true)])
      .then(() => toast('字典已刷新'))
      .catch((error) => toast('刷新失败：' + error.message, 'error'));
  });
  if ($('espdev-reload')) $('espdev-reload').addEventListener('click', () => {
    Promise.all([loadDeviceTypes(true), loadHaEntities().catch(() => {}), loadEspDevices(true)])
      .then(() => { if (state.espDevEditId) return openEspDevEditor(state.espDevEditId); })
      .catch((error) => toast('刷新失败：' + error.message, 'error'));
  });

  // ------------------------------------------------------------ Tab

