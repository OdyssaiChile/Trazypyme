-- ---------- RPC: eliminar (desactivar) una bodega ----------
-- Soft-delete, igual que los productos: la bodega deja de aparecer y libera
-- cupo del plan, pero su historial se conserva. Los productos que tuviera
-- adentro también se desactivan (con su registro de auditoría), porque un
-- producto sin bodega activa no tiene sentido operativo.
create or replace function eliminar_bodega(p_bodega_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid := current_tenant_id();
  v_bodega bodegas%rowtype;
  v_nombre_usuario text;
begin
  if v_tenant is null or not is_manager_or_owner() then
    raise exception 'Solo el dueño o gerente puede eliminar bodegas';
  end if;

  select * into v_bodega from bodegas where id = p_bodega_id and tenant_id = v_tenant for update;
  if not found then raise exception 'Bodega no encontrada'; end if;
  if not v_bodega.activo then raise exception 'Esta bodega ya estaba eliminada'; end if;

  select nombre into v_nombre_usuario from profiles where id = auth.uid();

  -- Registrar la eliminación de cada producto que quede dentro (auditoría)
  insert into movimientos (tenant_id, producto_id, tipo, cantidad, operario_id, operario_nombre, nota)
  select v_tenant, p.id, 'ELIMINACION', 0, auth.uid(), coalesce(v_nombre_usuario,'Usuario'),
         'Eliminado junto con la bodega "' || v_bodega.nombre || '"'
  from productos p where p.bodega_id = p_bodega_id and p.tenant_id = v_tenant and p.activo;

  update productos set activo = false where bodega_id = p_bodega_id and tenant_id = v_tenant and activo;
  delete from bodega_accesos where bodega_id = p_bodega_id;
  update bodegas set activo = false where id = p_bodega_id;
end;
$$;

-- ---------- Retiro del sistema de invitaciones por link ----------
-- Se reemplazó por creación directa de cuentas (Edge Function crear-usuario):
-- el dueño asigna correo y contraseña y la cuenta queda lista para usar. Los
-- links no funcionaban bien y agregaban un paso innecesario.
drop function if exists crear_invitacion(text, text, user_role);
drop table if exists invitations cascade;
