const url = process.env.SUPABASE_URL || 'https://hjgnomjawhozlquobspb.supabase.co';
const key = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_KEY;
const email = 'admin@mskaviaries.com';
const password = process.env.ADMIN_PASSWORD;
if (!key || !password) {
  console.error('Set SUPABASE_PUBLISHABLE_KEY and ADMIN_PASSWORD');
  process.exit(1);
}

const res = await fetch(`${url}/auth/v1/token?grant_type=password`, {
  method: 'POST',
  headers: { apikey: key, 'Content-Type': 'application/json' },
  body: JSON.stringify({ email, password }),
});
const body = await res.json();
if (!res.ok) {
  console.error('Login failed', res.status, body);
  process.exit(1);
}
console.log('Login OK, user id:', body.user?.id);
