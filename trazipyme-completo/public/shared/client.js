// Cliente Supabase + helpers de sesión compartidos por /app, /dashboard y /admin
const sb = window.supabase.createClient(window.TRAZI_CONFIG.SUPABASE_URL, window.TRAZI_CONFIG.SUPABASE_ANON_KEY);

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
    .select('id, nombre, email, role, activo, tenant_id, tenants(id, nombre, plan, subscription_status, trial_ends_at, current_period_end)')
    .eq('id', session.user.id)
    .single();
  if (error || !data) return null;
  return {
    id: data.id, nombre: data.nombre, email: data.email, role: data.role,
    activo: data.activo, tenant_id: data.tenant_id, tenant: data.tenants || null,
  };
}

function trazi_subscriptionOk(tenant) {
  if (!tenant) return true; // super_admin sin tenant
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
