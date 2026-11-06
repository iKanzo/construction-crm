// Invite only after verifying the caller's JWT and active administrator profile.
// SUPABASE_SERVICE_ROLE_KEY must exist only in the Edge Function environment.
import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (req.method !== 'POST') return reply(405, { error: 'method_not_allowed' });
  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) return reply(500, { error: 'server_configuration' });
  const authorization = req.headers.get('Authorization') ?? '';
  if (!/^Bearer\s+\S+$/i.test(authorization)) return reply(401, { error: 'authentication_required' });
  const client = createClient(url, anonKey, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
  const { data: userData, error: authError } = await client.auth.getUser();
  if (authError || !userData.user) return reply(401, { error: 'authentication_required' });
  const { data: profile, error: profileError } = await client.from('profiles')
    .select('role,is_active').eq('id', userData.user.id).maybeSingle();
  if (profileError) return reply(500, { error: 'profile_lookup_failed' });
  if (!profile || profile.role !== 'admin' || !profile.is_active) return reply(403, { error: 'admin_required' });

  let input: unknown;
  try { input = await req.json(); } catch { return reply(400, { error: 'invalid_input' }); }
  if (!input || typeof input !== 'object' || Array.isArray(input)) return reply(400, { error: 'invalid_input' });
  const { email, full_name, role } = input as Record<string, unknown>;
  if (typeof email !== 'string' || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) ||
      typeof full_name !== 'string' || full_name.trim().length < 1 || full_name.trim().length > 200 ||
      (role !== 'manager' && role !== 'executor')) return reply(400, { error: 'invalid_input' });

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await admin.auth.admin.inviteUserByEmail(email.trim().toLowerCase());
  if (error || !data.user) return reply(400, { error: 'invitation_failed' });
  const { error: insertError } = await admin.from('profiles').insert({ id: data.user.id, full_name: full_name.trim(), role });
  if (insertError) {
    // Auth and Postgres are separate operations: do not delete a possibly existing account.
    // The administrator must reconcile this user; never report success without a profile.
    console.error('invite-user: profile creation failed', data.user.id, insertError.code);
    return reply(500, { error: 'profile_creation_failed', user_id: data.user.id });
  }
  return reply(201, { user_id: data.user.id });
});
