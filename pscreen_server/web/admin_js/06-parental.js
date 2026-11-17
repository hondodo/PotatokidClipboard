'use strict';

  const QUIET_HOURS_RE = /^(?:[01]\d|2[0-3]):[0-5]\d-(?:[01]\d|2[0-3]):[0-5]\d$/;

  /** 逗号/换行分隔的名单文本 → 数组（服务端仍会再校验一遍）。 */
  function splitList(text) {
    return String(text || '').split(/[,，\n]/).map((item) => item.trim()).filter(Boolean);
  }

  function newChildId() {
    return `c${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
  }

  /** 单选 chip 组的选中态高亮（radio-row 内 radio-chip）。 */
  function bindRadioChips(row) {
    row.querySelectorAll('input[type="radio"]').forEach((input) => {
      input.addEventListener('change', () => {
        row.querySelectorAll('.radio-chip').forEach((chip) => {
          chip.classList.toggle('active', chip.querySelector('input').checked);
        });
      });
    });
  }

  function chipRow(name, options, activeValue) {
    const row = document.createElement('div');
    row.className = 'radio-row';
    options.forEach(([value, label]) => {
      const chip = document.createElement('label');
      chip.className = `radio-chip ${activeValue === value ? 'active' : ''}`;
      chip.innerHTML = `<input type="radio" name="${esc(name)}" value="${esc(value)}" ${activeValue === value ? 'checked' : ''}>${esc(label)}`;
      row.appendChild(chip);
    });
    return row;
  }

  function fieldInput({ field, value = '', type = 'text', placeholder = '', min, max }) {
    const input = document.createElement('input');
    input.dataset.field = field;
    input.type = type;
    if (placeholder) input.placeholder = placeholder;
    if (min !== undefined) input.min = String(min);
    if (max !== undefined) input.max = String(max);
    input.value = value === undefined || value === null ? '' : String(value);
    return input;
  }

  /** 档案卡片标题按顺序重编号（增删后调用）。 */
  function syncChildTitles(box) {
    box.querySelectorAll('.child-card').forEach((card, index) => {
      card.querySelector('.child-head strong').textContent = `档案 ${index + 1}`;
    });
  }

  /**
   * 单个儿童档案编辑卡片。
   * 按档位显隐（方案 §2.2 两档语义）：温和档显 hideGroups/hideChannels 黑名单，
   * 严格档显 allowGroups/allowChannels 白名单——另一侧字段不渲染，杜绝
   * 「家长填了不生效的字段」；切换档位时未渲染一侧的值不保留。
   */
  function childCard(child) {
    const card = document.createElement('div');
    card.className = 'child-card';
    card.dataset.childId = child.id || newChildId();

    const head = document.createElement('div');
    head.className = 'child-head';
    const title = document.createElement('strong');
    title.textContent = '档案';
    const del = document.createElement('button');
    del.type = 'button';
    del.className = 'btn small danger';
    del.textContent = '删除';
    head.appendChild(title);
    head.appendChild(del);
    card.appendChild(head);

    const base = document.createElement('div');
    base.className = 'field-row';
    const nameLabel = document.createElement('label');
    nameLabel.textContent = '名称';
    nameLabel.appendChild(fieldInput({ field: 'name', value: child.name, placeholder: '例如：小宝' }));
    const ageLabel = document.createElement('label');
    ageLabel.textContent = '年龄（可留空）';
    ageLabel.appendChild(fieldInput({ field: 'age', value: child.age, type: 'number', placeholder: '0~150', min: 0, max: 150 }));
    base.appendChild(nameLabel);
    base.appendChild(ageLabel);
    card.appendChild(base);

    const mode = child.profileMode === 'strict' ? 'strict' : 'mild';
    const modeRow = chipRow(`child-mode-${card.dataset.childId}`, [
      ['mild', '温和档 · 黑名单'],
      ['strict', '严格档 · 白名单'],
    ], mode);
    card.appendChild(modeRow);

    const limits = document.createElement('div');
    limits.className = 'field-row';
    const sessionLabel = document.createElement('label');
    sessionLabel.textContent = '单次限额（分钟，0 = 不限）';
    sessionLabel.appendChild(fieldInput({ field: 'session', value: child.sessionLimitMin || '', type: 'number', min: 0 }));
    const dailyLabel = document.createElement('label');
    dailyLabel.textContent = '当日限额（分钟，0 = 不限）';
    dailyLabel.appendChild(fieldInput({ field: 'daily', value: child.dailyLimitMin || '', type: 'number', min: 0 }));
    limits.appendChild(sessionLabel);
    limits.appendChild(dailyLabel);
    card.appendChild(limits);

    const quietLabel = document.createElement('label');
    quietLabel.textContent = '禁看时段（HH:MM-HH:MM，逗号分隔多段，支持跨午夜如 22:00-06:00）';
    quietLabel.appendChild(fieldInput({
      field: 'quiet',
      value: (Array.isArray(child.quietHours) ? child.quietHours : []).join(', '),
      placeholder: '例如：22:00-06:00, 08:00-12:00',
    }));
    card.appendChild(quietLabel);

    // 名单区：两档字段各自独立块，按档位显隐（未选中一侧不渲染值）。
    const listsBox = document.createElement('div');
    listsBox.style.display = 'grid';
    listsBox.style.gap = '10px';
    const mildBlock = document.createElement('div');
    mildBlock.style.display = 'grid';
    mildBlock.style.gap = '10px';
    mildBlock.hidden = mode !== 'mild';
    const hideGroupsLabel = document.createElement('label');
    hideGroupsLabel.textContent = '隐藏分组（分组黑名单，逗号分隔，m3u group-title 原文）';
    hideGroupsLabel.appendChild(fieldInput({ field: 'hideGroups', value: (child.hideGroups || []).join(', '), placeholder: '例如：📺购物频道' }));
    const hideChannelsLabel = document.createElement('label');
    hideChannelsLabel.textContent = '隐藏频道（频道名黑名单，支持 * 通配，如 *购物*）';
    hideChannelsLabel.appendChild(fieldInput({ field: 'hideChannels', value: (child.hideChannels || []).join(', '), placeholder: '例如：*购物*, *彩票*' }));
    mildBlock.appendChild(hideGroupsLabel);
    mildBlock.appendChild(hideChannelsLabel);

    const strictBlock = document.createElement('div');
    strictBlock.style.display = 'grid';
    strictBlock.style.gap = '10px';
    strictBlock.hidden = mode !== 'strict';
    const allowGroupsLabel = document.createElement('label');
    allowGroupsLabel.textContent = '允许分组（分组白名单，必填至少一项，逗号分隔）';
    allowGroupsLabel.appendChild(fieldInput({ field: 'allowGroups', value: (child.allowGroups || []).join(', '), placeholder: '例如：📺少儿频道, 📺动画频道' }));
    const allowChannelsLabel = document.createElement('label');
    allowChannelsLabel.textContent = '允许频道（频道名白名单，支持 * 通配，可留空 = 不限制）';
    allowChannelsLabel.appendChild(fieldInput({ field: 'allowChannels', value: (child.allowChannels || []).join(', '), placeholder: '例如：*少儿*' }));
    strictBlock.appendChild(allowGroupsLabel);
    strictBlock.appendChild(allowChannelsLabel);

    listsBox.appendChild(mildBlock);
    listsBox.appendChild(strictBlock);
    card.appendChild(listsBox);

    modeRow.querySelectorAll('input[type="radio"]').forEach((input) => {
      input.addEventListener('change', () => {
        modeRow.querySelectorAll('.radio-chip').forEach((chip) => {
          chip.classList.toggle('active', chip.querySelector('input').checked);
        });
        const value = modeRow.querySelector('input[type="radio"]:checked').value;
        mildBlock.hidden = value !== 'mild';
        strictBlock.hidden = value !== 'strict';
      });
    });

    const lockedLabel = document.createElement('label');
    lockedLabel.className = 'inline-check';
    lockedLabel.innerHTML = `<input type="checkbox" data-field="locked" ${child.locked === true ? 'checked' : ''}>受验证保护（电视上勾选该档案时需家长验证）`;
    card.appendChild(lockedLabel);

    del.addEventListener('click', () => {
      card.remove();
      syncChildTitles(card.parentElement);
    });
    return card;
  }

  /**
   * 儿童模式配置编辑（阶段 3）：全局开关 + 解锁方式/PIN/家长账号 +
   * 儿童档案增删改，按档案档位显隐黑名单/白名单字段。
   * 保存走 `PUT /api/admin/machines/:id` 的 parental 分支（服务端整体校验）。
   */
  function editParental(machine) {
    const current = machine.parental && typeof machine.parental === 'object' ? machine.parental : null;
    const wrap = document.createElement('div');
    wrap.style.display = 'grid';
    wrap.style.gap = '14px';

    const pushNote = document.createElement('p');
    pushNote.className = 'field-note';
    pushNote.textContent = '保存后立即推送给在线电视；离线电视下次连接生效。生效条件：开关为「开启」且至少一个档案。';
    wrap.appendChild(pushNote);

    // —— 全局开关 ——
    const modeRow = chipRow('pmode', [['off', '关闭'], ['on', '开启']], current && current.mode === 'on' ? 'on' : 'off');
    wrap.appendChild(modeRow);
    bindRadioChips(modeRow);

    // —— 解锁方式 ——
    const unlock = current && ['remote', 'pin', 'arith', 'quiz'].indexOf(current.unlockMode) >= 0 ? current.unlockMode : 'remote';
    const unlockRow = chipRow('unlock-mode', [
      ['remote', '远程确认'],
      ['pin', 'PIN'],
      ['arith', '算术题'],
      ['quiz', '答题解锁'],
    ], unlock);
    wrap.appendChild(unlockRow);
    bindRadioChips(unlockRow);
    const quizNote = document.createElement('p');
    quizNote.className = 'field-note';
    quizNote.textContent = '答题解锁：只能通过儿童题库答题解锁，题库请在 App「家长视图 → 档案 → 题库」中维护；题库为空时电视端回退算术题。';
    quizNote.hidden = unlock !== 'quiz';
    wrap.appendChild(quizNote);

    const pinLabel = document.createElement('label');
    pinLabel.textContent = 'PIN（仅「PIN 解锁」时使用）';
    pinLabel.appendChild(fieldInput({ field: 'pin', value: current ? current.pin : '', placeholder: '例如：1234' }));
    pinLabel.hidden = unlock !== 'pin';
    wrap.appendChild(pinLabel);
    unlockRow.addEventListener('change', () => {
      const next = unlockRow.querySelector('input[type="radio"]:checked').value;
      pinLabel.hidden = next !== 'pin';
      quizNote.hidden = next !== 'quiz';
    });

    const ownerLabel = document.createElement('label');
    ownerLabel.textContent = '家长账号 ownerAccount（解锁请求投递目标，可留空）';
    ownerLabel.appendChild(fieldInput({ field: 'ownerAccount', value: current ? current.ownerAccount : '', placeholder: '1000001' }));
    wrap.appendChild(ownerLabel);
    const ownerNote = document.createElement('p');
    ownerNote.className = 'field-note';
    ownerNote.textContent = '留空时回落该设备所属用户，再缺省 1000001（admin 账号）。家长账号需为「家长」角色才能收到解锁请求。';
    wrap.appendChild(ownerNote);

    // —— 儿童档案列表 ——
    const section = document.createElement('p');
    section.className = 'section-title';
    section.textContent = '儿童档案';
    wrap.appendChild(section);

    const box = document.createElement('div');
    box.style.display = 'grid';
    box.style.gap = '10px';
    const children = current && Array.isArray(current.children) ? current.children : [];
    children.forEach((child) => box.appendChild(childCard(child || {})));
    syncChildTitles(box);
    wrap.appendChild(box);

    const addBtn = document.createElement('button');
    addBtn.type = 'button';
    addBtn.className = 'btn small';
    addBtn.textContent = '+ 添加档案';
    addBtn.addEventListener('click', () => {
      box.appendChild(childCard({}));
      syncChildTitles(box);
    });
    wrap.appendChild(addBtn);

    const listNote = document.createElement('p');
    listNote.className = 'field-note';
    listNote.textContent = '暂无分组/频道上报数据，名单请直接输入文本（分组填 m3u group-title 原文，频道支持 * 通配）。多值用逗号分隔；填错的白名单会被电视端防黑屏保护忽略。';
    wrap.appendChild(listNote);

    openDialog({
      title: `儿童模式 · ${machine.name}`,
      content: wrap,
      onSave: () => {
        const globalMode = wrap.querySelector('input[name="pmode"]:checked').value;
        const unlockMode = wrap.querySelector('input[name="unlock-mode"]:checked').value;
        const pin = wrap.querySelector('[data-field="pin"]').value.trim();
        if (globalMode === 'on' && unlockMode === 'pin' && !pin) {
          throw new Error('选择「PIN 解锁」时必须设置 PIN');
        }
        const cards = box.querySelectorAll('.child-card');
        if (globalMode === 'on' && !cards.length) {
          throw new Error('开启儿童模式至少需要一个儿童档案');
        }
        const nextChildren = [];
        const ids = new Set();
        const readNum = (card, field, label) => {
          const text = card.querySelector(`[data-field="${field}"]`).value.trim();
          if (text === '') return 0;
          const value = Number(text);
          if (!Number.isInteger(value) || value < 0) throw new Error(`${label}必须是非负整数`);
          return value;
        };
        cards.forEach((card) => {
          const name = card.querySelector('[data-field="name"]').value.trim();
          if (!name) throw new Error(`档案 ${nextChildren.length + 1}：名称不能为空`);
          const ageText = card.querySelector('[data-field="age"]').value.trim();
          let age;
          if (ageText !== '') {
            age = Number(ageText);
            if (!Number.isInteger(age) || age < 0 || age > 150) {
              throw new Error(`档案「${name}」：年龄必须是 0~150 的整数`);
            }
          }
          const profileMode = card.querySelector(`input[name="child-mode-${card.dataset.childId}"]:checked`).value;
          const quietHours = splitList(card.querySelector('[data-field="quiet"]').value);
          quietHours.forEach((entry) => {
            if (!QUIET_HOURS_RE.test(entry)) {
              throw new Error(`档案「${name}」：禁看时段格式应为 HH:MM-HH:MM：${entry}`);
            }
            if (entry.slice(0, 5) === entry.slice(6, 11)) {
              throw new Error(`档案「${name}」：禁看时段起止时间不能相同：${entry}`);
            }
          });
          // 表单只覆盖自己展示的字段；其余（sharedTo / 头像 / 档位外名单等）
          // 原样保留，避免整份覆盖把授权名单或属性清空。
          const origin = children.find((item) => item && item.id === card.dataset.childId) || {};
          const child = {
            ...origin,
            id: card.dataset.childId,
            name,
            profileMode,
            locked: card.querySelector('[data-field="locked"]').checked,
            sessionLimitMin: readNum(card, 'session', `档案「${name}」的单次限额`),
            dailyLimitMin: readNum(card, 'daily', `档案「${name}」的当日限额`),
            quietHours,
          };
          if (age !== undefined) child.age = age;
          if (profileMode === 'strict') {
            const allowGroups = splitList(card.querySelector('[data-field="allowGroups"]').value);
            if (!allowGroups.length) {
              throw new Error(`严格档档案「${name}」必须至少填写一个允许分组（否则白名单等于没生效）`);
            }
            child.allowGroups = allowGroups;
            child.allowChannels = splitList(card.querySelector('[data-field="allowChannels"]').value);
            delete child.hideGroups;
            delete child.hideChannels;
          } else {
            child.hideGroups = splitList(card.querySelector('[data-field="hideGroups"]').value);
            child.hideChannels = splitList(card.querySelector('[data-field="hideChannels"]').value);
            delete child.allowGroups;
            delete child.allowChannels;
          }
          if (ids.has(child.id)) throw new Error('档案 id 冲突，请删除后重新添加');
          ids.add(child.id);
          nextChildren.push(child);
        });
        // activeChildIds 后台不直接编辑：保留原值并过滤掉已删除档案（悬空 id 由电视端再兜底）。
        const keptActive = current && Array.isArray(current.activeChildIds)
          ? current.activeChildIds.filter((id) => ids.has(id))
          : [];
        const parental = {
          mode: globalMode,
          activeChildIds: keptActive,
          children: nextChildren,
          unlockMode,
          pin,
          ownerAccount: wrap.querySelector('[data-field="ownerAccount"]').value.trim(),
        };
        // 家庭级模型迁移前，旧模型的跨电视引用数组必须原样保留，不能被整份表单覆盖清空。
        if (current && Array.isArray(current.shared) && current.shared.length) {
          parental.shared = current.shared;
        }
        return api(`/api/admin/machines/${encodeURIComponent(machine.id)}`, {
          method: 'PUT',
          body: JSON.stringify({ parental }),
        });
      },
    });
  }

  // ------------------------------------------------------------ 布局

