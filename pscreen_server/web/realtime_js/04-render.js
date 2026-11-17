'use strict';

      function renderHeader() {
        if (state.currentPeer === ALL) {
          peerAvatar.textContent = 'Σ';
          peerAvatar.style.background = avatarColor(ALL);
          peerTitle.textContent = '全部事件';
          const totalEvents = state.events.size;
          peerSubtitle.textContent = `${totalEvents} 条事件 · ${onlineCount()} 个账号在线`;
          return;
        }

        const peer = state.currentPeer;
        const peerState = state.peers.get(peer);
        peerAvatar.textContent = avatarText(peer);
        peerAvatar.style.background = avatarColor(peer);
        peerTitle.textContent = accountLabel(peer);
        const online = state.online.has(peer);
        const last = peerState?.last ? ` · ${truncate(peerState.last, 56)}` : '';
        const device = state.deviceIds.get(peer);
        const client = clientLabel(peer);
        peerSubtitle.textContent = `${online ? '在线' : '离线'}${device ? ` · 设备 ${device}` : ''}${client ? ` · ${client}` : ''}${last}`;
      }

      function renderAccounts() {
        const scrollTop = accountList.scrollTop;
        const query = searchInput.value.trim().toLowerCase();
        const online = onlineCount();
        onlineSummary.textContent = `${online} 个在线`;

        const peers = [];
        for (const peer of state.peers.values()) {
          if (peer.account === state.account) continue;
          peers.push(peer);
        }
        for (const account of state.online) {
          if (account === state.account || state.peers.has(account)) continue;
          peers.push({ account, last: '在线，暂无消息', ts: 0, unread: 0 });
        }

        peers.sort((a, b) => {
          const aOnline = state.online.has(a.account) ? 1 : 0;
          const bOnline = state.online.has(b.account) ? 1 : 0;
          if (aOnline !== bOnline) return bOnline - aOnline;
          if ((b.ts || 0) !== (a.ts || 0)) return (b.ts || 0) - (a.ts || 0);
          return a.account.localeCompare(b.account);
        });

        accountList.replaceChildren();

        if (!query) {
          accountList.append(renderAccountRow({
            account: ALL,
            last: `${state.events.size} 条事件`,
            ts: 0,
            unread: 0,
          }, true));
        }

        let count = 0;
        for (const peer of peers) {
          const label = accountLabel(peer.account);
          if (query && !label.toLowerCase().includes(query)) continue;
          accountList.append(renderAccountRow(peer, false));
          count++;
        }

        if (count === 0) {
          accountList.append(el('div', 'list-empty', query ? '没有匹配的账号' : '暂无其他账号'));
        }
        accountList.scrollTop = scrollTop;
      }

      function renderAccountRow(peer, isAll) {
        const active = state.currentPeer === peer.account;
        const button = el('button', `account${active ? ' active' : ''}`);
        button.type = 'button';
        button.title = peer.account;
        button.addEventListener('click', () => selectPeer(peer.account));

        const avatar = el('div', 'avatar', isAll ? 'Σ' : avatarText(peer.account));
        avatar.style.background = avatarColor(peer.account);

        const main = el('div', 'account-main');
        // 第一行拆分：账号名 / 设备号 / app版本 各占一行，状态（预览）行不变。
        const line = el('div', 'account-line');
        line.append(el('span', 'account-name', isAll ? '全部事件' : peer.account));
        if (!isAll && ACCOUNT_LABELS[peer.account]) {
          line.append(el('span', 'tag', ACCOUNT_LABELS[peer.account]));
        }
        main.append(line);
        const device = !isAll ? state.deviceIds.get(peer.account) : '';
        if (device) {
          const deviceLine = el('div', 'account-line account-sub');
          const chip = el('span', 'tag', `设备 ${device}`);
          chip.title = device;
          deviceLine.append(chip);
          main.append(deviceLine);
        }
        const info = isAll ? null : state.clientInfo.get(peer.account);
        // app 名称独立一行；版本号拆到右上角（状态点上方），避免长标识被省略。
        if (info && info.app) {
          const clientLine = el('div', 'account-line account-sub');
          const chip = el('span', 'tag', info.app);
          chip.title = info.app;
          clientLine.append(chip);
          main.append(clientLine);
        }
        main.append(el('div', 'account-preview', peer.last || '暂无消息'));

        const side = el('div', 'account-side');
        const version = info ? clientVersionLabel(peer.account) : '';
        if (version) {
          const verEl = el('span', 'account-version', version);
          verEl.title = `${info.app} ${version}`.trim();
          side.append(verEl);
        }
        if (!isAll) {
          const dot = el('span', `online-dot${state.online.has(peer.account) ? ' on' : ''}`);
          side.append(dot);
        } else {
          side.append(el('span', 'account-time', state.events.size ? `${state.events.size}` : ''));
        }
        if (peer.ts) side.append(el('span', 'account-time', formatTime(peer.ts)));
        if (peer.unread > 0) side.append(el('span', 'unread', peer.unread > 99 ? '99+' : String(peer.unread)));

        button.append(avatar, main, side);
        return button;
      }

      function collectTimeline() {
        const peer = state.currentPeer;
        const messages = state.filter === 'event' ? [] : messagesFor(peer);
        const events = state.filter === 'message' ? [] : eventsFor(peer);
        const items = [
          ...messages.map((message) => ({ kind: 'message', ts: message.ts, id: message.id, value: message })),
          ...events.map((event) => ({ kind: 'event', ts: event.ts, id: event.id, value: event })),
        ];
        // 倒序：最新的排最前，打开即见，无需每次滑到底部。
        items.sort((a, b) => {
          if ((a.ts || 0) !== (b.ts || 0)) return (b.ts || 0) - (a.ts || 0);
          return a.id.localeCompare(b.id);
        });
        return items;
      }

      function renderTimeline(forceTop = false) {
        // 是否停在顶部（最新消息处）：在顶部时新事件到达后保持吸顶。
        const nearTop = timeline.scrollTop < 80;
        const items = collectTimeline();
        timeline.replaceChildren();

        for (const item of items) {
          timeline.append(item.kind === 'message'
            ? renderMessage(item.value)
            : renderEvent(item.value));
        }

        const isEmpty = items.length === 0;
        emptyEl.hidden = !isEmpty;
        timeline.hidden = isEmpty;
        if (!isEmpty && !state.initialScrollDone) {
          state.initialScrollDone = true;
          timeline.scrollTop = 0;
        }
        if (isEmpty) {
          const title = emptyEl.querySelector('h3');
          const desc = emptyEl.querySelector('p');
          if (state.filter === 'message') {
            title.textContent = '暂无消息';
            desc.textContent = '这个筛选条件下还没有聊天消息。';
          } else if (state.filter === 'event') {
            title.textContent = '暂无事件';
            desc.textContent = '这个筛选条件下还没有场景或 HA 操作事件。';
          } else {
            title.textContent = '暂无信息';
            desc.textContent = '连接后选择左侧账号，或等待实时消息。';
          }
        }

        if (forceTop || nearTop) {
          timeline.scrollTop = 0;
        }
      }

      function renderMessage(message) {
        const mine = message.from === state.account;
        const row = el('div', `message-row${mine ? ' mine' : ''}`);
        const bubble = el('div', 'message');

        const meta = el('div', 'message-meta');
        meta.append(el('span', 'message-from', mine ? '我' : message.from));
        meta.append(el('span', null, formatTime(message.ts)));
        bubble.append(meta);
        bubble.append(el('div', 'message-body', message.body || '（空消息）'));
        row.append(bubble);
        return row;
      }

      function renderEvent(event) {
        const data = event.data || {};
        const card = el('article', 'event-card');
        card.dataset.event = event.event;
        if (data.success === false) card.classList.add('failed');

        const head = el('div', 'event-head');
        head.append(el('span', 'event-badge', EVENT_LABELS[event.event] || event.event || '事件'));
        head.append(el('span', 'event-route', `${event.from || '-'} → ${event.to || '仅落库'}`));
        head.append(el('span', 'event-time', formatTime(event.ts)));
        card.append(head);

        const body = el('div', 'event-body');
        if (event.event === 'ha_action') {
          renderHaAction(body, event, data);
        } else if (event.event === 'scene_changed') {
          renderSceneChanged(body, data);
        } else if (event.event === 'channel_changed') {
          renderChannelChanged(body, data);
        } else if (PLAYBACK_EVENTS.has(event.event)) {
          renderPlayback(body, event, data);
        } else {
          body.append(el('h3', 'event-title', event.event || '未命名事件'));
          body.append(el('p', 'event-line', '未知事件类型，展开原始 JSON 查看。'));
        }
        card.append(body);
        card.append(renderRaw(event));
        return card;
      }

      function renderHaAction(body, event, data) {
        const action = String(data.action || '');
        const title = action === 'open_device_detail'
          ? `打开卡片 · ${data.cardName || data.entityName || data.entityId || ''}`
          : action === 'press'
            ? `按下按钮 · ${data.entityName || data.entityId || ''}`
            : `${ACTION_LABELS[action] || action || '操作'} · ${data.entityName || data.entityId || ''}`;
        body.append(el('h3', 'event-title', title));

        const chips = el('div', 'chips');
        if (data.site) chips.append(el('span', 'chip', `站点 ${data.site}`));
        if (data.deviceName || data.deviceId) {
          chips.append(el('span', 'chip', `设备 ${data.deviceName || data.deviceId}`));
        }
        if (data.areaName || data.areaId) {
          chips.append(el('span', 'chip', `区域 ${data.areaName || data.areaId}`));
        }
        if (data.entityId) chips.append(el('span', 'chip', `实体 ${data.entityId}`));
        if (data.buttonId) chips.append(el('span', 'chip', `按钮 ${data.buttonId}`));
        if (data.trigger) chips.append(el('span', 'chip', `入口 ${TRIGGER_LABELS[data.trigger] || data.trigger}`));
        if (data.scene && data.scene.title) chips.append(el('span', 'chip', `场景 ${data.scene.title}`));
        chips.append(el('span', `chip ${data.success === false ? 'fail' : 'ok'}`, data.success === false ? '失败' : '成功'));
        body.append(chips);

        if (data.value !== undefined && data.value !== null && data.value !== '') {
          const line = el('p', 'event-line');
          line.append(document.createTextNode('值：'));
          line.append(el('strong', null, formatValue(action, data.value)));
          if (data.previousValue !== undefined && data.previousValue !== null && data.previousValue !== '') {
            line.append(document.createTextNode('（原：'));
            line.append(el('strong', null, formatValue(action, data.previousValue)));
            line.append(document.createTextNode('）'));
          }
          body.append(line);
        }

        if (data.error) body.append(el('p', 'event-error', data.error));
      }

      function renderSceneChanged(body, data) {
        body.append(el('h3', 'event-title', `场景：${data.title || '未知场景'}`));
        const chips = el('div', 'chips');
        if (data.kind) chips.append(el('span', 'chip', `类型 ${data.kind}`));
        if (data.route) chips.append(el('span', 'chip', `路由 ${data.route}`));
        // 直播窗口形态：全屏（路由 /live）/ 应用内悬浮小窗（路由为底层页）。
        if (data.kind === 'live' && data.floating !== undefined) {
          chips.append(el('span', 'chip', data.floating ? '形态 悬浮小窗' : '形态 全屏'));
        }
        if (data.channelName) chips.append(el('span', 'chip', `频道 ${data.channelName}`));
        if (data.deviceName || data.deviceId) chips.append(el('span', 'chip', `设备 ${data.deviceName || data.deviceId}`));
        if (data.areaName || data.areaId) chips.append(el('span', 'chip', `区域 ${data.areaName || data.areaId}`));
        body.append(chips);
      }

      function renderChannelChanged(body, data) {
        body.append(el('h3', 'event-title', `频道：${data.channelName || '未知频道'}`));
        const chips = el('div', 'chips');
        if (data.index !== undefined) chips.append(el('span', 'chip', `序号 ${data.index}`));
        if (data.scene && data.scene.title) chips.append(el('span', 'chip', `场景 ${data.scene.title}`));
        body.append(chips);
      }

      // 播放状态事件（play_start / play_ok / play_retry / play_fail）：
      // 字段来自 ReportingService.notifyPlayback（sourceIndex/round 均从 1 起，
      // source 为脱敏截断后的源地址）。
      function renderPlayback(body, event, data) {
        body.append(el('h3', 'event-title', `频道：${data.channelName || '未知频道'}`));
        const chips = el('div', 'chips');
        if (data.sourceIndex > 0 && data.sourceTotal > 0) {
          chips.append(el('span', 'chip', `源 ${data.sourceIndex}/${data.sourceTotal}`));
        }
        if (data.round > 0) chips.append(el('span', 'chip', `第 ${data.round} 轮`));
        if (data.viaProxy) chips.append(el('span', 'chip', '经代理'));
        if (typeof data.elapsedMs === 'number') {
          chips.append(el('span', 'chip', `耗时 ${(data.elapsedMs / 1000).toFixed(1)}s`));
        }
        if (data.source) {
          const source = el('span', 'chip', data.source);
          source.title = data.source;
          chips.append(source);
        }
        if (event.event === 'play_ok') {
          chips.append(el('span', 'chip ok', '成功'));
        } else if (event.event === 'play_fail') {
          chips.append(el('span', 'chip fail', '失败'));
        }
        body.append(chips);
        if (data.reason) body.append(el('p', 'event-line', `原因：${data.reason}`));
      }

      function renderRaw(event) {
        const details = el('details', 'raw');
        details.append(el('summary', null, '原始 JSON'));
        details.append(el('pre', null, JSON.stringify({
          id: event.id,
          from: event.from,
          to: event.to,
          event: event.event,
          ts: event.ts,
          data: event.data,
        }, null, 2)));
        return details;
      }

