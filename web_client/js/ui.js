/**
 * UI rendering and DOM helpers.
 */
const UI = (() => {
  function initTabs() {
    document.querySelectorAll('.tab').forEach(tab => {
      tab.addEventListener('click', () => {
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
        tab.classList.add('active');
        const target = document.getElementById(`tab-${tab.dataset.tab}`);
        if (target) target.classList.add('active');
      });
    });
  }

  function setConnectionStatus(connected) {
    const el = document.getElementById('connection-status');
    el.textContent = connected ? 'Connected' : 'Disconnected';
    el.className = `status ${connected ? 'connected' : 'disconnected'}`;
  }

  function showPinOverlay() {
    const overlay = document.getElementById('pin-overlay');
    overlay.classList.add('visible');
    const input = document.getElementById('pin-input');
    input.value = '';
    input.focus();
    document.getElementById('pin-error').textContent = '';

    // Set status to show we're waiting for PIN.
    const el = document.getElementById('connection-status');
    el.textContent = 'PIN Required';
    el.className = 'status disconnected';
  }

  function hidePinOverlay() {
    const overlay = document.getElementById('pin-overlay');
    overlay.classList.remove('visible');
  }

  function setPinError(message) {
    const el = document.getElementById('pin-error');
    el.textContent = message;
    // Shake the input.
    const input = document.getElementById('pin-input');
    input.classList.add('shake');
    setTimeout(() => input.classList.remove('shake'), 500);
    input.value = '';
    input.focus();
  }

  function renderClipboardHistory(items) {
    const container = document.getElementById('clipboard-history');

    if (!items || items.length === 0) {
      container.innerHTML = '<p class="empty-state">No clipboard history yet</p>';
      return;
    }

    container.innerHTML = items.map(item => `
      <div class="history-item" data-id="${item.id}">
        <div class="content">${escapeHtml(item.content)}</div>
        <div class="meta">
          <span>${item.sourceDeviceName || 'This device'} &middot; ${timeAgo(item.timestamp)}</span>
          <button class="copy-btn" onclick="App.copyItem('${item.id}')">Copy</button>
        </div>
      </div>
    `).join('');
  }

  function renderDeviceList(devices) {
    const container = document.getElementById('device-list');

    if (!devices || devices.length === 0) {
      container.innerHTML = '<p class="empty-state">No devices connected</p>';
      return;
    }

    container.innerHTML = devices.map(device => `
      <div class="device-item">
        <span class="icon">${platformIcon(device.platform)}</span>
        <div class="info">
          <div class="name">${escapeHtml(device.name)}</div>
          <div class="detail">${device.platform} &middot; ${device.ip}</div>
        </div>
      </div>
    `).join('');
  }

  function renderTransferList(transfers) {
    const container = document.getElementById('transfer-list');

    if (!transfers || transfers.length === 0) {
      container.innerHTML = '<p class="empty-state">No transfers yet</p>';
      return;
    }

    container.innerHTML = transfers.map(t => {
      const hasDownload = t.downloadId && t.status === 'completed';
      const statusLabel = t.status === 'inProgress' ? 'Transferring...'
        : t.status === 'completed' ? '✓ Completed'
        : t.status === 'failed' ? '✗ Failed'
        : t.status;

      return `
      <div class="history-item">
        <div class="content">${escapeHtml(t.filename)}${t.totalBytes ? ' (' + formatSize(t.totalBytes) + ')' : ''}</div>
        <div class="meta">
          <span>${t.direction === 'send' ? 'Sent to' : 'From'} ${escapeHtml(t.deviceName || 'Desktop')}</span>
          <span>${statusLabel}</span>
        </div>
        ${t.status === 'inProgress' ? `
          <div class="progress-bar">
            <div class="fill" style="width: ${((t.progress || 0) * 100).toFixed(1)}%"></div>
          </div>
        ` : ''}
        ${hasDownload ? `
          <button class="btn primary download-btn" onclick="App.downloadFile('${t.downloadId}', '${escapeHtml(t.filename)}')">
            Download
          </button>
        ` : ''}
      </div>`;
    }).join('');
  }

  function toast(message) {
    let el = document.querySelector('.toast');
    if (!el) {
      el = document.createElement('div');
      el.className = 'toast';
      document.body.appendChild(el);
    }
    el.textContent = message;
    el.classList.add('show');
    setTimeout(() => el.classList.remove('show'), 2000);
  }

  // Helpers

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  function timeAgo(timestamp) {
    const seconds = Math.floor((Date.now() - timestamp) / 1000);
    if (seconds < 60) return 'just now';
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
    return `${Math.floor(seconds / 86400)}d ago`;
  }

  function platformIcon(platform) {
    const icons = { macos: '💻', linux: '🖥️', windows: '🪟' };
    return icons[platform] || '📱';
  }

  function formatSize(bytes) {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(1)} MB`;
    return `${(bytes / 1073741824).toFixed(1)} GB`;
  }

  return {
    initTabs,
    setConnectionStatus,
    showPinOverlay,
    hidePinOverlay,
    setPinError,
    renderClipboardHistory,
    renderDeviceList,
    renderTransferList,
    toast,
  };
})();
