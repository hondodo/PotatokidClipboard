'use strict';

      const ALL = '__all__';
      const DEFAULT_ACCOUNT = '1000001';
      const DEFAULT_PASSWORD = '123456';
      const STORAGE_ACCOUNT = 'potatokid.realtime.account';
      const STORAGE_PASSWORD = 'potatokid.realtime.password';
      const POLL_MS = 20000;

      const ACCOUNT_LABELS = {
        '1000001': '系统管理员',
      };

      const ACTION_LABELS = {
        turn_on: '打开',
        turn_off: '关闭',
        set_brightness: '设置亮度',
        set_color_temperature: '设置色温',
        set_effect: '设置灯光效果',
        set_temperature: '设置温度',
        set_hvac_mode: '设置空调模式',
        set_fan_mode: '设置风速',
        set_swing_mode: '设置摆风',
        set_preset_mode: '设置预设模式',
        set_percentage: '设置档位',
        set_oscillating: '设置摆风',
        set_operation_mode: '设置模式',
        set_text: '设置文本',
        set_number: '设置数值',
        select_option: '选择选项',
        press: '按下按钮',
        notify: '发送通知',
        open_device_detail: '打开设备详情',
      };

      const EVENT_LABELS = {
        scene_changed: '场景变化',
        channel_changed: '频道变化',
        ha_action: 'HA 操作',
        play_start: '播放开始',
        play_ok: '播放成功',
        play_retry: '播放重试',
        play_fail: '播放失败',
      };

      // 播放状态事件（ReportingService.notifyPlayback 上报的一组）。
      const PLAYBACK_EVENTS = new Set(['play_start', 'play_ok', 'play_retry', 'play_fail']);

      const TRIGGER_LABELS = {
        home_card: '主页卡片',
        device_detail: '设备详情',
        unknown: '未知入口',
      };

      const state = {
        socket: null,
        account: '',
        token: '',
        manualClose: true,
        shouldReconnect: true,
        reconnectTimer: null,
        pollTimer: null,
        online: new Set(),
        peers: new Map(),
        // 账号 -> 设备号（presence/ready 带回，用于把自定义账号对回物理设备）
        deviceIds: new Map(),
        // 账号 -> {app, version, build}（presence/ready 带回，区分控制端形态）
        clientInfo: new Map(),
        messages: new Map(),
        events: new Map(),
        currentPeer: ALL,
        filter: 'all',
        pending: new Map(),
        seq: 0,
        initialScrollDone: false,
      };

      const $ = (id) => document.getElementById(id);
      const accountInput = $('account-input');
      const tokenInput = $('token-input');
      const statusEl = $('status');
      const statusText = $('status-text');
      const accountList = $('account-list');
      const onlineSummary = $('online-summary');
      const searchInput = $('search-input');
      const wsLabel = $('ws-label');
      const peerAvatar = $('peer-avatar');
      const peerTitle = $('peer-title');
      const peerSubtitle = $('peer-subtitle');
      const timeline = $('timeline');
      const emptyEl = $('empty');

      function el(tag, className, text) {
        const node = document.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined && text !== null) node.textContent = String(text);
        return node;
      }

      function append(parent, ...children) {
        for (const child of children) {
          if (child !== null && child !== undefined) parent.append(child);
        }
        return parent;
      }

      function truncate(value, max) {
        const text = String(value ?? '');
        return text.length > max ? `${text.slice(0, max - 1)}…` : text;
      }

      function formatTime(ts) {
        const value = Number(ts);
        if (!Number.isFinite(value) || value <= 0) return '--:--';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return '--:--';
        const now = new Date();
        const sameDay = date.toDateString() === now.toDateString();
        const time = date.toLocaleTimeString('zh-CN', { hour12: false });
        if (sameDay) return time;
        return `${date.getMonth() + 1}/${date.getDate()} ${time}`;
      }

      function formatValue(action, value) {
        if (value === undefined || value === null || value === '') return '—';
        if (typeof value === 'boolean') return value ? '开' : '关';
        if (action === 'set_brightness' || action === 'set_percentage') return `${value}%`;
        if (action === 'set_color_temperature') return `${value}K`;
        if (action === 'set_temperature') return `${value}°C`;
        return String(value);
      }

      function accountLabel(account) {
        return ACCOUNT_LABELS[account] ? `${account} · ${ACCOUNT_LABELS[account]}` : account;
      }

      function avatarText(account) {
        if (account === ALL) return 'Σ';
        const text = String(account || '?').replace(/[^a-zA-Z0-9\u4e00-\u9fa5]/g, '');
        return (text.slice(-2) || '?').toUpperCase();
      }

      function avatarColor(account) {
        if (account === ALL) return 'linear-gradient(135deg, #5eead4, #60a5fa)';
        let hash = 0;
        for (const char of String(account)) hash = ((hash << 5) - hash + char.codePointAt(0)) | 0;
        const hue = Math.abs(hash) % 360;
        return `linear-gradient(135deg, hsl(${hue} 55% 48%), hsl(${(hue + 34) % 360} 60% 42%))`;
      }

      function eventPeer(event) {
        if (event.from === state.account) return event.to;
        if (event.to === state.account) return event.from;
        return event.from || event.to || '';
      }

      function messagePeer(message) {
        if (message.from === state.account) return message.to;
        if (message.to === state.account) return message.from;
        return message.from || message.to || '';
      }

      function ensurePeer(account) {
        if (!account || account === state.account) return null;
        let peer = state.peers.get(account);
        if (!peer) {
          peer = { account, last: '', ts: 0, unread: 0 };
          state.peers.set(account, peer);
        }
        return peer;
      }

      function updatePeer(account, patch = {}) {
        const peer = ensurePeer(account);
        if (!peer) return;
        const incomingTs = Number(patch.ts) || 0;
        if (patch.last !== undefined) {
          if (incomingTs >= peer.ts) {
            peer.last = String(patch.last || '');
            peer.ts = incomingTs || peer.ts;
          } else if (!peer.last) {
            peer.last = String(patch.last || '');
          }
        } else if (incomingTs > peer.ts) {
          peer.ts = incomingTs;
        }
        if (patch.unread !== undefined) peer.unread = Math.max(0, Number(patch.unread) || 0);
      }

      function addMessage(peer, message) {
        if (!peer || peer === state.account) return;
        let map = state.messages.get(peer);
        if (!map) {
          map = new Map();
          state.messages.set(peer, map);
        }
        map.set(message.id, message);
      }

      function messagesFor(peer) {
        if (peer !== ALL) {
          return [...(state.messages.get(peer)?.values() || [])];
        }
        const result = [];
        for (const map of state.messages.values()) result.push(...map.values());
        return result;
      }

      function eventsFor(peer) {
        const all = [...state.events.values()];
        if (peer === ALL) return all;
        return all.filter((event) => event.from === peer || event.to === peer);
      }

