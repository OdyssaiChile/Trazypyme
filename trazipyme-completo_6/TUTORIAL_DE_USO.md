# Tutorial de uso — TraziPyme

Esta guía explica cómo usar TraziPyme según tu rol. Hay 3 aplicaciones
distintas (mismo sistema, distinta puerta de entrada):

| Rol | Entra a | Para qué |
|---|---|---|
| **Operario de bodega** | `/app` | Escanear productos, registrar entradas/salidas/muestras |
| **Dueño/a o Gerente** | `/dashboard` | Ver KPIs, alertas, reportes, gestionar equipo y suscripción |
| **Staff Odyssai (super_admin)** | `/admin` | Crear clientes nuevos, ver todos los tenants |

Reemplaza `/app`, `/dashboard`, `/admin` por tu dominio real, por ejemplo
`https://trazipyme.vercel.app/app`.

---

## 🔑 Credenciales de demo

⚠️ Son cuentas de prueba sobre el tenant **"TraziPyme Demo"** (2 bodegas, 7
productos, movimientos de ejemplo). Úsalas para practicar o hacer demos a
prospectos — no para datos reales de un cliente.

| Rol | Correo | Contraseña | Entra a |
|---|---|---|---|
| Operario | `operario@trazipyme-demo.cl` | `Demo#2026` | `/app` |
| Dueña (owner) | `duena@trazipyme-demo.cl` | `Demo#2026` | `/dashboard` |
| Super admin (Odyssai) | `admin@odyssai.cl` | `OdyssaiAdmin#2026` | `/admin` |

---

## 1. Tutorial — Operario de bodega (`/app`)

### Ingresar
1. Abre `/app` en el celular (funciona como acceso directo, no requiere instalar nada de una tienda de apps).
2. Ingresa correo y contraseña → **Ingresar**.
3. Elige la bodega activa arriba (si trabajas en más de una, puedes cambiarla en cualquier momento desde el mismo selector).

### Escanear y registrar un movimiento
1. Menú principal → **Escanear QR**.
2. Apunta la cámara al QR pegado en el producto (o escribe el código manualmente si no tienes cámara a mano o el QR está dañado).
3. El sistema te muestra el producto y su stock actual.
4. Elige el tipo de movimiento:
   - **Entrada**: llegó mercadería.
   - **Salida**: se vendió o se despachó.
   - **Muestra**: salió sin venta (regalo, control de calidad, etc.) — te pedirá quién se la llevó y a dónde va.
5. Ingresa la cantidad → **Confirmar**.

Si escaneas un QR que pertenece a **otra bodega**, el sistema te avisa y te lleva directo a "Crear producto" con los datos precargados, para que generes el QR correspondiente a tu propia bodega.

### Crear un producto nuevo (y su QR)
1. Menú principal → **Crear QR**.
2. Completa nombre, código interno, unidad de medida, lote, vencimiento, precio de costo, stock mínimo y stock inicial.
3. **Generar QR** → aparece el código para imprimir y pegar en el producto.
4. Tip: si ya existe un producto con ese código interno en otra bodega, el sistema te sugiere automáticamente su nombre, precio y stock mínimo.

### Ver todos los QR de tu bodega
1. Menú inferior → **QRs**.
2. Verás la grilla completa de productos de tu bodega, con buscador por nombre o código.
3. Los que tienen un **borde rojo** están en alerta (poco stock o por vencer).
4. Toca cualquiera para ver su detalle: stock actual, historial reciente, y un botón directo para **Registrar movimiento** sin tener que escanear de nuevo.

### Eliminar un QR
- Desde el detalle de cualquier producto (tócalo desde la grilla de QRs) → botón **🗑️ Eliminar este QR**, al final de la pantalla.
- Cualquiera puede eliminar un QR (operario, gerente o dueño) — a diferencia de editar sus datos, que sigue siendo solo de dueño/gerente.
- No se borra nada de verdad: el producto deja de aparecer en las listas activas, pero **todo su historial se conserva** y queda visible para el dueño en el dashboard, con quién lo eliminó y cuándo.

### Ver historial
- Menú inferior → **Historial**: los últimos 30 movimientos de tu bodega activa — incluye entradas/salidas/muestras y también los QR creados, editados o eliminados.

---

