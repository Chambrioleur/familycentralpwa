// supabase/functions/reset-password/index.ts
//
// Setzt das Passwort/PIN einer anderen Person zurück — nur der Master
// darf das auslösen. Braucht den Admin-API-Zugriff (service_role),
// deshalb als eigene Edge Function statt direkt im Browser.

import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { member_id, new_password } = await req.json();
    if (!member_id || !new_password) return json({ error: "Bitte Person und neues Passwort angeben." }, 400);
    if (new_password.length < 6) return json({ error: "Passwort/PIN muss mindestens 6 Zeichen haben." }, 400);

    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace("Bearer ", "");
    const { data: callerData, error: callerErr } = await supabaseAdmin.auth.getUser(token);
    if (callerErr || !callerData?.user) return json({ error: "Nicht angemeldet." }, 401);

    const { data: callerMember } = await supabaseAdmin
      .from("members").select("ist_master").eq("user_id", callerData.user.id).maybeSingle();
    if (!callerMember?.ist_master) return json({ error: "Nur der Master darf Passwörter zurücksetzen." }, 403);

    const { data: targetMember, error: targetErr } = await supabaseAdmin
      .from("members").select("user_id").eq("id", member_id).maybeSingle();
    if (targetErr || !targetMember?.user_id) return json({ error: "Person nicht gefunden." }, 404);

    const { error: updateErr } = await supabaseAdmin.auth.admin.updateUserById(targetMember.user_id, {
      password: new_password,
    });
    if (updateErr) return json({ error: updateErr.message }, 400);

    return json({ ok: true });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
