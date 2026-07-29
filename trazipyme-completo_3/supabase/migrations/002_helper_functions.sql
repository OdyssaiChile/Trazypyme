-- ---------- Helpers ----------
create or replace function public.current_tenant_id()
returns uuid
language sql stable security definer
set search_path = public
as $$
  select tenant_id from profiles where id = auth.uid();
$$;

create or replace function public.current_role()
returns user_role
language sql stable security definer
set search_path = public
as $$
  select role from profiles where id = auth.uid();
$$;

create or replace function public.is_super_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce((select role = 'super_admin' from profiles where id = auth.uid()), false);
$$;

create or replace function public.is_manager_or_owner()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce((select role in ('owner','manager','super_admin') from profiles where id = auth.uid()), false);
$$;

create or replace function public.tenant_subscription_ok(t_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce((
    select activo and subscription_status in ('trialing','active')
    from tenants where id = t_id
  ), false);
$$;

-- ---------- Trigger: crea profile automáticamente al crear un auth.user ----------
-- El usuario se crea (por Edge Function con service role) con user_metadata:
-- { tenant_id, nombre, role }
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, tenant_id, nombre, email, role)
  values (
    new.id,
    (new.raw_user_meta_data->>'tenant_id')::uuid,
    coalesce(new.raw_user_meta_data->>'nombre', new.email),
    new.email,
    coalesce((new.raw_user_meta_data->>'role')::user_role, 'operator')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Helper para actualizar estado de suscripción desde el webhook ----------
create or replace function public.touch_tenant_period(p_tenant_id uuid, p_status subscription_status, p_period_end timestamptz, p_stripe_customer text, p_stripe_sub text)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  update tenants set
    subscription_status = p_status,
    current_period_end = coalesce(p_period_end, current_period_end),
    stripe_customer_id = coalesce(p_stripe_customer, stripe_customer_id),
    stripe_subscription_id = coalesce(p_stripe_sub, stripe_subscription_id)
  where id = p_tenant_id;
end;
$$;
