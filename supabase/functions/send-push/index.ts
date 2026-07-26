// supabase/functions/send-push/index.ts
//
// Sendet eine Push-Benachrichtigung an alle Geräte einer Person.
// Ohne Angabe von member_id wird an die eigenen Geräte gesendet (Test-Button).

import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

webpush.setVapidDetails(
  Deno.env.get("VAPID_SUBJECT") ?? "mailto:familie@example.com",
  Deno.env.get("VAPID_PUBLIC_KEY")!,
  Deno.env.get("VAPID_PRIVATE_KEY")!
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...corsHeaders } });
}

async function sendToMember(memberId: string, payload: Record<string, unknown>) {
  const { data: subs } = await supabaseAdmin.from("push_subscriptions").select("*").eq("member_id", memberId);
  let sent = 0, removed = 0;
  for (const sub of subs ?? []) {
    try {
      await webpush.sendNotification(
        { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
        JSON.stringify(payload)
      );
      sent++;
    } catch (err) {
      // Ungültige/abgelaufene Abos (410/404) aufräumen
      if (String(err).includes("410") || String(err).includes("404")) {
        await supabaseAdmin.from("push_subscriptions").delete().eq("id", sub.id);
        removed++;
      }
    }
  }
  return { sent, removed };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace("Bearer ", "");
    const { data: callerData, error: callerErr } = await supabaseAdmin.auth.getUser(token);
    if (callerErr || !callerData?.user) return json({ error: "Nicht angemeldet." }, 401);

    const { data: caller } = await supabaseAdmin.from("members").select("id").eq("user_id", callerData.user.id).maybeSingle();
    if (!caller) return json({ error: "Kein Profil gefunden." }, 404);

    const body = await req.json().catch(() => ({}));
    const memberId = body.member_id || caller.id;
    const title = body.title || "Familienzentrale";
    const message = body.body || "Testbenachrichtigung — sieht gut aus! 🎉";

    const result = await sendToMember(memberId, { title, body: message, url: "/" });
    return json({ ok: true, ...result });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
