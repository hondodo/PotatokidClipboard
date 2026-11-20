'use strict';

  async function loadDeviceTypes(force = false) {
    if (state.deviceTypes && !force) return state.deviceTypes;
    const data = await api('/api/admin/device-types');
    state.deviceTypes = data.types || [];
    return state.deviceTypes;
  }

  // ------------------------------------------------------------ 设备判定规则（规则引擎）

  function reCurType() {
    return (state.deviceTypes || []).find((t) => t.key === state.reEditKey) || (state.deviceTypes || [])[0];
  }
  function reRulesOf(t) { return Array.isArray(t && t.rules) ? t.rules : []; }

  // 判定规则里的「字段 / 操作符」下拉：原生 datalist 会按已输入内容过滤，
  // 输入 contains 就只剩 contains/not_contains、输入 entity_id 就只剩自己，
  // 看不全。这里改成点击弹出「全部」候选（不过滤），同时保留手填任意值。
  const RE_COMBO_OPTIONS = {
    field: [
      { v: 'domain', d: '实体域：switch 开关 / climate 空调 / water_heater 热水器' },
      { v: 'entity_id', d: '实体 ID，如 switch.bedroom；常用「包含」匹配' },
      { v: 'name', d: '设备名，如「米家热水器」' },
      { v: 'state', d: '当前状态值，如 on / off' },
      { v: 'attr.current_temperature', d: '当前温度属性，空调/热水器用它判类型' },
      { v: 'attr.temperature', d: '温度属性，部分设备上报' },
      { v: 'attr.percentage', d: '百分比属性，如风扇风速、灯亮度' },
      { v: 'attr.options', d: '可选值列表，如「自来水」「标准洗」' },
      { v: 'device.model', d: '设备型号，如 xiaomi.waterheater3，比实体 ID 稳定' },
      { v: 'device.name', d: '设备名称（来自 HA 设备注册表）' },
      { v: 'device.manufacturer', d: '厂商，如 xiaomi' },
    ],
    op: [
      { v: 'eq', d: '等于，值完全相同' },
      { v: 'neq', d: '不等于' },
      { v: 'contains', d: '包含：字符串/列表里含某值' },
      { v: 'not_contains', d: '不包含' },
      { v: 'startsWith', d: '开头是，自动忽略 button./switch. 域前缀' },
      { v: 'not_startsWith', d: '开头不是' },
      { v: 'exists', d: '存在且有值（无需填右侧的值）' },
      { v: 'gt', d: '大于，按数值比较' },
      { v: 'lt', d: '小于，按数值比较' },
    ],
  };
  let reComboMenu = null;
  function closeReCombo() {
    if (!reComboMenu) return;
    const active = document.activeElement;
    // 焦点仍在某个候选框上（如从 A 点到 B）时不关，避免误关刚打开的菜单
    if (active && active.matches && active.matches('[data-combo]')) return;
    reComboMenu.hidden = true;
  }
  function attachReCombo(input) {
    input.addEventListener('click', () => {
      const kind = input.dataset.combo;
      const opts = RE_COMBO_OPTIONS[kind] || [];
      if (!reComboMenu) {
        reComboMenu = document.createElement('div');
        reComboMenu.className = 're-combo-menu';
        document.body.appendChild(reComboMenu);
        // 点菜单外关闭
        document.addEventListener('mousedown', (e) => {
          if (reComboMenu && !reComboMenu.hidden && !reComboMenu.contains(e.target)
              && !e.target.closest('[data-combo]')) reComboMenu.hidden = true;
        });
      }
      reComboMenu.innerHTML = opts.map((o) =>
        `<div class="re-combo-opt${o.v === input.value ? ' active' : ''}" data-val="${esc(o.v)}">`
        + `<span class="v">${esc(o.v)}</span><span class="d">${esc(o.d)}</span></div>`).join('');
      reComboMenu.querySelectorAll('.re-combo-opt').forEach((el) => {
        el.addEventListener('mousedown', (e) => {
          e.preventDefault(); // 抢在 input 失焦前，避免菜单先关
          input.value = el.dataset.val;
          input.dispatchEvent(new Event('input', { bubbles: true })); // 走原有同步逻辑
          reComboMenu.hidden = true;
          input.focus();
        });
      });
      const r = input.getBoundingClientRect();
      const menuW = Math.min(400, window.innerWidth * 0.92);
      reComboMenu.style.left = Math.max(8, Math.min(r.left, window.innerWidth - menuW - 8)) + 'px';
      // 空间不足时翻到输入框上方，避免菜单超出视口底部
      const menuH = Math.min(window.innerHeight * 0.6, 460);
      const below = r.bottom + 4;
      reComboMenu.style.top = (below + menuH > window.innerHeight ? Math.max(8, r.top - menuH - 4) : below) + 'px';
      reComboMenu.hidden = false;
    });
    // 菜单打开时不随输入过滤：输入任意内容仍显示全部候选；手填值照常生效
    input.addEventListener('blur', () => { setTimeout(closeReCombo, 150); });
  }

  function renderReTypeList() {
    const host = $('re-type-list');
    if (!host || !state.deviceTypes) return;
    const types = state.deviceTypes;
    if (!state.reEditKey || !types.some((t) => t.key === state.reEditKey)) state.reEditKey = types[0] ? types[0].key : null;
    host.innerHTML = types.map((t) => `
      <div class="dt-item ${t.key === state.reEditKey ? 'active' : ''}" data-key="${esc(t.key)}">
        <span class="ic">${esc(t.icon || '✦')}</span><span>${esc(t.label || t.key || '通用兜底')}</span>
        ${t.dynamic ? '<span class="use">自定义</span>' : ''}
        <span class="use">${reRulesOf(t).length} 规则</span>
      </div>`).join('');
    host.querySelectorAll('.dt-item').forEach((el) => {
      el.addEventListener('click', () => {
        state.reEditKey = el.dataset.key;
        renderReTypeList(); renderReRules(); clearReTestResult();
      });
    });
    if ($('re-meta')) $('re-meta').textContent = `${types.length} 种类型 · ${types.reduce((n, t) => n + reRulesOf(t).length, 0)} 条规则`;
  }

  /** 把当前类型的 card 配置（span / layout / 灰度开关）填进卡片布局编辑区。 */
  function renderReCard(t) {
    const card = (t && t.card) || {};
    const span = card.span || { col: 1, row: 1 };
    const spanSel = $('re-span');
    if (spanSel) spanSel.value = `${span.col || 1}x${span.row || 1}`;
    const ge = $('re-generic-enabled');
    if (ge) ge.checked = card.genericEnabled === true;
    const layoutEl = $('re-layout');
    if (layoutEl) {
      layoutEl.value = card.layout ? JSON.stringify(card.layout, null, 2) : '';
    }
    const status = $('re-layout-status');
    if (status) status.textContent = card.layout ? '已配置自定义布局' : '使用默认布局';
  }

  /** 从编辑区读取 card 配置；layout 文本解析失败时抛出，交调用方提示。 */
  function readReCard() {
    const spanSel = $('re-span');
    const parts = String((spanSel && spanSel.value) || '1x1').split('x').map(Number);
    const span = { col: parts[0] || 1, row: parts[1] || 1 };
    const ge = $('re-generic-enabled');
    const layoutEl = $('re-layout');
    let layout = null;
    if (layoutEl && layoutEl.value.trim()) {
      layout = JSON.parse(layoutEl.value); // 解析失败由调用方 catch
    }
    return {
      span,
      layout,
      genericEnabled: !!(ge && ge.checked),
    };
  }

  function setLayoutStatus(msg, ok = true) {
    const el = $('re-layout-status');
    if (el) {
      el.textContent = msg;
      el.style.color = ok ? 'var(--accent)' : '#ff8080';
    }
  }

  function renderReRules() {
    const host = $('re-rules');
    const t = reCurType();
    if (!host) return;
    if (!t) { host.innerHTML = '<div class="empty">无类型</div>'; return; }
    if ($('re-title')) $('re-title').textContent = `判定规则 · ${t.label || t.key || '通用兜底'}`;
    if ($('re-priority')) $('re-priority').value = Number(t.priority) || 5;
    renderReCard(t);
    const rules = reRulesOf(t);
    if (!rules.length) {
      host.innerHTML = '<div class="empty">该类型暂无规则，点下方「添加规则」。</div>';
      return;
    }
    host.innerHTML = rules.map((r, ri) => {
      const conds = Array.isArray(r.conds) ? r.conds : [];
      const condHtml = conds.map((c, ci) => `
        <div class="re-cond">
          <span class="lbl">${ci === 0 ? '当' : '且'}</span>
          <input type="text" value="${esc(c.field)}" data-r="${ri}" data-c="${ci}" data-k="field" data-combo="field" title="字段：点击看全部候选，也可手填 attr.xxx / device.model">
          <input type="text" value="${esc(c.op)}" data-r="${ri}" data-c="${ci}" data-k="op" data-combo="op" title="操作符：点击看全部候选">
          <input type="text" value="${esc(c.value)}" data-r="${ri}" data-c="${ci}" data-k="value" placeholder="值" ${c.op === 'exists' ? 'disabled' : ''}>
          <button class="re-btn-icon" type="button" data-del-cond="${ri}:${ci}" title="删除条件">×</button>
        </div>`).join('');
      return `
        <div class="re-rule ${r.enabled === false ? 'off' : ''}">
          <div class="re-rule-head">
            <input class="sw" type="checkbox" data-toggle-rule="${ri}" ${r.enabled !== false ? 'checked' : ''} title="启用">
            <input type="text" value="${esc(r.name || '')}" data-rule-name="${ri}" placeholder="规则名称">
            <button class="re-btn-icon" type="button" data-del-rule="${ri}" title="删除规则">×</button>
          </div>
          ${condHtml}
          <div class="re-btn-row"><button class="btn small" type="button" data-add-cond="${ri}">＋ 条件</button></div>
        </div>`;
    }).join('');

    host.querySelectorAll('[data-toggle-rule]').forEach((el) => el.addEventListener('change', () => {
      reCurType().rules[+el.dataset.toggleRule].enabled = el.checked;
      renderReRules(); renderReTypeList(); clearReTestResult();
    }));
    host.querySelectorAll('[data-rule-name]').forEach((el) => el.addEventListener('input', () => {
      reCurType().rules[+el.dataset.ruleName].name = el.value;
    }));
    host.querySelectorAll('[data-del-rule]').forEach((el) => el.addEventListener('click', () => {
      reCurType().rules.splice(+el.dataset.delRule, 1);
      renderReRules(); renderReTypeList(); clearReTestResult();
    }));
    host.querySelectorAll('[data-add-cond]').forEach((el) => el.addEventListener('click', () => {
      reCurType().rules[+el.dataset.addCond].conds.push({ field: 'domain', op: 'eq', value: '' });
      renderReRules(); clearReTestResult();
    }));
    host.querySelectorAll('[data-del-cond]').forEach((el) => el.addEventListener('click', () => {
      const [ri, ci] = el.dataset.delCond.split(':').map(Number);
      reCurType().rules[ri].conds.splice(ci, 1);
      renderReRules(); clearReTestResult();
    }));
    host.querySelectorAll('.re-cond input[data-k]').forEach((el) => el.addEventListener('input', () => {
      const ri = +el.dataset.r, ci = +el.dataset.c, k = el.dataset.k;
      const cond = reCurType().rules[ri].conds[ci];
      cond[k] = el.value;
      if (k === 'op') {
        const valInput = el.parentElement.querySelector('input[data-k="value"]');
        if (valInput) valInput.disabled = el.value === 'exists';
      }
      clearReTestResult();
    }));
    // 字段 / 操作符：点击展开全部候选（不过滤），仍可手填
    host.querySelectorAll('.re-cond input[data-combo]').forEach(attachReCombo);
  }

  /** 从 state.haDevices 构建 deviceId -> visible(true/false/null) 映射。 */
  function reVisibilityMap() {
    const map = {};
    for (const d of (state.haDevices || [])) map[d.id] = d.visible;
    return map;
  }

  function renderReTestSel() {
    const sel = $('re-test-device');
    if (!sel) return;
    const onlyVisible = !!($('re-test-only-visible') && $('re-test-only-visible').checked);
    const visMap = reVisibilityMap();
    const ents = (state.haEntities && state.haEntities.entities) || [];
    const byDevice = new Map();
    for (const e of ents) {
      const key = e.deviceId || e.id;
      if (onlyVisible && visMap[key] === false) continue;
      if (!byDevice.has(key)) byDevice.set(key, { name: e.device || e.name || key, id: key, entities: [] });
      byDevice.get(key).entities.push(e);
    }
    state.reTestEntities = Array.from(byDevice.values());
    if (state.reTestIdx >= state.reTestEntities.length) state.reTestIdx = 0;
    sel.innerHTML = state.reTestEntities.map((d, i) => `<option value="${i}" ${i === state.reTestIdx ? 'selected' : ''}>${esc(d.name)}</option>`).join('')
      || '<option>无 HA 实体</option>';
    renderReTestEnts();
  }

  function renderReTestEnts() {
    const host = $('re-test-ents');
    const d = state.reTestEntities[state.reTestIdx];
    if (host) host.innerHTML = d ? d.entities.map((e) => `<div class="en"><span class="d">${esc(e.domain)}</span><span class="eid">${esc(e.id)}${e.deviceModel ? ' · ' + esc(e.deviceModel) : ''}</span></div>`).join('') : '—';
  }

  function clearReTestResult() {
    const host = $('re-test-result');
    if (host) host.innerHTML = '<span class="hint">规则已改动，点「运行判定」重新验证。</span>';
  }

  async function runReTest() {
    const d = state.reTestEntities[state.reTestIdx];
    const host = $('re-test-result');
    if (!d || !host) return;
    host.textContent = '判定中…';
    const entities = d.entities.map((e) => ({
      id: e.id, domain: e.domain, name: e.name, state: e.state, attrs: e.attributes || {},
      device: { name: e.device || '', model: e.deviceModel || '', manufacturer: e.manufacturer || '' },
    }));
    try {
      // 传编辑器当前态（含未保存改动）：改完规则不保存也能立即试，错了直接再改即可回滚。
      // 优先级输入框的值要先同步进当前类型，否则测试仍用旧优先级。
      const cur = reCurType();
      const priorityEl = $('re-priority');
      if (cur && priorityEl) cur.priority = Number(priorityEl.value) || 0;
      const data = await api('/api/admin/device-types/classify', {
        method: 'POST', body: JSON.stringify({ entities, types: state.deviceTypes }),
      });
      const r = data.result;
      if (!r) {
        host.innerHTML = '<span class="hint">没有规则命中，将落到通用兜底类型。</span><br><span class="hint" style="font-size:11px">（用的是编辑器当前规则，尚未保存也能试）</span>';
        return;
      }
      const others = (r.allHits || []).filter((h) => h.key !== r.key);
      host.innerHTML = `<div class="re-hit win"><span class="nm">判定结果：${esc(r.label)}</span><br>
        <span class="sc">具体度 ${r.specificity} · 优先级 ${r.priority}</span></div>
        ${(r.matchedRules || []).map((n) => `<div class="re-hit">命中规则：${esc(n)}</div>`).join('')}
        ${others.length ? `<div class="re-hit others"><span class="sc">其他也命中的类型（裁决落选）：</span><br>${
          others.map((h) => `<span class="sc">· ${esc(h.label || h.key || '通用兜底')} — 具体度 ${h.specificity} · 优先级 ${h.priority}</span>`).join('<br>')
        }</div>` : ''}
        <div class="hint" style="font-size:11px;margin-top:6px">以上按编辑器当前规则计算（含未保存改动），未保存也能试；要生效请点「保存并生效」。</div>`;
    } catch (error) {
      host.innerHTML = `<span style="color:#ff8080">判定失败：${esc(error.message)}</span>`;
    }
  }

  async function saveReType() {
    const t = reCurType();
    if (!t) return;
    try {
      const priorityEl = $('re-priority');
      const priority = priorityEl ? (Number(priorityEl.value) || 0) : (Number(t.priority) || 5);
      t.priority = priority;
      const card = readReCard(); // layout JSON 非法时抛错，避免保存脏数据
      await api('/api/admin/device-types', {
        method: 'POST',
        body: JSON.stringify({
          key: t.key, rules: reRulesOf(t), priority, card,
          meta: t.dynamic ? { label: t.label, icon: t.icon, color: t.color } : undefined,
        }),
      });
      state.deviceTypes = null;
      await loadDeviceTypes();
      renderReTypeList(); renderReRules();
      toast('判定规则与卡片布局已保存，即时生效');
    } catch (error) { toast('保存失败：' + error.message, 'error'); }
  }

  async function resetReType() {
    const t = reCurType();
    if (!t) return;
    if (!confirm(`恢复「${t.label || t.key}」的默认规则？`)) return;
    try {
      await api('/api/admin/device-types/reset', { method: 'POST', body: JSON.stringify({ key: t.key }) });
      state.deviceTypes = null;
      await loadDeviceTypes();
      renderReTypeList(); renderReRules(); clearReTestResult();
      toast('已恢复默认');
    } catch (error) { toast('恢复失败：' + error.message, 'error'); }
  }

  async function createReType() {
    const label = ($('re-nt-label').value || '').trim();
    const key = ($('re-nt-key').value || '').trim();
    if (!label || !key) { toast('请填名称和 key', 'error'); return; }
    try {
      await api('/api/admin/device-types/create', {
        method: 'POST',
        body: JSON.stringify({
          key, label, icon: ($('re-nt-icon').value || '✦').trim(), color: ($('re-nt-color').value || '#4dd4ac').trim(),
        }),
      });
      $('re-nt-box').hidden = true;
      $('re-nt-label').value = ''; $('re-nt-key').value = '';
      state.deviceTypes = null;
      await loadDeviceTypes();
      state.reEditKey = key;
      renderReTypeList(); renderReRules();
      toast('类型已创建');
    } catch (error) { toast('创建失败：' + error.message, 'error'); }
  }

  $('re-add-type').addEventListener('click', () => { $('re-newtype-box').hidden = !$('re-newtype-box').hidden; });
  $('re-nt-save').addEventListener('click', createReType);
  $('re-add-rule').addEventListener('click', () => {
    const t = reCurType(); if (!t) return;
    t.rules.push({ id: 'r' + Date.now(), name: '新规则 ' + (t.rules.length + 1), enabled: true, conds: [{ field: 'domain', op: 'eq', value: '' }] });
    renderReRules(); renderReTypeList(); clearReTestResult();
  });
  $('re-save').addEventListener('click', saveReType);
  $('re-reset').addEventListener('click', resetReType);
  $('re-reload').addEventListener('click', async () => {
    state.deviceTypes = null;
    await loadDeviceTypes();
    renderReTypeList(); renderReRules();
  });
  $('re-test-device').addEventListener('change', (e) => {
    state.reTestIdx = parseInt(e.target.value, 10) || 0;
    renderReTestEnts(); clearReTestResult();
  });
  $('re-run-test').addEventListener('click', runReTest);

  // ------------------------------------------------------------ 全局判定测试
  async function runGlobalClassify() {
    const body = $('re-global-body');
    const meta = $('re-global-meta');
    if (!body) return;
    // 同步优先级到当前编辑类型（未保存也能用当前值测试）
    const cur = reCurType();
    const priorityEl = $('re-priority');
    if (cur && priorityEl) cur.priority = Number(priorityEl.value) || 0;
    const onlyVisible = !!($('re-global-only-visible') && $('re-global-only-visible').checked);
    body.innerHTML = '<tr><td colspan="6" class="empty">判定中…</td></tr>';
    if (meta) meta.textContent = '';
    try {
      const data = await api('/api/admin/device-types/classify-all', {
        method: 'POST',
        body: JSON.stringify({ types: state.deviceTypes, onlyVisible }),
      });
      const rows = data.results || [];
      const currentKey = cur ? cur.key : '';
      const matched = rows.filter((r) => r.key === currentKey).length;
      if (meta) meta.textContent = `共 ${data.total} 台设备 · 当前类型「${esc(cur ? (cur.label || cur.key) : '')}」命中 ${matched} 台`;
      if (!rows.length) {
        body.innerHTML = '<tr><td colspan="6" class="empty">没有匹配的设备。</td></tr>';
        return;
      }
      const frag = document.createDocumentFragment();
      rows.forEach((r, i) => {
        const tr = document.createElement('tr');
        const hit = r.key === currentKey;
        if (hit) tr.className = 're-global-hit';
        const visText = r.visible === null ? '默认' : (r.visible ? '显示' : '隐藏');
        const visCls = r.visible === false ? 'off' : '';
        const others = (r.allHits || []).filter((h) => h.key !== r.key)
          .map((h) => esc(h.label || h.key)).join('、');
        tr.innerHTML = `<td>${i + 1}</td>
          <td class="strong">${esc(r.name || r.id)}</td>
          <td class="muted">${esc(r.areaName || '—')}</td>
          <td>${r.label ? `<span class="badge">${esc(r.label)}</span>` : '<span class="muted">未命中/兜底</span>'}</td>
          <td><span class="re-global-vis ${visCls}">${visText}</span></td>
          <td class="muted">${others || '—'}</td>`;
        frag.appendChild(tr);
      });
      body.innerHTML = '';
      body.appendChild(frag);
    } catch (error) {
      body.innerHTML = `<tr><td colspan="6" class="empty" style="color:#ff8080">判定失败：${esc(error.message)}</td></tr>`;
    }
  }

  $('re-global-run').addEventListener('click', runGlobalClassify);
  const reTestOnly = $('re-test-only-visible');
  if (reTestOnly) reTestOnly.addEventListener('change', () => { state.reTestIdx = 0; renderReTestSel(); });

  // 卡片布局编辑：格式化 / 校验 / 载入默认（清空=用默认布局）
  const VALID_NODES = new Set(['row', 'column', 'wrap', 'text', 'icon', 'button', 'chip', 'progress', 'sparkline', 'repeat', 'divider']);
  function validateLayoutTree(node, path = 'root', errors = []) {
    if (!node || typeof node !== 'object' || Array.isArray(node)) { errors.push(`${path}: 节点必须是对象`); return errors; }
    if (!VALID_NODES.has(node.type)) errors.push(`${path}: 未知节点类型 ${node.type}`);
    if (node.template) validateLayoutTree(node.template, path + '.template', errors);
    if (Array.isArray(node.children)) {
      node.children.forEach((c, i) => validateLayoutTree(c, `${path}.children[${i}]`, errors));
    }
    return errors;
  }
  const fmtBtn = $('re-layout-format');
  if (fmtBtn) fmtBtn.addEventListener('click', () => {
    const el = $('re-layout');
    if (!el) return;
    try {
      if (!el.value.trim()) { setLayoutStatus('当前为空（使用默认布局）'); return; }
      el.value = JSON.stringify(JSON.parse(el.value), null, 2);
      setLayoutStatus('已格式化');
    } catch (e) { setLayoutStatus('JSON 格式错误：' + e.message, false); }
  });
  const valBtn = $('re-layout-validate');
  if (valBtn) valBtn.addEventListener('click', () => {
    const el = $('re-layout');
    if (!el) return;
    try {
      if (!el.value.trim()) { setLayoutStatus('空布局合法（使用默认布局）'); return; }
      const tree = JSON.parse(el.value);
      const errs = validateLayoutTree(tree);
      if (errs.length) setLayoutStatus('校验未通过：' + errs.slice(0, 3).join('; '), false);
      else setLayoutStatus(`校验通过（根类型 ${tree.type}）`);
    } catch (e) { setLayoutStatus('JSON 格式错误：' + e.message, false); }
  });
  const defBtn = $('re-layout-default');
  if (defBtn) defBtn.addEventListener('click', () => {
    const el = $('re-layout');
    if (el) { el.value = ''; setLayoutStatus('已清空，保存后将恢复默认布局'); }
    const spanSel = $('re-span');
    if (spanSel) spanSel.value = '1x1';
  });

  // ------------------------------------------------------------ ESP 设备分类（一页 = 一台被控设备）

  // 单色屏只有亮/灭两级，这里只切换「亮色」，与实物蓝/白/黄三种屏一致。
