// Edge Function: cancelar-suscripcion-mercadopago
// El dueño/gerente cancela su propia suscripción (o super_admin en su nombre).
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MP_ACCESS_TOKEN = Deno.env.get("MERCADOPAGO_ACCESS_TOKEN")!;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace("Bearer ", "");
    const asCaller = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await asCaller.auth.getUser(jwt);
    if (userErr || !userData?.user) return json({ error: "No autenticado" }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { data: profile } = await admin
      .from("profiles")
      .select("role, tenant_id")
      .eq("id", userData.user.id)
      .single();

    if (!profile || !["owner", "manager", "super_admin"].includes(profile.role)) {
      return json({ error: "Solo el dueño o gerente puede cancelar la suscripción" }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const tenant_id = profile.tenant_id ?? body.tenant_id;
    if (!tenant_id) return json({ error: "Falta tenant_id" }, 400);

    const { data: tenant, error: tErr } = await admin.from("tenants").select("*").eq("id", tenant_id).single();
    if (tErr || !tenant) return json({ error: "Tenant no encontrado" }, 404);

    if (tenant.mp_preapproval_id) {
      const mpRes = await fetch(`https://api.mercadopago.com/preapproval/${tenant.mp_preapproval_id}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${MP_ACCESS_TOKEN}` },
        body: JSON.stringify({ status: "cancelled" }),
      });
      if (!mpRes.ok) {
        const errData = await mpRes.json().catch(() => ({}));
        return json({ error: errData?.message || "No se pudo cancelar en MercadoPago" }, 400);
      }
    }

    await admin.from("tenants").update({ subscription_status: "canceled" }).eq("id", tenant_id);

    return json({ ok: true });
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
