// PWA Service Worker for Türkiye Yüzme Sonuçları
const CACHE_NAME = 'swim-portal-v1';
const STATIC_ASSETS = [
  '/',
  '/static/css/styles.css',
  '/static/js/swim-ui.js',
  '/static/manifest.json',
  '/static/icons/icon-192.png',
  '/static/icons/icon.svg'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(STATIC_ASSETS).catch((err) => console.log('SW pre-cache skip:', err));
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      );
    })
  );
  self.clients.claim();
});

// Network-first strategy for dynamic data, falling back to cache if offline
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  
  // For static assets: cache-first
  const url = new URL(event.request.url);
  if (url.pathname.startsWith('/static/')) {
    event.respondWith(
      caches.match(event.request).then((cached) => {
        return cached || fetch(event.request).then((res) => {
          if (res.status === 200) {
            const clone = res.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          }
          return res;
        });
      })
    );
    return;
  }

  // For pages: network-first
  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});

