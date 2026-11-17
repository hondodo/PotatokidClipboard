'use strict';

  const state = {
    me: null,
    overview: null,
    tab: 'machines',
    timer: null,
    // 稳定列表：进入页面 / 手动刷新时拍一次顺序快照，轮询只更新内容不重排。
    machineOrder: null,
    machineStatus: null,
    userOrder: null,
    layoutKey: '',
    layoutDraft: null,
    parentalRecords: null,
    parentalLoading: false,
    programs: null,
    programFile: null,
    programDirty: false,
    programPreview: null,
    // HA 实体目录：懒加载（首次切到该 tab 才拉），带筛选状态。
    haEntities: null,
    haEntitiesLoading: false,
    haFilter: { keyword: '', domain: '', home: '', room: '', onlyFree: false, onlyActionable: true },
    // 设备类型字典（全局真源）与 ESP 设备分类（每台设备）
    deviceTypes: null,
    dtEditKey: null,
    // 设备判定规则（规则引擎）
    reEditKey: null,
    reTestIdx: 0,
    reTestEntities: [],
    espDevices: null,
    espDevEditId: null,
  };

  const $ = (id) => document.getElementById(id);
  const esc = (value) => String(value == null ? '' : value)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

  function toast(message, kind = '') {
    const el = document.createElement('div');
    el.className = `toast ${kind}`;
    el.textContent = message;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 3200);
  }

  function timeAgo(ms) {
    if (!ms) return '—';
    const diff = Date.now() - Number(ms);
    if (diff < 0) return '刚刚';
    const sec = Math.floor(diff / 1000);
    if (sec < 10) return '刚刚';
    if (sec < 60) return `${sec} 秒前`;
    const min = Math.floor(sec / 60);
    if (min < 60) return `${min} 分钟前`;
    const hour = Math.floor(min / 60);
    if (hour < 24) return `${hour} 小时前`;
    const day = Math.floor(hour / 24);
    if (day < 30) return `${day} 天前`;
    return new Date(Number(ms)).toLocaleString('zh-CN', { hour12: false });
  }

  async function api(path, options = {}) {
    const opts = {
      credentials: 'same-origin',
      ...options,
      headers: {
        'Content-Type': 'application/json',
        ...(options.headers || {}),
      },
    };
    const res = await fetch(path, opts);
    let data = null;
    try { data = await res.json(); } catch (_) { /* 非 JSON 响应 */ }
    if (res.status === 401) {
      showLogin();
      throw new Error((data && data.msg) || '登录已过期');
    }
    if (!res.ok || (data && typeof data.code === 'number' && data.code !== 0)) {
      throw new Error((data && data.msg) || `请求失败 (HTTP ${res.status})`);
    }
    return data ? data.data : null;
  }

  // ------------------------------------------------------------ 登录 / 注册

  function setAuthMessage(message, kind = '') {
    const el = $('auth-msg');
    el.textContent = message || '';
    el.className = `msg ${kind}`;
  }

  // 公开注册已下线：登录页只有一种模式，不再切换表单。

  function showLogin() {
    state.me = null;
    state.overview = null;
    if (state.timer) { clearInterval(state.timer); state.timer = null; }
    $('login-view').hidden = false;
    $('dashboard-view').hidden = true;
    $('top-actions').hidden = true;
  }

  function isParentRole() {
    return !!(state.me && state.me.role === 'parent');
  }

  function applyRoleLayout() {
    const parent = isParentRole();
    document.querySelectorAll('[data-tab]').forEach((btn) => {
      const adminOnly = ['machines', 'users', 'layouts', 'traffic', 'programs', 'ha-entities', 'device-types', 'device-rules', 'esp-devices'].includes(btn.dataset.tab);
      btn.hidden = parent && adminOnly;
    });
    $('stats').hidden = parent;
    $('parental-bind-hint').textContent = parent
      ? '家长只能绑定未绑定设备，或解绑自己；其他家长的绑定关系需由管理员维护。'
      : '管理员可给任意设备勾选多个家长；家长只能认领未绑定设备，或解绑自己。';
    if (parent) activateTab('parental');
  }

  function showDashboard() {
    $('login-view').hidden = true;
    $('dashboard-view').hidden = false;
    $('top-actions').hidden = false;
    const roleLabel = isParentRole() ? '家长' : '管理员';
    $('admin-name').innerHTML = `${roleLabel} <strong>${esc(state.me.name)}</strong>`;
    applyRoleLayout();
  }

  async function tryAutoLogin() {
    try {
      const data = await api('/api/admin/me');
      state.me = data.user;
      showDashboard();
      await loadOverview(false, true);
      startPolling();
    } catch (_) {
      showLogin();
    }
  }

  $('login-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const username = $('login-username').value.trim();
    const password = $('login-password').value;
    if (!username || !password) return;
    setAuthMessage('登录中…');
    try {
      const data = await api('/api/admin/login', {
        method: 'POST',
        body: JSON.stringify({ username, password }),
      });
      state.me = data.user;
      $('login-password').value = '';
      setAuthMessage('');
      showDashboard();
      await loadOverview(false, true);
      startPolling();
    } catch (error) {
      setAuthMessage(error.message, 'error');
    }
  });

  $('logout-btn').addEventListener('click', async () => {
    try { await api('/api/admin/logout', { method: 'POST', body: '{}' }); } catch (_) { /* 忽略 */ }
    showLogin();
  });

  // 手动刷新是唯一会重新拍顺序快照的入口。
  $('refresh-btn').addEventListener('click', () => loadOverview(true, true));

  // ------------------------------------------------------------ 概览

  function startPolling() {
    if (state.timer) clearInterval(state.timer);
    state.timer = setInterval(() => {
      if (!document.hidden && state.me) loadOverview(false);
    }, 10000);
  }

  async function loadOverview(showError, snapshot = false) {
    try {
      const data = await api('/api/admin/overview');
      state.overview = data;
      state.me = data.admin;
      renderAll(snapshot);
      if (state.tab === 'parental') loadParentalRecords(false);
    } catch (error) {
      if (showError) toast(error.message, 'error');
    }
  }

  function renderAll(snapshot = false) {
    if (!state.overview) return;
    renderStats();
    renderMachines(snapshot);
    renderUsers(snapshot);
    renderLayouts();
    renderParental();
    const realtime = state.overview.realtimeOnline || [];
    $('realtime-pill').textContent = realtime.length
      ? `实时通道在线：${realtime.join('、')}`
      : '实时通道在线：—';
  }

