// supabase/functions/manage-member/index.ts
//
// Creates a new person including a real login. Runs server-side with
// the service_role key (every Edge Function gets this automatically
// from Supabase — no manual secret needed).
//
// Rules:
// - If NOBODY exists yet (very first setup): anyone may create this one
//   first person, who automatically becomes master.
// - After that: only someone already logged in as master may create
//   further people.

import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

// Without these headers the browser silently blocks the call from the
// web app (CORS) — no visible error, it just does nothing.
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
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const { name, rolle, farbe, geburtstag, login_email, password } = await req.json();

    if (!name || !rolle || !farbe || !login_email || !password) {
      return json({ error: "Please fill in all required fields." }, 400);
    }
    if (password.length < 6) {
      return json({ error: "Password/PIN must be at least 6 characters." }, 400);
    }

    const { count } = await supabaseAdmin
      .from("members")
      .select("*", { count: "exact", head: true });
    const isBootstrap = (count ?? 0) === 0;

    if (!isBootstrap) {
      const authHeader = req.headers.get("Authorization") || "";
      const token = authHeader.replace("Bearer ", "");
      const { data: callerData, error: callerErr } = await supabaseAdmin.auth.getUser(token);
      if (callerErr || !callerData?.user) {
        return json({ error: "Not signed in." }, 401);
      }
      const { data: callerMember } = await supabaseAdmin
        .from("members")
        .select("ist_master")
        .eq("user_id", callerData.user.id)
        .maybeSingle();
      if (!callerMember?.ist_master) {
        return json({ error: "Only the master may create new people." }, 403);
      }
    }

    const { data: newUser, error: createErr } = await supabaseAdmin.auth.admin.createUser({
      email: login_email,
      password,
      email_confirm: true,
    });
    if (createErr) return json({ error: createErr.message }, 400);

    const { data: inserted, error: insertErr } = await supabaseAdmin.from("members").insert({
      name,
      rolle,
      farbe,
      geburtstag: geburtstag || null,
      login_email,
      user_id: newUser.user.id,
      ist_master: isBootstrap,
    }).select().single();
    if (insertErr) {
      // Clean up if creating the DB entry fails
      await supabaseAdmin.auth.admin.deleteUser(newUser.user.id);
      return json({ error: insertErr.message }, 400);
    }

    return json({ ok: true, isBootstrap, member: inserted });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
