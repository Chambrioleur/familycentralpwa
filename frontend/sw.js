// sw.js — muss im Wurzelverzeichnis neben index.html liegen
// (gleiche Ebene, damit der Scope die ganze App abdeckt)

const CDN_CACHE = "fz-cdn-v2";

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CDN_CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// Cache-first, aber NUR für die vier Top-Level-Bibliotheken aus der
// Importmap (jeweils mit exakter Version in der URL, also für immer
// unveränderlich). Bewusst NICHT für jeden esm.sh-Request: esm.sh lädt
// dahinter noch eigene, transitive Sub-Requests nach (Node-Polyfills wie
// process.mjs/buffer.mjs, weitere Pakete mit Versions-Ranges statt fixer
// Version) — die lassen sich in Safari/WebKit nicht zuverlässig innerhalb
// eines Service Workers erneut abfeuern und rissen sonst die komplette
// Modul-Ladekette ab (weiße Seite). Ein try/catch mit Netzwerk-Fallback
// stellt zusätzlich sicher, dass ein Cache-Fehler nie die App blockiert.
const CDN_URLS = new Set([
  "https://esm.sh/react@18.3.1",
  "https://esm.sh/react-dom@18.3.1/client",
  "https://esm.sh/react@18.3.1/jsx-runtime",
  "https://esm.sh/@supabase/supabase-js@2.111.0",
  "https://esm.sh/lucide-react@0.383.0?external=react",
]);

self.addEventListener("fetch", (event) => {
  if (!CDN_URLS.has(event.request.url)) return;

  event.respondWith(
    (async () => {
      try {
        const cache = await caches.open(CDN_CACHE);
        const cached = await cache.match(event.request);
        if (cached) return cached;
        const response = await fetch(event.request);
        if (response.ok) cache.put(event.request, response.clone());
        return response;
      } catch (err) {
        return fetch(event.request);
      }
    })()
  );
});

self.addEventListener("push", (event) => {
  let data = { title: "Familienzentrale", body: "Es gibt etwas Neues." };
  try {
    if (event.data) data = event.data.json();
  } catch (e) {
    // Fallback auf Standardtext, falls die Nutzlast kein JSON ist
  }

  event.waitUntil(
    self.registration.showNotification(data.title || "Familienzentrale", {
      body: data.body || "",
      icon: data.icon || undefined,
      badge: data.badge || undefined,
      data: { url: data.url || "/" },
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = event.notification.data?.url || "/";
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        if ("focus" in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow(url);
    })
  );
});
