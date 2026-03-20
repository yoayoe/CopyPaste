/**
 * Authentication module.
 * Handles PIN-based auth challenge/response with HMAC-SHA256.
 */
const Auth = (() => {
  let _nonce = null;
  let _authenticated = false;

  /**
   * Compute HMAC-SHA256(key=PIN, data=nonce) and return base64 string.
   */
  async function computeHmac(pin, nonce) {
    const encoder = new TextEncoder();
    const keyData = encoder.encode(pin);
    const nonceData = encoder.encode(nonce);

    const key = await crypto.subtle.importKey(
      'raw', keyData, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
    );

    const signature = await crypto.subtle.sign('HMAC', key, nonceData);
    return btoa(String.fromCharCode(...new Uint8Array(signature)));
  }

  /**
   * Handle auth:challenge from server. Store nonce and show PIN UI.
   */
  function handleChallenge(data) {
    _nonce = data.nonce;
    _authenticated = false;
    UI.showPinOverlay();
  }

  /**
   * Submit PIN entered by user.
   */
  async function submitPin(pin) {
    if (!_nonce) {
      UI.toast('No auth challenge received');
      return;
    }

    const hmac = await computeHmac(pin, _nonce);
    WS.send('auth:verify', { hmac: hmac });
  }

  /**
   * Handle auth:success from server.
   */
  function handleSuccess() {
    _authenticated = true;
    _nonce = null;
    UI.hidePinOverlay();
    UI.setConnectionStatus(true);
    UI.toast('Authenticated!');
  }

  /**
   * Handle auth:failed from server.
   */
  function handleFailed(data) {
    UI.setPinError(data.message || 'Invalid PIN');
  }

  function isAuthenticated() {
    return _authenticated;
  }

  return { handleChallenge, submitPin, handleSuccess, handleFailed, isAuthenticated };
})();
