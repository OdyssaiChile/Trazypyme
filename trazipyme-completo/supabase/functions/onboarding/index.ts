// Edge Function: onboarding
// Solo super_admin (staff Odyssai) puede llamarla.
// Crea un tenant nuevo + su usuario dueño + (opcional) sesión de pago Stripe inicial.
import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe@17";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY");

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
    if (userErr || !userData?.user) {
      return json({ error: "No autenticado" }, 401);
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { data: callerProfile } = await admin
      .from("profiles")
      .select("role")
      .eq("id", userData.user.id)
      .single();

    if (!callerProfile || callerProfile.role !== "super_admin") {
      return json({ error: "Solo un super_admin puede crear clientes nuevos" }, 403);
    }

    const body = await req.json();
    const {
      tenant_nombre,
      tenant_rut,
      plan = "starter",
      owner_email,
      owner_nombre,
      price_id,
      success_url,
      cancel_url,
    } = body;

    if (!tenant_nombre || !owner_email || !owner_nombre) {
      return json({ error: "Faltan campos: tenant_nombre, owner_email, owner_nombre" }, 400);
    }

    // 1. Crear tenant
    const { data: tenant, error: tenantErr } = await admin
      .from("tenants")
      .insert({ nombre: tenant_nombre, rut: tenant_rut ?? null, plan })
      .select()
      .single();
    if (tenantErr) return json({ error: tenantErr.message }, 400);

    // 2. Crear usuario dueño (owner) con password temporal aleatoria
    const tempPassword = crypto.randomUUID();
    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email: owner_email,
      password: tempPassword,
      email_confirm: true,
      user_metadata: { nombre: owner_nombre, role: "owner", tenant_id: tenant.id },
    });
    if (createErr) return json({ error: createErr.message }, 400);

    // 3. Link para que el dueño defina su propia contraseña
    const { data: linkData, error: linkErr } = await admin.auth.admin.generateLink({
      type: "recovery",
      email: owner_email,
    });
    if (linkErr) return json({ error: linkErr.message }, 400);

    // 4. (Opcional) Sesión de pago Stripe para activar la suscripción
    let checkout_url: string | null = null;
    if (STRIPE_SECRET_KEY && price_id) {
      const stripe = new Stripe(STRIPE_SECRET_KEY, { apiVersion: "2024-06-20" });
      const customer = await stripe.customers.create({
        email: owner_email,
        name: tenant_nombre,
        metadata: { tenant_id: tenant.id },
      });
      await admin.from("tenants").update({ stripe_customer_id: customer.id }).eq("id", tenant.id);

      const session = await stripe.checkout.sessions.create({
        mode: "subscription",
        customer: customer.id,
        line_items: [{ price: price_id, quantity: 1 }],
        success_url: success_url ?? "https://example.com/success",
        cancel_url: cancel_url ?? "https://example.com/cancel",
        subscription_data: { metadata: { tenant_id: tenant.id } },
        metadata: { tenant_id: tenant.id },
      });
      checkout_url = session.url;
    }

    return json({
      tenant_id: tenant.id,
      owner_user_id: created.user?.id,
      set_password_link: linkData?.properties?.action_link ?? null,
      checkout_url,
    }, 201);
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
