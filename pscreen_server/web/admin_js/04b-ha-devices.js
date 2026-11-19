'use strict';

  // 「HA 设备」页：按 device_id 聚合的设备清单 + 是否显示到中控屏开关。
  // 数据与 HA 实体库共用同一份 catalog（服务端单独接口，但复用缓存）。

  let haDevicesLoading = false;

  async function loadHaDevices(force = false) {
    if (haDevicesLoading) return;
    haDevicesLoading = true;
    const meta = $('ha-devices-meta');
    if (meta) meta.textContent = '加载中…';
    try {
      const data = await api(`/api/admin/ha/devices${force ? '?refresh=1' : ''}`);
      state.haDevices = data.devices || [];
      state.haDevicesTime = data.updatedAt;
      renderHaDevices();
    } catch (error) {
      if (meta) meta.textContent = '加载失败';
      const body = $('ha-devices-body');
      if (body) body.innerHTML = `<tr><td colspan="8" class="empty">${esc(error.message)}</td></tr>`;
      toast(error.message, 'error');
    } finally {
      haDevicesLoading = false;
    }
  }

  function filteredHaDevices() {
    const list = state.haDevices || [];
    const keyword = (($('ha-devices-search') || {}).value || '').trim().toLowerCase();
    const onlyVisible = !!($('ha-devices-only-visible') && $('ha-devices-only-visible').checked);
    return list.filter((d) => {
      if (onlyVisible && d.visible !== true) return false;
      if (!keyword) return true;
      const hay = [d.name, d.model, d.manufacturer, d.integration, d.areaName]
        .map((v) => String(v || '').toLowerCase()).join(' ');
      return hay.indexOf(keyword) >= 0;
    });
  }

  function renderHaDevices() {
    const body = $('ha-devices-body');
    if (!body) return;
    const all = state.haDevices || [];
    const rows = filteredHaDevices();
    const shown = rows.filter((d) => d.visible !== false).length;
    const configured = all.filter((d) => d.visible !== null).length;
    const meta = $('ha-devices-meta');
    if (meta) meta.textContent = `${all.length} 台设备 · ${shown} 台上屏 · ${configured} 台已配置`;

    if (!rows.length) {
      body.innerHTML = '<tr><td colspan="8" class="empty">没有匹配的设备</td></tr>';
      return;
    }

    const frag = document.createDocumentFragment();
    for (const d of rows) {
      const tr = document.createElement('tr');

      const nameTd = document.createElement('td');
      nameTd.innerHTML = `<span class="strong">${esc(d.name || d.id)}</span>`;
      tr.appendChild(nameTd);

      const areaTd = document.createElement('td');
      areaTd.innerHTML = `<span class="muted">${esc(d.areaName || (d.home && d.room ? d.home + ' ' + d.room : '') || '—')}</span>`;
      tr.appendChild(areaTd);

      const intTd = document.createElement('td');
      intTd.innerHTML = `<span class="muted">${esc(d.integration || '—')}</span>`;
      tr.appendChild(intTd);

      const mfTd = document.createElement('td');
      mfTd.innerHTML = `<span class="muted">${esc(d.manufacturer || '—')}</span>`;
      tr.appendChild(mfTd);

      const modelTd = document.createElement('td');
      modelTd.innerHTML = `<span class="mono">${esc(d.model || '—')}</span>`;
      tr.appendChild(modelTd);

      const batTd = document.createElement('td');
      batTd.innerHTML = `<span class="muted">${esc(d.battery || '—')}</span>`;
      tr.appendChild(batTd);

      const countTd = document.createElement('td');
      countTd.innerHTML = `<span class="muted">${d.entityCount || 0}</span>`;
      tr.appendChild(countTd);

      // 显示开关：三态——未配置(null) / 显示(true) / 隐藏(false)。
      const visTd = document.createElement('td');
      const visWrap = document.createElement('div');
      visWrap.className = 'ha-vis-cell';
      const cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = d.visible !== false; // 未配置视为显示（保持现状）
      cb.title = d.visible === null ? '未配置（保持现状，等同显示）' : (d.visible ? '显示' : '隐藏');
      cb.addEventListener('change', async () => {
        cb.disabled = true;
        try {
          await api('/api/admin/ha/devices/visibility', {
            method: 'POST',
            body: JSON.stringify({ deviceId: d.id, visible: cb.checked }),
          });
          d.visible = cb.checked;
          cb.title = cb.checked ? '显示' : '隐藏';
          // 就地更新 meta，不整表重绘（避免输入焦点/勾选态丢失）
          const all2 = state.haDevices || [];
          const shown2 = all2.filter((x) => x.visible !== false).length;
          const configured2 = all2.filter((x) => x.visible !== null).length;
          if (meta) meta.textContent = `${all2.length} 台设备 · ${shown2} 台上屏 · ${configured2} 台已配置`;
          toast(cb.checked ? '已设为显示到中控屏' : '已从中控屏隐藏');
        } catch (error) {
          cb.checked = !cb.checked;
          toast('保存失败：' + error.message, 'error');
        } finally {
          cb.disabled = false;
        }
      });
      visWrap.appendChild(cb);
      const stateSpan = document.createElement('span');
      stateSpan.className = 'ha-vis-state';
      stateSpan.textContent = d.visible === null ? '默认' : (d.visible ? '显示' : '隐藏');
      visWrap.appendChild(stateSpan);
      visTd.appendChild(visWrap);
      tr.appendChild(visTd);

      frag.appendChild(tr);
    }
    body.innerHTML = '';
    body.appendChild(frag);
  }

  function bindHaDevicesOnce() {
    if (state._haDevicesBound) return;
    state._haDevicesBound = true;
    const search = $('ha-devices-search');
    if (search) search.addEventListener('input', renderHaDevices);
    const only = $('ha-devices-only-visible');
    if (only) only.addEventListener('change', renderHaDevices);
    const refresh = $('ha-devices-refresh');
    if (refresh) refresh.addEventListener('click', () => loadHaDevices(true));
  }
