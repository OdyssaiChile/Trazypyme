// Cliente Supabase + helpers de sesión compartidos por /app, /dashboard y /admin
// Cada app tiene su PROPIA sesión (storageKey distinto): iniciar sesión en el
// dashboard como dueño/gerente nunca afecta la sesión de /admin ni de /app, y
// viceversa. Así el acceso de Odyssai queda realmente separado del de los
// clientes, aunque vivan en el mismo dominio.
function trazi_storageKey() {
  if (location.pathname.startsWith('/admin')) return 'trazi-session-odyssai-admin';
  if (location.pathname.startsWith('/dashboard')) return 'trazi-session-dashboard';
  return 'trazi-session-app';
}
const sb = window.supabase.createClient(window.TRAZI_CONFIG.SUPABASE_URL, window.TRAZI_CONFIG.SUPABASE_ANON_KEY, {
  auth: { storageKey: trazi_storageKey(), persistSession: true, autoRefreshToken: true },
});

async function trazi_login(email, password) {
  const { data, error } = await sb.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data.session;
}

async function trazi_logout() {
  await sb.auth.signOut();
}

// Devuelve { id, nombre, email, role, tenant_id, tenant } o null si no hay sesión
async function trazi_getProfile() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) return null;
  const { data, error } = await sb
    .from('profiles')
    .select('id, nombre, email, role, activo, tenant_id, tenants(id, nombre, plan, subscription_status, activo, trial_ends_at, current_period_end, bodegas_incluidas, precio_base_clp, precio_bodega_adicional_clp, mp_preapproval_id)')
    .eq('id', session.user.id)
    .single();
  if (error || !data) return null;
  return {
    id: data.id, nombre: data.nombre, email: data.email, role: data.role,
    activo: data.activo, tenant_id: data.tenant_id, tenant: data.tenants || null,
  };
}

// false si la cuenta está suspendida (tenants.activo=false) o si la
// suscripción no está en un estado que permita operar (trialing/active).
function trazi_subscriptionOk(tenant) {
  if (!tenant) return true; // super_admin sin tenant
  if (tenant.activo === false) return false;
  return ['trialing', 'active'].includes(tenant.subscription_status);
}

async function trazi_callFunction(name, body) {
  const { data: { session } } = await sb.auth.getSession();
  const res = await fetch(`${window.TRAZI_CONFIG.FUNCTIONS_URL}/${name}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(session ? { Authorization: `Bearer ${session.access_token}` } : {}),
      apikey: window.TRAZI_CONFIG.SUPABASE_ANON_KEY,
    },
    body: JSON.stringify(body || {}),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || 'Error al llamar ' + name);
  return data;
}

function trazi_fmtCLP(n) {
  return '$' + Math.round(n || 0).toLocaleString('es-CL');
}
