// Edge Function: onboarding
// Solo super_admin (staff Odyssai) puede llamarla.
// Crea un tenant nuevo (en trial de 14 días) + su usuario dueño.
// La suscripción de pago (MercadoPago) se genera aparte, cuando se necesite,
// con la función crear-suscripcion-mercadopago.
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
    const { tenant_nombre, tenant_rut, owner_email, owner_nombre } = body;

    if (!tenant_nombre || !owner_email || !owner_nombre) {
      return json({ error: "Faltan campos: tenant_nombre, owner_email, owner_nombre" }, 400);
    }

    // 1. Crear tenant (nace en trial de 14 días, con el pricing default: $50.000 + 2 bodegas incluidas)
    const { data: tenant, error: tenantErr } = await admin
      .from("tenants")
      .insert({ nombre: tenant_nombre, rut: tenant_rut ?? null })
      .select()
      .single();
    if (tenantErr) return json({ error: tenantErr.message }, 400);

    // 2. Crear usuario dueño (owner) con password temporal aleatoria.
    // createUser() ya crea correctamente su fila en auth.identities —
    // no tocar auth.identities manualmente en ningún otro lado.
    const tempPassword = crypto.randomUUID();
    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email: owner_email,
      password: tempPassword,
      email_confirm: true,
      user_metadata: { nombre: owner_nombre, role: "owner", tenant_id: tenant.id },
    });
    if (createErr) {
      // limpiar el tenant huérfano si el usuario no se pudo crear
      await admin.from("tenants").delete().eq("id", tenant.id);
      return json({ error: createErr.message || "No se pudo crear el usuario dueño" }, 400);
    }

    // 3. Link para que el dueño defina su propia contraseña
    const { data: linkData, error: linkErr } = await admin.auth.admin.generateLink({
      type: "recovery",
      email: owner_email,
    });
    if (linkErr) return json({ error: linkErr.message }, 400);

    return json({
      tenant_id: tenant.id,
      owner_user_id: created.user?.id,
      set_password_link: linkData?.properties?.action_link ?? null,
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
