# PWA and Offline

Service workers, caching strategies, offline UX, background sync, push notifications, and
installability for progressive web apps.

## Service Worker Fundamentals

A service worker is a programmable network proxy between the page and the network. Key properties:

- Runs on its own thread; cannot access the DOM. Communicates via `postMessage`.
- **Scope** is the directory it is served from; serve from the root to control the whole origin.
- **Lifecycle**: install -> waiting -> activate. A new worker waits until all controlled clients
  close (or it calls `skipWaiting()`); `clients.claim()` takes control of existing pages.
- **Controlled pages**: the first load after registration is not controlled unless claimed;
  design for this.
- It terminates when idle. Do not keep state only in memory; persist to IndexedDB/Cache Storage.
- Requires HTTPS (localhost exempt). Never register it conditionally on production to "avoid
  caching": test the real thing.

```ts
// sw.ts (compiled/bundled) - install, activate, fetch
const VERSION = "v3";
const PRECACHE = `precache-${VERSION}`;

self.addEventListener("install", (event: ExtendableEvent) => {
  event.waitUntil(
    caches.open(PRECACHE).then((cache) => cache.addAll(["/", "/offline", "/app.css"]))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event: ExtendableEvent) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== PRECACHE).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event: FetchEvent) => {
  if (event.request.mode === "navigate") {
    event.respondWith(
      fetch(event.request).catch(() => caches.match("/offline"))
    );
  }
});
```

## Caching Strategies

| Strategy | Behavior | Use for |
|---|---|---|
| Cache first | Serve cache; network only on miss | Versioned static assets, fonts, offline shells |
| Network first | Network, fall back to cache | API GETs, HTML where freshness matters |
| Stale-while-revalidate | Serve cache immediately, refetch in background | Avatars, lists, non-critical API data |
| Network only | No cache | Auth, payments, real-time |
| Cache only | Never network | Precached offline assets |
| Revalidate on demand | Update cache on a message/sync event | Content after background sync |

Workbox (or framework integrations like `vite-plugin-pwa`, Next PWA plugins) provides these as
declarative route handlers:

```ts
import { registerRoute } from "workbox-routing";
import { CacheFirst, NetworkFirst, StaleWhileRevalidate } from "workbox-strategies";
import { ExpirationPlugin } from "workbox-expiration";

registerRoute(
  ({ request }) => request.destination === "image",
  new CacheFirst({
    cacheName: "images",
    plugins: [new ExpirationPlugin({ maxEntries: 100, maxAgeSeconds: 60 * 60 * 24 * 30 })],
  })
);

registerRoute(
  ({ url }) => url.pathname.startsWith("/api/"),
  new NetworkFirst({ cacheName: "api", networkTimeoutSeconds: 3 })
);
```

Rules:
- **Never cache non-GET** requests automatically; mutations need an explicit offline queue.
- **Never cache opaque cross-origin responses** blindly; they cannot be inspected and can be stale
  forever. Prefer CORS-enabled origins you control.
- Exclude auth endpoints and anything with `Authorization` headers or `Set-Cookie` semantics from
  shared caching.
- Set **expiration limits** on caches; unbounded caches consume user storage and get evicted
  wholesale.
- Version cache names so deploys can invalidate cleanly.

## Precaching and Updates

Precache is an explicit manifest of assets needed for the app shell. Build tooling generates a
revisioned manifest (content hash per file).

- On a new deploy, the new worker installs, precaches the new manifest, then waits. Decide the
  update UX:
  - `skipWaiting()` + `clients.claim()`: fast but can mix old page with new assets; only safe if
    assets are content-hashed and the app tolerates mixed versions.
  - User-prompted refresh ("A new version is available — Reload"): safer for stateful apps.
- Listen for updates and tell the user; do not silently run stale code for days.

```ts
navigator.serviceWorker.register("/sw.js").then((reg) => {
  reg.addEventListener("updatefound", () => {
    const sw = reg.installing;
    sw?.addEventListener("statechange", () => {
      if (sw.state === "installed" && navigator.serviceWorker.controller) {
        showUpdateBanner(() => reg.waiting?.postMessage({ type: "SKIP_WAITING" }));
      }
    });
  });
});
```

- Check for updates on navigation and periodically; browsers may cache `sw.js` for up to 24 hours
  unless `Cache-Control: no-cache` is set on the service worker script itself.

## Offline UX

Offline is a product state, not an error state. Design it:

1. **Detect** — `navigator.onLine` is unreliable; treat fetch failures as the signal. Use
   `online`/`offline` events for UI hints only.
2. **Communicate** — a persistent (but unobtrusive) indicator when offline; explain what still
   works.
3. **Degrade tasks** — reads work from cache; writes queue (see below) or are disabled with a clear
   explanation.
4. **Offline page** — a real page for uncached navigations, with links to what is available and a
   retry action. Never a browser error page.
5. **Reconnect** — flush queued work, refresh stale data, and show a summary of what synced.

Data to keep offline: app shell, recent content the user viewed, drafts, and the outbox of pending
mutations. Conflict resolution must be designed: last-write-wins is often wrong; prefer server
merge or explicit conflict UI for shared data.

## Background Sync and the Outbox Pattern

**Background Sync API** retries a failed request when connectivity returns, even if the page closed
(Chromium-based browsers; support elsewhere is partial — verify upstream and always provide an
in-page fallback).

