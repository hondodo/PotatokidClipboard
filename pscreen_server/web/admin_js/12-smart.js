'use strict';

  // 「智能」Tab：手动控制（点一下执行一组动作）+ 自动化（条件满足自动执行）。
  //
  // 数据来自 /api/admin/scenes；动作编辑复用 04-ha.js 的 createEntityPicker 与
  // /api/admin/remote/devices 的能力表，保证后台配的动作和小屏按键可用命令一致。
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
      // 动作编辑器要用：HA 实体目录 + 遥控目标能力表。失败不阻塞列表。
      loadHaEntities().catch(() => {}),
      loadSmartRemote().catch(() => {}),
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
    const running = autos.filter((item) => item.enabled).length;
    const windowSec = (state.sceneSettings && state.sceneSettings.occupiedWindowSec) || 90;
    $('smart-hint').textContent = `手动控制 ${manuals.length} 个 · 自动化 ${autos.length} 个（${running} 个已开启）`
      + ` · 感应实体 ${(state.smartPresence || []).length} 个（判空闲窗口 ${windowSec} 秒）`;

    body.innerHTML = `
      <div class="card smart-section">
        <h3>手动控制 <span class="muted">点「执行」立即跑一遍，可以反复用</span></h3>
        ${manuals.length
          ? `<div class="smart-manual-grid">${manuals.map(smartManualCard).join('')}</div>`
          : '<div class="empty">还没有手动控制。点右上角「+ 手动控制」建一个，比如「回家模式：开客厅灯 + 中控切首页 + 开夜灯」。</div>'}
      </div>
      <div class="card smart-section">
        <h3>自动化 <span class="muted">条件满足时自己执行，关掉开关立即停用</span></h3>
        ${autos.length
          ? `<div class="smart-auto-list">${autos.map(smartAutoRow).join('')}</div>`
          : '<div class="empty">还没有自动化。点右上角「+ 自动化」建一个，比如「小屏持续有人 10 秒 → 开客厅灯」，或「每天 22:00 → 中控切首页」。</div>'}
      </div>`;
  }

  function smartManualCard(scene) {
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
      if (act === 'run') return runSceneNow(scene);
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
   */
  async function runSceneNow(scene) {
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
    const pickers = [];

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
            delete action.entityId; delete action.target;
          } else if (action.type === 'ha') {
            action.entityId = action.entityId || '';
            action.action = 'turn_on';
            delete action.seconds; delete action.target;
          } else {
            action.target = action.target || '';
            action.action = action.action || '';
            delete action.seconds; delete action.entityId;
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

      // HA 实体
      const wrap = document.createElement('div');
      wrap.className = 'smart-ha-row';
      const picker = createEntityPicker({
        value: action.entityId || '',
        onChange: (entity) => { action.entityId = entity ? entity.id : ''; },
      });
      pickers.push(picker);
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
      wrap.appendChild(picker.root);
      wrap.appendChild(actions);
      if (picker.note) wrap.appendChild(picker.note);
      box.appendChild(wrap);
    }

    triggerTypeSel.addEventListener('change', (event) => {
      draft.trigger.type = event.target.value;
      if (draft.trigger.type === 'time' && !draft.trigger.at) draft.trigger.at = '07:30';
      renderTrigger();
    });
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
        if (!payload.name) throw new Error('请填写名称');
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
        await loadScenes(true);
      },
    });
  }

  state.smartReady = true;

