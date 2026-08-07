// Edge Function: mercadopago-webhook
// Recibe notificaciones de MercadoPago (preapproval creado/pausado/cancelado,
// pagos procesados), actualiza el estado de suscripción del tenant y guarda
// cada pago en la tabla "pagos" para que el cliente vea su historial.
// verify_jwt = false: MercadoPago no manda JWT de Supabase.
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MP_ACCESS_TOKEN = Deno.env.get("MERCADOPAGO_ACCESS_TOKEN")!;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

function mapEstado(mpStatus: string): string {
  switch (mpStatus) {
    case "authorized": return "active";
    case "pending": return "incomplete";
    case "paused": return "past_due";
    case "cancelled": return "canceled";
    default: return "incomplete";
  }
}

async function tenantIdDesdePreapproval(preapprovalId: string): Promise<{ tenantId: string | null; pre: any }> {
  const res = await fetch(`https://api.mercadopago.com/preapproval/${preapprovalId}`, {
    headers: { Authorization: `Bearer ${MP_ACCESS_TOKEN}` },
  });
  if (!res.ok) return { tenantId: null, pre: null };
  const pre = await res.json();
  return { tenantId: pre.external_reference ?? null, pre };
}

async function actualizarDesdePreapproval(preapprovalId: string) {
  const { tenantId, pre } = await tenantIdDesdePreapproval(preapprovalId);
  if (!pre) return;
  const estado = mapEstado(pre.status);
  const update: Record<string, unknown> = {
    subscription_status: estado,
    mp_preapproval_id: pre.id,
  };
  if (pre.auto_recurring?.next_payment_date) {
    update.current_period_end = pre.auto_recurring.next_payment_date;
  }
  if (tenantId) {
    await admin.from("tenants").update(update).eq("id", tenantId);
  } else {
    await admin.from("tenants").update(update).eq("mp_preapproval_id", pre.id);
  }
}

async function actualizarDesdePago(paymentId: string) {
  const res = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
    headers: { Authorization: `Bearer ${MP_ACCESS_TOKEN}` },
  });
  if (!res.ok) return;
  const pago = await res.json();

  const preapprovalId = pago.metadata?.preapproval_id
    || pago.point_of_interaction?.transaction_data?.subscription_id
    || null;

  // Resolver tenant_id: 1) external_reference del pago, 2) via la preapproval, 3) via tenants.mp_preapproval_id
  let tenantId: string | null = pago.external_reference ?? null;
  if (!tenantId && preapprovalId) {
    const r = await tenantIdDesdePreapproval(preapprovalId);
    tenantId = r.tenantId;
  }
  if (!tenantId && preapprovalId) {
    const { data } = await admin.from("tenants").select("id").eq("mp_preapproval_id", preapprovalId).maybeSingle();
    tenantId = data?.id ?? null;
  }

  if (tenantId) {
    await admin.from("pagos").insert({
      tenant_id: tenantId,
      mp_payment_id: String(pago.id),
      mp_preapproval_id: preapprovalId,
      monto: pago.transaction_amount,
      moneda: pago.currency_id ?? "CLP",
      estado: pago.status,
      metodo_pago: pago.payment_method_id ?? pago.payment_type_id ?? null,
      fecha: pago.date_approved ?? pago.date_created ?? new Date().toISOString(),
      raw: pago,
    });
  }

  if (preapprovalId) await actualizarDesdePreapproval(preapprovalId);
}

Deno.serve(async (req: Request) => {
  try {
    const url = new URL(req.url);
    let topic = url.searchParams.get("type") || url.searchParams.get("topic");
    let id = url.searchParams.get("data.id") || url.searchParams.get("id");

    if (req.method === "POST") {
      const body = await req.json().catch(() => null);
      if (body) {
        topic = topic || body.type || body.topic;
        id = id || body.data?.id || body.id;
      }
    }

    if (topic === "preapproval" && id) {
      await actualizarDesdePreapproval(id);
    } else if (topic === "payment" && id) {
      await actualizarDesdePago(id);
    }

    return new Response(JSON.stringify({ received: true }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (e) {
    console.error("mercadopago-webhook error:", e);
    return new Response(JSON.stringify({ received: true, error: String(e) }), { status: 200, headers: { "Content-Type": "application/json" } });
  }
});
