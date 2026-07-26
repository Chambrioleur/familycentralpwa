// supabase/functions/caldav-sync/index.ts
//
// Liest Termine aus dem gemeinsamen Apple-Kalender ("Familie").
//
// Verlauf der Fixes (der Reihe nach behoben):
// 1. "tsdav"-Bibliothek verursachte "Bad file descriptor" in Deno -> entfernt,
//    spricht CalDAV nur noch über Standard-fetch.
// 2. XML-Auswertung ignorierte Tags ohne Namespace-Präfix -> behoben.
// 3. Kalender-Suche verwechselte calendar-home-set mit dessen eigenem href
//    -> jetzt gezielt innerhalb des richtigen Elements gesucht.
// 4. Apple liefert teils absolute statt relative URLs -> resolveUrl() prüft das.
// 5. Kalender-Erkennung war zu ungenau (fing Inbox/Notifications mit ein)
//    -> jetzt über das korrekte resourcetype-Element + Ausschluss von
//    Sonder-Kollektionen.
// 6. "ical.js" kam mit Apples TZID=Europe/Berlin ohne mitgelieferte
//    VTIMEZONE-Definition nicht klar -> komplett durch eigene, lokal
//    getestete Auswertung ersetzt: eigene Regex-Extraktion der Felder +
//    zuverlässige Zeitzonen-Umrechnung über die eingebaute Intl-API
//    (keine externe Zeitzonen-Datenbank nötig) + "rrule"-Bibliothek für
//    wiederkehrende Termine.

import { createClient } from "npm:@supabase/supabase-js@2";
import RRulePkg from "npm:rrule@2.8.1";
const { RRule } = RRulePkg;

const APPLE_ID = Deno.env.get("APPLE_ID")!;
const APPLE_APP_PASSWORD = Deno.env.get("APPLE_APP_PASSWORD")!;
const CALENDAR_NAME = Deno.env.get("APPLE_CALENDAR_NAME") ?? null;
const DEFAULT_TZ = "Europe/Berlin";

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

// ── WebDAV/XML-Helfer ─────────────────────────────────────────────
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
  const matches = [...xml.matchAll(/<(?:[a-zA-Z0-9]+:)?response[^>]*>([\s\S]*?)<\/(?:[a-zA-Z0-9]+:)?response>/gi)];
  return matches.map((m) => m[1]);
}
async function davRequest(url: string, method: string, body: string, depth: string) {
  const res = await fetch(url, {
    method,
    headers: { Authorization: authHeader, "Content-Type": "application/xml; charset=utf-8", Depth: depth },
    body,
  });
  const text = await res.text();
  return { res, text, origin: new URL(res.url).origin };
}
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...corsHeaders } });
}

// ── ICS-Auswertung (eigen, lokal getestet — siehe Chat-Verlauf) ───
function unfoldICS(ics: string): string {
  return ics.replace(/\r\n[ \t]/g, "").replace(/\n[ \t]/g, "");
}
function splitVEvents(ics: string): string[] {
  return [...ics.matchAll(/BEGIN:VEVENT[\s\S]*?END:VEVENT/g)].map((m) => m[0]);
}
function extractProp(block: string, name: string): { value: string; params: Record<string, string> } | null {
  const re = new RegExp(`^${name}((?:;[^:\\n]+)?):(.+)$`, "im");
  const m = block.match(re);
  if (!m) return null;
  const params: Record<string, string> = {};
  (m[1] || "").split(";").filter(Boolean).forEach((p) => {
    const [k, v] = p.split("=");
    if (k) params[k.toUpperCase()] = v;
  });
  return { value: m[2].trim(), params };
}

