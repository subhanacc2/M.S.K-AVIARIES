const url = process.env.SUPABASE_URL || 'https://hjgnomjawhozlquobspb.supabase.co';
const secret = process.env.SUPABASE_SECRET_KEY;
if (!secret) {
  console.error('Set SUPABASE_SECRET_KEY');
  process.exit(1);
}

const email = 'admin@mskaviaries.com';
const password = process.env.ADMIN_PASSWORD;
if (!password) {
  console.error('Set ADMIN_PASSWORD');
  process.exit(1);
}

const res = await fetch(`${url}/auth/v1/admin/users`, {
  method: 'POST',
  headers: {
    apikey: secret,
    Authorization: `Bearer ${secret}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    email,
    password,
    email_confirm: true,
    user_metadata: { username: 'admin' },
  }),
});

const text = await res.text();
if (!res.ok) {
  if (text.includes('already been registered') || res.status === 422) {
    console.log('Admin user already exists:', email);
    process.exit(0);
  }
  console.error('Create user failed', res.status, text);
  process.exit(1);
}
console.log('Created admin:', email);
