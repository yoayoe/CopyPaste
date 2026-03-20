/**
 * Browser clipboard read/write operations.
 */
const Clip = (() => {
  async function read() {
    try {
      const text = await navigator.clipboard.readText();
      return text;
    } catch (e) {
      console.warn('[Clip] Read failed (needs user gesture):', e.message);
      return null;
    }
  }

  async function write(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (e) {
      // Fallback for older browsers.
      return fallbackCopy(text);
    }
  }

  function fallbackCopy(text) {
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);
    textarea.select();
    try {
      document.execCommand('copy');
      return true;
    } catch (e) {
      return false;
    } finally {
      document.body.removeChild(textarea);
    }
  }

  return { read, write };
})();
