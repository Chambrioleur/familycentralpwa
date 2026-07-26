// supabase/functions/push-event/index.ts
//
// Schritt 5 im Plan: schreibt Termine aus der App zurück in den Apple-
// Kalender (Rückrichtung zu caldav-sync, das nur liest). Bewusst nur für
// Termine mit quelle='app' — aus wiederkehrenden Apple-Terminen einzeln
// erzeugte Vorkommen (siehe caldav-sync) werden NICHT zurückgeschrieben,
// sonst entstünden in Apple viele Einzeltermine statt der einen Serie.

import { createClient } from "npm:@supabase/supabase-js@2";

const APPLE_ID = Deno.env.get("APPLE_ID")!;
const APPLE_APP_PASSWORD = Deno.env.get("APPLE_APP_PASSWORD")!;
const CALENDAR_NAME = Deno.env.get("APPLE_CALENDAR_NAME") ?? null;

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const authHeader = "Basic " + btoa(`${APPLE_ID}:${APPLE_APP_PASSWORD}`);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...corsHeaders } });
}
function resolveUrl(origin: string, href: string): string {
  return /^https?:\/\//i.test(href) ? href : origin + href;
}
function extractTag(xml: string, tag: string): string | null {
  const re = new RegExp(`<(?:[a-zA-Z0-9]+:)?${tag}[^>]*>([\\s\\S]*?)<\\/(?:[a-zA-Z0-9]+:)?${tag}>`, "i");
  const m = xml.match(re);
  return m ? m[1].trim() : null;
}
function extractHrefWithin(xml: string, containerTag: string): string | null {
  const container = extractTag(xml, containerTag);
  if (!container) return null;
  return extractTag(container, "href");
}
function splitResponses(xml: string): string[] {
  return [...xml.matchAll(/<(?:[a-zA-Z0-9]+:)?response[^>]*>([\s\S]*?)<\/(?:[a-zA-Z0-9]+:)?response>/gi)].map((m) => m[1]);
}
async function davRequest(url: string, method: string, body: string | null, depth: string | null) {
  const headers: Record<string, string> = { Authorization: authHeader };
  if (body) headers["Content-Type"] = "application/xml; charset=utf-8";
  if (depth) headers["Depth"] = depth;
  const res = await fetch(url, { method, headers, body: body ?? undefined });
  const text = await res.text();
  return { res, text, origin: new URL(res.url).origin };
}

function toICSDate(iso: string, allDay: boolean): string {
  const d = new Date(iso);
  if (allDay) return d.toISOString().slice(0, 10).replace(/-/g, "");
  return d.toISOString().replace(/[-:]/g, "").split(".")[0] + "Z";
}
function escapeICS(s: string): string {
  return (s || "").replace(/\\/g, "\\\\").replace(/([,;])/g, "\\$1").replace(/\n/g, "\\n");
}
function buildICS(event: any, uid: string): string {
  const now = toICSDate(new Date().toISOString(), false);
  const dtstart = event.ganztaegig
    ? `DTSTART;VALUE=DATE:${toICSDate(event.start_zeit, true)}`
    : `DTSTART:${toICSDate(event.start_zeit, false)}`;
  const dtend = event.ganztaegig
    ? `DTEND;VALUE=DATE:${toICSDate(event.end_zeit, true)}`
    : `DTEND:${toICSDate(event.end_zeit, false)}`;
  return [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Familienzentrale//DE", "BEGIN:VEVENT",
    `UID:${uid}`, `DTSTAMP:${now}`, dtstart, dtend, `SUMMARY:${escapeICS(event.titel)}`,
    "END:VEVENT", "END:VCALENDAR", "",
  ].join("\r\n");
}

