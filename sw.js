const CACHE = 'tunnel-status-v1';

// Assets to pre-cache on install
const PRECACHE = [
  '/',
  '/index.html',
  '/admin.html',
  'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;600;700&display=swap'
];

// ── Install: pre-cache shell ──────────────────────────────────────────────
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE).then(cache =>
      cache.addAll(PRECACHE).catch(() => {
        // Non-fatal: Google Fonts may be blocked in some environments
      })
    ).then(() => self.skipWaiting())
  );
});

// ── Activate: purge old caches ────────────────────────────────────────────
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// ── Fetch strategy ────────────────────────────────────────────────────────
self.addEventListener('fetch', event => {
  const { request } = event;
  const url = new URL(request.url);

  // Never intercept tunnel health-check fetches (no-cors, external hosts)
  if (request.mode === 'no-cors') return;

  // tunnel-config.json: network-first, fall back to cache
  if (url.pathname.includes('tunnel-config.json')) {
    event.respondWith(networkFirst(request));
    return;
  }

  // HTML pages: network-first so updates are picked up immediately
  if (request.destination === 'document') {
    event.respondWith(networkFirst(request));
    return;
  }

  // Fonts & static assets: cache-first
  if (
    request.destination === 'font' ||
    request.destination === 'style' ||
    url.hostname === 'fonts.googleapis.com' ||
    url.hostname === 'fonts.gstatic.com'
  ) {
    event.respondWith(cacheFirst(request));
    return;
  }

  // Everything else: network-first
  event.respondWith(networkFirst(request));
});

// ── Helpers ───────────────────────────────────────────────────────────────
async function networkFirst(request) {
  const cache = await caches.open(CACHE);
  try {
    const response = await fetch(request);
    if (response.ok || response.type === 'opaque') {
      cache.put(request, response.clone());
    }
    return response;
  } catch {
    const cached = await cache.match(request);
    if (cached) return cached;
    // Offline fallback for navigation
    if (request.destination === 'document') {
      return cache.match('/index.html');
    }
    return new Response('Offline', { status: 503, statusText: 'Service Unavailable' });
  }
}

async function cacheFirst(request) {
  const cache = await caches.open(CACHE);
  const cached = await cache.match(request);
  if (cached) return cached;
  try {
    const response = await fetch(request);
    if (response.ok) cache.put(request, response.clone());
    return response;
  } catch {
    return new Response('Offline', { status: 503, statusText: 'Service Unavailable' });
  }
}

// ── Background Sync: recheck tunnel when connectivity restores ────────────
self.addEventListener('sync', event => {
  if (event.tag === 'tunnel-check') {
    event.waitUntil(
      self.clients.matchAll().then(clients =>
        clients.forEach(client => client.postMessage({ type: 'SYNC_CHECK' }))
      )
    );
  }
});