```ts
// Page: queue the mutation and register sync
async function sendMessage(payload: Message) {
  await idb.outbox.add({ payload, id: crypto.randomUUID(), createdAt: Date.now() });
  const reg = await navigator.serviceWorker.ready;
  await reg.sync.register("outbox");
}

// Service worker: drain the queue when online
self.addEventListener("sync", (event: SyncEvent) => {
  if (event.tag === "outbox") event.waitUntil(flushOutbox());
});

async function flushOutbox() {
  for (const item of await idb.outbox.toArray()) {
    try {
      const res = await fetch("/api/messages", {
        method: "POST",
        body: JSON.stringify(item.payload),
        headers: { "content-type": "application/json" },
      });
      if (res.ok) await idb.outbox.delete(item.id);
      else if (res.status >= 400 && res.status < 500) await idb.outbox.delete(item.id); // poison
    } catch {
      return; // still offline; retry on next sync
    }
  }
  await showSyncedNotice();
}
```

Rules:
- Use **idempotency keys** server-side so retries never duplicate mutations.
- Order the outbox; some payloads depend on earlier ones.
- Distinguish transient failures (retry) from permanent ones (move to a failed tray, tell the user).
- Periodic Background Sync (`periodicsync`) is limited (installed PWAs, Chromium); use for content
  refresh, not mission-critical sync. Verify support.

## Push Notifications

Web Push requires three pieces: a service worker, the Push API, and the Notifications API.

- **Permission UX**: never prompt on page load. Ask after a user action that explains value
  ("Notify me when my order ships"), and honor denial. Repeated prompts are hostile and browsers
  increasingly suppress them.
- **Subscription**: create a `PushSubscription` from `PushManager.subscribe` with your VAPID public
  key, send it to your server, and associate it with the user.
- **Delivery**: your server sends encrypted payloads (RFC 8291) via a push service. Payloads are
  end-to-end encrypted; you need not trust the push service.
- **Handling**: `push` event shows a notification; `notificationclick` focuses/opens the right URL.
- **TTL** and **urgency** headers control delivery; set them deliberately.
- Clean up subscriptions on 404/410 responses from the push service.

```ts
self.addEventListener("push", (event: PushEvent) => {
  const data = event.data?.json() ?? { title: "Update", body: "You have a new update." };
  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: "/icons/192.png",
      data: { url: data.url ?? "/" },
    })
  );
});

self.addEventListener("notificationclick", (event: NotificationEvent) => {
  event.notification.close();
  event.waitUntil(self.clients.openWindow(event.notification.data.url));
});
```

- iOS supports web push for installed PWAs from Safari 16.4+; users must add to Home Screen first.
  Verify current behavior.
- Notifications must be actionable and rare; treat them as a product feature with owners.

## Installability

```json
{
  "name": "Example App",
  "short_name": "Example",
  "start_url": "/?source=pwa",
  "scope": "/",
  "display": "standalone",
  "theme_color": "#0f172a",
  "background_color": "#ffffff",
  "icons": [
    { "src": "/icons/192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "/icons/maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ],
  "shortcuts": [{ "name": "Orders", "url": "/orders" }]
}
```

- Serve a valid `manifest.webmanifest`, linked from every page: `<link rel="manifest" href="/manifest.webmanifest">`.
- Chromium install criteria: manifest with name, icons (192 + 512), `start_url`, `display`, plus a
  controlling service worker with a fetch handler. Verify the current criteria upstream.
- **maskable** icons are required for good Android presentation; test with the mask preview tool.
- Respect `prefers-color-scheme` in splash/background where supported.
- Safari/iOS installs via Share -> Add to Home Screen; `display: standalone` is honored. Web push
  and some capabilities require installation.
- Do not nag users to install; use a dismissible, contextual prompt (e.g. after repeat visits),
  and remember dismissal.

## Storage, Quota, and Eviction

- Cache Storage and IndexedDB are subject to per-origin quota (a share of disk, provider-specific)
  and can be evicted under pressure. Call `navigator.storage.persist()` before promising offline
  permanence; check `navigator.storage.estimate()` for usage.
- Eviction is per-origin, so keep caches small and reproducible. Never store the only copy of
  user-generated data in the browser; always sync to the server.
- `localStorage` is synchronous, tiny, and not available in workers. Use IndexedDB for structured
  offline data.

## Testing

- **Automated**: Playwright supports service workers; test offline by toggling `context.setOffline(true)`.
  Lighthouse PWA checks installability basics.
- **Manual**: DevTools Application panel — verify registrations, cache contents, storage usage, and
  "Update on reload". Test the full offline flow: first visit, kill network, navigate, queue a
  write, reconnect, verify sync.
- Test **upgrades**: deploy v2, verify the update prompt, reload behavior, and that stale caches are
  deleted.
- Test on a real mid-range Android device over throttled network; service worker bugs hide in
  emulators.

## Anti-Patterns

- Caching HTML network-first without a timeout, so slow networks feel broken.
- Precache of the entire site (build and storage waste).
- Silent `skipWaiting` in stateful apps, mixing versions mid-session.
- Caching API responses with auth headers in a shared cache.
- Offline writes with no idempotency keys, creating duplicates on retry.
- Push permission prompts on first load.
- Unbounded caches that get evicted wholesale.
- Claiming "offline support" when only the shell is cached.

## Checklist

- [ ] Service worker served from root over HTTPS with `no-cache` on the script itself.
- [ ] Caching strategy defined per resource class; expiration limits set.
- [ ] Offline page and reconnect UX designed; writes queue with idempotency keys.
- [ ] Update flow exposes new versions and cleans old caches.
- [ ] Manifest valid, maskable icons, install prompt respectful.
- [ ] Push permission contextual; subscriptions cleaned up on failure.
- [ ] Offline, upgrade, and storage-quota paths tested on real devices.
