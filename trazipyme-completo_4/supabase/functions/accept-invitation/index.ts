// Edge Function: accept-invitation
// El invitado (operario/gerente) llega con un token de invitación y define su contraseña.
// No requiere JWT de Supabase porque el usuario aún no tiene cuenta (se valida con el token).
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { token, password } = await req.json();
    if (!token || !password || password.length < 8) {
      return json({ error: "Token y contraseña (mínimo 8 caracteres) son obligatorios" }, 400);
    }

    const { data: invite, error: inviteErr } = await admin
      .from("invitations")
      .select("*")
      .eq("token", token)
      .is("used_at", null)
      .gt("expires_at", new Date().toISOString())
      .single();

    if (inviteErr || !invite) {
      return json({ error: "Invitación inválida, ya usada o expirada" }, 400);
    }

    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email: invite.email,
      password,
      email_confirm: true,
      user_metadata: { nombre: invite.nombre, role: invite.role, tenant_id: invite.tenant_id },
    });
    if (createErr) return json({ error: createErr.message }, 400);

    await admin.from("invitations").update({ used_at: new Date().toISOString() }).eq("id", invite.id);

    return json({ ok: true, user_id: created.user?.id, email: invite.email });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
