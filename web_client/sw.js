// Minimal service worker — enables PWA installability.
// JS files are NOT cached: they change frequently and the app requires a live
// connection to the desktop anyway, so stale JS would only cause bugs.

const CACHE = 'copypaste-v3';
// Only cache the shell (HTML + CSS). JS always fetched live from desktop.
const STATIC = ['/', '/css/style.css'];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(STATIC)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);

  // Never intercept API or WebSocket upgrade requests.
  if (url.pathname.startsWith('/api/') || url.pathname === '/ws') return;

  // JS files: always go straight to network (no SW interception).
  if (url.pathname.startsWith('/js/')) return;

  // HTML + CSS: network-first, fall back to cache for offline shell.
  e.respondWith(
    fetch(e.request).catch(() => caches.match(e.request))
  );
});
