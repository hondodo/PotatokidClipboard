'use strict';

  // 「智能」Tab：手动控制（点一下执行一组动作）+ 自动化（条件满足自动执行）。
  //
  // 数据来自 /api/admin/scenes；动作编辑复用 04-ha.js 的 openEntityPicker（与
  // ESP「插入实体」同一个窗口）和 /api/admin/remote/devices 的能力表，
  // 保证后台配的动作和小屏按键可用命令一致。
  //
  // 刻意不做的：HA 实体状态触发。服务端没有常驻 HA WS，只能 15 秒轮询，
  // 做出来会让人以为是秒级，所以 P1 只给 感应 / 按键 / 定时 三种触发。

  state.scenes = null;
  state.sceneSettings = null;
  state.smartPresence = null;
  state.smartRemote = null;

  const SMART_HA_ACTIONS = [
    ['turn_on', '开'],
    ['turn_off', '关'],
    ['toggle', '切换'],
    ['run', '执行'],
    ['set_temperature(+0.5)', '温度 +0.5'],
    ['set_temperature(-0.5)', '温度 −0.5'],
    ['set_percentage(+25)', '数值 +25'],
    ['set_percentage(-25)', '数值 −25'],
    ['next_effect', '下个效果'],
  ];

  const SMART_PRESENCE_LABEL = {
    present: '有人',
    absent: '无人',
  };

  function smartClock(ts) {
    if (!ts) return '—';
    const d = new Date(ts);
    const now = new Date();
    const hm = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    if (d.toDateString() === now.toDateString()) return hm;
    return `${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')} ${hm}`;
  }

  function smartResultText(scene) {
    if (scene.kind === 'manual') {
      if (!scene.lastRunAt) return '还没执行过';
      if (scene.lastResult === 'ok') return `最近 ${smartClock(scene.lastRunAt)} 成功`;
      return `最近 ${smartClock(scene.lastRunAt)} 失败`;
    }
    if (!scene.enabled) return '已停用';
    if (!scene.lastRunAt) return '还没触发过';
    if (scene.lastResult === 'ok') return `最近 ${smartClock(scene.lastRunAt)} 成功`;
    if (scene.lastResult === 'partial') return `最近 ${smartClock(scene.lastRunAt)} 部分失败`;
    return `最近 ${smartClock(scene.lastRunAt)} 失败`;
  }

  async function loadScenes(force = false) {
    if (state.scenes && !force) { renderSmart(); return; }
    const body = $('smart-body');
    if (body && !state.scenes) body.innerHTML = '<div class="empty">加载中…</div>';
    const [data] = await Promise.all([
      api('/api/admin/scenes'),
      // 动作编辑器要用：HA 实体目录 + 遥控目标能力表。已有缓存就不再重取——
      // 实体目录上千条，每次保存都重拉会让「点保存」到「弹窗关闭」空好几秒。
      state.haEntities ? null : loadHaEntities().catch(() => {}),
      state.smartRemote ? null : loadSmartRemote().catch(() => {}),
    ]);
    state.scenes = data.scenes || [];
    state.sceneSettings = data.settings || { occupiedWindowSec: 90 };
    state.smartPresence = data.presence || [];
    renderSmart();
  }

  async function loadSmartRemote(force = false) {
    if (state.smartRemote && !force) return state.smartRemote;
    const data = await api('/api/admin/remote/devices');
    state.smartRemote = data.devices || [];
    return state.smartRemote;
  }

  // ------------------------------------------------------------ 列表渲染

  function renderSmart() {
    const body = $('smart-body');
    if (!body) return;
    if (!state.scenes) { body.innerHTML = '<div class="empty">加载中…</div>'; return; }
    const manuals = state.scenes.filter((item) => item.kind === 'manual');
    const autos = state.scenes.filter((item) => item.kind === 'auto');
    // 手动控制被别的场景当动作引用的次数：卡片上标出来，删之前心里有数。
    const usedBy = new Map();
    state.scenes.forEach((item) => {
      (item.actions || []).forEach((action) => {
        if (!action || action.type !== 'scene') return;
        usedBy.set(action.sceneId, (usedBy.get(action.sceneId) || 0) + 1);
      });
    });
    const running = autos.filter((item) => item.enabled).length;
    const windowSec = (state.sceneSettings && state.sceneSettings.occupiedWindowSec) || 90;
    $('smart-hint').textContent = `手动控制 ${manuals.length} 个 · 自动化 ${autos.length} 个（${running} 个已开启）`
      + ` · 感应实体 ${(state.smartPresence || []).length} 个（判空闲窗口 ${windowSec} 秒）`;

    body.innerHTML = `
      <div class="card smart-section">
        <h3>手动控制 <span class="muted">点「执行」立即跑一遍，可以反复用</span></h3>
        ${manuals.length
          ? `<div class="smart-manual-grid">${manuals.map((item) => smartManualCard(item, usedBy.get(item.id) || 0)).join('')}</div>`
          : '<div class="empty">还没有手动控制。点右上角「+ 手动控制」建一个，比如「回家模式：开客厅灯 + 中控切首页 + 开夜灯」。</div>'}
      </div>
      <div class="card smart-section">
        <h3>自动化 <span class="muted">条件满足时自己执行，关掉开关立即停用</span></h3>
        ${autos.length
          ? `<div class="smart-auto-list">${autos.map(smartAutoRow).join('')}</div>`
          : '<div class="empty">还没有自动化。点右上角「+ 自动化」建一个，比如「小屏持续有人 10 秒 → 开客厅灯」，或「每天 22:00 → 中控切首页」。</div>'}
      </div>`;
  }

  function smartManualCard(scene, refCount = 0) {
    const actions = (scene.actionTexts || []).join(' · ') || '（没有动作）';
    const failed = scene.lastResult && scene.lastResult !== 'ok' && scene.lastRunAt;
    return `<div class="smart-card" data-id="${esc(scene.id)}">
      <div class="smart-card-head">
        <strong title="${esc(scene.name)}">${esc(scene.name)}</strong>
        <span class="smart-card-ops">
          <button class="icon-btn" type="button" data-act="edit" title="编辑">✎</button>
          <button class="icon-btn danger" type="button" data-act="del" title="删除">×</button>
        </span>
      </div>
      <div class="smart-card-desc" title="${esc(actions)}">${esc(actions)}</div>
      ${refCount ? `<div class="smart-ref">被 ${refCount} 处动作引用</div>` : ''}
      <div class="smart-card-foot">
        <button class="btn small primary" type="button" data-act="run">执行</button>
        <span class="smart-status${failed ? ' failed' : ''}">${esc(smartResultText(scene))}</span>
      </div>
    </div>`;
  }

  function smartAutoRow(scene) {
    const actions = (scene.actionTexts || []).join('、') || '（没有动作）';
    const failed = scene.enabled && scene.lastResult && scene.lastResult !== 'ok';
    return `<div class="smart-auto-row${scene.enabled ? '' : ' off'}" data-id="${esc(scene.id)}">
      <label class="smart-switch" title="${scene.enabled ? '点一下停用' : '点一下启用'}">
        <input type="checkbox" data-act="toggle"${scene.enabled ? ' checked' : ''}>
        <span></span>
      </label>
      <div class="smart-auto-main">
        <div class="smart-auto-name">
          <strong>${esc(scene.name)}</strong>
          <span class="smart-status${failed ? ' failed' : ''}">${esc(smartResultText(scene))}</span>
        </div>
        <div class="smart-auto-desc">
          <span class="smart-when">当 ${esc(scene.triggerText || '—')}</span>
          <span class="smart-arrow">→</span>
          <span class="smart-then" title="${esc(actions)}">${esc(actions)}</span>
        </div>
      </div>
      <div class="smart-auto-ops">
        <button class="btn small" type="button" data-act="run">执行</button>
        <button class="btn small" type="button" data-act="edit">编辑</button>
        <button class="icon-btn danger" type="button" data-act="del" title="删除">×</button>
      </div>
    </div>`;
  }

  function findSceneById(id) {
    return (state.scenes || []).find((item) => item.id === id) || null;
  }

  function bindSmartOnce() {
    if (bindSmartOnce.done) return;
    bindSmartOnce.done = true;
    $('smart-reload').addEventListener('click', () => {
      loadScenes(true).then(() => toast('已刷新', 'ok')).catch((error) => toast(error.message, 'error'));
      loadSmartRemote(true).catch(() => {});
    });
    $('smart-new-manual').addEventListener('click', () => openSceneEditor(null, 'manual'));
    $('smart-new-auto').addEventListener('click', () => openSceneEditor(null, 'auto'));
    $('smart-presence').addEventListener('click', openPresencePanel);

    $('smart-body').addEventListener('click', async (event) => {
      const trigger = event.target.closest('[data-act]');
      if (!trigger) return;
      // 开关是 checkbox，click 会被后面的 change 处理，这里跳过避免执行两次。
      if (trigger.dataset.act === 'toggle') return;
      const host = trigger.closest('[data-id]');
      const scene = host ? findSceneById(host.dataset.id) : null;
      if (!scene) return;
      const act = trigger.dataset.act;
      if (act === 'edit') return openSceneEditor(scene);
      if (act === 'del') return deleteScene(scene);
      if (act === 'run') return runSceneNow(scene, trigger);
    });

    $('smart-body').addEventListener('change', async (event) => {
      const input = event.target;
      if (input.dataset.act !== 'toggle') return;
      const host = input.closest('[data-id]');
      const scene = host ? findSceneById(host.dataset.id) : null;
      if (!scene) return;
      const enabled = input.checked;
      try {
        await api(`/api/admin/scenes/${encodeURIComponent(scene.id)}/enabled`, {
          method: 'PATCH',
          body: JSON.stringify({ enabled }),
        });
        scene.enabled = enabled;
        if (!enabled) scene.lastResult = '';
        renderSmart();
        toast(enabled ? '已开启' : '已停用', 'ok');
      } catch (error) {
        input.checked = !enabled;
        toast(error.message, 'error');
      }
    });
  }

  async function deleteScene(scene) {
    const ok = window.confirm(`删除「${scene.name}」？删除后无法恢复。`);
    if (!ok) return;
    try {
      await api(`/api/admin/scenes/${encodeURIComponent(scene.id)}`, { method: 'DELETE' });
      state.scenes = state.scenes.filter((item) => item.id !== scene.id);
      renderSmart();
      toast('已删除', 'ok');
    } catch (error) {
      toast(error.message, 'error');
    }
  }

  /**
   * 执行。成功只 toast，失败弹逐步结果 —— 日常点一次不该被弹窗打断，
   * 但失败必须能看清是哪一步、为什么，否则用户只能瞎猜。
   *
   * 动作里可能带「等待 N 秒」，点下去到出结果可能好几秒，按钮要自己说明在干活。
   */
  async function runSceneNow(scene, btn) {
    const restore = setBtnBusy(btn, '执行中…');
    try {
      const result = await api(`/api/admin/scenes/${encodeURIComponent(scene.id)}/run`, { method: 'POST' });
      scene.lastRunAt = Date.now();
      scene.lastResult = result.result;
      scene.runCount = (scene.runCount || 0) + 1;
      renderSmart();
      if (result.ok) {
        toast(`已执行 ${result.steps.length} 个动作`, 'ok');
        return;
      }
      showSceneResult(scene, result);
    } catch (error) {
      toast(error.message, 'error');
    } finally {
      restore();
    }
  }

  function showSceneResult(scene, result) {
    const box = document.createElement('div');
    box.className = 'smart-result';
    box.innerHTML = `<p class="smart-result-head">「${esc(scene.name)}」执行结果：${
      result.result === 'partial' ? '部分动作失败（后面的已按「失败即停」跳过）' : '执行失败'
    }</p>`
      + '<ol class="smart-result-steps">'
      + result.steps.map((step) => `<li class="step-${esc(step.status)}">
          <span class="step-no">${step.i}</span>
          <span class="step-label">${esc(step.label)}</span>
          <span class="step-status">${step.status === 'ok' ? `${step.ms}ms` : esc(step.error || '失败')}</span>
        </li>`).join('')
      + '</ol>';
    openDialog({
      title: '执行结果',
      content: box,
      saveLabel: '知道了',
      onSave: async () => {},
    });
  }

  // ------------------------------------------------------------ 人体感应实体

  function openPresencePanel() {
    const entities = state.smartPresence || [];
    const windowSec = (state.sceneSettings && state.sceneSettings.occupiedWindowSec) || 90;
    const box = document.createElement('div');
    box.className = 'smart-presence';
    if (!entities.length) {
      box.innerHTML = '<div class="empty">还没有小屏上报过人体感应。设备需要接 PIR 并在本机设置页配好 GPIO。</div>';
    } else {
      box.innerHTML = `
        <p class="smart-note">这是服务里的<strong>虚拟实体</strong>（<code>presence.&lt;设备ID&gt;</code>），不是 HA 里的 binary_sensor。
        <code>presence</code> 是传感器当前电平，人坐着不动约 2 秒就会变无人；<code>occupied</code> 是「最近 ${windowSec} 秒内出现过有人」的去抖值，
        判断「人还在不在」用它。</p>
        ${entities.map((entity) => `<div class="smart-presence-card">
          <div class="smart-presence-head">
            <strong>${esc(entity.name)}</strong>
            <code>${esc(entity.entityId)}</code>
          </div>
          <div class="smart-presence-states">
            <div class="smart-state${entity.presence === 'present' ? ' on' : ''}">
              <span>presence</span><b>${esc(entity.presenceText)}</b>
            </div>
            <div class="smart-state${entity.occupied ? ' on' : ''}">
              <span>occupied</span><b>${esc(entity.occupiedText)}</b>
              <small>${entity.occupied ? `还剩约 ${entity.occupiedLeftSec} 秒转空闲` : '已超过窗口'}</small>
            </div>
          </div>
          <div class="smart-presence-times">
            <span>进入 ${smartClock(entity.lastEnterAt)}</span>
            <span>离开 ${smartClock(entity.lastLeaveAt)}</span>
            <span>空闲 ${entity.idleSec == null ? '—' : `${entity.idleSec} 秒`}</span>
          </div>
        </div>`).join('')}
        <label class="smart-field smart-presence-window">
          <span>判空闲窗口（秒）</span>
          <input type="number" id="smart-presence-window" min="10" max="3600" value="${windowSec}">
          <small>传感器只认移动。人坐着不动会一直算「无人」，超过这个秒数才判空闲。调大更稳但「人走了灯还亮」更久。</small>
        </label>`;
    }
    openDialog({
      title: '人体感应实体',
      content: box,
      saveLabel: entities.length ? '保存窗口' : '关闭',
      onSave: async () => {
        const input = $('smart-presence-window');
        if (!input) return;
        const value = Number(input.value);
        if (!Number.isFinite(value) || value < 10 || value > 3600) throw new Error('窗口需要在 10–3600 秒之间');
        const saved = await api('/api/admin/scenes/settings', {
          method: 'PUT',
          body: JSON.stringify({ occupiedWindowSec: value }),
        });
        state.sceneSettings = saved;
        await loadScenes(true);
      },
    });
  }

  // ------------------------------------------------------------ 编辑弹层

  function openSceneEditor(scene, kind) {
    const isNew = !scene;
    const draft = isNew ? {
      id: '',
      kind: kind || 'auto',
      name: '',
      enabled: true,
      cooldownSec: 30,
      trigger: { type: 'presence', deviceId: '', state: 'present', slot: 0, at: '', holdSec: 10 },
      window: { days: [], start: '', end: '' },
      actions: [{ type: 'ha', entityId: '', action: 'turn_on', param: '', onError: 'stop' }],
    } : JSON.parse(JSON.stringify(scene));
    if (draft.kind === 'manual') {
      draft.trigger = null;
    } else if (!draft.trigger) {
      draft.trigger = { type: 'presence', deviceId: '', state: 'present', slot: 0, at: '', holdSec: 10 };
    }
    if (!draft.actions || !draft.actions.length) {
      draft.actions = [{ type: 'ha', entityId: '', action: 'turn_on', param: '', onError: 'stop' }];
    }

    const form = document.createElement('div');
    form.className = 'smart-form';
    form.innerHTML = `
      <label class="smart-field">
        <span>名称</span>
        <input data-f="name" maxlength="40" placeholder="${draft.kind === 'manual' ? '例如：回家模式' : '例如：回家自动开灯'}">
      </label>
      <div class="smart-trigger-block"${draft.kind === 'manual' ? ' hidden' : ''}>
        <div class="smart-field">
          <span>触发方式</span>
          <select data-f="triggerType">
            <option value="presence">人体感应（秒级）</option>
            <option value="button">小屏按键（按下即触发）</option>
            <option value="time">定时（按服务器时间）</option>
          </select>
        </div>
        <div class="smart-trigger-body"></div>
      </div>
      <label class="smart-field">
        <span>冷却时间（秒）</span>
        <input type="number" data-f="cooldown" min="0" max="3600">
        <small>一次执行后多少秒内不再触发，防止传感器抖动连续执行。0 = 不限制。</small>
      </label>
      <div class="smart-actions-head">
        <span>动作（按顺序执行）</span>
        <small>默认「失败即停」——前面失败就不做后面（例如灯没开就不该切台）</small>
      </div>
      <div class="smart-actions"></div>
      <button class="btn small" type="button" data-op="add-action">+ 添加动作</button>
      <p class="smart-form-error" data-role="error" hidden></p>`;

    const nameInput = form.querySelector('[data-f="name"]');
    nameInput.value = draft.name || '';
    form.querySelector('[data-f="cooldown"]').value = String(draft.cooldownSec == null ? 30 : draft.cooldownSec);
    form.querySelector('[data-f="cooldown"]').addEventListener('input', (event) => {
      draft.cooldownSec = Number(event.target.value) || 0;
    });
    nameInput.addEventListener('input', (event) => { draft.name = event.target.value; });

    const triggerTypeSel = form.querySelector('[data-f="triggerType"]');
    const triggerBody = form.querySelector('.smart-trigger-body');
    const actionsBox = form.querySelector('.smart-actions');

    function renderTrigger() {
      triggerBody.innerHTML = '';
      if (draft.kind === 'manual') return;
      const trigger = draft.trigger;
      triggerTypeSel.value = trigger.type;
      // 触发源只列 ESP 小屏。先收「上报过感应的设备」（scenes 接口已带回），
      // 再用 overview 里的 ESP 补齐没接过传感器的设备（按键触发需要）。
      const seen = new Set();
      const devices = [];
      const push = (id, name) => {
        if (!id || seen.has(id)) return;
        seen.add(id);
        devices.push({ id, name: name || id });
      };
      (state.smartPresence || []).forEach((entity) => push(entity.deviceId, entity.name));
      const overviewMachines = (state.overview && state.overview.machines) || [];
      overviewMachines.forEach((machine) => {
        const isEsp = /esp|oled/i.test(`${machine.platform || ''}${machine.model || ''}`)
          || Array.isArray(machine.espPages);
        if (isEsp) push(machine.id, machine.name);
      });
      const devOptions = devices.map((device) => `<option value="${esc(device.id)}">${esc(device.name)}</option>`).join('');

      if (trigger.type === 'time') {
        triggerBody.innerHTML = `<label class="smart-field"><span>每天几点</span>
          <input type="time" data-t="at" value="${esc(trigger.at || '07:30')}"></label>`;
        triggerBody.querySelector('[data-t="at"]').addEventListener('input', (event) => {
          draft.trigger.at = event.target.value;
        });
        return;
      }

      if (!devices.length) {
        triggerBody.innerHTML = '<p class="smart-note">还没有 ESP 小屏。感应和按键触发都需要一台先上报过的小屏。</p>';
        return;
      }
      if (trigger.type === 'presence') {
        triggerBody.innerHTML = `
          <div class="smart-field-row">
            <label class="smart-field"><span>哪台小屏</span>
              <select data-t="deviceId"><option value="">请选择…</option>${devOptions}</select></label>
            <label class="smart-field"><span>状态</span>
              <select data-t="state">
                <option value="present">有人</option>
                <option value="absent">无人</option>
              </select></label>
            <label class="smart-field"><span>持续（秒）</span>
              <input type="number" data-t="holdSec" min="0" max="3600" value="${Number(trigger.holdSec) || 0}"></label>
          </div>
          <p class="smart-note">持续 0 秒 = 检测到就执行。传感器只认移动，建议 5–15 秒，避免人走过走廊就开灯。</p>`;
      } else {
        triggerBody.innerHTML = `
          <div class="smart-field-row">
            <label class="smart-field"><span>哪台小屏</span>
              <select data-t="deviceId"><option value="">请选择…</option>${devOptions}</select></label>
            <label class="smart-field"><span>槽位</span>
              <select data-t="slot">
                <option value="0">任意按键</option>
                ${[1, 2, 3, 4, 5, 6, 7, 8].map((slot) => `<option value="${slot}">槽位 ${slot}</option>`).join('')}
              </select></label>
          </div>
          <p class="smart-note">按下按键时触发。按键自己的动作照常执行，这里是额外的联动。</p>`;
      }

      const devSel = triggerBody.querySelector('[data-t="deviceId"]');
      devSel.value = trigger.deviceId || '';
      devSel.addEventListener('change', (event) => { draft.trigger.deviceId = event.target.value; });
      const stateSel = triggerBody.querySelector('[data-t="state"]');
      if (stateSel) {
        stateSel.value = trigger.state || 'present';
        stateSel.addEventListener('change', (event) => { draft.trigger.state = event.target.value; });
      }
      const slotSel = triggerBody.querySelector('[data-t="slot"]');
      if (slotSel) {
        slotSel.value = String(trigger.slot || 0);
        slotSel.addEventListener('change', (event) => { draft.trigger.slot = Number(event.target.value) || 0; });
      }
      const holdInput = triggerBody.querySelector('[data-t="holdSec"]');
      if (holdInput) {
        holdInput.addEventListener('input', (event) => { draft.trigger.holdSec = Number(event.target.value) || 0; });
      }
    }

    function renderActions() {
      actionsBox.innerHTML = '';
      draft.actions.forEach((action, index) => {
        const row = document.createElement('div');
        row.className = 'smart-action';
        row.innerHTML = `
          <div class="smart-action-head">
            <span class="smart-action-no">${index + 1}</span>
            <select data-a="type">
              <option value="ha">HA 实体</option>
              <option value="remote">中控 / 电视</option>
              <option value="scene">手动控制</option>
              <option value="delay">等待</option>
            </select>
            <label class="smart-onerror" title="勾上后这条失败也继续执行后面的动作">
              <input type="checkbox" data-a="onError"> 失败也继续
            </label>
            <span class="smart-action-btns">
              <button class="icon-btn" type="button" data-op="up" title="上移">↑</button>
              <button class="icon-btn" type="button" data-op="down" title="下移">↓</button>
              <button class="icon-btn danger" type="button" data-op="del" title="删除">×</button>
            </span>
          </div>
          <div class="smart-action-body"></div>`;
        row.querySelector('[data-a="type"]').value = action.type;
        row.querySelector('[data-a="onError"]').checked = action.onError === 'continue';
        renderActionBody(row.querySelector('.smart-action-body'), action);
        actionsBox.appendChild(row);

        row.querySelector('[data-a="type"]').addEventListener('change', (event) => {
          action.type = event.target.value;
          // 换类型时清掉另一类字段，避免残留脏值被提交。
          if (action.type === 'delay') {
            action.seconds = action.seconds || 5;
            delete action.entityId; delete action.target; delete action.sceneId;
          } else if (action.type === 'ha') {
            action.entityId = action.entityId || '';
            action.action = 'turn_on';
            delete action.seconds; delete action.target; delete action.sceneId;
          } else if (action.type === 'scene') {
            delete action.seconds; delete action.entityId; delete action.target;
            // 默认指向第一条可用的手动控制，省一次点击；没有就留空提示去建。
            if (!action.sceneId) {
              const first = (state.scenes || []).find((item) => item.kind === 'manual' && item.id !== draft.id);
              action.sceneId = first ? first.id : '';
            }
          } else {
            action.target = action.target || '';
            action.action = action.action || '';
            delete action.seconds; delete action.entityId; delete action.sceneId;
          }
          renderActionBody(row.querySelector('.smart-action-body'), action);
        });
        row.querySelector('[data-a="onError"]').addEventListener('change', (event) => {
          action.onError = event.target.checked ? 'continue' : 'stop';
        });
        row.querySelectorAll('[data-op]').forEach((btn) => {
          btn.addEventListener('click', () => {
            const op = btn.dataset.op;
            if (op === 'del') {
              if (draft.actions.length === 1) { toast('至少要留一个动作', 'error'); return; }
              draft.actions.splice(index, 1);
            } else if (op === 'up' && index > 0) {
              const [item] = draft.actions.splice(index, 1);
              draft.actions.splice(index - 1, 0, item);
            } else if (op === 'down' && index < draft.actions.length - 1) {
              const [item] = draft.actions.splice(index, 1);
              draft.actions.splice(index + 1, 0, item);
            } else {
              return;
            }
            renderActions();
          });
        });
      });
    }

    function renderActionBody(box, action) {
      box.innerHTML = '';
      if (action.type === 'scene') {
        renderSceneActionBody(box, action);
        return;
      }
      if (action.type === 'delay') {
        const label = document.createElement('label');
        label.className = 'smart-field inline';
        label.innerHTML = `<span>等待</span><input type="number" min="1" max="600" value="${Number(action.seconds) || 5}"><span>秒</span>`;
        label.querySelector('input').addEventListener('input', (event) => {
          action.seconds = Number(event.target.value) || 1;
        });
        box.appendChild(label);
        return;
      }

      if (action.type === 'remote') {
        const devices = state.smartRemote || [];
        if (!devices.length) {
          box.innerHTML = '<p class="smart-note">没有可遥控的中控/电视。设备需要先连上并在「设备状态」里出现过。</p>';
          return;
        }
        const wrap = document.createElement('div');
        wrap.className = 'smart-field-row';
        wrap.innerHTML = `
          <label class="smart-field"><span>目标设备</span>
            <select data-a="target">
              <option value="">请选择…</option>
              ${devices.map((device) => `<option value="${esc(device.deviceId)}">${esc(device.name)}（${device.kind === 'home' ? '中控' : '电视'}${device.online ? '' : ' · 离线'}）</option>`).join('')}
            </select></label>
          <label class="smart-field"><span>命令</span>
            <select data-a="action"></select></label>`;
        const targetSel = wrap.querySelector('[data-a="target"]');
        const cmdSel = wrap.querySelector('[data-a="action"]');
        targetSel.value = action.target || '';
        const fillCmds = () => {
          const device = devices.find((item) => item.deviceId === targetSel.value);
          const caps = (device && device.capabilities) || [];
          cmdSel.innerHTML = caps.map((cap) => `<option value="${esc(cap.cmd)}">${esc(cap.label)}</option>`).join('')
            || '<option value="">（该设备没有可用命令）</option>';
          if (action.action && caps.some((cap) => cap.cmd === action.action)) cmdSel.value = action.action;
          else action.action = cmdSel.value;
        };
        fillCmds();
        targetSel.addEventListener('change', (event) => {
          action.target = event.target.value;
          action.action = '';
          fillCmds();
        });
        cmdSel.addEventListener('change', (event) => { action.action = event.target.value; });
        box.appendChild(wrap);
        return;
      }

      // HA 实体：与 ESP「插入实体」同一套弹窗（家庭/房间/设备筛选 + 搜索 + 当前状态）。
      // 场景编辑本身就在弹层里，所以选择器以叠加层打开，不会把下面正在填的表单顶掉。
      const wrap = document.createElement('div');
      wrap.className = 'smart-ha-row';
      const picker = document.createElement('div');
      picker.className = 'entity-picker';
      const entInput = document.createElement('input');
      entInput.className = 'entity-picker-input';
      entInput.placeholder = 'light.living_room';
      entInput.maxLength = 128;
      entInput.autocomplete = 'off';
      entInput.value = action.entityId || '';
      const entBtn = document.createElement('button');
      entBtn.type = 'button';
      entBtn.className = 'btn small entity-picker-btn';
      entBtn.textContent = '选择';
      const entNote = document.createElement('p');
      entNote.className = 'entity-picker-desc';
      entNote.textContent = action.entityId
        ? `当前：${action.entityId}`
        : '点「选择」打开实体窗口，按家庭/房间/设备挑，也可直接输入 entity_id。';
      picker.append(entInput, entBtn);
      entInput.addEventListener('input', (event) => { action.entityId = event.target.value.trim(); });
      entBtn.addEventListener('click', () => {
        openEntityPicker({
          title: '选择 HA 实体 · 动作',
          value: action.entityId || '',
          actionableOnly: true,   // 动作要真能执行，默认只看可控实体（弹窗里可取消）
          onPick: (entity) => {
            action.entityId = entity.id;
            entInput.value = entity.id;
            // 选中的实体可能只支持部分动作：把可用动作摆出来，避免配了 turn_on
            // 到执行时才失败。判断动作合不合法仍由服务端把关。
            const labels = (entity.actions || []).map((item) => item.label);
            entNote.textContent = labels.length
              ? `${entity.name || entity.id}｜${entity.home || '未归属家庭'} · ${haEntityRoom(entity)}｜可用动作：${labels.join(' / ')}`
              : `${entity.name || entity.id}｜该实体没有可用的开关动作，执行会失败`;
          },
        });
      });
      const actions = document.createElement('div');
      actions.className = 'smart-field-row';
      actions.innerHTML = `
        <label class="smart-field"><span>动作</span>
          <select data-a="action">
            ${SMART_HA_ACTIONS.map(([value, text]) => `<option value="${esc(value)}">${esc(text)}</option>`).join('')}
            <option value="__custom">自定义…</option>
          </select></label>
        <label class="smart-field"><span>参数</span>
          <input data-a="param" placeholder="+0.5 / 制冷（带参动作必填）" value="${esc(action.param || '')}"></label>`;
      const actionSel = actions.querySelector('[data-a="action"]');
      const paramInput = actions.querySelector('[data-a="param"]');
      const known = SMART_HA_ACTIONS.some(([value]) => value === action.action);
      actionSel.value = known ? action.action : (action.action ? '__custom' : 'turn_on');
      if (!known && action.action) {
        // 自定义动作：补一个输入框回显原值，不让它被静默改成 turn_on。
        const custom = document.createElement('input');
        custom.placeholder = '自定义 service，例如 set_hvac_mode';
        custom.value = action.action;
        custom.className = 'smart-custom-action';
        actions.prepend(custom);
        custom.addEventListener('input', (event) => { action.action = event.target.value.trim(); });
      }
      if (!action.action) action.action = 'turn_on';
      actionSel.addEventListener('change', (event) => {
        if (event.target.value === '__custom') {
          action.action = '';
          renderActionBody(box, action);
          return;
        }
        action.action = event.target.value;
      });
      paramInput.addEventListener('input', (event) => { action.param = event.target.value; });
      wrap.appendChild(picker);
      wrap.appendChild(actions);
      wrap.appendChild(entNote);
      box.appendChild(wrap);
    }

    triggerTypeSel.addEventListener('change', (event) => {
      draft.trigger.type = event.target.value;
      if (draft.trigger.type === 'time' && !draft.trigger.at) draft.trigger.at = '07:30';
      renderTrigger();
    });
    /**
     * 「手动控制」动作：引用一条已建好的手动控制。
     * 为什么不是把动作再抄一遍：抄一遍就变成两份配置，改一处忘一处；
     * 引用之后，改手动控制等于同时改所有用到它的自动化。
     */
    function renderSceneActionBody(box, action) {
      const manuals = (state.scenes || []).filter((item) => item.kind === 'manual' && item.id !== draft.id);
      if (!manuals.length) {
        box.innerHTML = '<p class="smart-note">还没有可调用的手动控制。先关掉这个窗口，在「手动控制」里建一个（比如「回家模式」），再回来引用。</p>';
        return;
      }
      // 引用的场景被删了：必须留占位项，否则下拉会自动跳到第一条，
      // 看着像换了绑定，实际存的还是那个不存在的 id。
      const orphan = action.sceneId && !manuals.some((item) => item.id === action.sceneId);
      const head = orphan ? `<option value="${esc(action.sceneId)}" selected>（原手动控制已删除，请重选）</option>` : '';
      const list = manuals
        .map((item) => `<option value="${esc(item.id)}" ${!orphan && item.id === action.sceneId ? 'selected' : ''}>${esc(item.name)}</option>`)
        .join('');
      const wrap = document.createElement('div');
      wrap.className = 'smart-scene-row';
      wrap.innerHTML = `
        <label class="smart-field"><span>调用的手动控制</span>
          <select data-a="sceneId">${head}${list}</select></label>
        <p class="smart-scene-desc"></p>`;
      const sel = wrap.querySelector('[data-a="sceneId"]');
      const desc = wrap.querySelector('.smart-scene-desc');
      const paint = () => {
        const target = manuals.find((item) => item.id === sel.value);
        if (!target) {
          desc.textContent = '该手动控制已不存在，执行到这里会失败。';
          desc.classList.add('warn');
          return;
        }
        desc.classList.remove('warn');
        const texts = (target.actionTexts || []).join(' · ') || '（这个手动控制还没有动作）';
        const cool = Number(target.cooldownSec) || 0;
        desc.textContent = `${texts}${cool ? `｜冷却 ${cool} 秒（被动作调用时忽略冷却）` : ''}`;
      };
      if (!action.sceneId && sel.value) action.sceneId = sel.value;
      sel.value = action.sceneId || sel.value;
      if (sel.value !== action.sceneId) action.sceneId = sel.value;
      paint();
      sel.addEventListener('change', (event) => {
        action.sceneId = event.target.value;
        paint();
      });
      box.appendChild(wrap);
    }

    form.querySelector('[data-op="add-action"]').addEventListener('click', () => {
      if (draft.actions.length >= 20) { toast('单个场景最多 20 个动作', 'error'); return; }
      draft.actions.push({ type: 'ha', entityId: '', action: 'turn_on', param: '', onError: 'stop' });
      renderActions();
    });

    renderTrigger();
    renderActions();

    openDialog({
      title: isNew
        ? (draft.kind === 'manual' ? '新建手动控制' : '新建自动化')
        : (draft.kind === 'manual' ? '编辑手动控制' : '编辑自动化'),
      content: form,
      wide: true,
      saveLabel: '保存',
      onSave: async () => {
        const errorEl = form.querySelector('[data-role="error"]');
        errorEl.hidden = true;
        const payload = {
          name: (draft.name || '').trim(),
          kind: draft.kind,
          enabled: draft.enabled !== false,
          cooldownSec: Number(draft.cooldownSec) || 0,
          window: draft.window,
          actions: draft.actions.map((action) => {
            if (action.type === 'delay') return { type: 'delay', seconds: Number(action.seconds) || 1, onError: action.onError };
            if (action.type === 'remote') {
              return { type: 'remote', target: action.target || '', action: action.action || '', onError: action.onError };
            }
            if (action.type === 'scene') {
              return { type: 'scene', sceneId: (action.sceneId || '').trim(), onError: action.onError };
            }
            return {
              type: 'ha',
              entityId: (action.entityId || '').trim(),
              action: (action.action || '').trim(),
              param: (action.param || '').trim(),
              onError: action.onError,
            };
          }),
        };
        if (draft.kind === 'auto') {
          payload.trigger = {
            type: draft.trigger.type,
            deviceId: draft.trigger.deviceId || '',
            state: draft.trigger.state || 'present',
            slot: Number(draft.trigger.slot) || 0,
            at: draft.trigger.at || '',
            holdSec: Number(draft.trigger.holdSec) || 0,
          };
        }
        if (!payload.name) {
          // 就地提示比 toast 更清楚：错误就在字段下面，不会跟着 3 秒后消失。
          errorEl.textContent = '请填写名称';
          errorEl.hidden = false;
          throw new Error('请填写名称');
        }
        try {
          if (isNew) {
            await api('/api/admin/scenes', { method: 'POST', body: JSON.stringify(payload) });
          } else {
            await api(`/api/admin/scenes/${encodeURIComponent(draft.id)}`, {
              method: 'PUT',
              body: JSON.stringify(payload),
            });
          }
        } catch (error) {
          errorEl.textContent = error.message;
          errorEl.hidden = false;
          throw error;
        }
        // 写入成功即可关窗。列表刷新放后台：这里会顺带核对 HA 实体目录等，
        // await 它会让「点保存」到「弹窗消失」之间空出几秒，看着像没点上。
        loadScenes(true).catch((error) => toast(`列表刷新失败：${error.message}`, 'error'));
      },
    });
  }

  state.smartReady = true;

