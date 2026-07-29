// Edge Function: crear-suscripcion-mercadopago
// El dueño/gerente (o super_admin en su nombre) genera el link de pago.
// El monto se calcula solo: $50.000 base (2 bodegas incluidas) + $20.000
// por cada bodega adicional activa. Nunca se pide un ID a mano.
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
      return json({ error: "Solo el dueño o gerente puede gestionar la suscripción" }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const tenant_id = profile.tenant_id ?? body.tenant_id;
    if (!tenant_id) return json({ error: "Falta tenant_id" }, 400);

    const { data: tenant, error: tErr } = await admin.from("tenants").select("*").eq("id", tenant_id).single();
    if (tErr || !tenant) return json({ error: "Tenant no encontrado" }, 404);

    // Correo del pagador: el dueño del tenant (o quien se indique)
    let payerEmail = body.payer_email;
    if (!payerEmail) {
      const { data: owner } = await admin.from("profiles").select("email").eq("tenant_id", tenant_id).eq("role", "owner").limit(1).maybeSingle();
      payerEmail = owner?.email ?? userData.user.email;
    }

    // Monto calculado automáticamente (base + bodegas extra), nunca a mano
    const { count: bodegasActivas } = await admin.from("bodegas").select("id", { count: "exact", head: true }).eq("tenant_id", tenant_id).eq("activo", true);
    const extra = Math.max(0, (bodegasActivas ?? 0) - tenant.bodegas_incluidas);
    const monto = Number(tenant.precio_base_clp) + extra * Number(tenant.precio_bodega_adicional_clp);

    const back_url = body.back_url ?? "https://trazpyme.vercel.app/dashboard/";

    const mpRes = await fetch("https://api.mercadopago.com/preapproval", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${MP_ACCESS_TOKEN}` },
      body: JSON.stringify({
        reason: `TraziPyme — ${tenant.nombre} (Plan Pro, ${tenant.bodegas_incluidas + extra} bodega${extra ? "s" : ""})`,
        external_reference: tenant.id,
        payer_email: payerEmail,
        back_url,
        auto_recurring: {
          frequency: 1,
          frequency_type: "months",
          transaction_amount: monto,
          currency_id: "CLP",
        },
      }),
    });

    const mpData = await mpRes.json();
    if (!mpRes.ok) {
      return json({ error: mpData?.message || "Error creando la suscripción en MercadoPago", mp_detail: mpData }, 400);
    }

    await admin.from("tenants").update({
      mp_preapproval_id: mpData.id,
      mp_payer_email: payerEmail,
    }).eq("id", tenant_id);

    return json({ checkout_url: mpData.init_point, preapproval_id: mpData.id, monto_mensual: monto });
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
