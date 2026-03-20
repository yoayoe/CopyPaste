/**
 * Authentication module.
 * Handles PIN-based auth with the desktop server.
 *
 * Note: Web Crypto API (crypto.subtle) is unavailable on non-HTTPS origins,
 * so we use a simple hash approach that works everywhere.
 */
const Auth = (() => {
  let _nonce = null;
  let _authenticated = false;

  /**
   * Simple hash: SHA-256 via crypto.subtle if available, otherwise basic hash.
   */
  async function hashPinNonce(pin, nonce) {
    const input = pin + ':' + nonce;

    // Try Web Crypto API first (works on HTTPS/localhost).
    if (window.crypto && window.crypto.subtle) {
      try {
        const encoder = new TextEncoder();
        const data = encoder.encode(input);
        const hashBuffer = await crypto.subtle.digest('SHA-256', data);
        return btoa(String.fromCharCode(...new Uint8Array(hashBuffer)));
      } catch (e) {
        console.warn('[Auth] crypto.subtle failed, using fallback:', e);
      }
    }

    // Fallback: simple string hash (works on HTTP).
    return simpleHash(input);
  }

  /**
   * Simple deterministic hash for non-secure contexts.
   */
  function simpleHash(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash + char) | 0;
    }
    // Combine with a more thorough mixing.
    let h1 = 0xdeadbeef, h2 = 0x41c6ce57;
    for (let i = 0; i < str.length; i++) {
      const ch = str.charCodeAt(i);
      h1 = Math.imul(h1 ^ ch, 2654435761);
      h2 = Math.imul(h2 ^ ch, 1597334677);
    }
    h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507);
    h1 ^= Math.imul(h2 ^ (h2 >>> 13), 3266489909);
    h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507);
    h2 ^= Math.imul(h1 ^ (h1 >>> 13), 3266489909);
    const combined = 4294967296 * (2097151 & h2) + (h1 >>> 0);
    return btoa(combined.toString(36) + ':' + hash.toString(36));
  }

  /**
   * Handle auth:challenge from server.
   */
  function handleChallenge(data) {
    _nonce = data.nonce;
    _authenticated = false;
    UI.showPinOverlay();
    console.log('[Auth] Challenge received, showing PIN input');
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
    const hash = await hashPinNonce(pin, _nonce);
    WS.send('auth:verify', { pin: pin, hash: hash });
  }

  /**
   * Handle auth:success from server.
   */
  function handleSuccess(data) {
    _authenticated = true;
    _nonce = null;

    // Save session token for reconnect/refresh.
    if (data && data.sessionToken) {
      localStorage.setItem('cp_session_token', data.sessionToken);
      console.log('[Auth] Session token saved');
    }

    UI.hidePinOverlay();
    UI.setConnectionStatus(true);
    UI.toast('Authenticated!');
    console.log('[Auth] Authenticated successfully');
  }

  /**
   * Handle auth:failed from server.
   */
  function handleFailed(data) {
    console.log('[Auth] Failed:', data.message);
    UI.setPinError(data.message || 'Invalid PIN');
  }

  /**
   * Handle auth:revoked from server (disconnected or expired).
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
