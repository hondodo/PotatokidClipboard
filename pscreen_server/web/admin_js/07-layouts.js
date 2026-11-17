'use strict';

  function renderLayouts() {
    const list = $('layout-list');
    const layouts = state.overview.layouts || [];
    if (!layouts.length) {
      list.innerHTML = '<div class="empty">暂无布局数据</div>';
      state.layoutKey = '';
      state.layoutDraft = null;
      renderLayoutMain();
      return;
    }
    if (!layouts.some((item) => item.key === state.layoutKey)) {
      state.layoutKey = layouts[0].key;
      state.layoutDraft = cloneLayout(layouts[0]);
    }
    list.innerHTML = layouts.map((item) => {
      const active = item.key === state.layoutKey ? 'active' : '';
      const owner = item.key.startsWith('device_') ? `设备 ${item.key.slice(7)}` : `用户 ${item.key}`;
      return `<button class="layout-item ${active}" type="button" data-layout-key="${esc(item.key)}">
        ${esc(owner)}
        <span class="sub">${item.all.length} 张卡片 · ${esc(timeAgo(item.updatedAt || item.savedAt))}</span>
      </button>`;
    }).join('');
    list.querySelectorAll('[data-layout-key]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const item = layouts.find((layout) => layout.key === btn.dataset.layoutKey);
        state.layoutKey = btn.dataset.layoutKey;
        state.layoutDraft = cloneLayout(item);
        renderLayouts();
      });
    });
    renderLayoutMain();
  }

  function cloneLayout(layout) {
    return {
      key: layout.key,
      all: Array.isArray(layout.all) ? [...layout.all] : [],
      byHome: Object.fromEntries(Object.entries(layout.byHome || {}).map(([home, list]) => [home, [...list]])),
      updatedAt: layout.updatedAt || 0,
    };
  }

  function renderLayoutMain() {
    const main = $('layout-main');
    const draft = state.layoutDraft;
    $('layout-save').disabled = !draft;
    $('layout-reset').disabled = !draft;
    if (!draft) {
      main.innerHTML = '<div class="empty">暂无布局数据。App 首次拖拽排序后会自动出现在这里。</div>';
      return;
    }
    const owner = draft.key.startsWith('device_') ? `设备 ${draft.key.slice(7)}` : `用户 ${draft.key}`;
    main.innerHTML = `
      <h3>${esc(owner)}</h3>
      <p class="field-note">最后更新：${esc(timeAgo(draft.updatedAt))}。顺序中的 key 对应设备卡片；App 会忽略已经不存在的卡片。</p>
      ${renderOrderGroup('全部视图', draft.all, 'all', null)}
      ${Object.entries(draft.byHome).map(([home, list]) => renderOrderGroup(`家庭：${home}`, list, 'home', home)).join('')}
    `;

    main.querySelectorAll('[data-move]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const scope = btn.dataset.scope;
        const home = btn.dataset.home || null;
        const index = Number(btn.dataset.index);
        const delta = Number(btn.dataset.move);
        const list = scope === 'all' ? draft.all : (draft.byHome[home] || []);
        const next = index + delta;
        if (next < 0 || next >= list.length) return;
        [list[index], list[next]] = [list[next], list[index]];
        renderLayoutMain();
      });
    });
    main.querySelectorAll('[data-remove]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const scope = btn.dataset.scope;
        const home = btn.dataset.home || null;
        const index = Number(btn.dataset.index);
        const list = scope === 'all' ? draft.all : (draft.byHome[home] || []);
        list.splice(index, 1);
        renderLayoutMain();
      });
    });
  }

  function renderOrderGroup(title, list, scope, home) {
    if (!list || !list.length) {
      return `<div class="order-group"><h4>${esc(title)}</h4><div class="empty" style="padding:14px">空</div></div>`;
    }
    return `<div class="order-group">
      <h4>${esc(title)} <span class="muted">(${list.length})</span></h4>
      <div class="order-list">
        ${list.map((key, index) => `
          <div class="order-row">
            <span class="order-index">${index + 1}</span>
            <span class="order-key">${esc(key)}</span>
            <button class="btn" type="button" data-move="-1" data-scope="${scope}" data-home="${esc(home || '')}" data-index="${index}" ${index === 0 ? 'disabled' : ''}>↑</button>
            <button class="btn" type="button" data-move="1" data-scope="${scope}" data-home="${esc(home || '')}" data-index="${index}" ${index === list.length - 1 ? 'disabled' : ''}>↓</button>
            <button class="btn danger" type="button" data-remove data-scope="${scope}" data-home="${esc(home || '')}" data-index="${index}">删</button>
          </div>`).join('')}
      </div>
    </div>`;
  }

  $('layout-save').addEventListener('click', async () => {
    const draft = state.layoutDraft;
    if (!draft) return;
    try {
      await api(`/api/admin/layouts/${encodeURIComponent(draft.key)}`, {
        method: 'PUT',
        body: JSON.stringify({ all: draft.all, byHome: draft.byHome }),
      });
      toast('布局已保存', 'ok');
      await loadOverview(false);
    } catch (error) {
      toast(error.message, 'error');
    }
  });

  $('layout-reset').addEventListener('click', async () => {
    const draft = state.layoutDraft;
    if (!draft) return;
    if (!confirm(`确定重置「${draft.key}」的首页布局？设备下次同步会恢复默认排序。`)) return;
    try {
      await api(`/api/admin/layouts/${encodeURIComponent(draft.key)}`, { method: 'DELETE' });
      state.layoutKey = '';
      state.layoutDraft = null;
      toast('布局已重置', 'ok');
      await loadOverview(false);
    } catch (error) {
      toast(error.message, 'error');
    }
  });

  // ------------------------------------------------------------ 流量统计

