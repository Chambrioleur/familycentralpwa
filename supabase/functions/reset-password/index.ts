// supabase/functions/reset-password/index.ts
//
// Resets another person's password/PIN — only the master may trigger
// this. Needs admin API access (service_role), hence a separate Edge
// Function instead of doing it directly in the browser.

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
    if (!member_id || !new_password) return json({ error: "Please provide a person and a new password." }, 400);
    if (new_password.length < 6) return json({ error: "Password/PIN must be at least 6 characters." }, 400);

    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace("Bearer ", "");
    const { data: callerData, error: callerErr } = await supabaseAdmin.auth.getUser(token);
    if (callerErr || !callerData?.user) return json({ error: "Not signed in." }, 401);

    const { data: callerMember } = await supabaseAdmin
      .from("members").select("ist_master").eq("user_id", callerData.user.id).maybeSingle();
    if (!callerMember?.ist_master) return json({ error: "Only the master may reset passwords." }, 403);

    const { data: targetMember, error: targetErr } = await supabaseAdmin
      .from("members").select("user_id").eq("id", member_id).maybeSingle();
    if (targetErr || !targetMember?.user_id) return json({ error: "Person not found." }, 404);

    const { error: updateErr } = await supabaseAdmin.auth.admin.updateUserById(targetMember.user_id, {
      password: new_password,
    });
    if (updateErr) return json({ error: updateErr.message }, 400);

    return json({ ok: true });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
