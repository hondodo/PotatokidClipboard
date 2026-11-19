'use strict';

  /**
   * 按钮忙态：改文案 + 转圈 + 禁用，返回 restore()。
   *
   * 只写 btn.disabled = true 是不够的——.btn 没有 :disabled 的视觉差异，点击被
   * 拦下了但外观一点没变（连 hover 高亮都在），用户会以为鼠标失灵反复点。
   */
  function setBtnBusy(btn, busyText = '处理中…') {
    if (!btn) return () => {};
    const idleText = btn.textContent;
    btn.classList.add('is-busy');
    btn.setAttribute('aria-busy', 'true');
    btn.textContent = busyText;
    btn.disabled = true;
    return () => {
      btn.classList.remove('is-busy');
      btn.removeAttribute('aria-busy');
      btn.textContent = idleText;
      btn.disabled = false;
    };
  }

  // 忙态延迟出现：请求在 120ms 内回来时不要闪一下「保存中」。
  const BUSY_DELAY_MS = 120;
  // 超过这个时间说明不是本机局域网那种快请求，补一句解释，免得用户以为卡死。
  const BUSY_SLOW_MS = 1800;

  function openDialog({ title, content, onSave, saveLabel = '保存', wide = false }) {
    const root = $('dialog-root');
    root.innerHTML = `
      <div class="overlay">
        <div class="card dialog${wide ? ' wide' : ''}" role="dialog" aria-modal="true">
          <div class="dialog-head">
            <h3>${esc(title)}</h3>
            <button class="icon-btn" type="button" data-close>×</button>
          </div>
          <div class="dialog-body"></div>
          <div class="dialog-busy" hidden><i></i><span>正在保存，请不要重复点击…</span></div>
          <div class="dialog-foot">
            <button class="btn" type="button" data-close>取消</button>
            <button class="btn primary" type="button" data-save>${esc(saveLabel)}</button>
          </div>
        </div>
      </div>`;
    const overlay = root.querySelector('.overlay');
    const body = root.querySelector('.dialog-body');
    const saveBtn = root.querySelector('[data-save]');
    const closeBtns = Array.from(root.querySelectorAll('[data-close]'));
    const busyEl = root.querySelector('.dialog-busy');
    const busyTextEl = busyEl.querySelector('span');
    body.appendChild(content);
    // 实体选择器的下拉菜单挂在 body 上（避免被 dialog-body 的 overflow 裁掉），
    // 关闭弹窗时要一并摘掉，否则会残留一个浮层。
    const close = () => {
      root.innerHTML = '';
      document.querySelectorAll('.entity-picker-menu').forEach((menu) => menu.remove());
    };
    let saving = false;
    // 请求长时间不回时的逃生阀门：超时后放开关闭，否则「保存中禁用关闭」会把弹窗锁死。
    let stalled = false;
    // 保存中锁住关闭：请求已发出但弹窗先关掉，用户会以为没保存成功，回头再建一条重复的。
    const lockClose = (locked) => {
      closeBtns.forEach((btn) => { btn.disabled = locked; });
      overlay.classList.toggle('is-busy', locked);
    };
    const tryClose = () => {
      if (saving && !stalled) return;
      if (stalled) toast('已放弃等待，请点「重新加载」确认是否保存成功', 'error');
      close();
    };
    closeBtns.forEach((btn) => btn.addEventListener('click', tryClose));
    overlay.addEventListener('click', (event) => {
      if (event.target === overlay) tryClose();
    });

    saveBtn.addEventListener('click', async () => {
      if (saving) return;
      saving = true;
      let restore = () => {};
      let shown = false;
      const showTimer = setTimeout(() => {
        shown = true;
        restore = setBtnBusy(saveBtn, '保存中…');
        busyEl.hidden = false;
        lockClose(true);
      }, BUSY_DELAY_MS);
      const slowTimer = setTimeout(() => {
        busyTextEl.textContent = '网络较慢，仍在保存…';
        if (shown) saveBtn.textContent = '仍在保存…';
      }, BUSY_SLOW_MS);
      const stallTimer = setTimeout(() => {
        stalled = true;
        busyTextEl.textContent = '已等待 20 秒仍未返回，可点「取消」放弃等待';
        lockClose(false);
      }, 20000);
      try {
        await onSave();
        restore();
        close();
        toast('已保存', 'ok');
        // 列表刷新不阻塞弹窗关闭：这一跳可能要代取 HA 实体目录（上千条），
        // 等它会让「点保存」到「弹窗消失」之间空出好几秒，正是「以为鼠标坏了」的来源。
        loadOverview(false);
      } catch (error) {
        restore();
        busyEl.hidden = true;
        lockClose(false);
        toast(error.message, 'error');
      } finally {
        clearTimeout(showTimer);
        clearTimeout(slowTimer);
        clearTimeout(stallTimer);
        saving = false;
      }
    });
  }

  function editHomes({ title, homes, onSave, level = 'machine' }) {
    const known = Array.from(new Set([
      ...(state.overview.homes || []),
      ...(Array.isArray(homes) ? homes : []),
    ])).sort((a, b) => a.localeCompare(b, 'zh-CN'));

    const mode = homes === null || homes === undefined ? 'inherit' : (homes.length === 0 ? 'all' : 'custom');
    const wrap = document.createElement('div');
    wrap.style.display = 'grid';
    wrap.style.gap = '14px';

    const modes = document.createElement('div');
    modes.className = 'radio-row';
    // 「跟随…」的名称与描述按入口区分：设备层的下一层是所属用户，用户层的下一层是 App 的 .env。
    const inheritLabel = level === 'user' ? '跟随.env' : '跟随绑定用户/.env';
    const inheritNote = level === 'user'
      ? '以App的.env的HONE_MANE为准'
      : '表示本层不限制，如果绑定了用户，且在用户里设置指定家庭则以用户设置为准，否则以App的.env的HONE_MANE为准';
    // 用户页选「全部/指定家庭」时提示：设备单独设置会覆盖本页。
    const deviceOverrideNote = '注意：若某台设备在设备状态页单独设置了可见家庭，则本页设置对该设备不生效';
    const notes = {
      inherit: inheritNote,
      all: level === 'user' ? deviceOverrideNote : '',
      custom: level === 'user' ? deviceOverrideNote : '',
    };
    const modeDefs = [
      ['inherit', inheritLabel],
      ['all', '全部家庭'],
      ['custom', '指定家庭'],
    ];
    modeDefs.forEach(([value, label]) => {
      const chip = document.createElement('label');
      chip.className = `radio-chip ${mode === value ? 'active' : ''}`;
      chip.innerHTML = `<input type="radio" name="home-mode" value="${value}" ${mode === value ? 'checked' : ''}>${esc(label)}`;
      modes.appendChild(chip);
    });
    wrap.appendChild(modes);

    const custom = document.createElement('div');
    custom.style.display = 'grid';
    custom.style.gap = '9px';
    custom.hidden = mode !== 'custom';
    const grid = document.createElement('div');
    grid.className = 'check-grid';
    const selected = new Set(Array.isArray(homes) ? homes : []);
    if (known.length) {
      known.forEach((home) => {
        const item = document.createElement('label');
        item.className = 'check-item';
        item.innerHTML = `<input type="checkbox" value="${esc(home)}" ${selected.has(home) ? 'checked' : ''}><span>${esc(home)}</span>`;
        grid.appendChild(item);
      });
    } else {
      const empty = document.createElement('p');
      empty.className = 'field-note';
      empty.textContent = '还没有上报过家庭名，可在下方手动输入。';
      grid.appendChild(empty);
    }
    custom.appendChild(grid);

    const extraLabel = document.createElement('label');
    extraLabel.textContent = '其他家庭（英文逗号分隔）';
    const extraInput = document.createElement('input');
    extraInput.placeholder = '例如：棠德304, 金科1204';
    extraInput.value = Array.from(selected).filter((home) => !known.includes(home)).join(', ');
    extraLabel.appendChild(extraInput);
    custom.appendChild(extraLabel);
    wrap.appendChild(custom);

    // 提示随选中项切换：跟随→回落说明；用户页的全部/指定→设备覆盖提醒。
    const note = document.createElement('p');
    note.className = 'field-note';
    const syncNote = (value) => {
      const text = notes[value] || '';
      note.textContent = text;
      note.hidden = !text;
    };
    syncNote(mode);
    wrap.appendChild(note);

    wrap.querySelectorAll('input[name="home-mode"]').forEach((input) => {
      input.addEventListener('change', () => {
        wrap.querySelectorAll('.radio-chip').forEach((chip) => {
          chip.classList.toggle('active', chip.querySelector('input').checked);
        });
        const checked = wrap.querySelector('input[name="home-mode"]:checked').value;
        custom.hidden = checked !== 'custom';
        syncNote(checked);
      });
    });

    openDialog({
      title,
      content: wrap,
      onSave: () => {
        const selectedMode = wrap.querySelector('input[name="home-mode"]:checked').value;
        if (selectedMode === 'inherit') return onSave(null);
        if (selectedMode === 'all') return onSave([]);
        const values = new Set();
        grid.querySelectorAll('input[type="checkbox"]').forEach((input) => {
          if (input.checked) values.add(input.value.trim());
        });
        extraInput.value.split(/[,，]/).map((item) => item.trim()).filter(Boolean).forEach((item) => values.add(item));
        if (!values.size) throw new Error('请至少选择一个家庭，或选择「跟随上层 / .env」');
        return onSave(Array.from(values));
      },
    });
  }

  function editMachineName(machine) {
    const wrap = document.createElement('div');
    const label = document.createElement('label');
    label.textContent = '设备备注名';
    const input = document.createElement('input');
    input.value = machine.nameSet ? machine.name : '';
    input.placeholder = machine.nameSet ? '' : '未设置（留空则回落账号 id）';
    input.maxLength = 40;
    label.appendChild(input);
    wrap.appendChild(label);
    const note = document.createElement('p');
    note.className = 'field-note';
    note.textContent = `名称生效顺序：设备备注 > 账号展示名 > 账号 id。设备 ID：${machine.id}（Android ID，重装 App 不变）`;
    wrap.appendChild(note);
    openDialog({
      title: '修改设备备注名',
      content: wrap,
      onSave: () => api(`/api/admin/machines/${encodeURIComponent(machine.id)}`, {
        method: 'PUT',
        body: JSON.stringify({ name: input.value.trim() }),
      }),
    });
  }

  function editDisplayName(user) {
    const wrap = document.createElement('div');
    const label = document.createElement('label');
    label.textContent = '账号展示名（displayName）';
    const input = document.createElement('input');
    // 未设置时留空（不要预填账号 id，否则「清空」会变成把 id 写进 displayName）。
    input.value = user.displayNameSet ? user.displayName : '';
    input.placeholder = `留空则回落账号 id（${user.name}）`;
    input.maxLength = 40;
    label.appendChild(input);
    wrap.appendChild(label);
    openDialog({
      title: '修改用户显示名',
      content: wrap,
      onSave: () => api(`/api/admin/users/${encodeURIComponent(user.name)}`, {
        method: 'PUT',
        body: JSON.stringify({ displayName: input.value.trim() }),
      }),
    });
  }

  // ------------------------------------------------------------ HA 实体库

  /**
   * 实体目录（家 → 房间 → 实体）。
   *
   * 服务端代取 HA 数据（令牌不下发到浏览器），60 秒缓存；这里只做筛选与渲染。
   */