// Zuverlässige Zeitzonen-Umrechnung ohne externe Zeitzonen-Datenbank —
// nutzt die in Deno eingebaute Intl-API (siehe lokaler Test im Chat).
function zonedTimeToUtc(y: number, mo: number, d: number, h: number, mi: number, s: number, timeZone: string): Date {
  const asUTC = Date.UTC(y, mo - 1, d, h, mi, s);
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone, hourCycle: "h23",
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  });
  const parts = dtf.formatToParts(new Date(asUTC));
  const map: Record<string, string> = {};
  for (const p of parts) map[p.type] = p.value;
  const hour = map.hour === "24" ? 0 : +map.hour;
  const asIfUTCInZone = Date.UTC(+map.year, +map.month - 1, +map.day, hour, +map.minute, +map.second);
  return new Date(2 * asUTC - asIfUTCInZone);
}

function parseDateTimeProp(prop: { value: string; params: Record<string, string> } | null) {
  if (!prop) return null;
  const v = prop.value.replace(/[^0-9TZ]/g, "");
  const y = +v.slice(0, 4), mo = +v.slice(4, 6), d = +v.slice(6, 8);
  if (!v.includes("T")) return { date: new Date(Date.UTC(y, mo - 1, d, 0, 0, 0)), allDay: true };
  const h = +v.slice(9, 11), mi = +v.slice(11, 13), s = +(v.slice(13, 15) || "0");
  if (v.endsWith("Z")) return { date: new Date(Date.UTC(y, mo - 1, d, h, mi, s)), allDay: false };
  const tzid = prop.params.TZID || DEFAULT_TZ;
  return { date: zonedTimeToUtc(y, mo, d, h, mi, s, tzid), allDay: false };
}