async function findCalendarHref(): Promise<{ origin: string; href: string }> {
  const step1 = await davRequest(
    "https://caldav.icloud.com/", "PROPFIND",
    `<?xml version="1.0" encoding="utf-8"?><D:propfind xmlns:D="DAV:"><D:prop><D:current-user-principal/></D:prop></D:propfind>`,
    "0"
  );
  if (!step1.res.ok) throw new Error(`Anmeldung fehlgeschlagen (Status ${step1.res.status})`);
  const principal = extractHrefWithin(step1.text, "current-user-principal");
  if (!principal) throw new Error("Kein current-user-principal gefunden.");

  const step2 = await davRequest(
    resolveUrl(step1.origin, principal), "PROPFIND",
    `<?xml version="1.0" encoding="utf-8"?><D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><D:prop><C:calendar-home-set/></D:prop></D:propfind>`,
    "0"
  );
  if (!step2.res.ok) throw new Error(`Kalender-Verzeichnis nicht gefunden (Status ${step2.res.status})`);
  const calendarHome = extractHrefWithin(step2.text, "calendar-home-set");
  if (!calendarHome) throw new Error("Kein calendar-home-set gefunden.");

  const step3 = await davRequest(
    resolveUrl(step1.origin, calendarHome), "PROPFIND",
    `<?xml version="1.0" encoding="utf-8"?><D:propfind xmlns:D="DAV:"><D:prop><D:displayname/><D:resourcetype/></D:prop></D:propfind>`,
    "1"
  );
  if (!step3.res.ok) throw new Error(`Kalenderliste nicht abrufbar (Status ${step3.res.status})`);
  const candidates = splitResponses(step3.text)
    .map((r) => {
      const href = extractTag(r, "href");
      const resourcetype = extractTag(r, "resourcetype") || "";
      const isRealCalendar = /<(?:[a-zA-Z0-9]+:)?calendar(?=[\s\/>])[^>]*\/?>/i.test(resourcetype);
      const looksSpecial = href && /inbox|outbox|notification|dropbox|freebusy/i.test(href);
      return { href, name: extractTag(r, "displayname"), isCollection: isRealCalendar && !looksSpecial };
    })
    .filter((c) => c.href && c.isCollection && c.href !== calendarHome);
  if (candidates.length === 0) throw new Error("Keine Kalender im Account gefunden.");
  const chosen = CALENDAR_NAME
    ? candidates.find((c) => (c.name ?? "").toLowerCase().includes(CALENDAR_NAME.toLowerCase())) ?? candidates[0]
    : candidates[0];
  return { origin: step1.origin, href: resolveUrl(step1.origin, chosen.href!) };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const authHeaderIn = req.headers.get("Authorization") || "";
  const callerToken = authHeaderIn.replace("Bearer ", "");
  const { data: callerData, error: callerErr } = await supabase.auth.getUser(callerToken);
  if (callerErr || !callerData?.user) return json({ ok: false, error: "Nicht angemeldet." }, 401);
  const { data: callerMember } = await supabase.from("members").select("id").eq("user_id", callerData.user.id).maybeSingle();
  if (!callerMember) return json({ ok: false, error: "Kein Familienprofil gefunden." }, 403);

  try {
    const { event_id, action } = await req.json();
    if (!event_id) return json({ ok: false, error: "event_id fehlt." }, 400);

    const { data: event, error: fetchErr } = await supabase.from("calendar_events").select("*").eq("id", event_id).maybeSingle();
    if (fetchErr || !event) return json({ ok: false, error: "Termin nicht gefunden." }, 404);

    // Löschen soll immer zurückgeschrieben werden, egal woher der Termin
    // ursprünglich kam (App oder Apple) — nur bei Neuanlegen/Ändern
    // beschränken wir uns bewusst auf App-Termine (siehe unten).
    if (action === "delete") {
      if (!event.caldav_uid) return json({ ok: true, skipped: "Kein caldav_uid vorhanden, nichts zum Löschen in Apple." });
      const { href: calendarHref } = await findCalendarHref();
      const objUrl = `${calendarHref}${event.caldav_uid}.ics`;
      const delRes = await fetch(objUrl, { method: "DELETE", headers: { Authorization: authHeader } });
      if (!delRes.ok && delRes.status !== 404) {
        const body = await delRes.text().catch(() => "");
        return json({ ok: false, error: `Löschen in Apple fehlgeschlagen (Status ${delRes.status}): ${body.slice(0, 200)}` }, 502);
      }
      return json({ ok: true, deleted: true });
    }

    if (event.quelle !== "app") return json({ ok: true, skipped: "Kein App-Termin, nicht zurückgeschrieben." });

    const { href: calendarHref } = await findCalendarHref();

    const uid = event.caldav_uid || `${crypto.randomUUID()}@familienzentrale`;
    const objUrl = `${calendarHref}${uid}.ics`;
    const ics = buildICS(event, uid);
    const putRes = await fetch(objUrl, {
      method: "PUT",
      headers: { Authorization: authHeader, "Content-Type": "text/calendar; charset=utf-8" },
      body: ics,
    });
    if (!putRes.ok) return json({ ok: false, error: `Apple hat den Termin abgelehnt (Status ${putRes.status}).` }, 500);
    const etag = putRes.headers.get("ETag") || null;
    await supabase.from("calendar_events").update({ caldav_uid: uid, caldav_etag: etag }).eq("id", event_id);

    return json({ ok: true, uid });
  } catch (err) {
    return json({ ok: false, error: String(err) }, 500);
  }
});