## 2. Tutorial — Dueño/a o Gerente (`/dashboard`)

### Ingresar
1. Abre `/dashboard` desde un computador (o celular, también funciona).
2. Ingresa correo y contraseña.
3. Si tu cuenta está en periodo de prueba, verás un aviso amarillo arriba con los días restantes. Si la suscripción está vencida, verás un aviso rojo y el registro de nuevos movimientos quedará bloqueado hasta reactivarla (botón **Activar / renovar plan** en la tarjeta "Suscripción").

### Vista general
Arriba del todo tienes 4 indicadores: SKUs activos, unidades en stock, valor de inventario y alertas activas. Puedes filtrar todo el dashboard por bodega con el selector de arriba a la derecha ("Todas las bodegas" o una en particular).

### Ver y editar el detalle de un producto
Puedes hacer clic en **cualquiera** de estos lugares para abrir la ficha completa de un producto:
- Una tarjeta QR en la sección "Códigos QR"
- Una fila en la tabla "Ventas en riesgo"
- Una fila en "Historial de movimientos"

La ficha te muestra:
- Stock actual, valor de inventario, bodega.
- **Historial completo** de ese producto (no solo los últimos 15) — incluye entradas/salidas/muestras y también cuándo se creó, editó o eliminó el QR.
- Un formulario para editar nombre, precio de costo, stock mínimo, lote y fecha de vencimiento.
- Un campo para **corregir el stock actual** directamente (por ejemplo después de un conteo físico) — esto no se guarda como un número suelto: queda registrado como un movimiento de ajuste en el historial, con la nota que escribas, para que siempre quede trazabilidad de por qué cambió el stock.
- Botón **🗑️ Eliminar este QR** al final — el producto deja de aparecer en las listas activas, pero su historial se conserva.

*(Nota: esta edición directa está disponible solo para dueños/gerentes — los operarios ven la misma ficha pero sin poder editarla, solo consultarla. Eliminar un QR sí lo puede hacer cualquiera, desde `/app` o `/dashboard`.)*

### Alertas
Están divididas en 3 secciones, todas clickeables (te llevan al detalle del producto):
- **⏰ Vencimiento** (en rojo): productos a 15 días o menos de vencer.
- **📉 Stock mínimo** (en rojo): productos con stock igual o por debajo de lo configurado.
- **💤 Sin movimiento reciente**: productos sin ningún movimiento en 7+ días (informativo, no en rojo).

### Reportes
Sección "Reportes exportables" → 3 botones que descargan un CSV (abrible en Excel):
- **Trazabilidad por lote**: todos los movimientos.
- **Mermas y bajas**: solo las salidas por muestra.
- **Valorización de inventario**: stock y valor por producto.

También hay gráficos interactivos para los mismos 3 reportes, más abajo en el dashboard.

### Invitar a tu equipo
1. Sección "Equipo" → completa nombre, correo y rol (Operario o Gerente) de la persona → **Enviar invitación**.
2. El sistema te da un link — cópialo y mándaselo por WhatsApp o correo.
3. Esa persona entra al link, define su propia contraseña, y ya puede usar `/app` (operario) o `/dashboard` (gerente) según el rol que le diste.
4. Puedes ver quién ya es parte del equipo y qué invitaciones están pendientes en esa misma sección.

### Gestionar tu suscripción y pagos
Sección "Suscripción": ves tu plan (Prueba gratuita o Pro), estado, el **monto mensual calculado automáticamente** (base $50.000 + $20.000 por cada bodega adicional a las 2 incluidas), y fecha de próximo cobro o fin de prueba.
- **Activar / renovar plan**: genera un link de pago de MercadoPago — ingresas tu tarjeta una vez y queda con cobro automático cada mes, sin volver a pagar manualmente.
- **Cancelar suscripción**: disponible cuando tu plan está activo o con pago pendiente. Cancela el cobro recurrente en MercadoPago.
- Debajo, la sección **"Historial de pagos"** muestra cada cobro procesado (fecha, monto, estado y método) — se llena solo apenas MercadoPago confirma cada pago, no hay que hacer nada para que aparezca ahí.

---

## 3. Tutorial — Staff Odyssai / super_admin (`/admin`)

