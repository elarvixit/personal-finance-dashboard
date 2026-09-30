// Vercel serverless function: GET /api/config
// Hands the browser the public Supabase settings from Vercel environment variables.
// Only the project URL and the public anon/publishable key are exposed; both are safe
// to ship to browsers because row-level security protects the data.
// Never put the service_role / secret key here.

function isSecretKey(key) {
  if (key.startsWith('sb_secret_')) return true;
  // Legacy JWT keys carry their role in the payload.
  const parts = key.split('.');
  if (parts.length !== 3) return false;
  try {
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    return payload.role === 'service_role';
  } catch (e) {
    return false;
  }
}

module.exports = (req, res) => {
  const env = process.env;
  const supabaseUrl = (env.SUPABASE_URL || env.NEXT_PUBLIC_SUPABASE_URL || '').trim();
  const supabaseAnonKey = (
    env.SUPABASE_ANON_KEY ||
    env.SUPABASE_PUBLISHABLE_KEY ||
    env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
    env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
    ''
  ).trim();

  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');

  if (supabaseAnonKey && isSecretKey(supabaseAnonKey)) {
    res.statusCode = 500;
    res.end(JSON.stringify({
      error: 'SUPABASE_ANON_KEY is set to a secret service_role key. Replace it with the anon (public) key from Supabase > Project Settings > API.'
    }));
    return;
  }

  res.statusCode = 200;
  res.end(JSON.stringify({
    supabaseUrl: supabaseUrl || null,
    supabaseAnonKey: supabaseAnonKey || null
  }));
};
