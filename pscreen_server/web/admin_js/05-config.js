'use strict';

  const ESP_ACTION_LABELS = [
    ['toggle', '切换'],
    ['turn_on', '开'],
    ['turn_off', '关'],
    ['run', '执行（script/scene）'],
  ];

  // 系统动作：不调用 HA，服务端只回执给设备做本地切换（分页）。
  const ESP_SYS_ACTION_LABELS = [
    ['next_page', '下一页'],
    ['prev_page', '上一页'],
    ['home_page', '回首页'],
  ];
  const ESP_SYS_VALUES = new Set(ESP_SYS_ACTION_LABELS.map(([value]) => value));

  function editHaConfig() {
    const wrap = document.createElement('div');
    wrap.style.display = 'grid';
    wrap.style.gap = '12px';

    const baseLabel = document.createElement('label');
    baseLabel.textContent = 'Home Assistant 地址';
    const baseInput = document.createElement('input');
    baseInput.placeholder = 'http://192.168.1.10:8123';
    baseInput.maxLength = 200;
    baseLabel.appendChild(baseInput);

    const tokenLabel = document.createElement('label');
    tokenLabel.textContent = '长期访问令牌';
    const tokenInput = document.createElement('input');
    tokenInput.type = 'password';
    tokenInput.placeholder = '已设置则留空表示不修改';
    tokenLabel.appendChild(tokenInput);

    const clearLabel = document.createElement('label');
    clearLabel.className = 'inline-check';
    const clearBox = document.createElement('input');
    clearBox.type = 'checkbox';
    clearLabel.appendChild(clearBox);
    clearLabel.appendChild(document.createTextNode('清除已保存的令牌'));

    const note = document.createElement('p');
    note.className = 'field-note';
    note.textContent = '令牌在 HA「用户资料 → 长期访问令牌」里创建。设备按键时由服务端代为调用 HA，令牌不会下发到 ESP。';

    wrap.append(baseLabel, tokenLabel, clearLabel, note);

    api('/api/admin/ha').then((data) => {
      if (!data) return;
      baseInput.value = data.baseUrl || '';
      // 令牌不回显：已保存时用 placeholder 提示，避免误以为被清空
      tokenInput.placeholder = data.hasToken ? '已保存，留空表示不修改' : '粘贴长期访问令牌';
      note.textContent = data.configured
        ? '当前已配置完整，可直接保存。令牌不会下发到 ESP。'
        : `尚未配置完整：地址${data.baseUrl ? '已填' : '为空'}、令牌${data.hasToken ? '已填' : '为空'}。设备按键会失败。`;
    }).catch(() => {});

    openDialog({
      title: 'HA 连接',
      content: wrap,
      onSave: () => api('/api/admin/ha', {
        method: 'PUT',
        body: JSON.stringify({
          baseUrl: baseInput.value.trim(),
          token: tokenInput.value.trim(),
          clearToken: clearBox.checked,
        }),
      }),
    });
  }

  document.getElementById('ha-config-btn').addEventListener('click', editHaConfig);

  // ------------------------------------------------------------ ESP 固件升级（OTA）

  /**
   * 上传编译产物 .bin 并发布版本号。
   *
   * 设备每次心跳会比对这里发布的版本；不一致就在屏幕提示，用户在设备本地
   * 设置页点「立即升级」。上传接口是 multipart，不能复用 api()。
   */
  function editFirmware() {
    const wrap = document.createElement('div');
    wrap.style.display = 'grid';
    wrap.style.gap = '12px';

    const status = document.createElement('div');
    status.className = 'field-note';
    status.textContent = '读取当前发布版本…';

    const fileLabel = document.createElement('label');
    fileLabel.textContent = '固件文件（.bin，应用分区镜像）';
    const fileInput = document.createElement('input');
    fileInput.type = 'file';
    fileInput.accept = '.bin';
    fileLabel.appendChild(fileInput);

    const versionLabel = document.createElement('label');
    versionLabel.textContent = '版本号（需与固件内 APP_VER 一致才不会再提示）';
    const versionInput = document.createElement('input');
    versionInput.placeholder = 'oled-1.3';
    versionInput.maxLength = 32;
    versionLabel.appendChild(versionInput);

    const notesLabel = document.createElement('label');
    notesLabel.textContent = '更新说明（可选，显示在设备设置页）';
    const notesInput = document.createElement('input');
    notesInput.maxLength = 200;
    notesInput.placeholder = '例如：修复按键无响应';
    notesLabel.appendChild(notesInput);

    const revoke = document.createElement('button');
    revoke.className = 'btn small danger';
    revoke.type = 'button';
    revoke.textContent = '撤回发布';
    revoke.addEventListener('click', async () => {
      if (!confirm('撤回后设备不再提示更新，确定？')) return;
      try {
        await api('/api/admin/firmware', { method: 'DELETE' });
        status.textContent = '当前没有已发布的固件';
        toast('已撤回', 'ok');
      } catch (error) {
        toast(error.message, 'error');
      }
    });

    wrap.append(status, fileLabel, versionLabel, notesLabel, revoke);

    api('/api/admin/firmware').then((data) => {
      if (!data || !data.published) {
        status.textContent = '当前没有已发布的固件。选择 .bin 并填写版本号后上传即可。';
        return;
      }
      status.textContent = `当前发布：v${data.version} · ${(data.size / 1024).toFixed(0)}KB · sha256 ${String(data.sha256 || '').slice(0, 12)}…${data.notes ? ` · ${data.notes}` : ''}`;
      versionInput.value = data.version || '';
    }).catch(() => { status.textContent = '读取发布状态失败'; });

    openDialog({
      title: 'ESP 固件升级',
      content: wrap,
      saveLabel: '上传并发布',
      onSave: async () => {
        const file = fileInput.files && fileInput.files[0];
        if (!file) throw new Error('请选择 .bin 文件');
        const version = versionInput.value.trim();
        if (!version) throw new Error('请填写版本号');
        const form = new FormData();
        form.append('version', version);
        form.append('notes', notesInput.value.trim());
        form.append('file', file);
        const res = await fetch('/api/admin/firmware', {
          method: 'POST',
          credentials: 'same-origin',
          body: form,
        });
        const data = await res.json().catch(() => null);
        if (!res.ok || !data || data.code !== 0) {
          throw new Error((data && data.msg) || `上传失败（HTTP ${res.status}）`);
        }
      },
    });
  }

  document.getElementById('firmware-btn').addEventListener('click', editFirmware);

  // ------------------------------------------------------------ 儿童模式（阶段 3）

  // 禁看时段条目格式（与服务端 normalizeParental / Flutter 端 QuietHour.tryParse 同口径）。
