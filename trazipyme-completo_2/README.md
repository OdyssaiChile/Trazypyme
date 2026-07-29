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

### Novedades de esta vuelta (v2.2)

- **Bug real corregido**: "Crear cliente" en `/admin` fallaba con un error
  `{}` poco claro. La causa era un trigger propio que chocaba con la
  creación normal de usuarios vía la API de Supabase — rompía la creación
  de *cualquier* usuario nuevo, no solo del onboarding. Corregido y probado
  de punta a punta contra la base real.
- **Sesiones aisladas por app**: `/app`, `/dashboard` y `/admin` ahora
  guardan su sesión de login en un lugar separado del navegador. Antes,
  iniciar sesión en una podía "contaminar" a las otras (por eso apareció
  el error de "Acceso restringido" al entrar a `/admin` después de haber
  entrado al dashboard). Ahora cada una es un acceso genuinamente
  independiente.
- **Modelo de planes simplificado**: se acabaron los planes
  Starter/Pro/Enterprise inventados. Ahora solo existe `trial` (14 días
  gratis) y `pro` (único plan pago: $50.000/mes con 2 bodegas incluidas,
  +$20.000/mes por bodega adicional). El monto se calcula siempre con la
  misma función (`calcular_monto_mensual`), nunca a mano.
- **Pivot completo de Stripe a MercadoPago**: se retiraron las funciones de
  Stripe y se reemplazaron por `crear-suscripcion-mercadopago` y
  `mercadopago-webhook`, usando Preapproval (pago recurrente automático:
  el cliente ingresa su tarjeta una vez y MercadoPago cobra solo cada mes).
  Ya no se pide ningún ID manual en ningún formulario.
- **Panel `/admin` mucho más completo**: el onboarding quedó con solo 4
  campos (sin plan ni ID). La tabla de clientes ahora es clickeable y abre
  una ficha completa: estado y monto de suscripción, bodegas, equipo,
  últimos 20 movimientos de actividad, y botones para generar el link de
  pago, marcar activa manualmente, extender prueba o cancelar.

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
  `actualizar_producto`, `crear_invitacion`, `calcular_monto_mensual`. Esto
  evita duplicar reglas (stock, suscripción activa, precio) en cada frontend
  y evita condiciones de carrera.
- **4 Edge Functions** (Deno, ya desplegadas en el proyecto):
  - `onboarding` — solo `super_admin`. Crea tenant (en trial) + usuario dueño.
  - `crear-suscripcion-mercadopago` — dueño/gerente (o Odyssai en su nombre)
    activa o renueva el plan Pro; calcula el monto solo, sin IDs manuales.
  - `mercadopago-webhook` — recibe notificaciones de MercadoPago y actualiza
    `tenants.subscription_status` automáticamente.
  - `accept-invitation` — el invitado (operario/gerente) define su contraseña
    con el link que le comparte su dueño/gerente.
- **Sesiones completamente aisladas por app**: `/app`, `/dashboard` y
  `/admin` guardan su sesión de login en un lugar distinto del navegador
  (`storageKey` separado en el cliente de Supabase). Iniciar sesión como
  dueño/gerente en el dashboard nunca afecta la sesión de `/admin`, ni
  viceversa — cada superficie tiene login genuinamente independiente aunque
  compartan dominio.
- **Frontend**: 100% estático (vanilla JS + supabase-js vía CDN), sin build.
  - `/app` — app del operario de bodega (escaneo QR, movimientos, historial,
    grilla de QRs con alertas, detalle de producto).
  - `/dashboard` — panel de dueños/gerentes (KPIs, alertas por vencimiento y
    stock mínimo, reportes CSV, gráficos, gestión de equipo, detalle/edición
    de producto, suscripción).
  - `/admin` — panel interno de Odyssai: onboarding de clientes nuevos y
    ficha completa por cliente (equipo, bodegas, actividad reciente, monto
    mensual calculado, generación de link de pago, marcar activa/cancelar
    manualmente, extender prueba).
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

