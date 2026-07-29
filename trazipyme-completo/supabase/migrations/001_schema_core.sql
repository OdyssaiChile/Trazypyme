-- =========================================================
-- TraziPyme — esquema multi-tenant
-- =========================================================
create extension if not exists "pgcrypto";

create type user_role as enum ('super_admin','owner','manager','operator');
create type subscription_status as enum ('trialing','active','past_due','canceled','incomplete');
create type movimiento_tipo as enum ('ENTRADA','SALIDA','MUESTRA');

-- ---------- Tenants (empresas cliente) ----------
create table tenants (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  rut text,
  plan text not null default 'starter',
  subscription_status subscription_status not null default 'trialing',
  trial_ends_at timestamptz not null default (now() + interval '14 days'),
  stripe_customer_id text,
  stripe_subscription_id text,
  current_period_end timestamptz,
  max_bodegas int not null default 3,
  max_usuarios int not null default 10,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------- Profiles (extiende auth.users) ----------
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  tenant_id uuid references tenants(id) on delete cascade,
  nombre text not null,
  email text not null,
  role user_role not null default 'operator',
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------- Bodegas ----------
create table bodegas (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  nombre text not null,
  direccion text,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------- Productos ----------
create table productos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  bodega_id uuid not null references bodegas(id) on delete cascade,
  codigo_interno text not null,
  nombre text not null,
  unidad_medida text not null,
  lote text,
  fecha_vencimiento date,
  precio_costo numeric(12,2) not null default 0,
  stock_minimo int not null default 5,
  stock_actual int not null default 0,
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);
create index idx_productos_tenant on productos(tenant_id);
create index idx_productos_bodega on productos(bodega_id);
create unique index uq_productos_codigo_bodega on productos(bodega_id, codigo_interno);

-- ---------- Movimientos ----------
create table movimientos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  producto_id uuid not null references productos(id) on delete cascade,
  tipo movimiento_tipo not null,
  cantidad int not null check (cantidad > 0),
  operario_id uuid references profiles(id),
  operario_nombre text not null,
  responsable_muestra text,
  destino_muestra text,
  fecha timestamptz not null default now(),
  deshecho boolean not null default false
);
create index idx_movimientos_tenant on movimientos(tenant_id);
create index idx_movimientos_producto on movimientos(producto_id);

-- ---------- Invitations (onboarding) ----------
create table invitations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  email text not null,
  nombre text not null,
  role user_role not null default 'operator',
  token uuid not null default gen_random_uuid(),
  invited_by uuid references profiles(id),
  expires_at timestamptz not null default (now() + interval '7 days'),
  used_at timestamptz,
  created_at timestamptz not null default now()
);
create index idx_invitations_token on invitations(token);
