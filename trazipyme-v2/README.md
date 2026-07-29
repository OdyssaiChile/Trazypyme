# TraziPyme v2 — SaaS multi-tenant (por Odyssai)

Revamp completo del MVP de un solo tenant (SQLite + Express) a una arquitectura
**multi-tenant real**, lista para vender por suscripción a bodegas/pymes: cada
cliente (tenant) tiene sus propios usuarios, bodegas, productos e historial,
completamente aislados por Row Level Security (RLS) en Postgres.

## Qué cambió respecto al prototipo original

| | Prototipo original | v2 (este proyecto) |
|---|---|---|
| Base de datos | SQLite local, un solo negocio | Postgres (Supabase), multi-tenant con RLS |
| Autenticación | PIN de 4 dígitos, sin aislar por empresa | Email + contraseña (Supabase Auth), por tenant |
| Backend | Node/Express + SQLite | Sin servidor propio: frontend habla directo con Supabase (Auth + Postgres + RPC) + 4 Edge Functions para lo que requiere privilegios elevados |
| Roles | Ninguno (todos iguales) | `super_admin` (Odyssai), `owner`, `manager`, `operator` |
| Suscripción | No existía | Tabla `tenants` con estado de suscripción + Stripe Checkout + webhook |
| Onboarding | Manual, editando código | Panel `/admin` para que Odyssai cree clientes nuevos en 1 formulario |

## Arquitectura

- **Base de datos**: Supabase Postgres, proyecto `trazipyme-prod`
  (`https://kqqhbhrovrqpqttlksmz.supabase.co`, org "Nexus", región `sa-east-1`).
- **Tablas**: `tenants`, `profiles` (extiende `auth.users`), `bodegas`, `productos`,
  `movimientos`, `invitations`. Todas con RLS activado — ver `supabase/migrations/`.
- **Aislamiento multi-tenant**: cada fila lleva `tenant_id`; las policies de RLS
  usan `current_tenant_id()` (lee el tenant del usuario autenticado desde
  `profiles`) para que cada empresa solo vea sus propios datos. **Probado**:
  ver sección "Pruebas realizadas" más abajo.
- **Lógica de negocio crítica en RPC (Postgres functions)**, no en el cliente:
  `registrar_movimiento`, `deshacer_movimiento`, `crear_producto`,
  `crear_invitacion`. Esto evita duplicar reglas (stock, suscripción activa)
  en cada frontend y evita condiciones de carrera.
- **4 Edge Functions** (Deno, ya desplegadas en el proyecto):
  - `onboarding` — solo `super_admin`. Crea tenant + usuario dueño + (opcional)
    sesión de pago Stripe inicial.
  - `create-checkout-session` — dueño/gerente activa o renueva su plan.
  - `stripe-webhook` — recibe eventos de Stripe y actualiza `tenants.subscription_status`.
  - `accept-invitation` — el invitado (operario/gerente) define su contraseña
    con el link que le comparte su dueño/gerente.
- **Frontend**: 100% estático (vanilla JS + supabase-js vía CDN), sin build.
  - `/app` — app del operario de bodega (escaneo QR, movimientos, historial).
  - `/dashboard` — panel de dueños/gerentes (KPIs, alertas, reportes CSV,
    gráficos, gestión de equipo, suscripción).
  - `/admin` — panel interno de Odyssai para onboarding de clientes nuevos.
  - `/invite` — el invitado activa su cuenta con el link que recibió.
  - `/reset` — define contraseña para links de recuperación de Supabase.

## Roles y permisos

- **operator**: usa `/app`. Escanea, registra entradas/salidas/muestras, crea
  productos nuevos, ve historial. No entra al dashboard.
- **manager** / **owner**: todo lo anterior + `/dashboard` completo (reportes,
  alertas, invitar usuarios, gestionar suscripción). `owner` es el dueño de la
  cuenta; `manager` es un gerente con los mismos permisos operativos.
- **super_admin**: staff de Odyssai. Entra a `/admin`, ve y crea todos los
  tenants, y tiene acceso de lectura a todo vía RLS (`is_super_admin()`).

## Suscripción / Billing (Stripe)

Cada tenant tiene `subscription_status`: `trialing` (14 días por defecto al
crear el cliente), `active`, `past_due`, `canceled`, `incomplete`.

- Si el estado **no** es `trialing` ni `active`, las funciones
  `registrar_movimiento`, `crear_producto` y la creación de bodegas quedan
  **bloqueadas a nivel de base de datos** (no solo en la UI) — ver
  `tenant_subscription_ok()` en las migraciones.
- El dashboard muestra un banner de aviso durante el trial y un banner de
  bloqueo si la suscripción no está activa, con botón para ir a Stripe Checkout.

### Lo que falta configurar de tu lado (no pude hacerlo yo por seguridad/credenciales)

1. Crea una cuenta de Stripe (o usa la que ya tengan) y crea un **Producto**
   con uno o más **Precios** (mensual/anual, por plan). Copia los `price_id`.
2. En el dashboard de Supabase → Project Settings → Edge Functions → Secrets,
   agrega:
   - `STRIPE_SECRET_KEY` (la de tu cuenta Stripe, modo test o live)
   - `STRIPE_WEBHOOK_SECRET` (se genera al crear el webhook, paso siguiente)
   - `STRIPE_PRICE_ID_STARTER`, `STRIPE_PRICE_ID_PRO`, etc. si quieres
     hardcodear precios por plan (opcional; hoy el price_id se pasa a mano
     desde `/admin` o `/dashboard`).
