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

### Novedades de esta vuelta (v2.1)

- **Detalle de producto en el dashboard**: clic en cualquier QR, fila de "ventas
  en riesgo" o fila del historial → modal con stock, valor, historial completo
  del producto y formulario de edición (nombre, precio, stock mínimo, lote,
  vencimiento). Cualquier corrección de stock queda registrada como un
  movimiento auditado, nunca se pisa el número sin dejar rastro.
- **Sección "QRs creados" en la app de operario**: grilla con todos los QR de
  la bodega activa, buscador, y marca visual (borde rojo) para los que tienen
  alerta. Tocar uno abre su detalle (solo lectura) con acceso directo a
  "Registrar movimiento".
- **"Deshacer último escaneo" ahora es realmente por operario**: un operario
  solo puede deshacer su propio último movimiento — reforzado a nivel de base
  de datos (no solo en el cliente), aunque dueños/gerentes sí pueden deshacer
  movimientos de cualquiera para corregir errores.
- **Alertas separadas en 3 secciones**: ⏰ Vencimiento y 📉 Stock mínimo (ambas
  resaltadas en rojo), y 💤 Sin movimiento reciente (informativa).
- **Permisos endurecidos**: solo dueños/gerentes pueden editar productos
  directamente (antes cualquier usuario autenticado del tenant podía hacerlo
  saltándose la UI). Los operarios siguen registrando movimientos normalmente,
  eso no cambió.

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

### 1. Sube esto a un repo de GitHub nuevo — con cuidado con la estructura

⚠️ **El error más común (y el que ya nos pasó una vez): que quede todo anidado
dentro de una carpeta extra.** El zip que te entregué está armado a propósito
para que, al descomprimirlo, los archivos (`public/`, `supabase/`,
`vercel.json`, `package.json`, `README.md`) queden **sueltos**, listos para ir
directo a la raíz del repo — no hay una carpeta `trazipyme-v2/` envolviéndolos.

- Crea el repo nuevo en GitHub (vacío, sin README ni .gitignore automático).
- Descomprime el zip en tu computador.
- Entra a la página del repo → "uploading an existing file" → **arrastra el
  contenido de la carpeta descomprimida** (selecciona `public`, `supabase`,
  `vercel.json`, `package.json`, `README.md` todos juntos y suéltalos ahí).
  No arrastres una carpeta contenedora ni el `.zip` sin descomprimir.
- Verifica en GitHub que en la raíz del repo (justo bajo el botón verde
  "Code") veas directamente `public/`, `supabase/`, `vercel.json`, etc. — si
  ves una sola carpeta y todo adentro, algo se anidó mal, corrígelo antes de
  seguir.

(Alternativa más segura si manejas git: `git init`, `git add .`,
`git commit`, `git remote add origin <url>`, `git push` — así nunca se
introduce una carpeta de más.)

### 2. Conecta con Vercel

1. En Vercel: "Add New" → "Project" → importa el repo.
2. Vercel detecta `vercel.json` (`outputDirectory: public`) automáticamente.
   No hace falta build command ni framework — dale "Deploy".
3. **No debieras necesitar tocar "Root Directory"** en Settings si la
   estructura del repo quedó bien (paso 1). Si en algún despliegue futuro ves
   un 404 con Status "Ready", ese es el primer lugar donde revisar.
4. Listo. `/app`, `/dashboard`, `/admin`, `/invite` y `/reset` quedan servidos
   como subcarpetas estáticas.
5. En Supabase → Authentication → URL Configuration, agrega la URL de
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
4. **(v2.1) Permisos de edición**: un operario que intenta llamar
   `actualizar_producto` directamente → rechazado ("Solo el dueño o gerente
   puede editar productos"). Una dueña sí puede editar y ajustar stock, y el
   ajuste queda registrado en `movimientos` con nota.
5. **(v2.1) Deshacer por operario**: el operario que creó un movimiento sí
   puede deshacerlo; un segundo operario del mismo tenant, distinto, que
   intenta deshacer el movimiento del primero → rechazado ("Solo puedes
   deshacer tus propios movimientos"). Un dueño/gerente sí puede deshacer
   movimientos de cualquiera (para corregir errores del equipo).

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
