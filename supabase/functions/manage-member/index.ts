// supabase/functions/manage-member/index.ts
//
// Legt eine neue Person inkl. echtem Login-Zugang an. Läuft serverseitig
// mit dem service_role-Schlüssel (den bekommt jede Edge Function
// automatisch von Supabase gestellt — kein manuelles Secret nötig).
//
// Regeln:
// - Wenn noch NIEMAND existiert (allererste Einrichtung): jeder darf
//   diese eine erste Person anlegen, sie wird automatisch Master.
// - Danach: nur wer bereits als Master eingeloggt ist, darf weitere
//   Personen anlegen.

import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

// Ohne diese Header blockiert der Browser den Aufruf von der Web-App aus
// lautlos (CORS) — kein Fehler sichtbar, einfach keine Reaktion.
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
      return json({ error: "Bitte alle Pflichtfelder ausfüllen." }, 400);
    }
    if (password.length < 6) {
      return json({ error: "Passwort/PIN muss mindestens 6 Zeichen haben." }, 400);
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
        return json({ error: "Nicht angemeldet." }, 401);
      }
      const { data: callerMember } = await supabaseAdmin
        .from("members")
        .select("ist_master")
        .eq("user_id", callerData.user.id)
        .maybeSingle();
      if (!callerMember?.ist_master) {
        return json({ error: "Nur der Master darf neue Personen anlegen." }, 403);
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
      // Aufräumen, falls das Anlegen des DB-Eintrags scheitert
      await supabaseAdmin.auth.admin.deleteUser(newUser.user.id);
      return json({ error: insertErr.message }, 400);
    }

    return json({ ok: true, isBootstrap, member: inserted });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
