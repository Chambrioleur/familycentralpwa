// supabase/functions/check-due-notifications/index.ts
//
// Runs on a schedule (Supabase cron job, e.g. hourly) and sends push
// notifications for tasks & reminders due today.
// Each entry is only notified once per day (benachrichtigt_am).

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

async function notifyMembers(memberIds: string[], payload: Record<string, unknown>) {
  let sent = 0;
  for (const memberId of memberIds) {
    const { data: subs } = await supabaseAdmin.from("push_subscriptions").select("*").eq("member_id", memberId);
    for (const sub of subs ?? []) {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          JSON.stringify(payload)
        );
        sent++;
      } catch (err) {
        if (String(err).includes("410") || String(err).includes("404")) {
          await supabaseAdmin.from("push_subscriptions").delete().eq("id", sub.id);
        }
      }
    }
  }
  return sent;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  // Runs automatically via a cron job (no logged-in user) — hence a
  // shared secret instead of a user login. Must be passed as the
  // "X-Cron-Secret" header when setting up the cron job.
  const providedSecret = req.headers.get("X-Cron-Secret");
  const expectedSecret = Deno.env.get("CRON_SECRET");
  if (!expectedSecret || providedSecret !== expectedSecret) {
    return new Response(JSON.stringify({ ok: false, error: "Not authorized." }), {
      status: 401, headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  try {
    const today = new Date().toISOString().slice(0, 10);
    const { data: allMembers } = await supabaseAdmin.from("members").select("id");
    const allMemberIds = (allMembers ?? []).map((m: { id: string }) => m.id);

    let benachrichtigt = 0;

    const { data: tasks } = await supabaseAdmin
      .from("tasks").select("*")
      .eq("status", "offen")
      .lte("frist", today)
      .or(`benachrichtigt_am.is.null,benachrichtigt_am.lt.${today}`);

    for (const t of tasks ?? []) {
      const targets = t.member_id ? [t.member_id] : allMemberIds;
      const n = await notifyMembers(targets, { title: "Task due", body: t.titel, url: "/#aufgaben" });
      if (n > 0) benachrichtigt++;
      await supabaseAdmin.from("tasks").update({ benachrichtigt_am: today }).eq("id", t.id);
    }

    const { data: reminders } = await supabaseAdmin
      .from("reminders").select("*")
      .eq("status", "offen")
      .lte("faelligkeit", today)
      .or(`benachrichtigt_am.is.null,benachrichtigt_am.lt.${today}`);

    for (const r of reminders ?? []) {
      const n = await notifyMembers(allMemberIds, { title: "Reminder", body: r.titel, url: "/#erinnerungen" });
      if (n > 0) benachrichtigt++;
      await supabaseAdmin.from("reminders").update({ benachrichtigt_am: today }).eq("id", r.id);
    }

    return json({ ok: true, geprueft: (tasks?.length ?? 0) + (reminders?.length ?? 0), benachrichtigt });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
