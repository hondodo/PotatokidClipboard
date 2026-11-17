'use strict';

  function formatBytes(bytes) {
    const n = Number(bytes) || 0;
    if (n < 1024) return `${n} B`;
    if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
    return `${(n / 1024 / 1024).toFixed(2)} MB`;
  }

  function formatDateTime(ms) {
    if (!ms) return '—';
    return new Date(Number(ms)).toLocaleString('zh-CN', { hour12: false });
  }

  function setProgramStatus(message, kind = '') {
    const el = $('programs-status');
    el.textContent = message || '';
    el.className = `program-status ${kind}`;
  }

  function renderProgramsList() {
    const box = $('programs-list');
    if (!state.programs) return;
    const files = state.programs.files || [];
    box.innerHTML = files.map((file) => `
      <button class="program-item${state.programFile && state.programFile.name === file.name ? ' active' : ''}" type="button" data-program-name="${esc(file.name)}">
        <span class="tag ${file.editable ? 'editable' : ''}">${file.editable ? '可编辑' : '只读'}</span>
        ${esc(file.label || file.name)}
        <span class="sub">${esc(file.name)} · ${formatBytes(file.size)} · ${esc(formatDateTime(file.mtime))} · ${file.backups} 个备份</span>
      </button>
    `).join('') || '<div class="empty">没有可展示的文件</div>';
    const updatedAt = state.programs.updatedAt;
    $('programs-version').innerHTML = `版本：<strong>${updatedAt ? esc(formatDateTime(updatedAt)) : '尚未保存'}</strong>`;
  }

  async function loadPrograms() {
    try {
      const data = await api('/api/admin/programs');
      state.programs = data;
      renderProgramsList();
    } catch (error) {
      $('programs-list').innerHTML = `<div class="empty">加载失败：${esc(error.message)}</div>`;
      toast(error.message, 'error');
    }
  }

  async function selectProgram(name, force = false) {
    if (!name) return;
    if (!force && state.programDirty && state.programFile && state.programFile.name !== name) {
      if (!window.confirm('当前文件有未保存修改，确定放弃并切换？')) return;
    }
    setProgramStatus('加载中…');
    try {
      const data = await api(`/api/admin/programs/${encodeURIComponent(name)}`);
      state.programFile = data;
      state.programDirty = false;
      const editable = !!data.editable;
      $('programs-title').textContent = data.label || data.name;
      $('programs-meta').textContent = `${data.name} · ${formatBytes(data.size)} · ${data.lines} 行 · 修改于 ${formatDateTime(data.mtime)} · ${(data.backups || []).length} 个备份${editable ? '' : ' · 只读'}`;
      const editor = $('programs-editor');
      editor.value = data.content || '';
      editor.disabled = !editable;
      $('programs-save').disabled = !editable;
      $('programs-reload').disabled = !editable;
      const backups = data.backups || [];
      $('programs-restore').disabled = !editable || !backups.length;
      const select = $('programs-backups');
      select.innerHTML = backups.length
        ? backups.map((item) => `<option value="${esc(item.timestamp)}">${esc(item.timestamp)} · ${esc(formatBytes(item.size))}</option>`).join('')
        : '<option value="">暂无备份</option>';
      select.disabled = !editable || !backups.length;
      $('programs-warnings').textContent = '';
      setProgramStatus(editable ? '已加载，可直接编辑' : '只读文件，不提供写入口', 'ok');
      renderProgramsList();
    } catch (error) {
      setProgramStatus(`加载失败：${error.message}`, 'error');
      toast(error.message, 'error');
    }
  }

  async function saveProgram() {
    const file = state.programFile;
    if (!file || !file.editable) return;
    const editorValue = $('programs-editor').value;
    if (file.kind === 'hosts' && !editorValue.split('\n').some((line) => {
      const item = line.trim();
      return item && !item.startsWith('#');
    })) {
      if (!window.confirm('白名单为空：保存后所有频道都直连播放，不再经过 relay 中转。确定保存？')) return;
    }
    const btn = $('programs-save');
    btn.disabled = true;
    setProgramStatus('保存中…');
    try {
      const data = await api(`/api/admin/programs/${encodeURIComponent(file.name)}`, {
        method: 'PUT',
        body: JSON.stringify({ content: editorValue, expectedMtime: file.mtime }),
      });
      const warnings = data.warnings || [];
      const warningText = warnings.length ? `提示：${warnings.join('；')}` : '';
      const message = `已保存 · ${formatBytes(data.size)} · 备份 ${data.backup || '—'} · ${data.pushed > 0
        ? `已通知 ${data.pushed} 个在线连接`
        : '当前离线设备下次上线/手动刷新时生效'}`;
      toast('保存成功', 'ok');
      await loadPrograms();
      await selectProgram(file.name, true);
      $('programs-warnings').textContent = warningText;
      setProgramStatus(message, 'ok');
      await loadProgramPreview();
    } catch (error) {
      setProgramStatus(`保存失败：${error.message}`, 'error');
      toast(error.message, 'error');
    } finally {
      btn.disabled = !state.programFile || !state.programFile.editable;
    }
  }

  async function restoreProgram() {
    const file = state.programFile;
    const timestamp = $('programs-backups').value;
    if (!file || !file.editable || !timestamp) {
      toast('请先选择要回退的备份', 'error');
      return;
    }
    if (!window.confirm(`确定把 ${file.name} 回退到 ${timestamp}？当前版本会先自动备份。`)) return;
    setProgramStatus('回退中…');
    try {
      const data = await api(`/api/admin/programs/${encodeURIComponent(file.name)}/restore`, {
        method: 'POST',
        body: JSON.stringify({ timestamp }),
      });
      const message = `已回退到 ${data.restoredFrom} · 当前版本已备份为 ${data.backup || '—'} · ${data.pushed > 0
        ? `已通知 ${data.pushed} 个在线连接`
        : '当前离线设备下次上线/手动刷新时生效'}`;
      toast('回退成功', 'ok');
      await loadPrograms();
      await selectProgram(file.name, true);
      setProgramStatus(message, 'ok');
      await loadProgramPreview();
    } catch (error) {
      setProgramStatus(`回退失败：${error.message}`, 'error');
      toast(error.message, 'error');
    }
  }

  async function loadProgramPreview() {
    const body = $('programs-preview-body');
    body.innerHTML = '<tr><td colspan="4" class="empty">加载中…</td></tr>';
    try {
      const data = await api('/api/admin/programs/preview');
      state.programPreview = data;
      const counts = data.counts || {};
      $('programs-preview-counts').textContent = `最终 ${counts.final || 0} 个频道`;
      const channels = data.channels || [];
      body.innerHTML = channels.slice(0, 1200).map((channel, index) => `
        <tr>
          <td class="muted">${index + 1}</td>
          <td><span class="strong">${esc(channel.name)}</span></td>
          <td class="muted">${esc(channel.group || '—')}</td>
          <td>${channel.sources}</td>
        </tr>
      `).join('') || '<tr><td colspan="4" class="empty">当前规则下没有频道</td></tr>';
      const parts = [
        `接口文件 ${data.remoteFile}`,
        `collect ${counts.collect} + 接口 ${counts.remote} + audio ${counts.audio} = 合并 ${counts.merged}`,
        `隐藏 ${counts.hidden}`,
        `置顶 ${counts.ordered}`,
        `移除频道 ${counts.removedChannels} / 移除源 ${counts.removedSources}`,
        `最终 ${counts.final}`,
      ];
      if (data.truncated || channels.length > 1200) parts.push('列表较长，仅展示前 1200 个');
      $('programs-preview-notes').textContent = parts.join(' · ');
    } catch (error) {
      body.innerHTML = `<tr><td colspan="4" class="empty">预览失败：${esc(error.message)}</td></tr>`;
      $('programs-preview-counts').textContent = '—';
      $('programs-preview-notes').textContent = '';
    }
  }

  async function pushPrograms() {
    const btn = $('programs-push');
    btn.disabled = true;
    setProgramStatus('正在通知设备…');
    try {
      const data = await api('/api/admin/programs/push', { method: 'POST', body: '{}' });
      const message = data.pushed > 0
        ? `已通知 ${data.pushed} 个在线连接重新拉取频道`
        : '当前没有在线设备；设备下次上线或手动刷新频道时生效';
      setProgramStatus(message, 'ok');
      toast(message, 'ok');
    } catch (error) {
      setProgramStatus(`通知失败：${error.message}`, 'error');
      toast(error.message, 'error');
    } finally {
      btn.disabled = false;
    }
  }

  $('programs-list').addEventListener('click', (event) => {
    const item = event.target.closest('[data-program-name]');
    if (item) selectProgram(item.dataset.programName);
  });
  $('programs-refresh').addEventListener('click', () => {
    loadPrograms();
    loadProgramPreview();
  });
  $('programs-preview-refresh').addEventListener('click', loadProgramPreview);
  $('programs-push').addEventListener('click', pushPrograms);
  $('programs-save').addEventListener('click', saveProgram);
  $('programs-restore').addEventListener('click', restoreProgram);
  $('programs-reload').addEventListener('click', () => {
    if (!state.programFile) return;
    if (state.programDirty && !window.confirm('放弃未保存修改并重新加载？')) return;
    selectProgram(state.programFile.name, true);
  });
  $('programs-editor').addEventListener('input', () => {
    state.programDirty = true;
    setProgramStatus('有未保存修改');
  });

  // ------------------------------------------------------------ HA 实体库事件

  $('ha-entities-refresh').addEventListener('click', () => loadHaEntities(true));
  $('ha-entities-search').addEventListener('input', (event) => {
    state.haFilter.keyword = event.target.value || '';
    renderHaEntities();
  });
  $('ha-entities-only-free').addEventListener('change', (event) => {
    state.haFilter.onlyFree = event.target.checked === true;
    renderHaEntities();
  });
  $('ha-entities-only-actionable').addEventListener('change', (event) => {
    state.haFilter.onlyActionable = event.target.checked === true;
    renderHaEntities();
  });

  // ------------------------------------------------------------ 设备类型字典（全局真源）

