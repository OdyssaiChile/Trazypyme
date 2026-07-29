-- ---------- Vista con campos calculados (respeta RLS del que consulta) ----------
create or replace view productos_con_estado
with (security_invoker = true)
as
select
  p.*,
  b.nombre as bodega_nombre,
  round(p.precio_costo * p.stock_actual, 2) as valor_inventario,
  (p.fecha_vencimiento - current_date) as dias_para_vencer,
  (p.fecha_vencimiento is not null and (p.fecha_vencimiento - current_date) <= 15) as vencimiento_proximo,
  (p.stock_actual <= p.stock_minimo) as stock_bajo
from productos p
join bodegas b on b.id = p.bodega_id;

-- ---------- RPC: registrar movimiento (atómico, valida stock y suscripción) ----------
create or replace function registrar_movimiento(
  p_producto_id uuid, p_tipo movimiento_tipo, p_cantidad int,
  p_responsable_muestra text default null, p_destino_muestra text default null
) returns table(movimiento_id uuid, stock_actual int)
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid := current_tenant_id();
  v_producto productos%rowtype;
  v_delta int;
  v_mov_id uuid;
  v_nombre text;
begin
  if v_tenant is null then raise exception 'No autenticado o sin tenant asignado'; end if;
  if not tenant_subscription_ok(v_tenant) then raise exception 'Suscripción inactiva: no se pueden registrar movimientos'; end if;
  if p_cantidad is null or p_cantidad <= 0 then raise exception 'Cantidad inválida'; end if;

  select * into v_producto from productos where id = p_producto_id and tenant_id = v_tenant for update;
  if not found then raise exception 'Producto no encontrado'; end if;

  v_delta := case when p_tipo = 'ENTRADA' then p_cantidad else -p_cantidad end;
  if v_producto.stock_actual + v_delta < 0 then
    raise exception 'Stock insuficiente. Disponible: %', v_producto.stock_actual;
  end if;

  select nombre into v_nombre from profiles where id = auth.uid();

  insert into movimientos (tenant_id, producto_id, tipo, cantidad, operario_id, operario_nombre, responsable_muestra, destino_muestra)
  values (v_tenant, p_producto_id, p_tipo, p_cantidad, auth.uid(), coalesce(v_nombre,'Operario'), p_responsable_muestra, p_destino_muestra)
  returning id into v_mov_id;

  update productos as t set stock_actual = t.stock_actual + v_delta where t.id = p_producto_id;

  return query select v_mov_id, (v_producto.stock_actual + v_delta);
end;
$$;

-- ---------- RPC: deshacer movimiento ----------
create or replace function deshacer_movimiento(p_movimiento_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_mov movimientos%rowtype;
  v_inverso int;
  v_tenant uuid := current_tenant_id();
begin
  select * into v_mov from movimientos where id = p_movimiento_id and tenant_id = v_tenant;
  if not found or v_mov.deshecho then raise exception 'Movimiento no disponible para deshacer'; end if;
  v_inverso := case when v_mov.tipo = 'ENTRADA' then -v_mov.cantidad else v_mov.cantidad end;
  update productos set stock_actual = stock_actual + v_inverso where id = v_mov.producto_id;
  update movimientos set deshecho = true where id = p_movimiento_id;
end;
$$;

-- ---------- RPC: crear producto (con stock inicial opcional) ----------
create or replace function crear_producto(
  p_bodega_id uuid, p_codigo_interno text, p_nombre text, p_unidad_medida text,
  p_lote text default null, p_fecha_vencimiento date default null,
  p_precio_costo numeric default 0, p_stock_minimo int default 5, p_stock_inicial int default 0
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_tenant uuid := current_tenant_id();
  v_producto_id uuid;
  v_nombre_operario text;
begin
  if v_tenant is null then raise exception 'No autenticado'; end if;
  if not tenant_subscription_ok(v_tenant) then raise exception 'Suscripción inactiva'; end if;

  insert into productos (tenant_id, bodega_id, codigo_interno, nombre, unidad_medida, lote, fecha_vencimiento, precio_costo, stock_minimo, stock_actual)
  values (v_tenant, p_bodega_id, p_codigo_interno, p_nombre, p_unidad_medida, p_lote, p_fecha_vencimiento, p_precio_costo, p_stock_minimo, greatest(p_stock_inicial,0))
  returning id into v_producto_id;

  if p_stock_inicial > 0 then
    select nombre into v_nombre_operario from profiles where id = auth.uid();
    insert into movimientos (tenant_id, producto_id, tipo, cantidad, operario_id, operario_nombre)
    values (v_tenant, v_producto_id, 'ENTRADA', p_stock_inicial, auth.uid(), coalesce(v_nombre_operario,'Sistema'));
  end if;

  return v_producto_id;
end;
$$;

-- ---------- RPC: invitar usuario (owner/manager invita operarios/gerentes) ----------
create or replace function crear_invitacion(p_email text, p_nombre text, p_role user_role default 'operator')
returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_tenant uuid := current_tenant_id();
  v_id uuid;
begin
  if v_tenant is null or not is_manager_or_owner() then
    raise exception 'Solo el dueño o gerente puede invitar usuarios';
  end if;
  insert into invitations (tenant_id, email, nombre, role, invited_by)
  values (v_tenant, p_email, p_nombre, p_role, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;
