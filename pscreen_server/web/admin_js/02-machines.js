'use strict';

  function renderStats() {
    const stats = state.overview.stats || {};
    $('stats').innerHTML = `
      <div class="stat accent"><div class="k">在线设备</div><div class="v">${stats.online || 0}<small>/ ${stats.machines || 0} 台</small></div></div>
      <div class="stat"><div class="k">已注册设备</div><div class="v">${stats.machines || 0}<small>台</small></div></div>
      <div class="stat blue"><div class="k">用户账号</div><div class="v">${stats.users || 0}<small>个</small></div></div>
      <div class="stat"><div class="k">已知家庭</div><div class="v">${stats.homes || 0}<small>个</small></div></div>
    `;
  }

  function homesBadges(homes, source) {
    if (homes === null || homes === undefined) {
      const label = source === 'none' ? '跟随 .env' : '跟随上层';
      return `<span class="badge inherit">${esc(label)}</span>`;
    }
    if (!Array.isArray(homes) || homes.length === 0) {
      return '<span class="badge all">全部家庭</span>';
    }
    return `<div class="badges">${homes.map((home) => `<span class="badge">${esc(home)}</span>`).join('')}</div>`;
  }

  function sourceLabel(source) {
    if (source === 'machine') return '机器设置';
    if (source === 'user') return '用户设置';
    return '未配置';
  }

  // 设备名称生效顺序：设备备注（nameSet 才有效）> 账号展示名（displayName）> 账号 id。
  // 设备备注是设备自己在设置页改的名字，比账号展示名更贴近这台设备；
  // 客户端本机备注别名优先级最高，但只存在于设备本地，后台不可见。
  function machineDisplay(machine) {
    if (machine.nameSet && String(machine.name || '').trim()) {
      return { name: String(machine.name).trim(), source: '设备备注' };
    }
    const accountDisplay = String(machine.commDisplayName || '').trim();
    if (accountDisplay) return { name: accountDisplay, source: '账号展示名' };
    if (machine.commAccount) return { name: machine.commAccount, source: '账号 id' };
    return { name: machine.name || machine.id, source: '设备 id（无通信账号）' };
  }

  // 用户名称生效顺序：账号展示名（displayName）> 账号 id（name）。
  function userDisplay(user) {
    if (user.displayNameSet && user.displayName) return { name: user.displayName, source: '账号展示名' };
    return { name: user.name, source: '账号 id' };
  }

  // 通信账号列：账号 / 展示名（未设置明确标注）/ ws 握手回写的客户端标识。
  function commCell(machine) {
    if (!machine.commAccount && !machine.commApp) return '<span class="muted">—</span>';
    let label = '';
    if (machine.commApp) {
      label = esc(machine.commApp);
      if (machine.commVersion) {
        label += ` v${esc(machine.commVersion)}`;
        if (machine.commBuild) label += `+${esc(machine.commBuild)}`;
      }
    }
    const displayName = String(machine.commDisplayName || '').trim();
    return `
      <div class="cell-stack">
        ${machine.commAccount ? `<span class="mono">${esc(machine.commAccount)}</span>` : '<span class="muted">账号 id：未设置</span>'}
        <span class="muted">展示名：${displayName ? esc(displayName) : '未设置（回落下一层）'}</span>
        ${label ? `<span class="muted">${label}</span>` : ''}
      </div>`;
  }

  function machineKind(machine) {
    if (machine && (machine.kind === 'home' || machine.kind === 'tv' || machine.kind === 'parent')) return machine.kind;
    const app = (machine && machine.commApp) || '';
    if (app === 'potatokid.tools.homecontroller' || app === 'potatokid.tools.homecontroller.phone' || app === 'pscreen_home') return 'home';
    if (app === 'potatokid.tools.homecontroller.parent') return 'parent';
    if (app === 'screen.potatokid.tools' || app === 'screen.potatokid.tools.phone' || app === 'screen.potatokid.tools.board' || app === 'screen.potatokid.potatokid_screen' || app === 'potatokid_screen') return 'tv';
    return '';
  }

  function kindBadge(machine) {
    const kind = machineKind(machine);
    if (kind === 'tv') return '<span class="badge kind-tv">电视</span>';
    if (kind === 'home') return '<span class="badge kind-home">中控</span>';
    if (kind === 'parent') return '<span class="badge kind-parent">家长端</span>';
    return '<span class="muted">—</span>';
  }

  /** 设备所属中控账号（owner）下拉：设备状态页负责设备 ↔ 中控绑定。 */
  function ownerSelect(machine) {
    const users = state.overview.users || [];
    const current = machine.owner || '';
    const options = ['<option value="">未关联</option>'].concat(
      users.map((user) => {
        const label = user.displayName && user.displayName !== user.name
          ? `${user.displayName} (${user.name})`
          : user.name;
        return `<option value="${esc(user.name)}"${user.name === current ? ' selected' : ''}>${esc(label)}</option>`;
      }),
    );
    if (current && !users.some((user) => user.name === current)) {
      options.push(`<option value="${esc(current)}" selected>${esc(current)}（账号已删除）</option>`);
    }
    return `<select data-owner-select title="所属中控">${options.join('')}</select>`;
  }

  function parentBadges(machine) {
    const kind = machineKind(machine);
    if (kind === 'home') {
      return '<span class="muted">中控端不支持</span>';
    }
    if (kind === 'parent') {
      return '<span class="muted">家长端不支持</span>';
    }
    const parents = Array.isArray(machine.parents) ? machine.parents : [];
    if (!parents.length) return '<span class="muted">未绑定</span>';
    return `<div class="badges">${parents.map((name) => `<span class="badge role-parent">${esc(name)}</span>`).join('')}</div>`;
  }

  // 稳定列表：轮询/心跳只就地更新内容，不按服务端排序重排。
  // 只有进入页面和点「刷新」时会拍一次顺序快照。

  /** 输入框 / 下拉框聚焦视为正在编辑，此时暂停列表的增删与重排。 */
  function isEditingElement(el) {
    return !!el && (el.tagName === 'INPUT' || el.tagName === 'SELECT'
      || el.tagName === 'TEXTAREA' || el.isContentEditable === true);
  }

  /** 弹窗打开或表内输入框/下拉框聚焦时，该表处于锁定状态。 */
  function tableLocked(bodyId) {
    if ($('dialog-root').querySelector('.overlay')) return true;
    const body = $(bodyId);
    const active = document.activeElement;
    return !!body && isEditingElement(active) && body.contains(active);
  }

  /** 就地更新一行：聚焦中的单元格跳过，避免替换正在编辑的控件。 */
  function updateRowContent(row, cells) {
    cells.forEach((html, index) => {
      const td = row.children[index];
      if (!td) return;
      const active = document.activeElement;
      if (isEditingElement(active) && td.contains(active)) return;
      if (td.innerHTML !== html) td.innerHTML = html;
    });
  }

  /** 家长私有别名：仅 admin overview 下发，只读展示，不参与机器行排序。 */
  function aliasNotes(machine) {
    const aliases = machine.aliases && typeof machine.aliases === 'object' ? machine.aliases : {};
    const entries = Object.entries(aliases);
    if (!entries.length) return '';
    const items = entries
      .map(([account, alias]) => `${esc(account)} → ${esc(alias)}`)
      .join('；');
    return `<span class="muted">家长私有别名（仅本人可见，不影响设备备注与其他家长）：${items}</span>`;
  }

  /** 深睡从机没有持续心跳，不能简单按「在线/离线」判断。 */
  function formatLeft(ms) {
    const minutes = Math.max(0, Math.round(ms / 60000));
    if (minutes < 1) return '不到 1 分钟';
    if (minutes < 60) return `${minutes} 分钟`;
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    return rest ? `${hours} 小时 ${rest} 分钟` : `${hours} 小时`;
  }

  /**
   * 深睡从机的「休眠中」状态：用最后上报时间 + 自报的定时唤醒间隔推算。
   * 在预期唤醒点之后留 10 分钟宽限，超过就算「已超预期」，便于发现设备真的掉线。
   */
  function sleepStatus(machine) {
    if (machine.platform !== 'esp32' || machine.role !== 'slave') return null;
    const sleepSec = Number(machine.sleepSec) || 0;
    const lastSeen = Number(machine.lastSeen) || 0;
    if (sleepSec <= 0 || !lastSeen) return null;
    const expected = lastSeen + sleepSec * 1000;
    const now = Date.now();
    if (now < expected + 10 * 60 * 1000) {
      return { text: `休眠中 · 预计 ${formatLeft(expected - now)} 后唤醒` };
    }
    return { text: `休眠中 · 已超预期唤醒 ${formatLeft(now - expected)}` };
  }

  function machineCells(machine) {
    const online = machine.online === true;
    const kind = machineKind(machine);
    const nameInfo = machineDisplay(machine);
    const sleep = online ? null : sleepStatus(machine);
    const statusText = online ? '在线' : (sleep ? sleep.text : '离线');
    const statusClass = online ? 'on' : (sleep ? 'sleep' : '');
    return [
      `<span class="dot ${online ? 'on' : 'off'}"></span><span class="status-text ${statusClass}">${statusText}</span>`,
      `
        <div class="cell-stack">
          <span class="strong">${esc(nameInfo.name)}</span>
          <span class="muted">当前显示 = ${esc(nameInfo.name)}（来源：${esc(nameInfo.source)}）</span>
          <span class="mono">${esc(machine.id)}</span>
          <span class="muted">设备备注：${machine.nameSet ? esc(machine.name) : '未设置'}</span>
          ${aliasNotes(machine)}
          <span class="muted">型号：${esc(machine.model || machine.platform || '未知设备')}${machine.appVersion ? ` · v${esc(machine.appVersion)}` : ''}</span>
        </div>`,
      kindBadge(machine),
      ownerSelect(machine),
      commCell(machine),
      `
        <div class="cell-stack">
          ${homesBadges(machine.effectiveHomes, machine.homesSource)}
          <span class="muted">来源：${esc(sourceLabel(machine.homesSource))}${machine.homesSource === 'machine' ? '' : (machine.owner ? ' → ' + esc(machine.owner) : '')}</span>
        </div>`,
      machine.currentHome ? `<span class="badge">${esc(machine.currentHome)}</span>` : '<span class="muted">—</span>',
      `<div class="cell-stack"><span>${esc(timeAgo(machine.lastSeen))}</span><span class="muted">最后连接 ${machine.lastConnectedAt ? esc(timeAgo(machine.lastConnectedAt)) : '—'}</span><span class="mono">${esc(machine.ip || '')}</span></div>`,
      `
        <div class="row-actions">
          <button class="btn small" data-action="homes" type="button">家庭</button>
          ${kind === 'home'
            ? '<span class="muted">中控端无儿童模式</span>'
            : kind === 'parent'
              ? '<span class="muted">家长端无儿童模式</span>'
              : `<button class="btn small${machine.parental && machine.parental.mode === 'on' ? ' primary' : ''}" data-action="parental" type="button">儿童模式</button>`}
          <button class="btn small" data-action="rename" type="button">改名</button>
          ${kind === '' ? '<button class="btn small" data-action="esp" type="button">ESP 控制</button>' : ''}
          ${machine.platform === 'esp32' ? '<button class="btn small" data-action="fwpush" type="button">远程更新</button>' : ''}
          <button class="btn small danger" data-action="delete" type="button">删除</button>
        </div>`,
    ];
  }

  function createMachineRow(machine) {
    const row = document.createElement('tr');
    row.dataset.machineId = machine.id;
    for (let index = 0; index < 9; index += 1) row.appendChild(document.createElement('td'));
    updateRowContent(row, machineCells(machine));
    return row;
  }

  /**
   * 机器行顺序：
   * - 拍快照时按服务端顺序（在线组 + 离线组）。
   * - 轮询时老行保持原位；新上线设备追加到在线组末尾，掉线设备移到在线组之后。
   */
  function computeMachineOrder(machines, snapshot) {
    const byId = new Map(machines.map((machine) => [machine.id, machine]));
    const serverOnline = machines.filter((machine) => machine.online === true).map((machine) => machine.id);
    const serverOffline = machines.filter((machine) => machine.online !== true).map((machine) => machine.id);
    if (snapshot || !state.machineOrder) {
      return serverOnline.concat(serverOffline);
    }
    let order = state.machineOrder.filter((id) => byId.has(id));
    const known = new Set(state.machineOrder);
    const firstOffline = () => order.findIndex((id) => {
      const machine = byId.get(id);
      return machine && machine.online !== true;
    });
    // 轮询期间新出现的设备：在线追加到在线组末尾，离线追加到表尾。
    for (const machine of machines) {
      if (known.has(machine.id)) continue;
      known.add(machine.id);
      if (machine.online === true) {
        const at = firstOffline();
        if (at >= 0) order.splice(at, 0, machine.id);
        else order.push(machine.id);
      } else {
        order.push(machine.id);
      }
    }
    // 已存在设备的状态变化：上线追加到在线组末尾；掉线移到在线组之后。
    if (state.machineStatus) {
      for (const machine of machines) {
        const wasOnline = state.machineStatus.get(machine.id);
        if (wasOnline === undefined || wasOnline === (machine.online === true)) continue;
        order = order.filter((id) => id !== machine.id);
        if (machine.online === true) {
          const at = firstOffline();
          if (at >= 0) order.splice(at, 0, machine.id);
          else order.push(machine.id);
        } else {
          const at = firstOffline();
          order.splice(at >= 0 ? at : order.length, 0, machine.id);
        }
      }
    }
    return order;
  }

  function renderMachines(snapshot = false) {
    const body = $('machines-body');
    const machines = state.overview.machines || [];
    if (!machines.length) {
      body.innerHTML = '<tr><td colspan="9"><div class="empty">还没有设备注册。中控屏启动并配置服务端地址后会自动出现。</div></td></tr>';
      state.machineOrder = [];
      state.machineStatus = new Map();
      return;
    }
    const byId = new Map(machines.map((machine) => [machine.id, machine]));
    if (tableLocked('machines-body')) {
      // 编辑/下拉/弹窗期间：不增删、不重排，只就地更新已有行的内容。
      body.querySelectorAll('tr[data-machine-id]').forEach((row) => {
        const machine = byId.get(row.dataset.machineId);
        if (machine) updateRowContent(row, machineCells(machine));
      });
      state.machineOrder = Array.from(body.querySelectorAll('tr[data-machine-id]'))
        .map((row) => row.dataset.machineId);
      return;
    }
    const order = computeMachineOrder(machines, snapshot);
    const placeholder = body.querySelector('tr:not([data-machine-id])');
    if (placeholder) placeholder.remove();
    const rows = new Map();
    body.querySelectorAll('tr[data-machine-id]').forEach((row) => {
      rows.set(row.dataset.machineId, row);
    });
    for (const id of order) {
      if (rows.has(id)) continue;
      const row = createMachineRow(byId.get(id));
      rows.set(id, row);
    }
    for (const id of order) updateRowContent(rows.get(id), machineCells(byId.get(id)));
    for (const [id, row] of rows) {
      if (!byId.has(id)) row.remove();
    }
    // 只移动必要的行，保留已有 DOM 节点（key = 设备 id）。
    let cursor = body.firstElementChild;
    for (const id of order) {
      const row = rows.get(id);
      if (!row) continue;
      if (row !== cursor) body.insertBefore(row, cursor);
      cursor = row.nextElementSibling;
    }
    state.machineOrder = order;
    state.machineStatus = new Map(machines.map((machine) => [machine.id, machine.online === true]));
  }

  function userCells(user) {
    const nameInfo = userDisplay(user);
    const machines = Array.isArray(user.machines) ? user.machines : [];
    return [
      `
        <div class="cell-stack">
          <span class="strong">${esc(nameInfo.name)}</span>
          <span class="muted">生效显示 = ${esc(nameInfo.name)}（来源：${esc(nameInfo.source)}）</span>
          <span class="mono">账号 id：${esc(user.name)}${user.enabled === false ? ' · 已禁用' : ''}</span>
          <span class="muted">账号展示名：${user.displayNameSet ? esc(user.displayName) : '未设置'}</span>
        </div>`,
      `
        <select data-action="role" ${user.name === state.me.name ? 'disabled' : ''}>
          <option value="user" ${user.role === 'user' ? 'selected' : ''}>普通用户</option>
          <option value="parent" ${user.role === 'parent' ? 'selected' : ''}>家长</option>
          <option value="admin" ${user.role === 'admin' ? 'selected' : ''}>管理员</option>
        </select>`,
      `
        <div class="cell-stack">
          ${homesBadges(user.homes, 'none')}
          <span class="muted">${user.homes === null || user.homes === undefined ? '未配置（回落 .env）' : (Array.isArray(user.homes) && user.homes.length === 0 ? '不限制' : '仅这些家庭')}</span>
        </div>`,
      `
        <div class="cell-stack">
          ${machines.length
            ? machines.map((machine) => `<span>${esc(machine.name)}${machine.nameSet ? '' : '（未设置备注）'}</span>`).join('')
            : '<span class="muted">无关联设备</span>'}
        </div>`,
      String(user.machineCount || 0),
      `<span class="muted">${esc(user.loginTime ? timeAgo(new Date(user.loginTime).getTime()) : '从未登录')}</span>`,
      `
        <div class="row-actions">
          <button class="btn small" data-action="homes" type="button">家庭</button>
          <button class="btn small" data-action="rename" type="button">改名</button>
        </div>`,
    ];
  }

  function createUserRow(user) {
    const row = document.createElement('tr');
    row.dataset.userName = user.name;
    for (let index = 0; index < 7; index += 1) row.appendChild(document.createElement('td'));
    updateRowContent(row, userCells(user));
    return row;
  }

  /** 用户行同样只在进页面/手动刷新时拍快照；轮询不因角色排序变化而移动行。 */
  function computeUserOrder(users, snapshot) {
    const names = users.map((user) => user.name);
    if (snapshot || !state.userOrder) return names.slice();
    const order = state.userOrder.filter((name) => names.includes(name));
    const known = new Set(order);
    for (const name of names) {
      if (!known.has(name)) order.push(name);
    }
    return order;
  }

  function renderUsers(snapshot = false) {
    const body = $('users-body');
    const users = state.overview.users || [];
    if (!users.length) {
      body.innerHTML = '<tr><td colspan="7"><div class="empty">还没有用户。</div></td></tr>';
      state.userOrder = [];
      return;
    }
    const byName = new Map(users.map((user) => [user.name, user]));
    if (tableLocked('users-body')) {
      body.querySelectorAll('tr[data-user-name]').forEach((row) => {
        const user = byName.get(row.dataset.userName);
        if (user) updateRowContent(row, userCells(user));
      });
      state.userOrder = Array.from(body.querySelectorAll('tr[data-user-name]'))
        .map((row) => row.dataset.userName);
      return;
    }
    const order = computeUserOrder(users, snapshot);
    const placeholder = body.querySelector('tr:not([data-user-name])');
    if (placeholder) placeholder.remove();
    const rows = new Map();
    body.querySelectorAll('tr[data-user-name]').forEach((row) => {
      rows.set(row.dataset.userName, row);
    });
    for (const name of order) {
      if (rows.has(name)) continue;
      const row = createUserRow(byName.get(name));
      rows.set(name, row);
    }
    for (const name of order) updateRowContent(rows.get(name), userCells(byName.get(name)));
    for (const [name, row] of rows) {
      if (!byName.has(name)) row.remove();
    }
    let cursor = body.firstElementChild;
    for (const name of order) {
      const row = rows.get(name);
      if (!row) continue;
      if (row !== cursor) body.insertBefore(row, cursor);
      cursor = row.nextElementSibling;
    }
    state.userOrder = order;
  }

  // 行内按钮/下拉走事件委托：复用行 DOM 时不会丢事件监听。
  function currentMachine(id) {
    return ((state.overview && state.overview.machines) || []).find((machine) => machine.id === id);
  }

  function currentUser(name) {
    return ((state.overview && state.overview.users) || []).find((user) => user.name === name);
  }

  function bindStableListEvents() {
    $('machines-body').addEventListener('click', (event) => {
      const btn = event.target.closest('button[data-action]');
      if (!btn) return;
      const row = btn.closest('tr[data-machine-id]');
      const machine = row && currentMachine(row.dataset.machineId);
      if (!machine) return;
      if (btn.dataset.action === 'homes') {
        editHomes({
          title: `可见家庭 · ${machine.name}`,
          homes: machine.homes,
          onSave: (homes) => api(`/api/admin/machines/${encodeURIComponent(machine.id)}`, {
            method: 'PUT',
            body: JSON.stringify({ homes }),
          }),
        });
      } else if (btn.dataset.action === 'rename') {
        editMachineName(machine);
      } else if (btn.dataset.action === 'parental') {
        editParental(machine);
      } else if (btn.dataset.action === 'esp') {
        // 直接跳到「ESP 设备分类」Tab 并选中这台设备，统一在页面编辑器里配置。
        state.espDevEditId = machine.id;
        activateTab('esp-devices');
      } else if (btn.dataset.action === 'fwpush') {
        if (!confirm(`确定让「${machine.name}」立即检查并安装最新固件？\n设备离线或休眠时，会在下次联网/唤醒时执行。`)) return;
        (async () => {
          try {
            await api(`/api/admin/machines/${encodeURIComponent(machine.id)}/fw_push`, { method: 'POST' });
            toast('已下发远程更新标记', 'ok');
            await loadOverview(false);
          } catch (error) {
            toast(error.message, 'error');
          }
        })();
      } else if (btn.dataset.action === 'delete') {
        if (!confirm(`确定删除设备「${machine.name}」？删除后它下次心跳会重新注册为未命名设备。`)) return;
        (async () => {
          try {
            await api(`/api/admin/machines/${encodeURIComponent(machine.id)}`, { method: 'DELETE' });
            toast('设备已删除', 'ok');
            await loadOverview(false);
          } catch (error) {
            toast(error.message, 'error');
          }
        })();
      }
    });
    $('machines-body').addEventListener('change', (event) => {
      const select = event.target.closest('select[data-owner-select]');
      if (!select) return;
      const row = select.closest('tr[data-machine-id]');
      if (!row) return;
      const id = row.dataset.machineId;
      (async () => {
        try {
          await api(`/api/admin/machines/${encodeURIComponent(id)}`, {
            method: 'PUT',
            body: JSON.stringify({ owner: select.value }),
          });
          toast('已更新所属中控', 'ok');
          await loadOverview(false);
        } catch (error) {
          toast(error.message, 'error');
        }
      })();
    });
    $('users-body').addEventListener('change', (event) => {
      const select = event.target.closest('select[data-action="role"]');
      if (!select) return;
      const row = select.closest('tr[data-user-name]');
      if (!row) return;
      const name = row.dataset.userName;
      (async () => {
        try {
          await api(`/api/admin/users/${encodeURIComponent(name)}`, {
            method: 'PUT',
            body: JSON.stringify({ role: select.value }),
          });
          toast('已更新角色', 'ok');
          await loadOverview(false);
        } catch (error) {
          toast(error.message, 'error');
        }
      })();
    });
    $('users-body').addEventListener('click', (event) => {
      const btn = event.target.closest('button[data-action]');
      if (!btn) return;
      const row = btn.closest('tr[data-user-name]');
      const user = row && currentUser(row.dataset.userName);
      if (!user) return;
      if (btn.dataset.action === 'homes') {
        editHomes({
          title: `可见家庭 · ${user.displayName || user.name}`,
          homes: user.homes,
          level: 'user',
          onSave: (homes) => api(`/api/admin/users/${encodeURIComponent(user.name)}`, {
            method: 'PUT',
            body: JSON.stringify({ homes }),
          }),
        });
      } else if (btn.dataset.action === 'rename') {
        editDisplayName(user);
      }
    });
  }

  bindStableListEvents();

  // ------------------------------------------------------------ 家庭编辑弹窗

