'use strict';

      function normalizeMessage(frame) {
        return {
          id: String(frame.id || ''),
          from: String(frame.from || ''),
          to: String(frame.to || ''),
          body: String(frame.body || ''),
          ts: Number(frame.ts) || 0,
        };
      }

      function normalizeEvent(frame) {
        const data = frame.data && typeof frame.data === 'object' && !Array.isArray(frame.data)
          ? frame.data
          : {};
        return {
          id: String(frame.id || frame.eventId || `${frame.from || ''}-${frame.ts || 0}-${frame.event || ''}`),
          from: String(frame.from || ''),
          to: String(frame.to || ''),
          event: String(frame.event || ''),
          data,
          ts: Number(frame.ts) || Number(data.ts) || 0,
        };
      }

      function addEvent(event, render = true) {
        if (!event.id) return;
        state.events.set(event.id, event);
        const peer = eventPeer(event);
        if (peer && peer !== state.account) {
          updatePeer(peer, {
            last: `事件：${EVENT_LABELS[event.event] || event.event}`,
            ts: event.ts,
          });
        }
        if (render) renderAccounts();
      }

      function refreshAll() {
        if (!isOpen()) return Promise.resolve();
        const tasks = [refreshConversations(), refreshEvents()];
        if (state.currentPeer !== ALL) tasks.push(refreshHistory(state.currentPeer));
        return Promise.allSettled(tasks).then(() => {
          renderAll();
        });
      }

      async function refreshConversations() {
        const reply = await request({ t: 'conversations' });
        if (!reply || !Array.isArray(reply.items)) return;
        for (const item of reply.items) {
          const account = String(item.account || '');
          if (!account || account === state.account) continue;
          updatePeer(account, {
            last: String(item.lastMessage || ''),
            ts: Number(item.ts) || 0,
            unread: Number(item.unread) || 0,
          });
        }
        renderAccounts();
      }

      async function refreshEvents() {
        const reply = await request({ t: 'events', limit: 200 });
        if (!reply || !Array.isArray(reply.items)) return;
        for (const item of reply.items) {
          const event = normalizeEvent(item);
          addEvent(event, false);
        }
        renderAccounts();
      }

      async function refreshHistory(peer) {
        if (peer === ALL) return;
        const reply = await request({ t: 'history', peer, limit: 200 });
        if (!reply || !Array.isArray(reply.messages)) return;
        for (const item of reply.messages) {
          const message = normalizeMessage(item);
          if (message.id) addMessage(peer, message);
        }
        if (state.currentPeer === peer) renderTimeline();
      }

      function markRead(peer) {
        if (!isOpen() || !peer || peer === ALL) return;
        const peerState = state.peers.get(peer);
        if (peerState) peerState.unread = 0;
        try {
          state.socket.send(JSON.stringify({ t: 'read', peer }));
        } catch (_) {
          // 忽略：已读游标失败不影响查看。
        }
        renderAccounts();
      }

      function selectPeer(peer) {
        state.currentPeer = peer;
        markRead(peer);
        renderAccounts();
        renderHeader();
        renderTimeline(true);
        if (peer !== ALL) refreshHistory(peer);
      }

      function onlineCount() {
        return [...state.online].filter((account) => account !== state.account).length;
      }

      function renderAll() {
        renderAccounts();
        renderHeader();
        renderTimeline();
      }