## Planes y suscripción (MercadoPago)

Solo existen 2 estados de negocio por tenant:

- **Trial**: 14 días gratis, automático al crear el cliente. No es algo que
  el staff elija — todo cliente nuevo nace así.
- **Pro** (único plan pago): **$50.000 CLP/mes**, incluye **2 bodegas**.
  Cada bodega adicional activa cuesta **+$20.000 CLP/mes**. El monto se
  calcula solo — nunca hay que ingresar un precio a mano en ningún lado.
  La única fuente de verdad para ese cálculo es la función de base de datos
  `calcular_monto_mensual(tenant_id)`, usada tanto por el dashboard como por
  el panel admin y la función que crea la suscripción.

`tenants.subscription_status` puede ser: `trialing`, `active`, `past_due`,
`canceled`, `incomplete`.

- Si el estado **no** es `trialing` ni `active`, las funciones
  `registrar_movimiento`, `crear_producto` y la creación de bodegas quedan
  **bloqueadas a nivel de base de datos** (no solo en la UI) — ver
  `tenant_subscription_ok()` en las migraciones.
- El dashboard muestra un banner de aviso durante el trial y un banner de
  bloqueo si la suscripción no está activa, con un botón que genera el link
  de pago de MercadoPago sin pedir ningún dato adicional.

### Cómo funciona el cobro (MercadoPago Suscripciones / Preapproval)

Cuando el dueño/gerente (o Odyssai desde `/admin`) hace clic en "Generar
link de pago" / "Activar plan", la función `crear-suscripcion-mercadopago`:
1. Calcula el monto mensual real (base + bodegas extra).
2. Crea una **Preapproval** en MercadoPago (su mecanismo de pago recurrente/
   suscripción) por ese monto, en CLP.
3. Devuelve un link (`init_point`) donde el cliente ingresa su tarjeta **una
   sola vez** — MercadoPago cobra automáticamente cada mes desde ahí en
   adelante, sin que el cliente tenga que volver a pagar manualmente.
4. MercadoPago avisa por webhook (`mercadopago-webhook`) cuando el pago se
   autoriza, se pausa (tarjeta rechazada) o se cancela, y el sistema
   actualiza `subscription_status` automáticamente.

### Lo que falta configurar de tu lado (no pude hacerlo yo por seguridad/credenciales)

1. Crea (o usa) una cuenta de MercadoPago para Odyssai y obtén tu
   **Access Token** de producción (Mercado Pago → Tu negocio → Configuración
   → Credenciales de producción).
2. En el dashboard de Supabase → Project Settings → Edge Functions → Secrets,
   agrega: `MERCADOPAGO_ACCESS_TOKEN`.
3. En MercadoPago → Tus integraciones → Webhooks, crea uno apuntando a:
   `https://kqqhbhrovrqpqttlksmz.supabase.co/functions/v1/mercadopago-webhook`
   Eventos a escuchar: `preapproval` y `payment`.
4. Prueba primero con credenciales de **test** de MercadoPago antes de pasar
   a producción — así puedes simular pagos sin cobrar tarjetas reales.

Mientras esto no esté configurado, todo el resto del producto sigue
funcionando normal (trial de 14 días, uso completo de `/app` y `/dashboard`);
solo el botón de activar/renovar plan no podrá completarse hasta que agregues
el `MERCADOPAGO_ACCESS_TOKEN`.

## Flujo de onboarding de un cliente nuevo

1. Staff de Odyssai entra a `/admin` (con su cuenta `super_admin`).
2. Llena solo 4 campos: nombre de la empresa, RUT (opcional), nombre y
   correo del dueño/a. No hay que elegir plan ni ingresar ningún ID — todo
   cliente nace en trial de 14 días.
3. El sistema crea el tenant y el usuario dueño, y devuelve un link para que
   el dueño defina su contraseña (Supabase recovery link).
4. Odyssai envía ese link al cliente (por WhatsApp, coherente con el resto
   del producto Odyssai).
