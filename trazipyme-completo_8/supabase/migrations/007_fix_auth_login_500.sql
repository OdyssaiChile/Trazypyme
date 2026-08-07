-- =========================================================
-- Fix: login fallaba con 500 "Database error querying schema"
-- =========================================================
-- Causa raíz #1: los usuarios creados por SQL directo (migración 004, seed
-- de demo) no tenían su fila correspondiente en auth.identities. GoTrue
-- (Supabase Auth) la necesita para resolver login por email/password.
insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select
  gen_random_uuid(),
  u.id,
  u.id::text,
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true, 'phone_verified', false),
  'email',
  now(), now(), now()
from auth.users u
where not exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'email');

-- Causa raíz #2 (la que realmente rompía el login): varias columnas
-- varchar de auth.users quedaron en NULL en vez de '' (email_change y
-- afines). El driver Go de GoTrue las escanea como string no-nullable,
-- así que un NULL ahí revienta CUALQUIER query de login con 500.
update auth.users set
  email_change = coalesce(email_change, ''),
  email_change_token_new = coalesce(email_change_token_new, ''),
  email_change_token_current = coalesce(email_change_token_current, ''),
  phone_change = coalesce(phone_change, ''),
  phone_change_token = coalesce(phone_change_token, ''),
  reauthentication_token = coalesce(reauthentication_token, ''),
  confirmation_token = coalesce(confirmation_token, ''),
  recovery_token = coalesce(recovery_token, '')
where email_change is null
   or email_change_token_new is null
   or email_change_token_current is null
   or phone_change is null
   or phone_change_token is null
   or reauthentication_token is null
   or confirmation_token is null
   or recovery_token is null;

-- Blindaje a futuro: si alguna vez se vuelve a insertar en auth.users por
-- SQL directo (en vez de supabase.auth.admin.createUser, que sí hace esto
-- bien), el trigger crea la identity automáticamente para que esto no se
-- repita.
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

  if not exists (select 1 from auth.identities i where i.user_id = new.id and i.provider = 'email') then
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (
      gen_random_uuid(), new.id, new.id::text,
      jsonb_build_object('sub', new.id::text, 'email', new.email, 'email_verified', true, 'phone_verified', false),
      'email', now(), now(), now()
    );
  end if;

  return new;
end;
$$;
