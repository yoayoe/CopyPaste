/**
 * WebSocket connection manager with HTTP polling fallback.
 *
 * Safari iOS cannot maintain WSS connections over self-signed certs after
 * page refresh. We detect Safari and use HTTP polling directly — no WSS
 * attempts, no waiting, instant reconnect.
 */
const WS = (() => {
  let socket = null;
  let reconnectTimer = null;
  let reconnectAttempts = 0;
  let pollInterval = null;
  let usePolling = false;
  const POLL_INTERVAL_MS = 1500;
  const listeners = {};

  // Detect Safari (excludes Chrome/Firefox on iOS which also have Safari in UA).
  const isSafari = /safari/i.test(navigator.userAgent) && !/chrome|crios|fxios|edgios/i.test(navigator.userAgent);
  const isHttps = window.location.protocol === 'https:';

  // Safari + HTTPS (self-signed) → always use polling. WSS will never work reliably.
  const forcePoll = isSafari && isHttps;

  function getWsUrl() {
    const sessionToken = localStorage.getItem('cp_session_token') || '';
    const protocol = isHttps ? 'wss:' : 'ws:';
    return `${protocol}//${window.location.host}/ws?token=${encodeURIComponent(sessionToken)}`;
  }

  function connect() {
    if (forcePoll) {
      console.log('[WS] Safari + HTTPS detected — using HTTP polling');
      startPolling();
      return;
    }
    connectWs();
  }

  function connectWs() {
    if (usePolling) return;
    if (socket && socket.readyState === WebSocket.OPEN) return;
    if (socket && socket.readyState !== WebSocket.CLOSED) {
      try { socket.close(); } catch (_) {}
      socket = null;
    }

    const url = getWsUrl();
    try {
      socket = new WebSocket(url);
    } catch (e) {
      console.error('[WS] Failed to create WebSocket:', e);
      scheduleReconnect();
      return;
    }

    const timeout = setTimeout(() => {
      if (socket && socket.readyState === WebSocket.CONNECTING) {
        console.warn('[WS] Connect timeout');
        socket.close();
      }
    }, 5000);

    socket.onopen = () => {
      clearTimeout(timeout);
      console.log('[WS] Connected');
      reconnectAttempts = 0;
      clearTimeout(reconnectTimer);
      emit('_connected');
    };

    socket.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        emit(msg.event, msg.data);
      } catch (e) {
        console.error('[WS] Parse error:', e);
      }
    };

    socket.onclose = () => {
      clearTimeout(timeout);
      socket = null;
      emit('_disconnected');
      scheduleReconnect();
    };

    socket.onerror = () => {
      clearTimeout(timeout);
    };
  }

  function scheduleReconnect() {
    reconnectAttempts++;
    // After 3 failures, switch to polling.
    if (reconnectAttempts >= 3) {
      console.log('[WS] Switching to polling after', reconnectAttempts, 'failures');
      startPolling();
      return;
    }
    const delay = Math.min(1000 * Math.pow(2, reconnectAttempts - 1), 8000);
    clearTimeout(reconnectTimer);
    reconnectTimer = setTimeout(connectWs, delay);
  }

  // --- HTTP Polling ---

  function startPolling() {
    if (usePolling) return;
    usePolling = true;

    const token = localStorage.getItem('cp_session_token');
    if (token) {
      console.log('[Poll] Using existing session');
      // Signal connected + auth restored.
      emit('_connected');
      emit('auth:success', { message: 'Session restored' });
      // Fetch initial state (devices, clipboard, transfers) then start polling.
      fetchInitialState(token).then(() => beginPollLoop());
    } else {
      console.log('[Poll] No token — starting HTTP auth');
      pollAuth();
    }
  }

  async function pollAuth() {
    try {
      const name = (typeof App !== 'undefined' && App.getDeviceName)
        ? App.getDeviceName() : 'Mobile Browser';

      const resp = await fetch('/api/auth/start', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name }),
      });
      const data = await resp.json();

      localStorage.setItem('cp_poll_auth_token', data.authToken);
      localStorage.setItem('cp_poll_nonce', data.nonce);

      emit('auth:challenge', { nonce: data.nonce, polling: true });
    } catch (e) {
      console.error('[Poll] Auth start failed:', e);
      setTimeout(pollAuth, 3000);
    }
  }

  async function fetchInitialState(token) {
    try {
      const resp = await fetch(`/api/init?token=${encodeURIComponent(token)}`);
      if (!resp.ok) {
        if (resp.status === 401) {
          localStorage.removeItem('cp_session_token');
          emit('auth:revoked', { reason: 'expired' });
          return;
        }
        return;
      }
      const data = await resp.json();

      // Emit device list.
      if (data.devices) {
        emit('device:list', { devices: data.devices, webClients: data.webClients || 0 });
      }
      // Emit clipboard history.
      if (data.clipboardHistory && data.clipboardHistory.length > 0) {
        emit('clipboard:history', { items: data.clipboardHistory });
      }
      // Emit transfer history.
      if (data.transferHistory && data.transferHistory.length > 0) {
        emit('transfer:history', { items: data.transferHistory });
      }
    } catch (e) {
      console.error('[Poll] Failed to fetch initial state:', e);
    }
  }

  function beginPollLoop() {
    if (pollInterval) return;
    // Immediate first poll, then interval.
    pollMessages();
    pollInterval = setInterval(pollMessages, POLL_INTERVAL_MS);
  }

  async function pollMessages() {
    const token = localStorage.getItem('cp_session_token');
    if (!token) return;

    try {
      const resp = await fetch(`/api/poll?token=${encodeURIComponent(token)}`);
      if (resp.status === 401) {
        console.warn('[Poll] Unauthorized — session expired');
        stopPolling();
        localStorage.removeItem('cp_session_token');
        emit('auth:revoked', { reason: 'expired' });
        return;
      }
      const messages = await resp.json();
      for (const msg of messages) {
        emit(msg.event, msg.data);
      }
    } catch (_) {
      // Network hiccup — will retry next interval.
    }
  }

  function stopPolling() {
    if (pollInterval) {
      clearInterval(pollInterval);
      pollInterval = null;
    }
    usePolling = false;
  }

  // --- Send ---

  function send(event, data) {
    if (usePolling) {
      const token = localStorage.getItem('cp_session_token');
      if (!token) return false;
      fetch(`/api/send?token=${encodeURIComponent(token)}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ event, data }),
      }).catch(e => console.error('[Poll] Send failed:', e));
      return true;
    }

    if (!socket || socket.readyState !== WebSocket.OPEN) return false;
    socket.send(JSON.stringify({ event, data }));
    return true;
  }

  // --- Event system ---

  function on(event, callback) {
    if (!listeners[event]) listeners[event] = [];
    listeners[event].push(callback);
  }

  function emit(event, data) {
    (listeners[event] || []).forEach(cb => cb(data));
  }

  function disconnect() {
    clearTimeout(reconnectTimer);
    reconnectAttempts = 0;
    stopPolling();
    if (socket) { socket.close(); socket = null; }
  }

  function isPolling() { return usePolling; }

  /// Called after fresh poll auth to start the poll loop + fetch initial data.
  function onPollAuthenticated() {
    if (!usePolling) return;
    const token = localStorage.getItem('cp_session_token');
    if (token) {
      fetchInitialState(token).then(() => beginPollLoop());
    }
  }

  return { connect, send, on, disconnect, isPolling, onPollAuthenticated };
})();
