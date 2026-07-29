-- ---------- Historial de pagos (alimentado por el webhook de MercadoPago) ----------
-- Guardamos cada notificación de pago que llega, para que el cliente vea su
-- historial en el dashboard sin tener que consultar la API de MercadoPago en vivo.
create table pagos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  mp_payment_id text,
  mp_preapproval_id text,
  monto numeric,
  moneda text default 'CLP',
  estado text not null,
  metodo_pago text,
  fecha timestamptz not null default now(),
  raw jsonb
);
create index idx_pagos_tenant on pagos(tenant_id);

alter table pagos enable row level security;

create policy pagos_select on pagos for select
  using (tenant_id = current_tenant_id() or is_super_admin());

-- Los pagos solo los inserta el webhook con service role (bypassa RLS), no
-- se necesita policy de insert para clientes.
