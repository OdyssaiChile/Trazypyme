// Edge Function: create-checkout-session
// El dueño/gerente de un tenant la llama para (re)activar o cambiar su suscripción.
import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe@17";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY")!;

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

    const body = await req.json();
    const { price_id, success_url, cancel_url, tenant_id: tenantIdParam } = body;
    const tenant_id = profile.tenant_id ?? tenantIdParam;
    if (!tenant_id || !price_id) return json({ error: "Faltan price_id / tenant_id" }, 400);

    const { data: tenant, error: tErr } = await admin.from("tenants").select("*").eq("id", tenant_id).single();
    if (tErr || !tenant) return json({ error: "Tenant no encontrado" }, 404);

    const stripe = new Stripe(STRIPE_SECRET_KEY, { apiVersion: "2024-06-20" });

    let customerId = tenant.stripe_customer_id;
    if (!customerId) {
      const customer = await stripe.customers.create({
        name: tenant.nombre,
        metadata: { tenant_id: tenant.id },
      });
      customerId = customer.id;
      await admin.from("tenants").update({ stripe_customer_id: customerId }).eq("id", tenant.id);
    }

    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      customer: customerId,
      line_items: [{ price: price_id, quantity: 1 }],
      success_url: success_url ?? "https://example.com/success",
      cancel_url: cancel_url ?? "https://example.com/cancel",
      subscription_data: { metadata: { tenant_id: tenant.id } },
      metadata: { tenant_id: tenant.id },
    });

    return json({ checkout_url: session.url });
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