Este panel es solo para el equipo interno de Odyssai, no para los clientes — tiene su propio acceso, completamente separado del login de clientes/operarios (aunque compartan el mismo sitio, la sesión de uno nunca se mezcla con la del otro).

### Ingresar
1. Abre `/admin`.
2. Ingresa con la cuenta `admin@odyssai.cl` (o la que le hayan creado a cada persona del equipo).

### Dar de alta un cliente nuevo
1. Sección "Nuevo cliente (onboarding)" → completa solo 4 campos:
   - Nombre de la empresa y RUT (opcional).
   - Nombre y correo del dueño/a.
2. **Crear cliente**. No hay que elegir plan ni ingresar ningún ID — todo cliente nace automáticamente en **prueba gratis de 14 días**.
3. El sistema te devuelve un link para que el dueño/a defina su propia contraseña — mándaselo por WhatsApp.
4. Listo — ese cliente ya puede entrar a `/dashboard` y empezar a usar el sistema. Desde ahí, el mismo dueño/a invita a sus operarios (tú no tienes que crear cada usuario operario a mano).

### Monitorear a todos tus clientes de un vistazo
Arriba de la tabla hay 4 indicadores generales: clientes totales, suscripciones activas, cuántos están en prueba, y el **MRR** (ingreso mensual recurrente — la suma de lo que pagan todos los clientes activos). Útil para ver la salud del negocio sin entrar a cada cliente.

### Ver y gestionar un cliente
La tabla "Clientes existentes" tiene un buscador por nombre, y muestra empresa, estado, **monto mensual calculado** y fecha de próximo cobro/fin de prueba — las pruebas que vencen en 3 días o menos se resaltan en rojo para que no se te pasen. **Haz clic en cualquier fila** para abrir su ficha completa:
- KPIs: estado, monto mensual, cantidad de bodegas, valor de inventario.
- **Datos de la empresa**: editar nombre/RUT, y un botón **Suspender cuenta** / **Reactivar cuenta** — a diferencia de una suscripción vencida (que solo bloquea nuevos movimientos), suspender bloquea el acceso completo: ningún usuario de esa empresa puede iniciar sesión hasta que la reactives.
- **Suscripción**: botones para generar el link de pago de MercadoPago, marcar la suscripción como activa manualmente (si cobraste por fuera), extender la prueba 14 días más, o cancelarla.
- **Bodegas** y **Equipo** del cliente (quién es dueño, gerente, operario).
- **Actividad reciente**: los últimos 20 movimientos registrados — incluye entradas/salidas/muestras y también QR creados, editados o eliminados, para saber de un vistazo si el cliente realmente está usando el sistema.
- **Historial de pagos**: cada cobro que MercadoPago ha procesado para ese cliente, con fecha, monto, estado y método.

Recuerda: el precio siempre es el mismo modelo — $50.000/mes con 2 bodegas incluidas, +$20.000/mes por cada bodega adicional que el cliente active. El sistema lo calcula solo, nunca hay que hacerlo a mano.

`/admin` tiene su propio acceso completamente separado del de tus clientes — no aparece ningún link hacia él en la página de inicio pública del producto; solo el staff de Odyssai que conoce la URL directa puede llegar ahí.

---

## Preguntas frecuentes

**¿Un operario puede editar precios o el stock mínimo de un producto?**
No. Solo puede registrar movimientos (entradas/salidas/muestras), crear productos nuevos y eliminar QR. Editar campos existentes de un producto (nombre, precio, stock mínimo, lote, vencimiento) es exclusivo de dueños/gerentes, desde el dashboard.

**¿Un operario puede eliminar un QR sin permiso del dueño?**
Sí, cualquier miembro del equipo puede eliminar un QR — es intencional, para que cualquiera pueda limpiar productos duplicados o mal creados sobre la marcha. No es destructivo: no se borra nada, el historial completo queda visible para el dueño en el dashboard, incluyendo quién eliminó qué y cuándo.

**¿Qué pasa si dos operarios trabajan en la misma bodega a la vez?**
No hay problema — cada uno ve el mismo stock en tiempo real (el dashboard se refresca solo cada 5 segundos).

**¿Los datos de un cliente se mezclan con los de otro?**
No. Cada empresa (tenant) está completamente aislada a nivel de base de datos — ni un dueño ni un operario pueden ver ni editar datos de otra empresa, aunque estén en el mismo sistema.
