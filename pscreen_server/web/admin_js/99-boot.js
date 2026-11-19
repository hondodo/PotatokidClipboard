'use strict';

  function activateTab(tab) {
    if (!tab) return;
    state.tab = tab;
    document.querySelectorAll('[data-tab]').forEach((item) => {
      item.classList.toggle('active', item.dataset.tab === tab);
    });
    ['machines', 'users', 'layouts', 'parental', 'traffic', 'programs', 'ha-entities', 'ha-devices', 'device-rules', 'esp-devices', 'smart'].forEach((name) => {
      const section = $('tab-' + name);
      if (section) section.hidden = state.tab !== name;
    });
    // 首次切到流量页才拉数据，之后跟随页面刷新按钮
    if (tab === 'traffic' && !state.traffic) loadTraffic();
    if (tab === 'programs' && !state.programs) {
      loadPrograms();
      loadProgramPreview();
    }
    if (tab === 'ha-entities') {
      // 数据可能在智能页/ESP 页先加载过（那时 tab 隐藏、没渲染），这里补上。
      if (!state.haEntities) loadHaEntities();
      else renderHaEntities();
    }
    if (tab === 'ha-devices') {
      bindHaDevicesOnce();
      if (!state.haDevices) loadHaDevices();
      else renderHaDevices();
    }
    if (tab === 'parental') loadParentalRecords(false);
    if (tab === 'device-rules') {
      Promise.all([
        loadDeviceTypes(),
        loadHaEntities().catch(() => {}),
        (typeof loadHaDevices === 'function' ? loadHaDevices().catch(() => {}) : Promise.resolve()),
      ])
        .then(() => { renderReTypeList(); renderReRules(); renderReTestSel(); })
        .catch((error) => { $('re-type-list').innerHTML = `<div class="empty">加载失败：${esc(error.message)}</div>`; });
    }
    if (tab === 'esp-devices') {
      // 按键可以绑「手动控制」，所以这里要把场景列表一起拉好，否则下拉是空的。
      Promise.all([loadDeviceTypes(), loadHaEntities().catch(() => {}), loadEspDevices(), loadScenes().catch(() => {})])
        .then(() => { if (state.espDevEditId) return openEspDevEditor(state.espDevEditId); })
        .catch((error) => { $('espdev-list').innerHTML = `<div class="empty">加载失败：${esc(error.message)}</div>`; });
    }
    // 智能 Tab：首次进入才拉数据；事件委托只绑一次，避免切回来重复触发。
    if (tab === 'smart') {
      bindSmartOnce();
      loadScenes().catch((error) => {
        $('smart-body').innerHTML = `<div class="empty">加载失败：${esc(error.message)}</div>`;
      });
    }
  }

  document.querySelectorAll('[data-tab]').forEach((btn) => {
    btn.addEventListener('click', () => activateTab(btn.dataset.tab));
  });

  tryAutoLogin();
