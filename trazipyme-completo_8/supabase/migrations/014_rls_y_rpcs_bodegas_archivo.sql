-- ---------- RLS: filtrado por bodega permitida ----------
drop policy if exists bodegas_select on bodegas;
create policy bodegas_select on bodegas for select
  using ((tenant_id = current_tenant_id() and puede_ver_bodega(id)) or is_super_admin());

drop policy if exists productos_select on productos;
create policy productos_select on productos for select
  using ((tenant_id = current_tenant_id() and puede_ver_bodega(bodega_id)) or is_super_admin());

drop policy if exists movimientos_select on movimientos;
create policy movimientos_select on movimientos for select
  using (
    (tenant_id = current_tenant_id()
      and exists (select 1 from productos p where p.id = movimientos.producto_id and puede_ver_bodega(p.bodega_id)))
    or is_super_admin()
  );

-- ---------- RPC: gestionar accesos de un usuario a una bodega ----------
create or replace function set_acceso_bodega(p_profile_id uuid, p_bodega_id uuid, p_permitir boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid := current_tenant_id();
begin
  if v_tenant is null or not is_manager_or_owner() then
    raise exception 'Solo el dueño o gerente puede gestionar accesos a bodegas';
  end if;
  if not exists (select 1 from bodegas b where b.id = p_bodega_id and b.tenant_id = v_tenant) then
    raise exception 'Bodega no encontrada';
  end if;
  if not exists (select 1 from profiles pr where pr.id = p_profile_id and pr.tenant_id = v_tenant) then
    raise exception 'Usuario no encontrado en tu empresa';
  end if;

  if p_permitir then
    insert into bodega_accesos (tenant_id, bodega_id, profile_id)
    values (v_tenant, p_bodega_id, p_profile_id)
    on conflict (bodega_id, profile_id) do nothing;
  else
    delete from bodega_accesos where bodega_id = p_bodega_id and profile_id = p_profile_id;
  end if;
end;
$$;

-- ---------- RPC: crear bodega (respeta el cupo pagado del plan) ----------
create or replace function crear_bodega(p_nombre text, p_direccion text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid := current_tenant_id();
  v_tenant_row tenants%rowtype;
  v_activas int;
  v_id uuid;
begin
  if v_tenant is null or not is_manager_or_owner() then
    raise exception 'Solo el dueño o gerente puede crear bodegas';
  end if;
  if not tenant_subscription_ok(v_tenant) then
    raise exception 'Suscripción inactiva: no se pueden crear bodegas';
  end if;

  select * into v_tenant_row from tenants where id = v_tenant;
  select count(*) into v_activas from bodegas where tenant_id = v_tenant and activo;

  if v_activas >= v_tenant_row.bodegas_contratadas then
    raise exception 'Alcanzaste el máximo de % bodegas de tu plan. Contrata una bodega adicional desde Suscripción y pagos para agregar más.', v_tenant_row.bodegas_contratadas;
  end if;

  insert into bodegas (tenant_id, nombre, direccion)
  values (v_tenant, p_nombre, p_direccion)
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------- RPC: contratar / quitar bodegas adicionales ----------
create or replace function ajustar_bodegas_contratadas(p_nueva_cantidad int)
returns numeric
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid := current_tenant_id();
  v_tenant_row tenants%rowtype;
  v_activas int;
begin
  if v_tenant is null or not is_manager_or_owner() then
    raise exception 'Solo el dueño o gerente puede cambiar el plan';
  end if;
  select * into v_tenant_row from tenants where id = v_tenant;
  select count(*) into v_activas from bodegas where tenant_id = v_tenant and activo;

  if p_nueva_cantidad < v_tenant_row.bodegas_incluidas then
    raise exception 'El plan incluye % bodegas como mínimo', v_tenant_row.bodegas_incluidas;
  end if;
  if p_nueva_cantidad < v_activas then
    raise exception 'Tienes % bodegas activas. Desactiva alguna antes de reducir el plan a %.', v_activas, p_nueva_cantidad;
  end if;

  update tenants set bodegas_contratadas = p_nueva_cantidad where id = v_tenant;
  return calcular_monto_mensual(v_tenant);
end;
$$;

-- ---------- RPC: archivar / restaurar un cliente (solo Odyssai) ----------
create or replace function archivar_cliente(p_tenant_id uuid, p_motivo text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_super_admin() then
    raise exception 'Solo el staff de Odyssai puede archivar clientes';
  end if;
  update tenants set
    archivado_at = now(),
    archivado_motivo = p_motivo,
    activo = false,
    subscription_status = 'canceled'
  where id = p_tenant_id;
end;
$$;

create or replace function restaurar_cliente(p_tenant_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_super_admin() then
    raise exception 'Solo el staff de Odyssai puede restaurar clientes';
  end if;
  update tenants set
    archivado_at = null,
    archivado_motivo = null,
    activo = true
  where id = p_tenant_id;
end;
$$;

-- ---------- Retrocompatibilidad ----------
-- Hasta ahora todos los operarios veían todas las bodegas de su empresa. Al
-- introducir permisos por bodega, se les concede acceso a todas las bodegas
-- existentes para que nadie pierda acceso con el cambio. De aquí en adelante,
-- el dueño decide bodega por bodega desde su panel.
insert into bodega_accesos (tenant_id, bodega_id, profile_id)
select b.tenant_id, b.id, p.id
from bodegas b
join profiles p on p.tenant_id = b.tenant_id and p.role = 'operator'
on conflict (bodega_id, profile_id) do nothing;
