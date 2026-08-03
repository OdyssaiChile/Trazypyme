-- Se quitó el botón "Deshacer último escaneo" de la app (a pedido). Nada en
-- el frontend vuelve a llamar deshacer_movimiento(); en vez de dejarla
-- huérfana, se elimina — ahora la corrección de stock se hace vía
-- actualizar_producto() (dueño/gerente) o eliminando el QR.
drop function if exists deshacer_movimiento(uuid);

-- touch_tenant_period() era un helper de la época de Stripe que nunca se usó
-- en ningún lado, y ahora referencia columnas ya eliminadas
-- (stripe_customer_id/stripe_subscription_id). Vestigio limpio.
drop function if exists public.touch_tenant_period(uuid, subscription_status, timestamptz, text, text);
