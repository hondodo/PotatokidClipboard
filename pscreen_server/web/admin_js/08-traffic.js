'use strict';

  const SCOPE_LABELS = { wan: '外网', tail: 'Tailscale', lan: '内网' };

  function fmtBytes(n) {
    if (!n) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    let i = 0;
    let v = Number(n);
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
    return `${v >= 100 ? Math.round(v) : v.toFixed(1)} ${units[i]}`;
  }

  state.traffic = null;

  async function loadTraffic() {
    try {
      const date = $('traffic-date').value || '';
      const data = await api(`/api/admin/traffic${date ? `?date=${encodeURIComponent(date)}` : ''}`);
      state.traffic = data;
      renderTraffic();
    } catch (error) {
      toast(error.message, 'error');
    }
  }

  function renderTraffic() {
    const data = state.traffic;
    if (!data) return;
    const { dates, stats } = data;

    // 日期下拉：只在选项变化时重建，保留当前选择
    const sel = $('traffic-date');
    const current = sel.value;
    sel.innerHTML = dates.map((d) => `<option value="${esc(d)}"${d === (current || dates[0]) ? ' selected' : ''}>${esc(d === dates[0] ? `${d}（今天）` : d)}</option>`).join('');

    // 按来源分组：外网 → Tailscale → 内网；组内按流量降序（大头置顶）
    const groups = [];
    for (const scope of ['wan', 'tail', 'lan']) {
      const rows = [];
      const httpMap = (stats.http || {})[scope] || {};
      for (const [route, item] of Object.entries(httpMap)) {
        rows.push({ name: route, ...item });
      }
      const wsMap = (stats.ws || {})[scope] || {};
      for (const [channel, item] of Object.entries(wsMap)) {
        rows.push({ name: `WS ${channel}`, ...item });
      }
      if (!rows.length) continue;
      rows.sort((a, b) => (b.in + b.out) - (a.in + a.out));
      const total = rows.reduce((acc, r) => ({
        count: acc.count + r.count, in: acc.in + r.in, out: acc.out + r.out,
      }), { count: 0, in: 0, out: 0 });
      groups.push({ scope, label: SCOPE_LABELS[scope] || scope, rows, total });
    }

    const body = $('traffic-body');
    if (!groups.length) {
      body.innerHTML = '<tr><td colspan="6" class="empty">暂无统计数据。</td></tr>';
    } else {
      // 每组：来源分组标题 → 明细行（降序）→ 紧跟该来源的总计行
      body.innerHTML = groups.map((g) => `
        <tr class="traffic-scope-header"><td colspan="6">${esc(g.label)}</td></tr>` +
        g.rows.map((r) => `
        <tr>
          <td>${esc(r.name)}</td>
          <td>${esc(g.label)}</td>
          <td>${r.count}</td>
          <td>${fmtBytes(r.in)}</td>
          <td>${fmtBytes(r.out)}</td>
          <td><strong>${fmtBytes(r.in + r.out)}</strong></td>
        </tr>`).join('') +
        `
        <tr class="traffic-total">
          <td>${esc(g.label)} 总计</td>
          <td></td>
          <td>${g.total.count}</td>
          <td>${fmtBytes(g.total.in)}</td>
          <td>${fmtBytes(g.total.out)}</td>
          <td><strong>${fmtBytes(g.total.in + g.total.out)}</strong></td>
        </tr>`).join('');
    }

    // WS 账号明细：跨账号汇总展示（wan 优先，无则退到 tail/lan）
    const acctHost = $('traffic-ws-accounts');
    const acctMap = (stats.wsAccounts || {});
    let acctHtml = '';
    for (const scope of ['wan', 'tail', 'lan']) {
      const entries = Object.entries(acctMap[scope] || {}).sort((a, b) => (b[1].in + b[1].out) - (a[1].in + a[1].out));
      if (!entries.length) continue;
      const acctTotal = entries.reduce((acc, [, v]) => ({
        in: acc.in + v.in, out: acc.out + v.out,
      }), { in: 0, out: 0 });
      acctHtml += `<p style="margin:6px 0;color:var(--muted)">WebSocket 账号流量（${esc(SCOPE_LABELS[scope] || scope)}）</p><div class="table-wrap"><table><thead><tr><th>账号</th><th style="width:130px">上行</th><th style="width:130px">下行</th><th style="width:130px">合计</th></tr></thead><tbody>` +
        entries.map(([name, v]) => `<tr><td>${esc(name)}</td><td>${fmtBytes(v.in)}</td><td>${fmtBytes(v.out)}</td><td><strong>${fmtBytes(v.in + v.out)}</strong></td></tr>`).join('') +
        `<tr class="traffic-total"><td>总计</td><td>${fmtBytes(acctTotal.in)}</td><td>${fmtBytes(acctTotal.out)}</td><td><strong>${fmtBytes(acctTotal.in + acctTotal.out)}</strong></td></tr>` +
        '</tbody></table></div>';
    }
    acctHost.innerHTML = acctHtml;

    // 流量汇总：页面最底部按来源给一份合计（HTTP + WS），内外网各花了多少一眼看到
    const sumHost = $('traffic-summary');
    if (!groups.length) {
      sumHost.innerHTML = '';
    } else {
      const grand = groups.reduce((acc, g) => ({
        count: acc.count + g.total.count, in: acc.in + g.total.in, out: acc.out + g.total.out,
      }), { count: 0, in: 0, out: 0 });
      sumHost.innerHTML = `<p style="margin:6px 0;color:var(--muted)">流量汇总（HTTP + WebSocket）</p><div class="table-wrap"><table><thead><tr><th>来源</th><th style="width:130px">上行</th><th style="width:130px">下行</th><th style="width:130px">合计</th></tr></thead><tbody>` +
        groups.map((g) => `<tr><td>${esc(g.label)}</td><td>${fmtBytes(g.total.in)}</td><td>${fmtBytes(g.total.out)}</td><td><strong>${fmtBytes(g.total.in + g.total.out)}</strong></td></tr>`).join('') +
        `<tr class="traffic-total"><td>总计</td><td>${fmtBytes(grand.in)}</td><td>${fmtBytes(grand.out)}</td><td><strong>${fmtBytes(grand.in + grand.out)}</strong></td></tr>` +
        '</tbody></table></div>';
    }
  }

  $('traffic-date').addEventListener('change', loadTraffic);
  $('traffic-refresh').addEventListener('click', loadTraffic);

  // ------------------------------------------------------------ 家长控制

  function fmtTime(ms) {
    if (!ms) return '—';
    return new Date(Number(ms)).toLocaleString('zh-CN', { hour12: false });
  }

  function fmtDuration(value) {
    const total = Math.max(0, Math.floor(Number(value) || 0));
    const hour = Math.floor(total / 3600);
    const minute = Math.floor((total % 3600) / 60);
    const second = total % 60;
    if (hour > 0) return `${hour} 小时 ${minute} 分`;
    if (minute > 0) return `${minute} 分 ${second} 秒`;
    return `${second} 秒`;
  }

  async function loadParentalRecords(showError) {
    if (!state.me || state.parentalLoading) return;
    state.parentalLoading = true;
    try {
      state.parentalRecords = await api('/api/admin/parental/records?limit=200');
      renderParental();
    } catch (error) {
      if (showError) toast(error.message, 'error');
    } finally {
      state.parentalLoading = false;
    }
  }

  function renderParentalBinding() {
    const body = $('parental-bind-body');
    const parent = isParentRole();
    // 家长控制只列电视：中控设备不参与家长绑定。
    const machines = (state.overview.machines || [])
      .filter((machine) => machineKind(machine) === 'tv');
    const available = (state.overview.availableMachines || [])
      .filter((machine) => machineKind(machine) === 'tv');
    if (parent) {
      const rows = machines.map((machine) => ({ machine, own: true }))
        .concat(available.map((machine) => ({ machine, own: false })));
      if (!rows.length) {
        body.innerHTML = '<tr><td colspan="3"><div class="empty">还没有可绑定的电视。电视端注册后会出现在这里，未绑定电视可直接认领。</div></td></tr>';
        return;
      }
      body.innerHTML = rows.map(({ machine, own }) => `
        <tr data-bind-id="${esc(machine.id)}" data-own="${own}">
          <td>
            <div class="cell-stack">
              <span class="strong">${esc(machineDisplay(machine).name)}</span>
              <span class="muted">设备备注：${machine.nameSet ? esc(machine.name) : '未设置'}</span>
              <span class="mono">${esc(machine.id)}</span>
              <span class="badge kind-tv">电视</span>
              <span class="${machine.online ? 'status-text on' : 'status-text'}">${machine.online ? '在线' : '离线'}</span>
            </div>
          </td>
          <td>${parentBadges(machine)}</td>
          <td>
            <button class="btn small ${own ? 'danger' : 'primary'}" type="button"
              data-bind-action="${own ? 'unbind' : 'bind'}">${own ? '解绑我' : '加入绑定'}</button>
          </td>
        </tr>`).join('');
      return;
    }

    const parents = (state.overview.users || [])
      .filter((user) => user.role === 'parent' || user.role === 'admin');
    if (!machines.length) {
      body.innerHTML = '<tr><td colspan="3"><div class="empty">还没有电视设备注册。中控设备不参与家长绑定。</div></td></tr>';
      return;
    }
    if (!parents.length) {
      body.innerHTML = '<tr><td colspan="3"><div class="empty">还没有家长账号，请先在「用户与家庭」把账号角色改为家长。</div></td></tr>';
      return;
    }
    body.innerHTML = machines.map((machine) => {
      const bound = new Set(machine.parents || []);
      const chips = parents.map((user) => `
        <label class="parent-chip">
          <input type="checkbox" data-parent value="${esc(user.name)}" ${bound.has(user.name) ? 'checked' : ''}>
          ${esc(user.displayName || user.name)} (${esc(user.name)})
        </label>`).join('');
      return `
        <tr data-bind-id="${esc(machine.id)}" data-own="false">
          <td>
            <div class="cell-stack">
              <span class="strong">${esc(machineDisplay(machine).name)}</span>
              <span class="muted">设备备注：${machine.nameSet ? esc(machine.name) : '未设置'}</span>
              <span class="mono">${esc(machine.id)}</span>
              <span class="badge kind-tv">电视</span>
              <span class="${machine.online ? 'status-text on' : 'status-text'}">${machine.online ? '在线' : '离线'}</span>
            </div>
          </td>
          <td><div class="parent-chips">${chips}</div></td>
          <td><button class="btn small primary" type="button" data-bind-action="save">保存绑定</button></td>
        </tr>`;
    }).join('');
  }

  function renderParentalRecords() {
    const records = state.parentalRecords || {};
    const sessions = records.sessions || [];
    const context = state.overview.machines || [];
    const machineById = new Map(context.map((machine) => [machine.id, machine]));
    $('parental-sessions-body').innerHTML = sessions.length
      ? sessions.map((item) => {
        const machine = machineById.get(item.machineId);
        return `
          <tr>
            <td>${esc(fmtTime(item.startMs))}</td>
            <td>${esc(fmtTime(item.endMs))}</td>
            <td><span class="strong">${esc(item.childName || item.childId)}</span></td>
            <td>${esc(item.machineName || (machine && machine.name) || item.machineId)}</td>
            <td>${esc(fmtDuration(item.durationSec))}</td>
            <td>${esc(fmtDuration(item.dailySec))}</td>
          </tr>`;
      }).join('')
      : '<tr><td colspan="6"><div class="empty">暂无观看记录。电视端开启儿童模式并上报心跳后会自动出现。</div></td></tr>';

    const unlocks = records.unlockRequests || [];
    $('parental-unlocks-body').innerHTML = unlocks.length
      ? unlocks.map((event) => {
        const data = event.data || {};
        const children = Array.isArray(data.childIds) ? data.childIds.join('、') : '';
        return `
          <tr>
            <td>${esc(fmtTime(event.ts))}</td>
            <td>${esc(event.machineName || event.from || '—')}</td>
            <td>${esc(children || '—')}</td>
            <td>${esc(data.reason || '锁屏解锁')}</td>
          </tr>`;
      }).join('')
      : '<tr><td colspan="4"><div class="empty">暂无解锁请求。</div></td></tr>';
  }

  function renderParental() {
    if (!state.overview) return;
    renderParentalBinding();
    renderParentalRecords();
    $('parental-bind-body').querySelectorAll('button[data-bind-action]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const row = btn.closest('tr[data-bind-id]');
        const id = row && row.dataset.bindId;
        if (!id) return;
        btn.disabled = true;
        try {
          if (isParentRole()) {
            await api('/api/admin/parental/bind', {
              method: 'POST',
              body: JSON.stringify({ deviceId: id, bind: btn.dataset.bindAction === 'bind' }),
            });
            toast(btn.dataset.bindAction === 'bind' ? '已绑定到当前账号' : '已解绑', 'ok');
          } else {
            const parents = Array.from(row.querySelectorAll('input[data-parent]:checked'))
              .map((input) => input.value);
            await api(`/api/admin/machines/${encodeURIComponent(id)}`, {
              method: 'PUT',
              body: JSON.stringify({ parents }),
            });
            toast('已更新家长绑定', 'ok');
          }
          await loadOverview(false);
          await loadParentalRecords(false);
        } catch (error) {
          toast(error.message, 'error');
        } finally {
          btn.disabled = false;
        }
      });
    });
  }

  $('parental-refresh').addEventListener('click', () => {
    loadOverview(false);
    loadParentalRecords(true);
  });

  // ------------------------------------------------------------ 节目编辑

