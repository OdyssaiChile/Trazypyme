-- ---------- Nota libre para movimientos (ajustes manuales, correcciones) ----------
alter table movimientos add column if not exists nota text;

-- ---------- Endurecer RLS: solo dueño/gerente puede editar productos directamente ----------
-- (los operarios siguen pudiendo mover stock vía registrar_movimiento/crear_producto,
--  que son SECURITY DEFINER y no dependen de esta policy)
drop policy if exists productos_update on productos;
create policy productos_update on productos for update
  using ((tenant_id = current_tenant_id() and is_manager_or_owner()) or is_super_admin());

-- ---------- Endurecer deshacer_movimiento: cada operario solo deshace lo suyo ----------
-- (dueños/gerentes pueden deshacer movimientos de cualquiera, para corregir errores)
create or replace function deshacer_movimiento(p_movimiento_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_mov movimientos%rowtype;
  v_inverso int;
  v_tenant uuid := current_tenant_id();
begin
  select * into v_mov from movimientos where id = p_movimiento_id and tenant_id = v_tenant;
  if not found or v_mov.deshecho then raise exception 'Movimiento no disponible para deshacer'; end if;
  if v_mov.operario_id is distinct from auth.uid() and not is_manager_or_owner() then
    raise exception 'Solo puedes deshacer tus propios movimientos';
  end if;
  v_inverso := case when v_mov.tipo = 'ENTRADA' then -v_mov.cantidad else v_mov.cantidad end;
  update productos as t set stock_actual = t.stock_actual + v_inverso where t.id = v_mov.producto_id;
  update movimientos set deshecho = true where id = p_movimiento_id;
end;
$$;

-- ---------- RPC: editar producto (solo dueño/gerente) + ajuste manual de stock auditado ----------
-- Cualquier corrección de stock queda registrada como un movimiento ENTRADA/SALIDA
-- con nota, para mantener trazabilidad completa (no se permite pisar stock_actual directo).
create or replace function actualizar_producto(
  p_producto_id uuid,
  p_nombre text default null,
  p_precio_costo numeric default null,
  p_stock_minimo int default null,
  p_fecha_vencimiento date default null,
  p_lote text default null,
  p_nuevo_stock int default null,
  p_nota text default null
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_tenant uuid := current_tenant_id();
  v_producto productos%rowtype;
  v_delta int;
  v_tipo movimiento_tipo;
  v_nombre_usuario text;
begin
  if v_tenant is null or not is_manager_or_owner() then
    raise exception 'Solo el dueño o gerente puede editar productos';
  end if;

  select * into v_producto from productos where id = p_producto_id and tenant_id = v_tenant for update;
  if not found then raise exception 'Producto no encontrado'; end if;

  update productos as t set
    nombre = coalesce(p_nombre, t.nombre),
    precio_costo = coalesce(p_precio_costo, t.precio_costo),
    stock_minimo = coalesce(p_stock_minimo, t.stock_minimo),
    fecha_vencimiento = coalesce(p_fecha_vencimiento, t.fecha_vencimiento),
    lote = coalesce(p_lote, t.lote)
  where t.id = p_producto_id;

  if p_nuevo_stock is not null and p_nuevo_stock <> v_producto.stock_actual then
    if p_nuevo_stock < 0 then raise exception 'El stock no puede ser negativo'; end if;
    v_delta := p_nuevo_stock - v_producto.stock_actual;
    v_tipo := case when v_delta > 0 then 'ENTRADA' else 'SALIDA' end;
    select nombre into v_nombre_usuario from profiles where id = auth.uid();
    insert into movimientos (tenant_id, producto_id, tipo, cantidad, operario_id, operario_nombre, nota)
    values (v_tenant, p_producto_id, v_tipo, abs(v_delta), auth.uid(), coalesce(v_nombre_usuario,'Ajuste'), coalesce(p_nota, 'Ajuste manual de stock desde dashboard'));
    update productos as t set stock_actual = p_nuevo_stock where t.id = p_producto_id;
  end if;
end;
$$;
