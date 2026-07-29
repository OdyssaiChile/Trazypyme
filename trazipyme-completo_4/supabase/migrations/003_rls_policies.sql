alter table tenants enable row level security;
alter table profiles enable row level security;
alter table bodegas enable row level security;
alter table productos enable row level security;
alter table movimientos enable row level security;
alter table invitations enable row level security;

-- ---------- TENANTS ----------
create policy tenants_select on tenants for select
  using (id = current_tenant_id() or is_super_admin());
create policy tenants_update_own on tenants for update
  using (is_super_admin());
create policy tenants_insert on tenants for insert
  with check (is_super_admin());

-- ---------- PROFILES ----------
create policy profiles_select on profiles for select
  using (tenant_id = current_tenant_id() or is_super_admin() or id = auth.uid());
create policy profiles_update_self_or_admin on profiles for update
  using (id = auth.uid() or is_super_admin() or (is_manager_or_owner() and tenant_id = current_tenant_id()));
create policy profiles_insert_admin on profiles for insert
  with check (is_super_admin());

-- ---------- BODEGAS ----------
create policy bodegas_select on bodegas for select
  using (tenant_id = current_tenant_id() or is_super_admin());
create policy bodegas_insert on bodegas for insert
  with check ((tenant_id = current_tenant_id() and is_manager_or_owner() and tenant_subscription_ok(tenant_id)) or is_super_admin());
create policy bodegas_update on bodegas for update
  using ((tenant_id = current_tenant_id() and is_manager_or_owner()) or is_super_admin());

-- ---------- PRODUCTOS ----------
create policy productos_select on productos for select
  using (tenant_id = current_tenant_id() or is_super_admin());
create policy productos_insert on productos for insert
  with check ((tenant_id = current_tenant_id() and tenant_subscription_ok(tenant_id)) or is_super_admin());
create policy productos_update on productos for update
  using ((tenant_id = current_tenant_id() and tenant_subscription_ok(tenant_id)) or is_super_admin());

-- ---------- MOVIMIENTOS ----------
create policy movimientos_select on movimientos for select
  using (tenant_id = current_tenant_id() or is_super_admin());
create policy movimientos_insert on movimientos for insert
  with check ((tenant_id = current_tenant_id() and tenant_subscription_ok(tenant_id)) or is_super_admin());
create policy movimientos_update on movimientos for update
  using ((tenant_id = current_tenant_id() and is_manager_or_owner()) or is_super_admin());

-- ---------- INVITATIONS ----------
create policy invitations_select on invitations for select
  using (tenant_id = current_tenant_id() and is_manager_or_owner() or is_super_admin());
create policy invitations_insert on invitations for insert
  with check ((tenant_id = current_tenant_id() and is_manager_or_owner()) or is_super_admin());
