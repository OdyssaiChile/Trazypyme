-- Nota: esta migración usa los valores de enum agregados en 010_*.sql — en
-- Postgres, ALTER TYPE ... ADD VALUE debe quedar confirmado en una
-- transacción separada antes de poder usarse, por eso está en su propio
-- archivo/migración.

-- Permitir cantidad = 0 para los eventos de auditoría (creación/edición/eliminación)
alter table movimientos drop constraint if exists movimientos_cantidad_check;
alter table movimientos add constraint movimientos_cantidad_check check (cantidad >= 0);

-- ---------- RPC: eliminar producto (soft-delete) ----------
-- Cualquier miembro del tenant (operario, gerente o dueño) puede eliminar un QR.
-- No se borra la fila: se marca activo=false para conservar el historial de
-- movimientos intacto (las FK a movimientos siguen siendo válidas). El QR
-- deja de aparecer en las grillas activas, pero su historial sigue visible.
create or replace function eliminar_producto(p_producto_id uuid, p_nota text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid := current_tenant_id();
  v_producto productos%rowtype;
  v_nombre_usuario text;
begin
  if v_tenant is null then raise exception 'No autenticado o sin tenant asignado'; end if;

  select * into v_producto from productos where id = p_producto_id and tenant_id = v_tenant for update;
  if not found then raise exception 'Producto no encontrado'; end if;
  if not v_producto.activo then raise exception 'Este producto ya estaba eliminado'; end if;

  update productos as t set activo = false where t.id = p_producto_id;

  select nombre into v_nombre_usuario from profiles where id = auth.uid();
  insert into movimientos (tenant_id, producto_id, tipo, cantidad, operario_id, operario_nombre, nota)
  values (v_tenant, p_producto_id, 'ELIMINACION', 0, auth.uid(), coalesce(v_nombre_usuario, 'Usuario'), coalesce(p_nota, 'QR eliminado'));
end;
$$;

-- ---------- crear_producto: ahora registra el evento de creación en el historial ----------
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

  select nombre into v_nombre_operario from profiles where id = auth.uid();
  insert into movimientos (tenant_id, producto_id, tipo, cantidad, operario_id, operario_nombre, nota)
  values (v_tenant, v_producto_id, 'CREACION', greatest(p_stock_inicial,0), auth.uid(), coalesce(v_nombre_operario,'Sistema'), 'QR creado' || case when p_stock_inicial > 0 then format(' con %s unidades de stock inicial', p_stock_inicial) else '' end);

  return v_producto_id;
end;
$$;

-- ---------- actualizar_producto: ahora registra el evento de edición en el historial ----------
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
  v_cambios text[] := array[]::text[];
begin
  if v_tenant is null or not is_manager_or_owner() then
    raise exception 'Solo el dueño o gerente puede editar productos';
  end if;

  select * into v_producto from productos where id = p_producto_id and tenant_id = v_tenant for update;
  if not found then raise exception 'Producto no encontrado'; end if;

  select nombre into v_nombre_usuario from profiles where id = auth.uid();

  if p_nombre is not null and p_nombre <> v_producto.nombre then
    v_cambios := array_append(v_cambios, format('nombre "%s"→"%s"', v_producto.nombre, p_nombre));
  end if;
  if p_precio_costo is not null and p_precio_costo <> v_producto.precio_costo then
    v_cambios := array_append(v_cambios, format('precio %s→%s', v_producto.precio_costo, p_precio_costo));
  end if;
  if p_stock_minimo is not null and p_stock_minimo <> v_producto.stock_minimo then
    v_cambios := array_append(v_cambios, format('stock mínimo %s→%s', v_producto.stock_minimo, p_stock_minimo));
  end if;
  if p_fecha_vencimiento is distinct from v_producto.fecha_vencimiento then
    v_cambios := array_append(v_cambios, format('vencimiento %s→%s', coalesce(v_producto.fecha_vencimiento::text,'s/f'), coalesce(p_fecha_vencimiento::text,'s/f')));
  end if;
  if p_lote is not null and p_lote <> coalesce(v_producto.lote,'') then
    v_cambios := array_append(v_cambios, format('lote "%s"→"%s"', coalesce(v_producto.lote,'s/n'), p_lote));
  end if;

  update productos as t set
    nombre = coalesce(p_nombre, t.nombre),
    precio_costo = coalesce(p_precio_costo, t.precio_costo),
    stock_minimo = coalesce(p_stock_minimo, t.stock_minimo),
    fecha_vencimiento = coalesce(p_fecha_vencimiento, t.fecha_vencimiento),
    lote = coalesce(p_lote, t.lote)
  where t.id = p_producto_id;

  if array_length(v_cambios, 1) > 0 then
    insert into movimientos (tenant_id, producto_id, tipo, cantidad, operario_id, operario_nombre, nota)
    values (v_tenant, p_producto_id, 'EDICION', 0, auth.uid(), coalesce(v_nombre_usuario,'Usuario'), 'Editado: ' || array_to_string(v_cambios, ', '));
  end if;

  if p_nuevo_stock is not null and p_nuevo_stock <> v_producto.stock_actual then
    if p_nuevo_stock < 0 then raise exception 'El stock no puede ser negativo'; end if;
    v_delta := p_nuevo_stock - v_producto.stock_actual;
    v_tipo := case when v_delta > 0 then 'ENTRADA' else 'SALIDA' end;
    insert into movimientos (tenant_id, producto_id, tipo, cantidad, operario_id, operario_nombre, nota)
    values (v_tenant, p_producto_id, v_tipo, abs(v_delta), auth.uid(), coalesce(v_nombre_usuario,'Ajuste'), coalesce(p_nota, 'Ajuste manual de stock desde dashboard'));
    update productos as t set stock_actual = p_nuevo_stock where t.id = p_producto_id;
  end if;
end;
$$;
