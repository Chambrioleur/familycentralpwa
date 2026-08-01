// supabase/functions/push-event/index.ts
//
// Writes events from the app back into the Apple calendar (the reverse
// direction of caldav-sync, which only reads). Deliberately only for
// events with quelle='app' — individual occurrences generated from
// recurring Apple events (see caldav-sync) are NOT written back,
// otherwise Apple would end up with many individual events instead of
// the one series.

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
  const lines = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Familienzentrale//DE", "BEGIN:VEVENT",
    `UID:${uid}`, `DTSTAMP:${now}`, dtstart, dtend, `SUMMARY:${escapeICS(event.titel)}`,
  ];
  // Recurring series (see EventForm/expandRecurrence in the frontend) —
  // a single RRULE is enough, Apple expands the occurrences itself.
  if (event.rrule) lines.push(`RRULE:${event.rrule}`);
  // Individually skipped occurrences ("delete just this event") as
  // EXDATE, in the same value type (DATE vs. DATE-TIME) as DTSTART.
  for (const ex of event.rrule_exdates ?? []) {
    lines.push(event.ganztaegig ? `EXDATE;VALUE=DATE:${toICSDate(ex, true)}` : `EXDATE:${toICSDate(ex, false)}`);
  }
  lines.push("END:VEVENT", "END:VCALENDAR", "");
  return lines.join("\r\n");
}

async function findCalendarHref(): Promise<{ origin: string; href: string }> {
  const step1 = await davRequest(
    "https://caldav.icloud.com/", "PROPFIND",
    `<?xml version="1.0" encoding="utf-8"?><D:propfind xmlns:D="DAV:"><D:prop><D:current-user-principal/></D:prop></D:propfind>`,
    "0"
  );
  if (!step1.res.ok) throw new Error(`Sign-in failed (status ${step1.res.status})`);
  const principal = extractHrefWithin(step1.text, "current-user-principal");
  if (!principal) throw new Error("No current-user-principal found.");

  const step2 = await davRequest(
    resolveUrl(step1.origin, principal), "PROPFIND",
    `<?xml version="1.0" encoding="utf-8"?><D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><D:prop><C:calendar-home-set/></D:prop></D:propfind>`,
    "0"
  );
  if (!step2.res.ok) throw new Error(`Calendar directory not found (status ${step2.res.status})`);
  const calendarHome = extractHrefWithin(step2.text, "calendar-home-set");
  if (!calendarHome) throw new Error("No calendar-home-set found.");

  const step3 = await davRequest(
    resolveUrl(step1.origin, calendarHome), "PROPFIND",
    `<?xml version="1.0" encoding="utf-8"?><D:propfind xmlns:D="DAV:"><D:prop><D:displayname/><D:resourcetype/></D:prop></D:propfind>`,
    "1"
  );
  if (!step3.res.ok) throw new Error(`Calendar list not retrievable (status ${step3.res.status})`);
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
  if (candidates.length === 0) throw new Error("No calendars found in the account.");
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
  if (callerErr || !callerData?.user) return json({ ok: false, error: "Not signed in." }, 401);
  const { data: callerMember } = await supabase.from("members").select("id").eq("user_id", callerData.user.id).maybeSingle();
  if (!callerMember) return json({ ok: false, error: "No family profile found." }, 403);

  try {
    const { event_id, action } = await req.json();
    if (!event_id) return json({ ok: false, error: "event_id is missing." }, 400);

    const { data: event, error: fetchErr } = await supabase.from("calendar_events").select("*").eq("id", event_id).maybeSingle();
    if (fetchErr || !event) return json({ ok: false, error: "Event not found." }, 404);

    // Deletion should always be written back, regardless of where the
    // event originally came from (app or Apple) — only for creating/
    // updating do we deliberately restrict ourselves to app events (see
    // below).
    if (action === "delete") {
      if (!event.caldav_uid) return json({ ok: true, skipped: "No caldav_uid present, nothing to delete in Apple." });
      const { href: calendarHref } = await findCalendarHref();
      const objUrl = `${calendarHref}${event.caldav_uid}.ics`;
      const delRes = await fetch(objUrl, { method: "DELETE", headers: { Authorization: authHeader } });
      if (!delRes.ok && delRes.status !== 404) {
        const body = await delRes.text().catch(() => "");
        return json({ ok: false, error: `Deleting in Apple failed (status ${delRes.status}): ${body.slice(0, 200)}` }, 502);
      }
      return json({ ok: true, deleted: true });
    }

    if (event.quelle !== "app") return json({ ok: true, skipped: "Not an app event, not written back." });

    const { href: calendarHref } = await findCalendarHref();

    const uid = event.caldav_uid || `${crypto.randomUUID()}@familienzentrale`;
    const objUrl = `${calendarHref}${uid}.ics`;
    const ics = buildICS(event, uid);
    const putRes = await fetch(objUrl, {
      method: "PUT",
      headers: { Authorization: authHeader, "Content-Type": "text/calendar; charset=utf-8" },
      body: ics,
    });
    if (!putRes.ok) return json({ ok: false, error: `Apple rejected the event (status ${putRes.status}).` }, 500);
    const etag = putRes.headers.get("ETag") || null;
    await supabase.from("calendar_events").update({ caldav_uid: uid, caldav_etag: etag }).eq("id", event_id);

    return json({ ok: true, uid });
  } catch (err) {
    return json({ ok: false, error: String(err) }, 500);
  }
});
