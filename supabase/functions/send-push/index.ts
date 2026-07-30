// supabase/functions/send-push/index.ts
//
// Sends a push notification to all of a person's devices.
// Without a member_id, it sends to the caller's own devices (test button).
//
// Can also be called with a cron secret (no signed-in user) using
// { notify_all_adults: true, ... } — used by the other cron functions
// (caldav-sync, check-due-notifications) to alert every adult when a
// scheduled job actually fails. Without this, a silent cron failure
// (expired app password, etc.) would otherwise go unnoticed.

import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

webpush.setVapidDetails(
  Deno.env.get("VAPID_SUBJECT") ?? "mailto:family@example.com",
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
      // Clean up invalid/expired subscriptions (410/404)
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
    const cronSecret = req.headers.get("X-Cron-Secret");
    const expectedCronSecret = Deno.env.get("CRON_SECRET");
    const isCronCall = !!expectedCronSecret && cronSecret === expectedCronSecret;

    const body = await req.json().catch(() => ({}));
    const title = body.title || "Familienzentrale";
    const message = body.body || "Test notification — looks good! 🎉";

    if (isCronCall && body.notify_all_adults) {
      const { data: adults } = await supabaseAdmin.from("members").select("id").eq("rolle", "erwachsen");
      let sent = 0, removed = 0;
      for (const adult of adults ?? []) {
        const r = await sendToMember(adult.id, { title, body: message, url: "/" });
        sent += r.sent; removed += r.removed;
      }
      return json({ ok: true, sent, removed });
    }

    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace("Bearer ", "");
    const { data: callerData, error: callerErr } = await supabaseAdmin.auth.getUser(token);
    if (callerErr || !callerData?.user) return json({ error: "Not signed in." }, 401);

    const { data: caller } = await supabaseAdmin.from("members").select("id").eq("user_id", callerData.user.id).maybeSingle();
    if (!caller) return json({ error: "No profile found." }, 404);

    const memberId = body.member_id || caller.id;
    const result = await sendToMember(memberId, { title, body: message, url: "/" });
    return json({ ok: true, ...result });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
