// sw.js — muss im Wurzelverzeichnis neben index.html liegen
// (gleiche Ebene, damit der Scope die ganze App abdeckt)

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
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
