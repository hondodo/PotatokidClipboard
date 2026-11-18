'use strict';

  async function loadHaEntities(force = false) {
    if (state.haEntitiesLoading) return;
    state.haEntitiesLoading = true;
    const meta = $('ha-entities-meta');
    if (meta) meta.textContent = '加载中…';
    try {
      const data = await api(`/api/admin/ha/entities${force ? '?refresh=1' : ''}`);
      state.haEntities = data;
      renderHaEntities();
    } catch (error) {
      if (meta) meta.textContent = '加载失败';
      const body = $('ha-entities-body');
      if (body) {
        body.innerHTML = `<tr><td colspan="7" class="empty">${esc(error.message)}</td></tr>`;
      }
      toast(error.message, 'error');
    } finally {
      state.haEntitiesLoading = false;
    }
  }

  /** 已绑定实体集合（来自各页面的显示绑定与按键），用于「只看未绑定」。 */
  function boundEntityIds() {
    const set = new Set();
    const machines = (state.overview && state.overview.machines) || [];
    for (const machine of machines) {
      for (const page of machine.espPages || []) {
        for (const slot of ['main', 's1', 's2']) {
          const entityId = page.bindings && page.bindings[slot];
          if (entityId) set.add(entityId);
        }
        for (const button of page.buttons || []) {
          if (button.entityId) set.add(button.entityId);
        }
      }
    }
    return set;
  }

  /** 实体的房间名（与后端分组口径一致：room → areaName → '未命名区域'）。 */
  function haEntityRoom(entity) {
    return entity.room || entity.areaName || '未命名区域';
  }

  function filterHaEntities() {
    const catalog = state.haEntities;
    if (!catalog) return [];
    const { keyword, domain, home, room, onlyFree } = state.haFilter;
    const bound = onlyFree ? boundEntityIds() : null;
    const needle = keyword.trim().toLowerCase();

    return (catalog.entities || []).filter((entity) => {
      if (domain && entity.domain !== domain) return false;
      if (home && (entity.home || '未归属家庭') !== home) return false;
      // 房间名在不同家庭里会重名（「客厅」几乎每家都有），
      // 所以房间筛选**必须**跟着家一起生效，不能只按房间名匹配。
      // room 存在而 home 为空属于非法组合，直接排除，避免列出所有家的同名房间。
      if (room) {
        if (!home) return false;
        if (haEntityRoom(entity) !== room) return false;
      }
      if (bound && bound.has(entity.id)) return false;
      // 默认只看能配到 ESP 的实体——sensor 之类有 900 多个，
      // 但它们没有可用的开关动作，列出来只会淹没真正要用的。
      // 用户主动搜索时放宽：这时候他就是冲着某个具体 id 来的，
      // 哪怕它是 sensor 也要能搜到（可以只复制 ID）。
      if (state.haFilter.onlyActionable && !needle && !(entity.actions && entity.actions.length)) return false;
      if (needle) {
        const haystack = `${entity.name} ${entity.id} ${entity.device} ${entity.room}`.toLowerCase();
        if (!haystack.includes(needle)) return false;
      }
      return true;
    });
  }

  function renderHaEntities() {
    const catalog = state.haEntities;
    if (!catalog) return;

    const total = (catalog.entities || []).length;
    const bound = boundEntityIds();
    const actionable = (catalog.entities || []).filter((e) => e.actions && e.actions.length).length;
    $('ha-entities-meta').textContent = `${total} 个实体 · ${actionable} 个可控制 · ${bound.size} 个已绑定`;

    renderHaDomains();
    renderHaTree();
    renderHaTable();
  }

  function renderHaDomains() {
    const wrap = $('ha-entities-domains');
    const catalog = state.haEntities;
    wrap.innerHTML = '';
    const chip = (label, value, count) => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = `ha-chip${state.haFilter.domain === value ? ' active' : ''}`;
      btn.innerHTML = `${esc(label)}${count == null ? '' : `<span class="n">${count}</span>`}`;
      btn.addEventListener('click', () => {
        state.haFilter.domain = state.haFilter.domain === value ? '' : value;
        renderHaEntities();
      });
      wrap.appendChild(btn);
    };
    chip('全部域', '', null);
    for (const domain of catalog.domains || []) {
      chip(domain.label, domain.id, domain.count);
    }
  }

  function renderHaTree() {
    const wrap = $('ha-entities-tree');
    const catalog = state.haEntities;
    wrap.innerHTML = '';
    const { home, room } = state.haFilter;

    const homeNode = (name, count) => {
      const box = document.createElement('div');
      box.className = 'ha-tree-home';
      const head = document.createElement('div');
      head.className = `ha-tree-home-name${home === name && !room ? ' active' : ''}`;
      head.innerHTML = `<span>${esc(name)}</span><span class="n">${count}</span>`;
      head.addEventListener('click', () => {
        // 点家：只按家过滤，并清掉房间。
        const isActive = home === name && !room;
        state.haFilter.home = isActive ? '' : name;
        state.haFilter.room = '';
        renderHaEntities();
      });
      box.appendChild(head);
      return box;
    };

    // 房间节点必须带上它所属的家——房间名在不同家之间会重名，
    // 只记房间名会导致「选了 A 家的客厅，却列出所有家的客厅」。
    const roomNode = (homeName, roomName, count, isActive) => {
      const item = document.createElement('div');
      item.className = `ha-tree-room${isActive ? ' active' : ''}`;
      item.innerHTML = `<span>${esc(roomName)}</span><span class="n">${count}</span>`;
      item.addEventListener('click', () => {
        const isActiveNow = state.haFilter.home === homeName && state.haFilter.room === roomName;
        state.haFilter.home = isActiveNow ? '' : homeName;
        state.haFilter.room = isActiveNow ? '' : roomName;
        renderHaEntities();
      });
      return item;
    };

    for (const homeItem of catalog.homes || []) {
      const box = homeNode(homeItem.name, homeItem.count);
      const rooms = document.createElement('div');
      rooms.className = 'ha-tree-rooms';
      for (const roomItem of homeItem.rooms) {
        rooms.appendChild(roomNode(
          homeItem.name,
          roomItem.name,
          roomItem.count,
          home === homeItem.name && room === roomItem.name,
        ));
      }
      box.appendChild(rooms);
      wrap.appendChild(box);
    }

    if (!wrap.childElementCount) {
      wrap.innerHTML = '<div class="empty">没有匹配的分组</div>';
    }
  }

  function renderHaTable() {
    const body = $('ha-entities-body');
    const rows = filterHaEntities();
    const bound = boundEntityIds();
    const { home, room, domain } = state.haFilter;

    const titleParts = [];
    if (home) titleParts.push(home);
    if (room) titleParts.push(room);
    if (domain) {
      const found = (state.haEntities.domains || []).find((d) => d.id === domain);
      titleParts.push(found ? found.label : domain);
    }
    if (!titleParts.length) {
      const needle = state.haFilter.keyword.trim();
      titleParts.push(needle
        ? `搜索「${needle}」`
        : (state.haFilter.onlyActionable ? '可控制实体' : '全部实体'));
    }
    $('ha-entities-title').textContent = titleParts.join(' / ');
    const totalEntities = (state.haEntities.entities || []).length;
    $('ha-entities-count').textContent = `${rows.length} / ${totalEntities}`;

    if (!rows.length) {
      body.innerHTML = '<tr><td colspan="7" class="empty">没有匹配的实体</td></tr>';
      return;
    }

    const frag = document.createDocumentFragment();
    for (const entity of rows.slice(0, 500)) {
      const tr = document.createElement('tr');

      const nameTd = document.createElement('td');
      const stack = document.createElement('div');
      stack.className = 'ha-entity-name';
      const title = document.createElement('span');
      title.className = 'strong';
      title.textContent = entity.name || entity.id;
      stack.appendChild(title);
      if (entity.device) {
        const sub = document.createElement('span');
        sub.className = 'sub';
        sub.textContent = entity.device;
        stack.appendChild(sub);
      }
      nameTd.appendChild(stack);

      const idTd = document.createElement('td');
      idTd.innerHTML = `<span class="mono ha-id-text">${esc(entity.id)}</span>`;

      const domainTd = document.createElement('td');
      const badge = document.createElement('span');
      badge.className = 'badge';
      badge.textContent = entity.domainLabel || entity.domain;
      domainTd.appendChild(badge);

      const homeTd = document.createElement('td');
      homeTd.innerHTML = `<span class="muted">${esc(entity.home || '未归属家庭')}</span>`;

      const roomTd = document.createElement('td');
      const roomName = haEntityRoom(entity);
      roomTd.innerHTML = `<span class="muted">${esc(roomName)}</span>`;

      const stateTd = document.createElement('td');
      const isOn = entity.state === 'on' || entity.state === 'open' || entity.state === 'home'
        || entity.state === 'playing' || entity.state === 'heat' || entity.state === 'cool';
      const dot = document.createElement('span');
      dot.className = `dot ${isOn ? 'on' : 'off'}`;
      const stateText = document.createElement('span');
      stateText.className = 'status-text';
      // 状态值 + 单位 / 关键属性（current_temperature、brightness…）：
      // 只看裸 state 分不清 ESP 上屏会显示什么，这里直接给出完整值。
      stateText.textContent = haStateText(entity);
      // 状态可能是 sensor 的超长属性串，直接完整换行铺开显示。
      const stateWrap = document.createElement('div');
      stateWrap.className = 'ha-state-cell';
      stateWrap.append(dot, stateText);
      stateTd.appendChild(stateWrap);

      const actionTd = document.createElement('td');
      actionTd.className = 'ha-actions-td';
      const actions = document.createElement('div');
      actions.className = 'ha-actions-cell';

      const copyBtn = document.createElement('button');
      copyBtn.type = 'button';
      copyBtn.className = 'btn small';
      copyBtn.textContent = '复制 ID';
      copyBtn.addEventListener('click', async () => {
        try {
          await navigator.clipboard.writeText(entity.id);
          toast(`已复制 ${entity.id}`, 'ok');
        } catch (_) {
          toast('复制失败，请手动选中 entity_id 复制', 'error');
        }
      });
      actions.appendChild(copyBtn);

      if (entity.actions && entity.actions.length) {
        const bindBtn = document.createElement('button');
        bindBtn.type = 'button';
        bindBtn.className = 'btn small primary';
        bindBtn.textContent = '绑定到 ESP';
        bindBtn.addEventListener('click', () => bindEntityToEsp(entity));
        actions.appendChild(bindBtn);
      }

      if (bound.has(entity.id)) {
        const tag = document.createElement('span');
        tag.className = 'badge all';
        tag.textContent = '已绑定';
        actions.appendChild(tag);
      }

      actionTd.appendChild(actions);
      tr.append(nameTd, idTd, domainTd, homeTd, roomTd, stateTd, actionTd);
      frag.appendChild(tr);
    }
    body.replaceChildren(frag);
    if (rows.length > 500) {
      const tr = document.createElement('tr');
      tr.innerHTML = `<td colspan="7" class="empty">仅显示前 500 条，共 ${rows.length} 条，请用搜索或筛选缩小范围</td>`;
      body.appendChild(tr);
    }
  }

  /**
   * 从实体库跳到某台 ESP 设备的页面编辑器，并把该实体预填成当前页的一个按键。
   *
   * ESP 小屏设备在 machines 里的 kind 是**空字符串**（不是 'esp'）——
   * 设备表里「ESP 控制」按钮也是按 kind === '' 渲染的，这里口径保持一致。
   */
  function bindEntityToEsp(entity) {
    const machines = ((state.overview && state.overview.machines) || [])
      .filter((machine) => !machine.kind);
    if (!machines.length) {
      toast('没有 ESP 设备，先在「设备状态」里确认设备已注册', 'error');
      return;
    }
    const wrap = document.createElement('div');
    wrap.style.display = 'grid';
    wrap.style.gap = '12px';

    const note = document.createElement('p');
    note.className = 'field-note';
    note.textContent = `把「${entity.name}」（${entity.id}）加到哪台 ESP 设备的页面里？`;
    wrap.appendChild(note);

    const select = document.createElement('select');
    for (const machine of machines) {
      const opt = document.createElement('option');
      opt.value = machine.id;
      opt.textContent = machine.name || machine.id;
      select.appendChild(opt);
    }
    wrap.appendChild(select);

    openDialog({
      title: '绑定实体到 ESP',
      content: wrap,
      saveLabel: '去配置',
      onSave: () => {
        const machine = machines.find((m) => m.id === select.value);
        if (!machine) throw new Error('设备不存在');
        state.espDevEditId = machine.id;
        state.espPreset = { deviceId: machine.id, entityId: entity.id, name: entity.name };
        activateTab('esp-devices');
      },
    });
  }

  // ------------------------------------------------------------ 实体选择弹窗

  /** HA 常见英文状态 → 中文（只翻译明确枚举值，数值与自定义串原样保留）。 */
  const HA_STATE_LABELS = {
    on: '开', off: '关', open: '开', closed: '关', opening: '打开中', closing: '关闭中',
    unavailable: '离线', unknown: '未知', idle: '空闲', playing: '播放中', paused: '暂停',
    standby: '待机', heat: '制热', cool: '制冷', auto: '自动', dry: '除湿', fan_only: '送风',
    heating: '加热中', cooling: '制冷中', home: '在家', not_home: '离家',
    locked: '已上锁', unlocked: '未上锁', charging: '充电中', docked: '已回充',
  };

  /**
   * 实体当前值：state + 单位 + 关键属性。
   *
   * ESP 屏幕绑定的常常是属性（当前温度 / 目标温度 / 亮度），只看裸 state
   * 看不出上屏后会显示什么，所以把常用属性一并列出来。
   */
  function haStateText(entity) {
    if (!entity) return '—';
    const attrs = entity.attributes || {};
    const raw = entity.state == null || entity.state === '' ? '' : String(entity.state);
    const unit = attrs.unit_of_measurement ? String(attrs.unit_of_measurement) : '';
    let text = HA_STATE_LABELS[raw] || raw || '—';
    if (unit && /^-?\d+(\.\d+)?$/.test(raw)) text = `${raw} ${unit}`;
    const extras = [];
    if (attrs.current_temperature != null && attrs.current_temperature !== '') {
      extras.push(`当前 ${attrs.current_temperature}°C`);
    }
    if (attrs.temperature != null && attrs.temperature !== '') {
      extras.push(`目标 ${attrs.temperature}°C`);
    }
    if (attrs.brightness != null && attrs.brightness !== '') {
      extras.push(`亮度 ${Math.round(Number(attrs.brightness) / 2.55)}%`);
    }
    if (attrs.percentage != null && attrs.percentage !== '') {
      extras.push(`比例 ${attrs.percentage}%`);
    }
    return extras.length ? `${text}（${extras.join(' · ')}）` : text;
  }

  /**
   * 实体选择弹窗：按「家庭 → 房间 → 设备」筛选 + 搜索 + 显示当前状态值。
   *
   * ESP 的三个显示绑定与按键实体都走这里——只给一个 entity_id 输入框时，
   * 用户只能靠记 id 猜；这里把归属信息和当前值一起列出来再选。
   *
   * @param {object} options
   * @param {string} options.title 弹窗标题
   * @param {string} options.value 当前 entity_id（高亮）
   * @param {boolean} options.actionableOnly 只列有可用动作的实体（按键用）
   * @param {Function} options.onPick 选中回调 (entity)
   */
  function openEntityPicker({ title = '选择实体', value = '', actionableOnly = false, quickTokens = null, extraEntities = null, onPick } = {}) {
    const root = $('dialog-root');
    const filters = { home: '', room: '', device: '', keyword: '', onlyActionable: !!actionableOnly };
    let catalog = state.haEntities;

    root.innerHTML = `
      <div class="overlay">
        <div class="card dialog wide ent-pick-dialog" role="dialog" aria-modal="true">
          <div class="dialog-head">
            <h3>${esc(title)}</h3>
            <button class="icon-btn" type="button" data-close>×</button>
          </div>
          <div class="dialog-body">
            ${quickTokens && quickTokens.length ? `<div class="ent-pick-quick">
              <div class="ent-pick-quick-title">${esc(quickTokens.label || '快捷标签')}</div>
              <div class="ent-pick-quick-list">${quickTokens.items.map((t, i) =>
                `<button class="ent-pick-quick-btn" type="button" data-quick="${i}" title="${esc(t.id)}">${esc(t.name)}${t.value ? ` <span class="ent-pick-quick-val">${esc(t.value)}</span>` : ''}</button>`).join('')}</div>
            </div>` : ''}
            <div class="ent-pick-filters">
              <label>家庭<select data-filter="home"></select></label>
              <label>房间<select data-filter="room"></select></label>
              <label>设备<select data-filter="device"></select></label>
              <label class="ent-pick-search">搜索<input type="search" data-filter="keyword" placeholder="名称 / entity_id" autocomplete="off"></label>
              <label class="ent-pick-only"><input type="checkbox" data-filter="onlyActionable" ${filters.onlyActionable ? 'checked' : ''}>只看可控制</label>
              <button class="btn small" type="button" data-refresh>刷新状态</button>
            </div>
            <div class="ent-pick-meta"></div>
            <div class="ent-pick-list"></div>
          </div>
          <div class="dialog-foot">
            <span class="ent-pick-tip">当前：<code>${esc(value || '未选择')}</code></span>
            <button class="btn" type="button" data-close>取消</button>
          </div>
        </div>
      </div>`;

    const close = () => { root.innerHTML = ''; };
    root.querySelectorAll('[data-close]').forEach((btn) => btn.addEventListener('click', close));
    if (quickTokens && quickTokens.length) {
      root.querySelectorAll('[data-quick]').forEach((btn) => btn.addEventListener('click', () => {
        const token = quickTokens.items[Number(btn.dataset.quick)];
        if (token && typeof onPick === 'function') onPick(token);
        close();
      }));
    }
    const overlay = root.querySelector('.overlay');
    overlay.addEventListener('click', (event) => { if (event.target === overlay) close(); });

    const homeSel = root.querySelector('[data-filter="home"]');
    const roomSel = root.querySelector('[data-filter="room"]');
    const deviceSel = root.querySelector('[data-filter="device"]');
    const keywordInput = root.querySelector('[data-filter="keyword"]');
    const onlyBox = root.querySelector('[data-filter="onlyActionable"]');
    const refreshBtn = root.querySelector('[data-refresh]');
    const meta = root.querySelector('.ent-pick-meta');
    const list = root.querySelector('.ent-pick-list');

    // 主目录（HA 实体）+ 附加实体（遥控状态等虚拟实体），统一参与筛选/搜索/列表。
    const all = () => [...((catalog && catalog.entities) || []), ...(extraEntities || [])];

    /** 按「家 / 关键词」过滤：用于推导房间候选。 */
    function poolForRooms() {
      const needle = filters.keyword.trim().toLowerCase();
      return all().filter((entity) => {
        if (filters.onlyActionable && !(entity.actions && entity.actions.length)) return false;
        if (filters.home && (entity.home || '未归属家庭') !== filters.home) return false;
        if (needle) {
          const hay = `${entity.name} ${entity.id} ${entity.device} ${entity.room} ${entity.areaName}`.toLowerCase();
          if (!hay.includes(needle)) return false;
        }
        return true;
      });
    }

    /** 在家 + 房间 + 关键词范围内推导设备候选。 */
    function poolForDevices() {
      return poolForRooms().filter((entity) => !filters.room || haEntityRoom(entity) === filters.room);
    }

    function fillSelect(sel, allLabel, values, current) {
      const keep = values.includes(current) ? current : '';
      sel.innerHTML = `<option value="">${esc(allLabel)}</option>`
        + values.map((v) => `<option value="${esc(v)}" ${v === keep ? 'selected' : ''}>${esc(v)}</option>`).join('');
      return keep;
    }

    function renderFilters() {
      const homeNames = Array.from(new Set([
        ...((catalog && catalog.homes) || []).map((item) => item.name),
        ...(extraEntities || []).map((item) => item.home).filter(Boolean),
      ]));
      filters.home = fillSelect(homeSel, '全部家庭', homeNames, filters.home);

      const roomNames = Array.from(new Set(poolForRooms().map((entity) => haEntityRoom(entity))))
        .sort((a, b) => a.localeCompare(b, 'zh-CN'));
      filters.room = fillSelect(roomSel, '全部房间', roomNames, filters.room);

      const deviceNames = Array.from(new Set(poolForDevices().map((entity) => entity.device || '未归属设备')))
        .sort((a, b) => a.localeCompare(b, 'zh-CN'));
      filters.device = fillSelect(deviceSel, '全部设备', deviceNames, filters.device);
    }

    function matched() {
      return poolForDevices().filter((entity) => {
        if (filters.device && (entity.device || '未归属设备') !== filters.device) return false;
        return true;
      }).sort((a, b) => {
        // 遥控状态虚拟实体置顶，避免淹没在上千个 HA 实体里。
        if (!!a.__remoteBadge !== !!b.__remoteBadge) return a.__remoteBadge ? -1 : 1;
        const key = (e) => `${e.home || ''}|${haEntityRoom(e)}|${e.device || ''}|${e.name || e.id}`;
        return key(a).localeCompare(key(b), 'zh-CN');
      });
    }

    function renderList() {
      const rows = matched();
      const hasCatalog = !!catalog || !!(extraEntities && extraEntities.length);
      meta.textContent = hasCatalog
        ? `${rows.length} 个实体${filters.onlyActionable ? '（可控制）' : ''}${rows.length > 300 ? '，仅显示前 300 条' : ''}`
        : '实体目录未加载';
      list.innerHTML = '';
      if (!hasCatalog) {
        list.innerHTML = '<div class="ent-pick-empty">实体目录未加载，点「刷新状态」从 HA 拉取</div>';
        return;
      }
      if (!rows.length) {
        list.innerHTML = '<div class="ent-pick-empty">没有匹配的实体，试试清空筛选或换个关键词</div>';
        return;
      }
      const frag = document.createDocumentFragment();
      for (const entity of rows.slice(0, 300)) {
        const row = document.createElement('button');
        row.type = 'button';
        row.className = `ent-pick-row${entity.id === value ? ' current' : ''}`;

        const main = document.createElement('div');
        main.className = 'ent-pick-main';
        const name = document.createElement('span');
        name.className = 'nm';
        name.textContent = entity.__remoteBadge ? `[${entity.__remoteBadge}] ${entity.name || entity.id}` : (entity.name || entity.id);
        name.title = name.textContent;
        const state = document.createElement('span');
        state.className = 'st';
        state.textContent = haStateText(entity);
        // 长状态（sensor 原始串可能有几百字符）在列表里省略显示，hover 看全值。
        state.title = state.textContent;
        main.append(name, state);

        const where = document.createElement('div');
        where.className = 'ent-pick-where';
        where.textContent = `${entity.home || '未归属家庭'} · ${haEntityRoom(entity)} · ${entity.device || '未归属设备'}`;

        const idText = document.createElement('div');
        idText.className = 'ent-pick-id';
        idText.textContent = entity.id;

        row.append(main, where, idText);
        row.addEventListener('click', () => {
          if (typeof onPick === 'function') onPick(entity);
          close();
        });
        frag.appendChild(row);
      }
      list.appendChild(frag);
    }

    function renderAll() {
      renderFilters();
      renderList();
    }

    homeSel.addEventListener('change', () => {
      filters.home = homeSel.value;
      filters.room = '';
      filters.device = '';
      renderAll();
    });
    roomSel.addEventListener('change', () => {
      filters.room = roomSel.value;
      filters.device = '';
      renderAll();
    });
    deviceSel.addEventListener('change', () => {
      filters.device = deviceSel.value;
      renderFilters();
      renderList();
    });
    keywordInput.addEventListener('input', () => {
      filters.keyword = keywordInput.value;
      renderAll();
    });
    onlyBox.addEventListener('change', () => {
      filters.onlyActionable = onlyBox.checked;
      renderAll();
    });
    refreshBtn.addEventListener('click', async () => {
      refreshBtn.disabled = true;
      meta.textContent = '正在从 HA 拉取…';
      try {
        await loadHaEntities(true);
        catalog = state.haEntities;
      } catch (error) {
        toast('刷新失败：' + error.message, 'error');
      } finally {
        refreshBtn.disabled = false;
        renderAll();
      }
    });

    renderAll();
  }

  // ------------------------------------------------------------ 实体选择器

  /**
   * 可搜索的实体选择器（可复用组件）。
   *
   * 交互：点输入框或「选择」按钮展开菜单 → 按「家 → 房间」分组列出 → 搜索过滤 →
   * 点一项填入 entity_id。输入框仍可直接手填，兼容存量配置与手输场景。
   *
   * @param {object} options
   * @param {string} options.value 初始 entity_id
   * @param {Function} options.onChange 选中实体后回调 (entity|null)
   */
  function createEntityPicker({ value = '', onChange } = {}) {
    const catalog = state.haEntities;
    const entities = (catalog && catalog.entities) || [];

    const wrap = document.createElement('div');
    wrap.className = 'entity-picker';

    const input = document.createElement('input');
    input.className = 'entity-picker-input';
    input.placeholder = 'light.living_room';
    input.maxLength = 128;
    input.value = value;
    input.autocomplete = 'off';

    const toggle = document.createElement('button');
    toggle.type = 'button';
    toggle.className = 'btn small entity-picker-btn';
    toggle.textContent = '选择';

    // 说明文字是独立元素（不塞进 .entity-picker），由调用方放到整行下方——
    // 塞在 picker 里会被 grid 列宽计算牵连，把整行撑歪。
    const note = document.createElement('p');
    note.className = 'entity-picker-desc';

    wrap.append(input, toggle);

    // 菜单挂到 body 上：弹窗 body 是 overflow:auto，绝对定位会被裁掉。
    const menu = document.createElement('div');
    menu.className = 'entity-picker-menu';
    menu.hidden = true;
    document.body.appendChild(menu);

    let current = value;
    let keyword = '';
    let highlighted = null;
    // document/window 级监听统一挂在这个 AbortController 上，
    // 弹窗关闭时 abort 掉，避免残留监听影响后续弹窗。
    const listeners = new AbortController();

    /** 按 entity_id 找实体（用于回显友好名与可用动作）。 */
    const findEntity = (id) => entities.find((entity) => entity.id === id) || null;

    function describe() {
      const entity = findEntity(current);
      if (!current) {
        note.textContent = entities.length
          ? '从「选择」下拉里挑，或直接输入 entity_id。'
          : '实体目录未加载，可直接手填 entity_id（保存后生效）。';
        return;
      }
      if (!entity) {
        note.textContent = '当前值不在 HA 实体目录中（可能已删除），将按原样保存。';
        return;
      }
      const actions = entity.actions || [];
      // 带上家/房间：不同家可能有同名房间，光看名称分不清是哪台设备。
      const where = `${entity.home || '未归属家庭'} · ${haEntityRoom(entity)}`;
      note.textContent = actions.length
        ? `${entity.name}｜${where}｜${entity.domainLabel}｜可用动作：${actions.map((a) => a.label).join(' / ')}`
        : `${entity.name}｜${where}｜${entity.domainLabel}｜该域没有可用的开关动作，绑定后按键会失败`;
    }

    function renderMenu() {
      menu.innerHTML = '';
      if (!entities.length) {
        menu.innerHTML = '<div class="entity-picker-empty">实体目录未加载，请先到「HA 实体库」页加载</div>';
        return;
      }
      const needle = keyword.trim().toLowerCase();
      const matched = entities.filter((entity) => {
        if (!entity.actions || !entity.actions.length) return false;  // 只列可控制的
        if (!needle) return true;
        return `${entity.name} ${entity.id} ${entity.device} ${entity.room}`.toLowerCase().includes(needle);
      });

      if (!matched.length) {
        menu.innerHTML = '<div class="entity-picker-empty">没有匹配的实体</div>';
        return;
      }

      // 按「家 → 房间」分组渲染。
      const groups = new Map();
      for (const entity of matched) {
        const homeName = entity.home || '未归属家庭';
        if (!groups.has(homeName)) groups.set(homeName, new Map());
        const rooms = groups.get(homeName);
        const roomName = entity.room || entity.areaName || '未命名区域';
        if (!rooms.has(roomName)) rooms.set(roomName, []);
        rooms.get(roomName).push(entity);
      }

      const frag = document.createDocumentFragment();
      for (const [homeName, rooms] of groups) {
        const groupLabel = document.createElement('div');
        groupLabel.className = 'entity-picker-group';
        groupLabel.textContent = homeName;
        frag.appendChild(groupLabel);
        for (const [roomName, list] of rooms) {
          const roomLabel = document.createElement('div');
          roomLabel.className = 'entity-picker-group';
          roomLabel.textContent = `　${roomName}`;
          frag.appendChild(roomLabel);
          for (const entity of list) {
            const option = document.createElement('div');
            option.className = 'entity-picker-option';
            const title = document.createElement('span');
            title.className = 't';
            title.textContent = entity.name || entity.id;
            const sub = document.createElement('span');
            sub.className = 's';
            sub.textContent = entity.id;
            option.append(title, sub);
            option.addEventListener('mousedown', (event) => {
              // mousedown 而非 click：input blur 会先关菜单，click 就收不到了。
              event.preventDefault();
              select(entity);
            });
            frag.appendChild(option);
          }
        }
      }
      menu.appendChild(frag);
    }

    function select(entity) {
      current = entity.id;
      input.value = entity.id;
      highlighted = entity;
      keyword = '';
      close();
      describe();
      if (typeof onChange === 'function') onChange(entity);
    }

    /** 把菜单定位到输入框下方；空间不够时翻到上方。 */
    function positionMenu() {
      const rect = input.getBoundingClientRect();
      // 菜单最大高度与 CSS 保持一致（min(60vh, 460px)），用于判断上下翻转。
      const maxHeight = Math.min(window.innerHeight * 0.6, 460);
      const height = Math.min(menu.scrollHeight || maxHeight, maxHeight);
      const below = window.innerHeight - rect.bottom;
      const top = below < height + 12 && rect.top > height + 12
        ? rect.top - height - 6
        : rect.bottom + 4;
      menu.style.left = `${Math.max(8, Math.min(rect.left, window.innerWidth - 428))}px`;
      menu.style.top = `${Math.max(8, top)}px`;
    }

    function open() {
      if (!entities.length) {
        renderMenu();
        menu.hidden = false;
        positionMenu();
        return;
      }
      keyword = '';
      input.value = current || '';
      renderMenu();
      menu.hidden = false;
      positionMenu();
    }

    /** 展开菜单并把焦点交给输入框，用户可以直接打字搜索。 */
    function openForSearch() {
      open();
      input.focus();
      // focus 事件里 openKeepingInput 看到菜单已展开会直接返回，不会覆盖 keyword。
      // 选中全文：用户一打字就是「替换成搜索词」，而不是追加在 entity_id 后面。
      keyword = '';
      input.select();
    }

    function close() {
      menu.hidden = true;
    }

    // focus / click：展开菜单，但**不覆盖用户已经输入的内容**——
    // 直接调 open() 会把 input.value 重置成已选实体，用户打的字就没了。
    const openKeepingInput = () => {
      if (!menu.hidden) return;
      const typed = input.value.trim();
      keyword = (typed && typed !== current) ? typed : '';
      renderMenu();
      menu.hidden = false;
      positionMenu();
    };
    input.addEventListener('focus', openKeepingInput);
    input.addEventListener('click', openKeepingInput);
    toggle.addEventListener('click', (event) => {
      event.preventDefault();
      if (menu.hidden) openForSearch(); else close();
    });
    input.addEventListener('input', () => {
      // 输入框里可能还留着上次选中的 entity_id，用户接着打字会变成
      // 「switch.xxx洗衣机」这种拼接串，直接拿去搜必然搜不到。
      // 这里把旧 id 前缀剥掉，只用「新输入的部分」做搜索词，
      // 并把输入框内容也改成干净的搜索词（光标移到末尾）。
      let typed = input.value;
      if (current && typed.startsWith(current) && typed.length > current.length) {
        typed = typed.slice(current.length);
        input.value = typed;
        const pos = typed.length;
        input.setSelectionRange(pos, pos);
      }
      keyword = typed;
      if (menu.hidden) menu.hidden = false;
      renderMenu();
      positionMenu();
    });
    // 关闭条件只有一个：焦点真正离开了下拉区域。
    //
    // 这里用 focusout + activeElement 判定，而不是 blur 直接关：
    //  ① 拖动菜单滚动条 / 用滚轮滚动菜单时，浏览器会把焦点甩到 body，
    //     blur 会误判成「用户离开了」而把菜单关掉，导致根本没法选中；
    //  ② 焦点掉到 body（点滚动条、点空白）不算「离开」，真正的离开
    //     由下面的 focusin / mousedown 判定负责。
    input.addEventListener('focusout', () => {
      setTimeout(() => {
        if (menu.hidden) return;
        const active = document.activeElement;
        if (!active || active === document.body) return;   // 焦点散失：不算离开
        if (wrap.contains(active) || menu.contains(active)) return;
        close();
      }, 0);
    });
    // 焦点真正落到别的可聚焦元素（Tab 走人等）→ 关闭。
    document.addEventListener('focusin', (event) => {
      if (menu.hidden) return;
      const target = event.target;
      if (target instanceof Node && (wrap.contains(target) || menu.contains(target))) return;
      if (target === document.body) return;
      close();
    }, { signal: listeners.signal });
    // 鼠标按下在下拉之外 → 关闭（点空白处、点其它控件）。
    document.addEventListener('mousedown', (event) => {
      if (!wrap.contains(event.target) && !menu.contains(event.target)) close();
    }, { signal: listeners.signal });
    // 滚动/缩放：菜单是 position:fixed，跟随输入框重新定位即可。
    // 注意 scroll 用捕获阶段监听才能收到元素的滚动，但**菜单自身滚动
    // （滚轮 / 拖滚动条）绝不能关菜单**——否则用户还没点中就被关掉。
    window.addEventListener('scroll', (event) => {
      if (menu.hidden) return;
      if (event.target instanceof Node && menu.contains(event.target)) return;
      positionMenu();
    }, { capture: true, signal: listeners.signal });
    window.addEventListener('resize', () => {
      if (menu.hidden) return;
      positionMenu();
    }, { signal: listeners.signal });
    // Esc 关闭。
    document.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape') return;
      if (menu.hidden) return;
      close();
    }, { signal: listeners.signal });

    describe();
    if (highlighted || value) {
      const entity = findEntity(current);
      if (entity && typeof onChange === 'function') onChange(entity);
    }

    return {
      root: wrap,
      input,
      note,
      getValue: () => input.value.trim(),
      getEntity: () => findEntity(input.value.trim()),
      focus: open,
      // 弹窗关闭时把挂在 body 上的菜单节点摘掉，避免残留。
      dispose: () => {
        close();
        listeners.abort();
        menu.remove();
      },
    };
  }

  // ------------------------------------------------------------ ESP 小屏控制