function parseVEvent(block: string, rangeStart: Date, rangeEnd: Date) {
  const uid = extractProp(block, "UID")?.value;
  if (!uid) return [];
  const summary = extractProp(block, "SUMMARY")?.value || "(ohne Titel)";
  const dtstart = parseDateTimeProp(extractProp(block, "DTSTART"));
  const dtend = parseDateTimeProp(extractProp(block, "DTEND"));
  if (!dtstart) return [];
  const end = dtend ?? dtstart;
  const durationMs = end.date.getTime() - dtstart.date.getTime();
  const rruleProp = extractProp(block, "RRULE");

  const occurrences: { uid: string; titel: string; start: string; end: string; allDay: boolean }[] = [];

  if (rruleProp) {
    const options = RRule.parseString(rruleProp.value);
    options.dtstart = dtstart.date;
    const rule = new RRule(options);
    const dates = rule.between(rangeStart, rangeEnd, true);
    for (const occStart of dates) {
      const occEnd = new Date(occStart.getTime() + durationMs);
      occurrences.push({
        uid: `${uid}-${occStart.toISOString()}`,
        titel: summary, start: occStart.toISOString(), end: occEnd.toISOString(), allDay: dtstart.allDay,
      });
    }
  } else if (dtstart.date <= rangeEnd && end.date >= rangeStart) {
    occurrences.push({ uid, titel: summary, start: dtstart.date.toISOString(), end: end.date.toISOString(), allDay: dtstart.allDay });
  }
  return occurrences;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  // Entweder ein echter, angemeldeter Familien-Login ODER ein Cron-Aufruf
  // mit geteiltem Geheimnis (für den automatischen Zeitplan) — nicht mehr
  // der öffentliche anon-key allein.
  const cronSecret = req.headers.get("X-Cron-Secret");
  const expectedCronSecret = Deno.env.get("CRON_SECRET");
  const isCronCall = !!expectedCronSecret && cronSecret === expectedCronSecret;

  if (!isCronCall) {
    const authHeaderIn = req.headers.get("Authorization") || "";
    const callerToken = authHeaderIn.replace("Bearer ", "");
    const { data: callerData, error: callerErr } = await supabase.auth.getUser(callerToken);
    if (callerErr || !callerData?.user) {
      return json({ ok: false, error: "Nicht angemeldet." }, 401);
    }
    const { data: callerMember } = await supabase.from("members").select("id").eq("user_id", callerData.user.id).maybeSingle();
    if (!callerMember) {
      return json({ ok: false, error: "Kein Familienprofil gefunden." }, 403);
    }
  }

  try {
    const step1 = await davRequest(
      "https://caldav.icloud.com/", "PROPFIND",
      `<?xml version="1.0" encoding="utf-8"?><D:propfind xmlns:D="DAV:"><D:prop><D:current-user-principal/></D:prop></D:propfind>`,
      "0"
    );
    if (!step1.res.ok) throw new Error(`Anmeldung fehlgeschlagen (Schritt 1, Status ${step1.res.status}) — App-Passwort/Apple-ID prüfen`);
    const principal = extractHrefWithin(step1.text, "current-user-principal");
    if (!principal) throw new Error("Kein current-user-principal gefunden. Rohantwort: " + step1.text.slice(0, 400));

    const step2 = await davRequest(
      resolveUrl(step1.origin, principal), "PROPFIND",
      `<?xml version="1.0" encoding="utf-8"?><D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><D:prop><C:calendar-home-set/></D:prop></D:propfind>`,
      "0"
    );
    if (!step2.res.ok) throw new Error(`Kalender-Verzeichnis nicht gefunden (Schritt 2, Status ${step2.res.status})`);
    const calendarHome = extractHrefWithin(step2.text, "calendar-home-set");
    if (!calendarHome) throw new Error("Kein calendar-home-set gefunden. Rohantwort: " + step2.text.slice(0, 400));

    const step3 = await davRequest(
      resolveUrl(step1.origin, calendarHome), "PROPFIND",
      `<?xml version="1.0" encoding="utf-8"?><D:propfind xmlns:D="DAV:"><D:prop><D:displayname/><D:resourcetype/></D:prop></D:propfind>`,
      "1"
    );
    if (!step3.res.ok) throw new Error(`Kalenderliste nicht abrufbar (Schritt 3, Status ${step3.res.status}). Rohantwort: ${step3.text.slice(0, 400)}`);
    const candidates = splitResponses(step3.text)
      .map((r) => {
        const href = extractTag(r, "href");
        const resourcetype = extractTag(r, "resourcetype") || "";
        const isRealCalendar = /<(?:[a-zA-Z0-9]+:)?calendar(?=[\s\/>])[^>]*\/?>/i.test(resourcetype);
        const looksSpecial = href && /inbox|outbox|notification|dropbox|freebusy/i.test(href);
        const fallbackName = href ? decodeURIComponent(href.replace(/\/$/, "").split("/").pop() || "") : null;
        return { href, name: extractTag(r, "displayname") || fallbackName, isCollection: isRealCalendar && !looksSpecial };
      })
      .filter((c) => c.href && c.isCollection && c.href !== calendarHome);

    if (candidates.length === 0) throw new Error("Keine Kalender im Account gefunden. Rohantwort: " + step3.text.slice(0, 600));
    const chosen = CALENDAR_NAME
      ? candidates.find((c) => (c.name ?? "").toLowerCase().includes(CALENDAR_NAME.toLowerCase())) ?? candidates[0]
      : candidates[0];

    const rangeStart = new Date(); rangeStart.setMonth(rangeStart.getMonth() - 1);
    const rangeEnd = new Date(); rangeEnd.setMonth(rangeEnd.getMonth() + 6);
    const isoUtc = (d: Date) => d.toISOString().replace(/[-:]/g, "").split(".")[0] + "Z";

    const step4 = await davRequest(
      resolveUrl(step1.origin, chosen.href), "REPORT",
      `<?xml version="1.0" encoding="utf-8"?><C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><D:prop><D:getetag/><C:calendar-data/></D:prop><C:filter><C:comp-filter name="VCALENDAR"><C:comp-filter name="VEVENT"><C:time-range start="${isoUtc(rangeStart)}" end="${isoUtc(rangeEnd)}"/></C:comp-filter></C:comp-filter></C:filter></C:calendar-query>`,
      "1"
    );
    if (!step4.res.ok) throw new Error(`Termine nicht abrufbar (Schritt 4, Status ${step4.res.status}). Rohantwort: ${step4.text.slice(0, 400)}`);

    const objects = splitResponses(step4.text).map((r) => ({
      etag: extractTag(r, "getetag"),
      data: extractTag(r, "calendar-data"),
    })).filter((o) => o.data);

    let neu = 0, aktualisiert = 0, fehlerhaft = 0, geloescht = 0;
    let letzterFehler: string | undefined;
    let veventsGefunden = 0;
    let occurrencesGefunden = 0;
    let letzterInsertFehler: string | undefined;
    const gesehenUids = new Set<string>();

    for (const obj of objects) {
      const unfolded = unfoldICS(obj.data!);
      const veventBlocks = splitVEvents(unfolded);
      veventsGefunden += veventBlocks.length;

      for (const block of veventBlocks) {
        let occurrences;
        try {
          occurrences = parseVEvent(block, rangeStart, rangeEnd);
        } catch (err) {
          fehlerhaft++;
          letzterFehler = `${String(err)} | Daten: ${block.slice(0, 400)}`;
          continue;
        }
        occurrencesGefunden += occurrences.length;

        for (const occ of occurrences) {
          gesehenUids.add(occ.uid);
          const { data: existing } = await supabase
            .from("calendar_events").select("id, caldav_etag").eq("caldav_uid", occ.uid).maybeSingle();

          if (existing) {
            if (existing.caldav_etag !== obj.etag) {
              const { error: updErr } = await supabase.from("calendar_events").update({
                titel: occ.titel, start_zeit: occ.start, end_zeit: occ.end,
                ganztaegig: occ.allDay, caldav_etag: obj.etag, quelle: "apple",
              }).eq("id", existing.id);
              if (updErr) letzterInsertFehler = updErr.message; else aktualisiert++;
            }
          } else {
            const { error: insErr } = await supabase.from("calendar_events").insert({
              titel: occ.titel, start_zeit: occ.start, end_zeit: occ.end,
              ganztaegig: occ.allDay, caldav_uid: occ.uid, caldav_etag: obj.etag, quelle: "apple",
            });
            if (insErr) letzterInsertFehler = insErr.message; else neu++;
          }
        }
      }
    }

    // In Apple gelöschte/verschobene Termine erkennen: alles, was wir aus
    // Apple im gleichen Zeitraum in der DB haben, aber diesmal NICHT in der
    // Antwort war, wurde dort entfernt -> auch hier als gelöscht markieren.
    const { data: bekannte } = await supabase
      .from("calendar_events")
      .select("id, caldav_uid")
      .eq("quelle", "apple")
      .eq("geloescht", false)
      .not("caldav_uid", "is", null)
      .gte("start_zeit", rangeStart.toISOString())
      .lte("start_zeit", rangeEnd.toISOString());

    for (const row of bekannte ?? []) {
      if (!gesehenUids.has(row.caldav_uid)) {
        const { error: delErr } = await supabase.from("calendar_events").update({ geloescht: true }).eq("id", row.id);
        if (!delErr) geloescht++;
      }
    }

    await supabase.from("sync_log").insert({
      tabelle: "calendar_events", richtung: "pull", ergebnis: "erfolg",
      details: `Kalender "${chosen.name}": ${neu} neu, ${aktualisiert} aktualisiert, ${geloescht} gelöscht, ${fehlerhaft} fehlerhaft`,
    });

    return json({
      ok: true, neu, aktualisiert, geloescht, fehlerhaft, kalender: chosen.name, alle_kalender: candidates.map((c) => c.name),
      letzter_fehler: letzterFehler,
      diagnose: `${objects.length} Rohobjekte, ${veventsGefunden} Termine im Kalender-Datensatz, ${occurrencesGefunden} Vorkommen im Zeitraum berechnet.`,
      letzter_insert_fehler: letzterInsertFehler,
    });
  } catch (err) {
    await supabase.from("sync_log").insert({
      tabelle: "calendar_events", richtung: "pull", ergebnis: "fehler", details: String(err),
    });
    return json({ ok: false, error: String(err) }, 500);
  }
});