3. En Stripe Dashboard → Developers → Webhooks, crea un endpoint apuntando a:
   `https://kqqhbhrovrqpqttlksmz.supabase.co/functions/v1/stripe-webhook`
   Eventos a escuchar: `checkout.session.completed`,
   `customer.subscription.created`, `customer.subscription.updated`,
   `customer.subscription.deleted`.
4. (Recomendado) Evalúa Mercado Pago como método de pago local adicional más
   adelante — Stripe se eligió para esta primera vuelta porque su API de
   suscripciones/webhooks es más simple de integrar y funciona bien con
   tarjetas chilenas; Mercado Pago Suscripciones tiene mejor soporte nativo en
   Argentina/Brasil/México que en Chile.

## Flujo de onboarding de un cliente nuevo

1. Staff de Odyssai entra a `/admin` (con su cuenta `super_admin`).
2. Llena: nombre de la empresa, nombre/correo del dueño, plan, y opcionalmente
   el `price_id` de Stripe si quiere generar el link de pago de una.
3. El sistema crea el tenant, el usuario dueño, y devuelve:
   - Un link para que el dueño defina su contraseña (Supabase recovery link).
   - Si se pasó `price_id`: un link de Stripe Checkout.
4. Odyssai envía esos links al cliente (por WhatsApp, coherente con el resto
   del producto Odyssai).
5. El dueño entra a `/dashboard`, y desde ahí puede invitar a sus operarios y
   gerentes (genera un link de invitación por cada uno, para compartir por
   WhatsApp/correo) desde la sección "Equipo".

## Cómo desplegar

Este proyecto es **estático** — no necesita servidor Node en producción.

1. Sube esta carpeta a un repo de GitHub.
2. En Vercel: "New Project" → importa el repo → Vercel detecta `vercel.json`
   (`outputDirectory: public`) automáticamente. Sin build command.
3. Listo. `/app`, `/dashboard`, `/admin`, `/invite` y `/reset` quedan servidos
   como subcarpetas estáticas.
4. En Supabase → Authentication → URL Configuration, agrega la URL de
   producción de Vercel a "Redirect URLs" (necesario para que los links de
   `/reset` funcionen correctamente tras el despliegue).

Para desarrollo local: `npm run dev` (sirve `public/` en `localhost:3000` con
`npx serve`).

## Credenciales de demo (proyecto ya provisionado y con datos de ejemplo)

⚠️ **Son contraseñas de prueba visibles en el código. Cámbialas o elimina
estos usuarios antes de vender a un cliente real** (la migración que las crea
está aislada en `supabase/migrations/004_seed_demo_OPTIONAL.sql`).

| Rol | Correo | Contraseña | Dónde entra |
|---|---|---|---|
| Super admin (Odyssai) | `admin@odyssai.cl` | `OdyssaiAdmin#2026` | `/admin` |
| Dueña (tenant demo) | `duena@trazipyme-demo.cl` | `Demo#2026` | `/dashboard` |
| Operario (tenant demo) | `operario@trazipyme-demo.cl` | `Demo#2026` | `/app` |

El tenant demo ("TraziPyme Demo") trae 2 bodegas, 7 productos y movimientos de
ejemplo — igual que el prototipo original — para que puedas hacer demos de
venta sin depender de datos reales de ningún cliente.

## Pruebas realizadas (antes de entregar)

Corrí pruebas directas contra la base de datos de producción para validar lo
crítico antes de dártelo por bueno:

1. **`registrar_movimiento` + `deshacer_movimiento`**: entrada de 5 unidades
   sobre un producto con stock 42 → sube a 47 → deshacer → vuelve a 42.
   Encontré y corregí un bug real en el camino (ambigüedad de columna
   `stock_actual` entre el parámetro de retorno de la función y la columna de
   la tabla, que habría roto todos los movimientos en producción).
2. **Aislamiento multi-tenant**: un operario del tenant demo crea un producto
   nuevo → lo ve (1 fila). Un dueño de una empresa distinta, con su propia
   sesión, intenta leer ese mismo producto por id → 0 filas. RLS funcionando
   como se espera.
3. Encontré y corregí un segundo bug en `crear_invitacion` (intentaba meter
   dos columnas de un `RETURNING` en una sola variable).

Todo esto se hizo dentro de transacciones que terminan en `ROLLBACK`
(vía una excepción forzada), así que **no quedaron datos de prueba** en tu
base — los conteos de filas de las tablas están intactos.

## Pendientes / próximos pasos recomendados

- **Stripe**: falta que configures las llaves y el webhook (ver sección de
  arriba) — sin eso, el botón "Activar/renovar plan" no funcionará aunque el
  resto del producto sí opera normalmente en modo trial.
- **Envío de correos**: hoy los links de invitación/reset se generan pero
  Odyssai los reenvía manualmente (WhatsApp/correo) — no hay un proveedor de
  email transaccional conectado. Si más adelante quieres que salgan solos,
  se puede conectar Resend/Postmark a las Edge Functions.
- **Límites de plan**: `tenants.max_bodegas` y `tenants.max_usuarios` ya
  existen en el esquema pero todavía no se validan al crear bodegas/usuarios —
  fácil de agregar cuando definan los límites reales por plan.
- **INAPI / marca**: sin relación con este proyecto, pero recuerda que sigue
  pendiente el registro de marca que ya tenían identificado como urgente.
