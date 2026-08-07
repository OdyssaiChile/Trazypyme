-- Nota: usa los valores de enum agregados en 016_*.sql — en Postgres,
-- ALTER TYPE ... ADD VALUE debe confirmarse en una transacción separada
-- antes de poder usarse, por eso van en archivos distintos.

alter table movimientos add column if not exists traspaso_id uuid;
create index if not exists idx_movimientos_traspaso on movimientos(traspaso_id);

-- ---------- RPC: traspasar stock entre bodegas ----------
-- Mueve unidades de un producto desde su bodega a otra del mismo tenant.
-- Si en destino ya existe un producto con el mismo código interno, le suma
-- el stock; si no, lo crea allá copiando sus datos. Todo en una sola
-- transacción: o se mueve completo, o no se mueve nada.
create or replace function traspasar_stock(
  p_producto_id uuid,
  p_bodega_destino_id uuid,
  p_cantidad int,
  p_motivo text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid := current_tenant_id();
  v_origen productos%rowtype;
  v_bodega_origen bodegas%rowtype;
  v_bodega_destino bodegas%rowtype;
  v_destino_id uuid;
  v_traspaso_id uuid := gen_random_uuid();
  v_nombre_usuario text;
begin
  if v_tenant is null then raise exception 'No autenticado'; end if;
  if not tenant_subscription_ok(v_tenant) then raise exception 'Suscripción inactiva'; end if;
  if p_cantidad <= 0 then raise exception 'La cantidad a traspasar debe ser mayor a cero'; end if;

  select * into v_origen from productos
    where id = p_producto_id and tenant_id = v_tenant and activo for update;
  if not found then raise exception 'Producto no encontrado'; end if;

  select * into v_bodega_origen from bodegas where id = v_origen.bodega_id;
  select * into v_bodega_destino from bodegas
    where id = p_bodega_destino_id and tenant_id = v_tenant and activo;
  if not found then raise exception 'Bodega de destino no encontrada'; end if;
  if v_origen.bodega_id = p_bodega_destino_id then
    raise exception 'El producto ya está en esa bodega';
  end if;

  -- Hay que tener acceso a AMBAS bodegas para poder traspasar
  if not (puede_ver_bodega(v_origen.bodega_id) and puede_ver_bodega(p_bodega_destino_id)) then
    raise exception 'No tienes acceso a una de las dos bodegas';
  end if;

  if v_origen.stock_actual < p_cantidad then
    raise exception 'Stock insuficiente: hay % y quieres traspasar %', v_origen.stock_actual, p_cantidad;
  end if;

  select nombre into v_nombre_usuario from profiles where id = auth.uid();

  select id into v_destino_id from productos
    where tenant_id = v_tenant and bodega_id = p_bodega_destino_id
      and codigo_interno = v_origen.codigo_interno and activo
    limit 1;

  if v_destino_id is null then
    insert into productos (tenant_id, bodega_id, codigo_interno, nombre, unidad_medida, lote,
                           fecha_vencimiento, precio_costo, stock_minimo, stock_actual)
    values (v_tenant, p_bodega_destino_id, v_origen.codigo_interno, v_origen.nombre,
            v_origen.unidad_medida, v_origen.lote, v_origen.fecha_vencimiento,
            v_origen.precio_costo, v_origen.stock_minimo, 0)
    returning id into v_destino_id;
  end if;

  update productos set stock_actual = stock_actual - p_cantidad where id = p_producto_id;
  update productos set stock_actual = stock_actual + p_cantidad where id = v_destino_id;

  insert into movimientos (tenant_id, producto_id, tipo, cantidad, operario_id, operario_nombre, nota, traspaso_id)
  values (v_tenant, p_producto_id, 'TRASPASO_SALIDA', p_cantidad, auth.uid(), coalesce(v_nombre_usuario,'Usuario'),
          'Enviado a ' || v_bodega_destino.nombre || coalesce(' · ' || p_motivo, ''), v_traspaso_id);

  insert into movimientos (tenant_id, producto_id, tipo, cantidad, operario_id, operario_nombre, nota, traspaso_id)
  values (v_tenant, v_destino_id, 'TRASPASO_ENTRADA', p_cantidad, auth.uid(), coalesce(v_nombre_usuario,'Usuario'),
          'Recibido desde ' || v_bodega_origen.nombre || coalesce(' · ' || p_motivo, ''), v_traspaso_id);

  return v_traspaso_id;
end;
$$;
