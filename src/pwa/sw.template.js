/* Mimi Locks service worker (generated at build time from src/pwa/sw.template.js).
 *  - The app shell and every built file are precached, so the installed app
 *    opens instantly and even offline.
 *  - Pages: network first, falling back to the cached shell when offline.
 *  - Built assets (hashed, never change): cache first.
 *  - Icons, manifest, Google Fonts: stale-while-revalidate.
 *  - Pictures from other sites (uploads, avatars): the last 200 are kept so
 *    they still show offline.
 *  - Everything else (Firebase, uploads, APIs) goes straight to the network.
 * A new version waits until every open window is closed, then replaces the
 * old caches — so a running session never loses the files it was built with. */
const VERSION = "__VERSION__";
const SHELL = `mimi-shell-${VERSION}`;
const RUNTIME = "mimi-runtime";
const IMAGES = "mimi-images";
const MAX_IMAGES = 200;
const PRECACHE = __PRECACHE__;

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(SHELL).then((cache) => cache.addAll(PRECACHE)));
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((k) => k.startsWith("mimi-shell-") && k !== SHELL).map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener("message", (event) => {
  if (event.data === "skip-waiting") self.skipWaiting();
});

const FONT_HOSTS = ["fonts.googleapis.com", "fonts.gstatic.com"];

async function staleWhileRevalidate(request) {
  const cache = await caches.open(RUNTIME);
  const cached = await cache.match(request);
  const network = fetch(request).then((res) => {
    if (res && (res.ok || res.type === "opaque")) cache.put(request, res.clone());
    return res;
  }).catch(() => cached);
  return cached || network;
}

async function cachedImage(request) {
  const cache = await caches.open(IMAGES);
  const hit = await cache.match(request);
  if (hit) return hit;
  const res = await fetch(request);
  if (res && (res.ok || res.type === "opaque")) {
    await cache.put(request, res.clone());
    const keys = await cache.keys();
    for (const old of keys.slice(0, Math.max(0, keys.length - MAX_IMAGES))) await cache.delete(old);
  }
  return res;
}

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;
  const url = new URL(request.url);

  if (request.destination === "image" && url.origin !== self.location.origin && url.protocol === "https:") {
    event.respondWith(cachedImage(request).catch(() => Response.error()));
    return;
  }

  if (FONT_HOSTS.includes(url.hostname)) { event.respondWith(staleWhileRevalidate(request)); return; }
  if (url.origin !== self.location.origin || url.pathname.startsWith("/__/")) return;

  if (request.mode === "navigate") {
    event.respondWith((async () => {
      try {
        return await fetch(request);
      } catch {
        return (await caches.match("/index.html")) || (await caches.match("/")) || Response.error();
      }
    })());
    return;
  }

  if (url.pathname.startsWith("/assets/")) {
    event.respondWith(caches.match(request).then((hit) => hit || fetch(request).then((res) => {
      if (res.ok) caches.open(SHELL).then((c) => c.put(request, res.clone()));
      return res;
    })));
    return;
  }

  event.respondWith(staleWhileRevalidate(request));
});
