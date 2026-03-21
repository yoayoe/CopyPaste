/**
 * Authentication module.
 * Handles PIN-based auth via WebSocket or HTTP polling fallback.
 */
const Auth = (() => {
  let _nonce = null;
  let _authenticated = false;
  let _isPollingAuth = false;

  /**
   * Compute HMAC-SHA256(nonce, pin) matching the server's verification.
   * Uses Web Crypto API on secure contexts (HTTPS/localhost).
   */
  async function computeHmac(pin, nonce) {
    if (window.crypto && window.crypto.subtle) {
      try {
        const encoder = new TextEncoder();
        const key = await crypto.subtle.importKey(
          'raw', encoder.encode(pin), { name: 'HMAC', hash: 'SHA-256' },
          false, ['sign']
        );
        const sig = await crypto.subtle.sign('HMAC', key, encoder.encode(nonce));
        return btoa(String.fromCharCode(...new Uint8Array(sig)));
      } catch (e) {
        console.warn('[Auth] crypto.subtle HMAC failed:', e);
      }
    }
    return null;
  }

  /**
   * Handle auth:challenge from server (WebSocket or polling).
   */
  function handleChallenge(data) {
    _nonce = data.nonce;
    _authenticated = false;
    _isPollingAuth = !!data.polling;
    UI.showPinOverlay();
    console.log('[Auth] Challenge received' + (_isPollingAuth ? ' (polling mode)' : ''));
  }

  /**
   * Submit PIN entered by user.
   */
  async function submitPin(pin) {
    if (!_nonce) {
      UI.toast('No auth challenge received');
      return;
    }

    console.log('[Auth] Submitting PIN verification...');

    if (_isPollingAuth) {
      // Polling mode — verify via HTTP POST.
      await submitPinViaPoll(pin);
    } else {
      // WebSocket mode.
      const hmac = await computeHmac(pin, _nonce);
      if (hmac) {
        WS.send('auth:verify', { hmac: hmac });
      } else {
        WS.send('auth:verify', { pin: pin });
      }
    }
  }

  /**
   * Submit PIN via HTTP polling auth endpoint.
   */
  async function submitPinViaPoll(pin) {
    const authToken = localStorage.getItem('cp_poll_auth_token');
    if (!authToken) {
      UI.setPinError('Auth session expired — please refresh');
      return;
    }

    try {
      const hmac = await computeHmac(pin, _nonce);
      const body = { authToken };
      if (hmac) {
        body.hmac = hmac;
      } else {
        body.pin = pin;
      }

      const resp = await fetch('/api/auth/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });

      const data = await resp.json();

      if (data.error) {
        UI.setPinError(data.error);
        return;
      }

      if (data.sessionToken) {
        localStorage.setItem('cp_session_token', data.sessionToken);
        localStorage.removeItem('cp_poll_auth_token');
        localStorage.removeItem('cp_poll_nonce');
        handleSuccess({ sessionToken: data.sessionToken, message: 'Authenticated (polling)' });
        // Start poll loop + fetch initial data now that we have a token.
        WS.onPollAuthenticated();
      }
    } catch (e) {
      console.error('[Auth] Poll verify failed:', e);
      UI.setPinError('Verification failed — try again');
    }
  }

  /**
   * Handle auth:success from server.
   */
  function handleSuccess(data) {
    _authenticated = true;
    _nonce = null;
    _isPollingAuth = false;

    if (data && data.sessionToken) {
      localStorage.setItem('cp_session_token', data.sessionToken);
      console.log('[Auth] Session token saved');
    }

    UI.hidePinOverlay();
    UI.setConnectionStatus(true);
    UI.toast(WS.isPolling() ? 'Connected (polling)' : 'Authenticated!');
    console.log('[Auth] Authenticated successfully' + (WS.isPolling() ? ' (polling)' : ''));
  }

  /**
   * Handle auth:failed from server.
   */
  function handleFailed(data) {
    console.log('[Auth] Failed:', data.message);
    UI.setPinError(data.message || 'Invalid PIN');
  }

  /**
   * Handle auth:revoked from server.
   */
  function handleRevoked(data) {
    const reason = data.reason || 'revoked';
    console.log('[Auth] Session revoked:', reason);
    _authenticated = false;
    _nonce = null;
    localStorage.removeItem('cp_session_token');

    if (reason === 'expired') {
      UI.toast('Session expired — please re-enter PIN');
    } else if (reason === 'max_sessions') {
      UI.toast('Too many sessions — disconnected');
    } else {
      UI.toast('Disconnected by desktop');
    }

    UI.showPinOverlay();
    UI.setConnectionStatus(false);
  }

  function isAuthenticated() {
    return _authenticated;
  }

  return { handleChallenge, submitPin, handleSuccess, handleFailed, handleRevoked, isAuthenticated };
})();
