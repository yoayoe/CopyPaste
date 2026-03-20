/**
 * Main application logic — wires WebSocket events to UI.
 */
const App = (() => {
  let clipboardHistory = [];
  let devices = [];
  let transfers = [];

  function init() {
    UI.initTabs();

    // Connect WebSocket.
    WS.connect();

    // Connection events.
    WS.on('_connected', () => {
      // Don't set connected status yet — wait for auth.
      // Send device info to server (allowed before auth).
      WS.send('device:info', {
        name: getDeviceName(),
        userAgent: navigator.userAgent,
        platform: navigator.platform,
      });
    });
    WS.on('_disconnected', () => UI.setConnectionStatus(false));
    WS.on('_error', (url) => {
      UI.toast('Connection failed');
      // Show debug info.
      const bar = document.getElementById('debug-bar');
      if (bar) {
        bar.style.display = 'block';
        bar.textContent = 'WS: ' + url + ' | UA: ' + navigator.userAgent.substring(0, 60) + '...';
      }
    });

    // Auth events.
    WS.on('auth:challenge', (data) => Auth.handleChallenge(data));
    WS.on('auth:success', (data) => Auth.handleSuccess(data));
    WS.on('auth:failed', (data) => Auth.handleFailed(data));
    WS.on('auth:required', () => UI.toast('Please enter PIN first'));

    // Clipboard events from desktop.
    WS.on('clipboard:update', (data) => {
      clipboardHistory.unshift(data);
      if (clipboardHistory.length > 50) clipboardHistory.pop();
      UI.renderClipboardHistory(clipboardHistory);
      UI.toast('New clipboard from ' + (data.sourceDeviceName || 'desktop'));
    });

    WS.on('clipboard:history', (data) => {
      clipboardHistory = data.items || [];
      UI.renderClipboardHistory(clipboardHistory);
    });

    // Device events.
    WS.on('device:list', (data) => {
      devices = data.devices || [];
      UI.renderDeviceList(devices);
    });

    WS.on('device:connected', (data) => {
      devices = devices.filter(d => d.id !== data.id);
      devices.push(data);
      UI.renderDeviceList(devices);
    });

    WS.on('device:disconnected', (data) => {
      devices = devices.filter(d => d.id !== data.id);
      UI.renderDeviceList(devices);
    });

    // Transfer events.
    WS.on('transfer:incoming', (data) => {
      if (confirm(`Receive "${data.filename}" (${formatSize(data.size)}) from ${data.deviceName}?`)) {
        WS.send('transfer:accept', { id: data.id });
      } else {
        WS.send('transfer:reject', { id: data.id });
      }
    });

    WS.on('transfer:progress', (data) => {
      const idx = transfers.findIndex(t => t.id === data.id);
      if (idx >= 0) {
        transfers[idx] = { ...transfers[idx], ...data };
      } else {
        transfers.unshift(data);
      }
      UI.renderTransferList(transfers);
    });

    WS.on('transfer:complete', (data) => {
      const idx = transfers.findIndex(t => t.id === data.id);
      if (idx >= 0) {
        transfers[idx] = { ...transfers[idx], ...data, status: 'completed' };
      } else {
        // New file from desktop — add to transfer list.
        transfers.unshift({
          id: data.id,
          filename: data.filename,
          totalBytes: data.size || 0,
          progress: 1,
          status: 'completed',
          direction: 'receive',
          deviceName: data.deviceName || 'Desktop',
          downloadId: data.downloadId || data.id,
        });
      }
      UI.renderTransferList(transfers);

      // Show toast notification.
      if (data.filename) {
        UI.toast(`File available: ${data.filename}`);
      }
    });

    // UI button handlers.
    document.getElementById('btn-send').addEventListener('click', sendClipboard);
    document.getElementById('btn-read-clipboard').addEventListener('click', readClipboard);
    document.getElementById('btn-pick-file').addEventListener('click', pickFile);
    document.getElementById('file-input').addEventListener('change', handleFileSelected);

    // PIN verification handlers.
    document.getElementById('btn-verify-pin').addEventListener('click', verifyPin);
    document.getElementById('pin-input').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') verifyPin();
    });
  }

  function verifyPin() {
    const input = document.getElementById('pin-input');
    const pin = input.value.trim();
    if (pin.length !== 6) {
      UI.setPinError('PIN must be 6 digits');
      return;
    }
    Auth.submitPin(pin);
  }

  async function sendClipboard() {
    const input = document.getElementById('clip-input');
    const text = input.value.trim();
    if (!text) {
      UI.toast('Nothing to send');
      return;
    }

    const sent = WS.send('clipboard:send', {
      type: 'text',
      content: text,
      timestamp: Date.now(),
    });

    if (sent) {
      input.value = '';
      UI.toast('Sent to desktop');
    } else {
      UI.toast('Not connected');
    }
  }

  async function readClipboard() {
    const text = await Clip.read();
    if (text) {
      document.getElementById('clip-input').value = text;
    } else {
      UI.toast('Could not read clipboard');
    }
  }

  function pickFile() {
    document.getElementById('file-input').click();
  }

  async function handleFileSelected(event) {
    const files = event.target.files;
    if (!files || files.length === 0) return;

    for (const file of files) {
      const transferId = crypto.randomUUID();
      transfers.unshift({
        id: transferId,
        filename: file.name,
        totalBytes: file.size,
        progress: 0,
        status: 'inProgress',
        direction: 'send',
        deviceName: 'Desktop',
      });
      UI.renderTransferList(transfers);

      try {
        const result = await Transfer.upload(file, (progress) => {
          const idx = transfers.findIndex(t => t.id === transferId);
          if (idx >= 0) {
            transfers[idx].progress = progress;
            UI.renderTransferList(transfers);
          }
        });

        const idx = transfers.findIndex(t => t.id === transferId);
        if (idx >= 0) {
          transfers[idx].status = 'completed';
          // Save downloadId from server response so file can be re-downloaded.
          if (result && result.downloadId) {
            transfers[idx].downloadId = result.downloadId;
          }
        }
        UI.renderTransferList(transfers);
        UI.toast(`Sent: ${file.name}`);
      } catch (e) {
        const idx = transfers.findIndex(t => t.id === transferId);
        if (idx >= 0) transfers[idx].status = 'failed';
        UI.renderTransferList(transfers);
        UI.toast(`Failed: ${file.name}`);
      }
    }

    event.target.value = '';
  }

  function copyItem(id) {
    const item = clipboardHistory.find(i => i.id === id);
    if (item) {
      Clip.write(item.content).then(ok => {
        UI.toast(ok ? 'Copied!' : 'Copy failed');
      });
    }
  }

  function downloadFile(downloadId, filename) {
    Transfer.download(downloadId, filename);
  }

  function formatSize(bytes) {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / 1048576).toFixed(1)} MB`;
  }

  function getDeviceName() {
    const ua = navigator.userAgent;

    // Try to extract device model from UA string.
    // Android: "... Android 13; SM-S901B ..."
    const androidMatch = ua.match(/;\s*([^;)]+)\s+Build\//);
    if (androidMatch) return androidMatch[1].trim();

    // iOS: "... iPhone OS 16_0 ..." or "... iPad ..."
    if (/iPad/.test(ua)) return 'iPad';
    if (/iPhone/.test(ua)) return 'iPhone';

    // Fallback: use platform or generic name.
    if (/Android/.test(ua)) return 'Android Device';
    if (/Mac/.test(ua)) return 'Mac Browser';
    if (/Linux/.test(ua)) return 'Linux Browser';
    if (/Windows/.test(ua)) return 'Windows Browser';

    return 'Mobile Browser';
  }

  // Expose for onclick handlers in HTML.
  return { init, copyItem, downloadFile };
})();

document.addEventListener('DOMContentLoaded', App.init);
