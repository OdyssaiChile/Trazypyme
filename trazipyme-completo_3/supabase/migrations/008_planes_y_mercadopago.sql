-- =========================================================
-- Pivot de precios y de pasarela de pago: Stripe -> MercadoPago
-- =========================================================
-- Modelo de negocio real de Odyssai: solo 2 estados posibles por tenant:
--   - "trial": 14 días gratis (automático al crear el cliente)
--   - "pro":   único plan pago, $50.000 CLP/mes, incluye 2 bodegas,
--              + $20.000 CLP/mes por cada bodega adicional activa.
-- Ya no existen los planes "starter"/"enterprise" que estaban de más.

alter table tenants
  add column if not exists bodegas_incluidas int not null default 2,
  add column if not exists precio_base_clp numeric not null default 50000,
  add column if not exists precio_bodega_adicional_clp numeric not null default 20000,
  add column if not exists mp_preapproval_id text,
  add column if not exists mp_payer_email text;

-- Stripe ya no se usa (pivot a MercadoPago) — se eliminan las columnas para
-- no dejar campos muertos.
alter table tenants
  drop column if exists stripe_customer_id,
  drop column if exists stripe_subscription_id;

-- max_bodegas ya no aplica (ahora se paga por bodega extra, no hay tope
-- duro); max_usuarios no se usaba en ningún lado del código.
alter table tenants
  drop column if exists max_bodegas,
  drop column if exists max_usuarios;

alter table tenants alter column plan set default 'trial';
update tenants set plan = 'trial' where plan not in ('trial','pro');

-- ---------- Función: calcular el monto mensual real de un tenant ----------
-- Única fuente de verdad para el monto (la usan el dashboard, el panel
-- admin y la función que crea la suscripción en MercadoPago).
create or replace function calcular_monto_mensual(p_tenant_id uuid)
returns numeric
language plpgsql stable security definer set search_path = public as $$
declare
  v_tenant tenants%rowtype;
  v_bodegas_activas int;
  v_extra int;
begin
  if not (current_tenant_id() = p_tenant_id or is_super_admin()) then
    raise exception 'No autorizado';
  end if;
  select * into v_tenant from tenants where id = p_tenant_id;
  if not found then raise exception 'Tenant no encontrado'; end if;
  select count(*) into v_bodegas_activas from bodegas where tenant_id = p_tenant_id and activo;
  v_extra := greatest(0, v_bodegas_activas - v_tenant.bodegas_incluidas);
  return v_tenant.precio_base_clp + (v_extra * v_tenant.precio_bodega_adicional_clp);
end;
$$;
