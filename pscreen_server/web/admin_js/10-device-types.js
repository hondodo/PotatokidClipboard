'use strict';

  async function loadDeviceTypes(force = false) {
    if (state.deviceTypes && !force) return state.deviceTypes;
    const data = await api('/api/admin/device-types');
    state.deviceTypes = data.types || [];
    if (!state.dtEditKey && state.deviceTypes.length) state.dtEditKey = state.deviceTypes[0].key;
    renderDeviceTypes();
    return state.deviceTypes;
  }

  function renderDeviceTypes() {
    const list = $('dt-list');
    if (!list || !state.deviceTypes) return;
    // 统计每种类型被多少个屏幕页面使用（一个页面 = 一台被控设备）。
    const usage = {};
    for (const dev of (state.espDevices || [])) {
      for (const page of (dev.espPages || [])) {
        const key = page.deviceType || '';
        usage[key] = (usage[key] || 0) + 1;
      }
    }
    list.innerHTML = state.deviceTypes.map((t) => {
      const active = t.key === state.dtEditKey ? ' active' : '';
      const cus = t.customized ? '<span class="cus" title="已自定义"></span>' : '';
      const use = usage[t.key] ? `<span class="use">${usage[t.key]} 页</span>` : '';
      return `<div class="dt-item${active}" data-key="${esc(t.key)}"><span class="ic">${esc(t.icon)}</span><span>${esc(t.label)}</span>${cus}${use}</div>`;
    }).join('');
    list.querySelectorAll('.dt-item').forEach((el) => {
      el.addEventListener('click', () => { state.dtEditKey = el.dataset.key; renderDeviceTypes(); });
    });
    $('dt-meta').textContent = `${state.deviceTypes.length} 种类型 · ${state.deviceTypes.filter((t) => t.customized).length} 已自定义`;
    renderDictEditor();
  }

  function renderDictEditor() {
    const host = $('dt-editor');
    if (!host || !state.deviceTypes) return;
    const t = state.deviceTypes.find((x) => x.key === state.dtEditKey);
    if (!t) return;
    $('dt-title').textContent = `字典规则 · ${t.label || '通用兜底'}`;
    const d = t.dict || {};
    const f = (id, label, val) => `<div class="dt-field"><label>${label}</label><input id="${id}" value="${esc(val)}"></div>`;
    host.innerHTML = `
      <div class="dt-col shared">
        <h4>共用语义字段（两端都读）</h4>
        ${f('df-mainAttr', '主状态属性', d.mainAttr)}
        ${f('df-mainFmt', '显示格式（{v}=值）', d.mainFmt)}
        ${f('df-subTpl', '副状态模板（{s1}/{s2}）', d.subTpl)}
        ${f('df-step', '步长 / 单位', d.step)}
      </div>
      <div class="dt-col home">
        <h4>home 端消费</h4>
        ${f('df-homeLabel', '详情大字标签', d.homeLabel)}
        ${f('df-homeCtrls', '控件组', d.homeCtrls)}
        ${f('df-homeActs', '控制动作', d.homeActs)}
        <p class="field-note">只影响 App 详情面板，与 ESP 屏幕无关。</p>
      </div>
      <div class="dt-col esp">
        <h4>ESP 端消费（128×64 四行）</h4>
        ${f('df-espTitle', '标题行模板', d.espTitle)}
        ${f('df-espMain', '主状态行模板', d.espMain)}
        ${f('df-espSub', '副状态行模板', d.espSub)}
        ${f('df-espKeys', '按键提示行模板', d.espKeys)}
        <div class="dt-actions">
          <button class="btn primary small" id="dt-save" type="button">保存（两端生效）</button>
          ${t.customized ? '<button class="btn small" id="dt-reset" type="button">恢复默认</button>' : ''}
        </div>
      </div>`;
    $('dt-save').addEventListener('click', () => saveDict(t.key));
    if ($('dt-reset')) $('dt-reset').addEventListener('click', () => resetDict(t.key));
  }

  function collectDictPatch() {
    const keys = ['mainAttr', 'mainFmt', 'subTpl', 'step', 'homeLabel', 'homeCtrls', 'homeActs', 'espTitle', 'espMain', 'espSub', 'espKeys'];
    const patch = {};
    for (const k of keys) patch[k] = $('df-' + k).value;
    return patch;
  }

  async function saveDict(key) {
    try {
      await api('/api/admin/device-types', { method: 'POST', body: JSON.stringify({ key, dict: collectDictPatch() }) });
      toast('字典已保存，home 与 ESP 两端同步生效', 'success');
      await loadDeviceTypes(true);
    } catch (error) { toast('保存失败：' + error.message, 'error'); }
  }

  async function resetDict(key) {
    try {
      await api('/api/admin/device-types/reset', { method: 'POST', body: JSON.stringify({ key }) });
      toast('已恢复默认规则', 'success');
      await loadDeviceTypes(true);
    } catch (error) { toast('恢复失败：' + error.message, 'error'); }
  }

  // ------------------------------------------------------------ 设备判定规则（规则引擎）

  function reCurType() {
    return (state.deviceTypes || []).find((t) => t.key === state.reEditKey) || (state.deviceTypes || [])[0];
  }
  function reRulesOf(t) { return Array.isArray(t && t.rules) ? t.rules : []; }
  function reCardOf(t) {
    return t && t.card ? t.card : { label: '当前值', mainAttr: 'state', mainFmt: '{v}', subTpl: '{state}', icon: '✦', color: '#4dd4ac', mainEntity: '主实体', buttons: [], genericEnabled: false };
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
        renderReTypeList(); renderReRules(); renderReCard(); clearReTestResult();
      });
    });
    if ($('re-meta')) $('re-meta').textContent = `${types.length} 种类型 · ${types.reduce((n, t) => n + reRulesOf(t).length, 0)} 条规则`;
  }

  function renderReRules() {
    const host = $('re-rules');
    const t = reCurType();
    if (!host) return;
    if (!t) { host.innerHTML = '<div class="empty">无类型</div>'; return; }
    if ($('re-title')) $('re-title').textContent = `判定规则 · ${t.label || t.key || '通用兜底'}`;
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
          <input type="text" list="re-dl-fields" value="${esc(c.field)}" data-r="${ri}" data-c="${ci}" data-k="field" title="字段：attr.xxx 取任意 HA 属性，device.model 取型号">
          <input type="text" list="re-dl-ops" value="${esc(c.op)}" data-r="${ri}" data-c="${ci}" data-k="op" title="操作符">
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
  }

  function renderReCard() {
    const host = $('re-card');
    const t = reCurType();
    if (!host || !t) return;
    const c = reCardOf(t);
    host.innerHTML = `
      <div class="re-card-row"><label>大字标签</label><input type="text" data-card="label" value="${esc(c.label)}"></div>
      <div class="re-card-row"><label>主属性</label><input type="text" data-card="mainAttr" value="${esc(c.mainAttr)}"></div>
      <div class="re-card-row"><label>主格式</label><input type="text" data-card="mainFmt" value="${esc(c.mainFmt)}"></div>
      <div class="re-card-row"><label>副文案</label><input type="text" data-card="subTpl" value="${esc(c.subTpl)}"></div>
      <div class="re-card-row"><label>主实体</label><input type="text" data-card="mainEntity" value="${esc(c.mainEntity)}"></div>
      <div class="re-card-row"><label>图标/色</label><input type="text" data-card="icon" value="${esc(c.icon)}" style="flex:0 0 24%"><input type="text" data-card="color" value="${esc(c.color)}"></div>
      <div class="re-card-row"><label>灰度开关</label><label class="ha-only-free" style="width:auto"><input type="checkbox" data-card="genericEnabled" ${c.genericEnabled ? 'checked' : ''} style="width:auto"> 用通用卡片渲染该类型（home）</label></div>
      <div style="font-size:11.5px;color:var(--muted);margin:10px 0 5px">按钮（文案 + 动作 kind）</div>
      <div id="re-card-btns">${(c.buttons || []).map((b, i) => `
        <div class="re-btn-chip">
          <input type="text" list="re-dl-actions" value="${esc(b.action)}" data-btn-action="${i}" title="动作 kind">
          <input type="text" value="${esc(b.label)}" data-btn-label="${i}" title="按钮文案">
          <button class="re-btn-icon" type="button" data-del-btn="${i}" title="删除按钮">×</button>
        </div>`).join('')}</div>
      <div class="re-btn-row"><button class="btn small" type="button" id="re-add-btn">＋ 按钮</button></div>`;
    host.querySelectorAll('[data-card]').forEach((el) => {
      if (el.dataset.card === 'genericEnabled') {
        el.addEventListener('change', () => { reCardOf(reCurType()).genericEnabled = el.checked; });
      } else {
        el.addEventListener('input', () => {
          reCardOf(reCurType())[el.dataset.card] = el.value;
          renderRePreview();
        });
      }
    });
    host.querySelectorAll('[data-btn-action]').forEach((el) => el.addEventListener('input', () => {
      reCardOf(reCurType()).buttons[+el.dataset.btnAction].action = el.value; renderRePreview();
    }));
    host.querySelectorAll('[data-btn-label]').forEach((el) => el.addEventListener('input', () => {
      reCardOf(reCurType()).buttons[+el.dataset.btnLabel].label = el.value; renderRePreview();
    }));
    host.querySelectorAll('[data-del-btn]').forEach((el) => el.addEventListener('click', () => {
      reCardOf(reCurType()).buttons.splice(+el.dataset.delBtn, 1); renderReCard(); renderRePreview();
    }));
    const addBtn = $('re-add-btn');
    if (addBtn) addBtn.addEventListener('click', () => {
      reCardOf(reCurType()).buttons.push({ label: '新按钮', action: 'toggle' }); renderReCard(); renderRePreview();
    });
    renderRePreview();
  }

  function renderRePreview() {
    const t = reCurType();
    if (!t) return;
    const c = reCardOf(t);
    const home = $('re-preview-home'), esp = $('re-preview-esp');
    if (home) home.innerHTML = `<div style="color:${esc(c.color)}">${esc(c.icon)} ${esc(t.label || t.key)}</div>
      <div class="big">${esc(c.mainFmt || '{v}').replace('{v}', '--')}</div>
      <div class="sub">${esc(c.label)} · ${esc(c.subTpl || '')}</div>
      <div class="re-btn-row">${(c.buttons || []).map((b) => `<span class="pill">${esc(b.label)}</span>`).join('')}</div>`;
    if (esp) esp.innerHTML = `<div class="top">1/${esc(c.icon)} ${esc(t.label || t.key)}  ·  IP</div>
      <div>${esc(c.mainFmt || '{v}').replace('{v}', '--')}</div>
      <div>${esc((c.subTpl || '').replace('{s1}', '在线').replace('{s2}', '就绪').replace('{state}', '开启'))}</div>
      <div>${(c.buttons || []).map((b) => esc(b.label)).join(' ')}</div>`;
  }

  function renderReTestSel() {
    const sel = $('re-test-device');
    if (!sel) return;
    const ents = (state.haEntities && state.haEntities.entities) || [];
    const byDevice = new Map();
    for (const e of ents) {
      const key = e.deviceId || e.id;
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
      const data = await api('/api/admin/device-types/classify', { method: 'POST', body: JSON.stringify({ entities }) });
      const r = data.result;
      if (!r) {
        host.innerHTML = '<span class="hint">没有规则命中，将落到通用兜底类型。</span>';
        return;
      }
      host.innerHTML = `<div class="re-hit win"><span class="nm">判定结果：${esc(r.label)}</span><br>
        <span class="sc">具体度 ${r.specificity} · 优先级 ${r.priority}</span></div>
        ${(r.matchedRules || []).map((n) => `<div class="re-hit">命中规则：${esc(n)}</div>`).join('')}`;
    } catch (error) {
      host.innerHTML = `<span style="color:#ff8080">判定失败：${esc(error.message)}</span>`;
    }
  }

  async function saveReType() {
    const t = reCurType();
    if (!t) return;
    try {
      await api('/api/admin/device-types', {
        method: 'POST',
        body: JSON.stringify({
          key: t.key, rules: reRulesOf(t), card: reCardOf(t), priority: t.priority,
          meta: t.dynamic ? { label: t.label, icon: t.icon, color: t.color } : undefined,
        }),
      });
      state.deviceTypes = null;
      await loadDeviceTypes();
      renderReTypeList(); renderReRules(); renderReCard();
      toast('判定规则已保存，home 与 ESP 两端即时生效');
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
      renderReTypeList(); renderReRules(); renderReCard(); clearReTestResult();
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
      renderReTypeList(); renderReRules(); renderReCard();
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
    renderReTypeList(); renderReRules(); renderReCard();
  });
  $('re-test-device').addEventListener('change', (e) => {
    state.reTestIdx = parseInt(e.target.value, 10) || 0;
    renderReTestEnts(); clearReTestResult();
  });
  $('re-run-test').addEventListener('click', runReTest);

  // ------------------------------------------------------------ ESP 设备分类（一页 = 一台被控设备）

  // 单色屏只有亮/灭两级，这里只切换「亮色」，与实物蓝/白/黄三种屏一致。