5. El dueño entra a `/dashboard`, y desde ahí puede invitar a sus operarios y
   gerentes (genera un link de invitación por cada uno, para compartir por
   WhatsApp/correo) desde la sección "Equipo".
6. Cuando corresponda cobrar (fin del trial, o el cliente quiere más
   bodegas), Odyssai entra a la ficha del cliente en `/admin` (clic en la
   fila) y genera ahí el link de pago de MercadoPago — o el propio dueño lo
   genera desde su dashboard.

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

## Incidente resuelto: error 500 al iniciar sesión (ya corregido)

Después de la primera entrega, el login fallaba en producción con
`Correo o contraseña incorrectos` aunque las credenciales eran correctas.
La causa real (confirmada revisando los logs del servicio de Auth):

1. Los usuarios de demo se habían creado insertando directo en `auth.users`
   por SQL, sin su fila correspondiente en `auth.identities` (que Supabase
   Auth necesita para resolver el login por correo/contraseña).
2. Más grave: varias columnas de texto de `auth.users` (`email_change` y
   afines) quedaron en `NULL` en vez de `''`. El driver de Supabase Auth no
   tolera `NULL` ahí y revienta con `500 Database error querying schema`
   en **cualquier** intento de login, sin importar si la contraseña era
   correcta.

**Ya está corregido en la base de datos en producción** (migración
`007_fix_auth_login_500.sql`) y también en el archivo de seed
(`004_seed_demo_OPTIONAL.sql`), para que si alguna vez recreas el proyecto
desde cero con estas migraciones, el problema no vuelva a aparecer.

Lección para el futuro: si necesitas crear usuarios por SQL directo en vez
de `supabase.auth.admin.createUser()` (que sí hace todo esto bien
automáticamente), siempre completa explícitamente `email_change`,
`email_change_token_new`, `email_change_token_current`, `phone_change`,
`phone_change_token`, `reauthentication_token` con `''` (nunca `NULL`), y
crea manualmente la fila correspondiente en `auth.identities`.

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
6. **(v2.2) Onboarding de punta a punta**: creé un cliente real vía la
   función `onboarding` → tenant creado en `trial`, usuario dueño creado con
   rol `owner`, ambos verificados directamente en la base. Encontré y
   corregí el bug del trigger que chocaba con la creación de usuarios (ver
   sección de incidentes arriba).
7. **(v2.2) `calcular_monto_mensual`**: verificado que un tenant con las 2
   bodegas incluidas (sin extras) calcula exactamente $50.000.
8. **(v2.2) Default de plan**: confirmé que el valor por defecto de
   `tenants.plan` había quedado en `'starter'` (heredado del esquema
   original) y lo corregí a `'trial'` — sin este fix, todo cliente nuevo
   habría nacido con un plan que ya no existe en el producto.

Todo esto se hizo dentro de transacciones que terminan en `ROLLBACK`
(vía una excepción forzada) o limpiando explícitamente los datos de prueba
después, así que **no quedaron datos de prueba** en tu base — los conteos
de filas de las tablas están intactos.

## Pendientes / próximos pasos recomendados

- **MercadoPago**: falta que configures el Access Token y el webhook (ver
  sección de arriba) — sin eso, el botón "Generar link de pago" no podrá
  completarse, aunque el resto del producto sí opera normalmente en modo
  trial. Mientras tanto, `/admin` tiene un botón "Marcar activa (pago
  manual)" para llevar la cuenta a mano si cobras por fuera.
- **Envío de correos**: hoy los links de invitación/reset se generan pero
  Odyssai los reenvía manualmente (WhatsApp/correo) — no hay un proveedor de
  email transaccional conectado. Si más adelante quieres que salgan solos,
  se puede conectar Resend/Postmark a las Edge Functions.
- **INAPI / marca**: sin relación con este proyecto, pero recuerda que sigue
  pendiente el registro de marca que ya tenían identificado como urgente.
