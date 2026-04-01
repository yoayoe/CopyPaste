// Minimal service worker — enables PWA installability.
// Uses network-first: always fetch live data, no offline caching
// (app requires local network connection to the desktop).

const CACHE = 'copypaste-v1';
const STATIC = ['/', '/css/style.css', '/js/app.js', '/js/auth.js',
  '/js/clipboard.js', '/js/transfer.js', '/js/ui.js', '/js/websocket.js'];

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
  // Always go to network; fall back to cache for static assets only.
  e.respondWith(
    fetch(e.request).catch(() => caches.match(e.request))
  );
});
