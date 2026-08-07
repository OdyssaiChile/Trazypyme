-- =========================================================
-- 1) Archivar clientes (soft-delete a nivel de tenant)
-- 2) Cupo de bodegas contratadas (lo que el cliente paga)
-- 3) Permisos de bodega por usuario
-- =========================================================

-- ---------- 1) Archivar clientes ----------
-- "Eliminar" un cliente no borra datos: lo archiva. Sale de la lista principal
-- de administración pero su información sigue accesible en la vista de
-- archivados (histórico, pagos, equipo, actividad).
alter table tenants
  add column if not exists archivado_at timestamptz,
  add column if not exists archivado_motivo text;

-- ---------- 2) Cupo de bodegas contratadas ----------
-- Distinto de las bodegas ya creadas: es el cupo PAGADO. Arranca igual a las
-- incluidas en el plan (2) y sube cuando el cliente contrata adicionales.
alter table tenants
  add column if not exists bodegas_contratadas int not null default 2;

update tenants t set bodegas_contratadas = greatest(
  t.bodegas_incluidas,
  (select count(*) from bodegas b where b.tenant_id = t.id and b.activo)
);

-- El monto mensual se calcula sobre el CUPO CONTRATADO (lo que paga), no
-- sobre cuántas bodegas alcanzó a crear.
create or replace function calcular_monto_mensual(p_tenant_id uuid)
returns numeric
language plpgsql stable security definer set search_path = public as $$
declare
  v_tenant tenants%rowtype;
  v_extra int;
begin
  if not (current_tenant_id() = p_tenant_id or is_super_admin()) then
    raise exception 'No autorizado';
  end if;
  select * into v_tenant from tenants where id = p_tenant_id;
  if not found then raise exception 'Tenant no encontrado'; end if;
  v_extra := greatest(0, v_tenant.bodegas_contratadas - v_tenant.bodegas_incluidas);
  return v_tenant.precio_base_clp + (v_extra * v_tenant.precio_bodega_adicional_clp);
end;
$$;

-- ---------- 3) Permisos de bodega por usuario ----------
-- Regla: owner/manager ven TODAS las bodegas de su tenant siempre.
-- Los operarios solo ven las bodegas que tengan asignadas explícitamente.
create table if not exists bodega_accesos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  bodega_id uuid not null references bodegas(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (bodega_id, profile_id)
);
create index if not exists idx_bodega_accesos_profile on bodega_accesos(profile_id);
create index if not exists idx_bodega_accesos_tenant on bodega_accesos(tenant_id);

alter table bodega_accesos enable row level security;

create policy bodega_accesos_select on bodega_accesos for select
  using (tenant_id = current_tenant_id() or is_super_admin());
create policy bodega_accesos_insert on bodega_accesos for insert
  with check ((tenant_id = current_tenant_id() and is_manager_or_owner()) or is_super_admin());
create policy bodega_accesos_delete on bodega_accesos for delete
  using ((tenant_id = current_tenant_id() and is_manager_or_owner()) or is_super_admin());

create or replace function public.puede_ver_bodega(p_bodega_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select
    is_super_admin()
    or is_manager_or_owner()
    or exists (
      select 1 from bodega_accesos ba
      where ba.bodega_id = p_bodega_id and ba.profile_id = auth.uid()
    );
$$;
