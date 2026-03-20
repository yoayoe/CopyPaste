/**
 * WebSocket connection manager.
 * Handles connection, reconnection, and message routing.
 */
const WS = (() => {
  let socket = null;
  let reconnectTimer = null;
  const listeners = {};

  function getWsUrl() {
    const params = new URLSearchParams(window.location.search);
    const token = params.get('token') || '';
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    return `${protocol}//${window.location.host}/ws?token=${token}`;
  }

  function connect() {
    if (socket && socket.readyState === WebSocket.OPEN) return;

    const url = getWsUrl();
    socket = new WebSocket(url);

    socket.onopen = () => {
      console.log('[WS] Connected to', url);
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

    socket.onclose = (event) => {
      console.log('[WS] Disconnected, code:', event.code, 'reason:', event.reason);
      emit('_disconnected');
      scheduleReconnect();
    };

    socket.onerror = (err) => {
      console.error('[WS] Error:', err);
      emit('_error', url || '');
    };
  }

  function scheduleReconnect() {
    clearTimeout(reconnectTimer);
    reconnectTimer = setTimeout(() => {
      console.log('[WS] Reconnecting...');
      connect();
    }, 3000);
  }

  function send(event, data) {
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      console.warn('[WS] Not connected, cannot send:', event);
      return false;
    }
    socket.send(JSON.stringify({ event, data }));
    return true;
  }

  function on(event, callback) {
    if (!listeners[event]) listeners[event] = [];
    listeners[event].push(callback);
  }

  function emit(event, data) {
    (listeners[event] || []).forEach(cb => cb(data));
  }

  function disconnect() {
    clearTimeout(reconnectTimer);
    if (socket) {
      socket.close();
      socket = null;
    }
  }

  return { connect, send, on, disconnect };
})();
