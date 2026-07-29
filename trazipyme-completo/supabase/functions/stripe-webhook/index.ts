// Edge Function: stripe-webhook
// Recibe eventos de Stripe (checkout completado, suscripción actualizada/cancelada)
// y actualiza el estado de suscripción del tenant correspondiente.
// verify_jwt = false: Stripe no manda JWT de Supabase, se verifica con la firma de Stripe.
import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe@17";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY")!;
const STRIPE_WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;

const stripe = new Stripe(STRIPE_SECRET_KEY, { apiVersion: "2024-06-20" });
const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

function mapStatus(stripeStatus: string): string {
  switch (stripeStatus) {
    case "trialing": return "trialing";
    case "active": return "active";
    case "past_due": return "past_due";
    case "canceled": return "canceled";
    case "unpaid": return "past_due";
    default: return "incomplete";
  }
}

async function updateTenantFromSubscription(sub: Stripe.Subscription) {
  const tenantId = sub.metadata?.tenant_id;
  const status = mapStatus(sub.status);
  const periodEnd = new Date(sub.current_period_end * 1000).toISOString();

  if (tenantId) {
    await admin.from("tenants").update({
      subscription_status: status,
      current_period_end: periodEnd,
      stripe_subscription_id: sub.id,
      stripe_customer_id: typeof sub.customer === "string" ? sub.customer : sub.customer.id,
    }).eq("id", tenantId);
  } else {
    await admin.from("tenants").update({
      subscription_status: status,
      current_period_end: periodEnd,
      stripe_subscription_id: sub.id,
    }).eq("stripe_customer_id", typeof sub.customer === "string" ? sub.customer : sub.customer.id);
  }
}

Deno.serve(async (req: Request) => {
  const signature = req.headers.get("stripe-signature");
  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, signature!, STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    return new Response(`Webhook signature error: ${err}`, { status: 400 });
  }

  try {
    switch (event.type) {
      case "checkout.session.completed": {
        const session = event.data.object as Stripe.Checkout.Session;
        if (session.subscription) {
          const sub = await stripe.subscriptions.retrieve(session.subscription as string);
          await updateTenantFromSubscription(sub);
        }
        break;
      }
      case "customer.subscription.updated":
      case "customer.subscription.created": {
        await updateTenantFromSubscription(event.data.object as Stripe.Subscription);
        break;
      }
      case "customer.subscription.deleted": {
        const sub = event.data.object as Stripe.Subscription;
        const tenantId = sub.metadata?.tenant_id;
        if (tenantId) {
          await admin.from("tenants").update({ subscription_status: "canceled" }).eq("id", tenantId);
        }
        break;
      }
      default:
        break;
    }
    return new Response(JSON.stringify({ received: true }), { status: 200 });
  } catch (e) {
    return new Response(`Handler error: ${e}`, { status: 500 });
  }
});
