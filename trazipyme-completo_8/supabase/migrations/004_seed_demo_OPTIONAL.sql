-- =========================================================
-- OPCIONAL — Datos de demo para ventas/onboarding interno.
-- Crea 1 super_admin de Odyssai + 1 tenant demo con datos de ejemplo.
-- Las contraseñas quedan en texto plano en este archivo: cámbialas
-- apenas las uses, o simplemente no ejecutes esta migración en un
-- proyecto Supabase que vaya a producción con clientes reales.
-- =========================================================
do $$
declare
  v_tenant_id uuid;
  v_bodega1 uuid;
  v_bodega2 uuid;
  v_owner_id uuid := gen_random_uuid();
  v_operator_id uuid := gen_random_uuid();
  v_admin_id uuid := gen_random_uuid();
  v_p1 uuid; v_p2 uuid; v_p3 uuid; v_p4 uuid; v_p5 uuid; v_p6 uuid; v_p7 uuid;
begin
  insert into auth.users
    (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
     raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
     confirmation_token, recovery_token, email_change, email_change_token_new,
     email_change_token_current, phone_change, phone_change_token, reauthentication_token)
  values
    ('00000000-0000-0000-0000-000000000000', v_admin_id, 'authenticated', 'authenticated',
     'admin@odyssai.cl', crypt('OdyssaiAdmin#2026', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}', jsonb_build_object('nombre','Odyssai Admin','role','super_admin'),
     now(), now(), '', '', '', '', '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_admin_id, v_admin_id::text,
    jsonb_build_object('sub', v_admin_id::text, 'email', 'admin@odyssai.cl', 'email_verified', true, 'phone_verified', false),
    'email', now(), now(), now());

  insert into tenants (nombre, rut, plan, subscription_status, trial_ends_at, max_bodegas, max_usuarios)
  values ('TraziPyme Demo', '76.000.000-0', 'pro', 'trialing', now() + interval '14 days', 5, 20)
  returning id into v_tenant_id;

  insert into bodegas (tenant_id, nombre, direccion) values
    (v_tenant_id, 'Bodega Central - Comercial AyB', 'Av. Providencia 1234, Santiago') returning id into v_bodega1;
  insert into bodegas (tenant_id, nombre, direccion) values
    (v_tenant_id, 'Sucursal Sur - Comercial AyB', 'Camino a Melipilla 5678, Santiago') returning id into v_bodega2;

  insert into auth.users
    (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
     raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
     confirmation_token, recovery_token, email_change, email_change_token_new,
     email_change_token_current, phone_change, phone_change_token, reauthentication_token)
  values
    ('00000000-0000-0000-0000-000000000000', v_owner_id, 'authenticated', 'authenticated',
     'duena@trazipyme-demo.cl', crypt('Demo#2026', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}',
     jsonb_build_object('nombre','Carolina (Dueña)','role','owner','tenant_id', v_tenant_id::text),
     now(), now(), '', '', '', '', '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', v_operator_id, 'authenticated', 'authenticated',
     'operario@trazipyme-demo.cl', crypt('Demo#2026', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}',
     jsonb_build_object('nombre','Juan Pérez','role','operator','tenant_id', v_tenant_id::text),
     now(), now(), '', '', '', '', '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values
    (gen_random_uuid(), v_owner_id, v_owner_id::text,
     jsonb_build_object('sub', v_owner_id::text, 'email', 'duena@trazipyme-demo.cl', 'email_verified', true, 'phone_verified', false),
     'email', now(), now(), now()),
    (gen_random_uuid(), v_operator_id, v_operator_id::text,
     jsonb_build_object('sub', v_operator_id::text, 'email', 'operario@trazipyme-demo.cl', 'email_verified', true, 'phone_verified', false),
     'email', now(), now(), now());

  insert into productos (tenant_id, bodega_id, codigo_interno, nombre, unidad_medida, lote, fecha_vencimiento, precio_costo, stock_minimo, stock_actual)
  values (v_tenant_id, v_bodega1, 'JER-001','Jeringas 5ml caja x100','caja','L2026-014', current_date + 12, 8500, 10, 42) returning id into v_p1;
  insert into productos (tenant_id, bodega_id, codigo_interno, nombre, unidad_medida, lote, fecha_vencimiento, precio_costo, stock_minimo, stock_actual)
  values (v_tenant_id, v_bodega1, 'GUA-002','Guantes nitrilo talla M caja x100','caja','L2026-022', current_date + 45, 6200, 15, 8) returning id into v_p2;
  insert into productos (tenant_id, bodega_id, codigo_interno, nombre, unidad_medida, lote, fecha_vencimiento, precio_costo, stock_minimo, stock_actual)
  values (v_tenant_id, v_bodega1, 'MAS-003','Mascarillas quirúrgicas caja x50','caja','L2026-031', current_date + 5, 3100, 20, 31) returning id into v_p3;
  insert into productos (tenant_id, bodega_id, codigo_interno, nombre, unidad_medida, lote, fecha_vencimiento, precio_costo, stock_minimo, stock_actual)
  values (v_tenant_id, v_bodega1, 'ALC-004','Alcohol gel 1L','unidad','L2026-009', current_date + 90, 2900, 12, 3) returning id into v_p4;
  insert into productos (tenant_id, bodega_id, codigo_interno, nombre, unidad_medida, lote, fecha_vencimiento, precio_costo, stock_minimo, stock_actual)
  values (v_tenant_id, v_bodega1, 'TER-005','Termómetro digital infrarrojo','unidad', 'L2026-002', null, 15900, 5, 6) returning id into v_p5;
  insert into productos (tenant_id, bodega_id, codigo_interno, nombre, unidad_medida, lote, fecha_vencimiento, precio_costo, stock_minimo, stock_actual)
  values (v_tenant_id, v_bodega2, 'JER-001','Jeringas 5ml caja x100','caja','L2026-015', current_date + 20, 8500, 10, 18) returning id into v_p6;
  insert into productos (tenant_id, bodega_id, codigo_interno, nombre, unidad_medida, lote, fecha_vencimiento, precio_costo, stock_minimo, stock_actual)
  values (v_tenant_id, v_bodega2, 'SUE-006','Suero fisiológico 500ml caja x20','caja','L2026-040', current_date + 3, 11200, 8, 2) returning id into v_p7;

  insert into movimientos (tenant_id, producto_id, tipo, cantidad, operario_id, operario_nombre, fecha) values
    (v_tenant_id, v_p1, 'ENTRADA', 50, v_operator_id, 'Juan Pérez', now() - interval '2 days'),
    (v_tenant_id, v_p1, 'SALIDA', 8, v_operator_id, 'Juan Pérez', now() - interval '1 days'),
    (v_tenant_id, v_p2, 'ENTRADA', 20, v_operator_id, 'Juan Pérez', now() - interval '5 days'),
    (v_tenant_id, v_p2, 'SALIDA', 12, v_operator_id, 'Juan Pérez', now() - interval '3 hours'),
    (v_tenant_id, v_p3, 'MUESTRA', 2, v_operator_id, 'Juan Pérez', now() - interval '1 hours');
end $$;
