'use strict';

      function setStatus(kind, text) {
        statusEl.className = `status ${kind || ''}`.trim();
        statusText.textContent = text;
      }

      function setWsLabel() {
        wsLabel.textContent = buildWsUrl(state.account || accountInput.value.trim(), state.token || '…')
          .replace(/token=[^&]+/, 'token=***');
      }

      function buildWsUrl(account, token) {
        const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
        const host = location.host || 'localhost:3000';
        const params = new URLSearchParams({
          account,
          token,
          role: 'viewer',
          name: 'web-realtime',
          app: 'web',
        });
        return `${protocol}//${host}/ws?${params.toString()}`;
      }

      // 记录客户端标识（app/version/build），供账号行与会话头展示。
      function rememberClientInfo(account, frame) {
        if (!account || typeof frame.app !== 'string') return;
        const info = {
          app: String(frame.app || ''),
          version: String(frame.version || ''),
          build: String(frame.build || ''),
        };
        if (info.app || info.version || info.build) {
          state.clientInfo.set(account, info);
        }
      }

      // 版本号文案：`v1.0.0+2`（未知时为空串）。
      function clientVersionLabel(account) {
        const info = state.clientInfo.get(account);
        if (!info || !info.version) return '';
        return `v${info.version}${info.build ? `+${info.build}` : ''}`;
      }

      // 客户端标识文案：`com.x.y v1.0.0+2`（未知时为空串）。
      function clientLabel(account) {
        const info = state.clientInfo.get(account);
        if (!info) return '';
        const ver = clientVersionLabel(account);
        return [info.app, ver].filter(Boolean).join(' ');
      }

      // 浏览器 WebCrypto 不支持 MD5，也不引外网 CDN，
      // 口令摘要统一由服务端 /api/password_md5 下发。
      async function fetchPasswordMd5(password) {
        const resp = await fetch('/api/password_md5', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ password }),
        });
        const body = await resp.json();
        if (body.code !== 0 || !body.data || typeof body.data.md5 !== 'string') {
          throw new Error(body.msg || '获取口令摘要失败');
        }
        return body.data.md5;
      }

      function isOpen() {
        return state.socket && state.socket.readyState === WebSocket.OPEN;
      }

      function request(frame, timeoutMs = 8000) {
        return new Promise((resolve) => {
          if (!isOpen()) {
            resolve(null);
            return;
          }
          const id = `web-${Date.now()}-${++state.seq}`;
          const timer = setTimeout(() => {
            state.pending.delete(id);
            resolve(null);
          }, timeoutMs);
          state.pending.set(id, {
            resolve: (value) => {
              clearTimeout(timer);
              state.pending.delete(id);
              resolve(value);
            },
          });
          try {
            state.socket.send(JSON.stringify({ ...frame, id }));
          } catch (_) {
            clearTimeout(timer);
            state.pending.delete(id);
            resolve(null);
          }
        });
      }

      function rejectPending() {
        for (const pending of state.pending.values()) pending.resolve(null);
        state.pending.clear();
      }

      function disconnectSocket() {
        const old = state.socket;
        state.socket = null;
        if (old) {
          old.onopen = null;
          old.onmessage = null;
          old.onerror = null;
          old.onclose = null;
          try { old.close(); } catch (_) { /* ignore */ }
        }
        rejectPending();
      }

      function resetData() {
        state.online.clear();
        state.peers.clear();
        state.messages.clear();
        state.events.clear();
        state.currentPeer = ALL;
        state.filter = 'all';
        state.initialScrollDone = false;
        document.querySelectorAll('.filters button').forEach((button) => {
          button.classList.toggle('active', button.dataset.filter === 'all');
        });
        renderAll();
      }

      async function connect() {
        const account = accountInput.value.trim();
        const password = tokenInput.value;
        if (!account) {
          setStatus('error', '账号不能为空');
          accountInput.focus();
          return;
        }
        if (!password) {
          setStatus('error', '口令不能为空');
          tokenInput.focus();
          return;
        }

        setStatus('connecting', '获取口令摘要…');
        let token;
        try {
          token = await fetchPasswordMd5(password);
        } catch (error) {
          setStatus('error', `获取口令摘要失败：${error.message || error}`);
          return;
        }

        // 与各端一致：先 HTTP 登录（账号不存在且口令为默认时服务端自动建档），
        // 否则 ws 握手会因「账号不存在」被拒；登录失败不阻断，由 ws 侧独立报错。
        try {
          await fetch('/api/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username: account, password: token }),
          });
        } catch (_) { /* 网络失败交由 ws 连接报错 */ }

        localStorage.setItem(STORAGE_ACCOUNT, account);
        localStorage.setItem(STORAGE_PASSWORD, password);

        if (state.reconnectTimer) {
          clearTimeout(state.reconnectTimer);
          state.reconnectTimer = null;
        }
        disconnectSocket();
        resetData();
        state.account = account;
        state.token = token;
        state.manualClose = false;
        state.shouldReconnect = true;

        setStatus('connecting', '连接中…');
        setWsLabel();

        let socket;
        try {
          socket = new WebSocket(buildWsUrl(account, token));
        } catch (error) {
          setStatus('error', `无法创建连接：${error.message || error}`);
          return;
        }
        state.socket = socket;

        socket.onopen = () => {
          if (state.socket !== socket) return;
          setStatus('connecting', '已连接，等待服务端 ready…');
        };

        socket.onmessage = (event) => {
          if (state.socket !== socket) return;
          handleFrame(event.data);
        };

        socket.onerror = () => {
          if (state.socket !== socket) return;
          setStatus('error', '连接错误');
        };

        socket.onclose = (event) => {
          if (state.socket !== socket) return;
          state.socket = null;
          rejectPending();
          const suffix = event.code ? ` (${event.code}${event.reason ? ` ${event.reason}` : ''})` : '';
          setStatus('offline', `已断开${suffix}`);
          if (!state.manualClose && state.shouldReconnect) scheduleReconnect();
        };
      }

      function scheduleReconnect() {
        if (state.manualClose || !state.shouldReconnect || state.reconnectTimer) return;
        setStatus('connecting', '3 秒后重连…');
        state.reconnectTimer = setTimeout(() => {
          state.reconnectTimer = null;
          if (!state.manualClose && state.shouldReconnect) connect();
        }, 3000);
      }

      function disconnect() {
        state.manualClose = true;
        state.shouldReconnect = false;
        if (state.reconnectTimer) {
          clearTimeout(state.reconnectTimer);
          state.reconnectTimer = null;
        }
        disconnectSocket();
        setStatus('offline', '已断开');
      }

      function handleFrame(raw) {
        let frame;
        try {
          frame = JSON.parse(raw);
        } catch (_) {
          return;
        }
        if (!frame || typeof frame.t !== 'string') return;

        if (frame.id && state.pending.has(frame.id)) {
          const pending = state.pending.get(frame.id);
          state.pending.delete(frame.id);
          pending.resolve(frame);
        }

        switch (frame.t) {
          case 'ready': {
            if (typeof frame.account === 'string' && frame.account) state.account = frame.account;
            if (state.account && typeof frame.deviceId === 'string' && frame.deviceId) {
              state.deviceIds.set(state.account, frame.deviceId);
            }
            rememberClientInfo(state.account, frame);
            state.online = new Set((Array.isArray(frame.online) ? frame.online : []).map(String));
            // roster：服务端下发的在线端明细（设备号 + app/version/build）。
            // presence 只在对方新连接时广播，刷新页面后靠它补齐已有在线端标识。
            if (Array.isArray(frame.roster)) {
              for (const item of frame.roster) {
                if (!item || typeof item.account !== 'string' || !item.account) continue;
                if (typeof item.deviceId === 'string' && item.deviceId) {
                  state.deviceIds.set(item.account, item.deviceId);
                }
                rememberClientInfo(item.account, item);
              }
            }
            setStatus('connected', `已连接 · ${onlineCount()} 个在线`);
            renderAll();
            refreshAll();
            break;
          }
          case 'presence': {
            const account = String(frame.account || '');
            if (!account) return;
            if (typeof frame.deviceId === 'string' && frame.deviceId) {
              state.deviceIds.set(account, frame.deviceId);
            }
            rememberClientInfo(account, frame);
            if (frame.online === true) {
              state.online.add(account);
              ensurePeer(account);
            } else {
              state.online.delete(account);
            }
            setStatus(isOpen() ? 'connected' : 'offline', isOpen() ? `已连接 · ${onlineCount()} 个在线` : '未连接');
            renderAll();
            break;
          }
          case 'msg': {
            const message = normalizeMessage(frame);
            if (!message.id) return;
            const peer = messagePeer(message);
            if (!peer || peer === state.account) return;
            addMessage(peer, message);
            const peerState = ensurePeer(peer);
            const shouldUnread = message.from === peer && state.currentPeer !== peer && state.currentPeer !== ALL;
            updatePeer(peer, {
              last: `消息：${truncate(message.body, 80)}`,
              ts: message.ts,
              unread: shouldUnread ? (peerState?.unread || 0) + 1 : peerState?.unread,
            });
            renderAccounts();
            renderTimeline();
            break;
          }
          case 'event': {
            const event = normalizeEvent(frame);
            if (!event.id) return;
            addEvent(event);
            renderAccounts();
            renderTimeline();
            break;
          }
          case 'conversations': {
            const items = Array.isArray(frame.items) ? frame.items : [];
            for (const item of items) {
              const account = String(item.account || '');
              if (!account || account === state.account) continue;
              updatePeer(account, {
                last: String(item.lastMessage || ''),
                ts: Number(item.ts) || 0,
                unread: Number(item.unread) || 0,
              });
            }
            renderAccounts();
            break;
          }
          case 'history': {
            const peer = String(frame.peer || '');
            const items = Array.isArray(frame.messages) ? frame.messages : [];
            if (peer && peer !== state.account) {
              for (const item of items) {
                const message = normalizeMessage(item);
                if (message.id) addMessage(peer, message);
              }
              if (state.currentPeer === peer) renderTimeline();
            }
            break;
          }
          case 'events': {
            const items = Array.isArray(frame.items) ? frame.items : [];
            for (const item of items) {
              const event = normalizeEvent(item);
              if (event.id) addEvent(event, false);
            }
            renderAccounts();
            renderTimeline();
            break;
          }
          case 'error': {
            const code = Number(frame.code) || 0;
            const message = String(frame.msg || '未知错误');
            setStatus('error', `服务端 ${code || ''}：${message}`.trim());
            if (code === 401 || code === 403 || /invalid (account|token)/i.test(message)) {
              state.shouldReconnect = false;
            }
            break;
          }
          case 'read_ok':
          case 'pong':
            break;
          default:
            break;
        }
      }

