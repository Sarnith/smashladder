// Creates a Team Admin or Scoring User without sending email.
// Deploy with `supabase functions deploy admin-provision-user`.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

type RequestBody = {
  action?: 'provision_user' | 'create_team';
  teamId: string;
  teamName?: string;
  email: string;
  role: 'team_admin' | 'scorer';
  playerId?: number;
  password?: string;
  generatePassword?: boolean;
};

function generatedPassword() {
  // Two UUIDs include sufficient cryptographic randomness and the separator
  // makes the temporary password readable when copied privately.
  return `${crypto.randomUUID()}-${crypto.randomUUID().slice(0, 8)}`;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return Response.json({ error: 'Method not allowed' }, { status: 405, headers: corsHeaders });

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const authorization = request.headers.get('Authorization') || '';
  const token = authorization.replace(/^Bearer\s+/i, '');
  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: actorResult, error: actorError } = await admin.auth.getUser(token);
  if (actorError || !actorResult.user) return Response.json({ error: 'Unauthenticated' }, { status: 401, headers: corsHeaders });

  try {
    const body = await request.json() as RequestBody;
    const email = body.email?.trim().toLowerCase();
    const isCreateTeam = body.action === 'create_team';
    if (!email || !['team_admin', 'scorer'].includes(body.role)) throw new Error('Email and a valid role are required');
    if (isCreateTeam && (!body.teamName?.trim() || body.role !== 'team_admin')) throw new Error('A team name and Team Admin are required');
    if (!isCreateTeam && !body.teamId) throw new Error('teamId is required');
    if (body.role === 'team_admin' || isCreateTeam) {
      const { data: allowed } = await admin.rpc('is_platform_admin_for', { p_user_id: actorResult.user.id });
      if (allowed !== true) return Response.json({ error: 'Only a Platform Admin can appoint a Team Admin' }, { status: 403, headers: corsHeaders });
    } else {
      const { data: allowed } = await admin.rpc('can_manage_team_for', { p_user_id: actorResult.user.id, p_team_id: body.teamId });
      if (allowed !== true) return Response.json({ error: 'Only the Team Admin or Platform Admin can create a Scoring User' }, { status: 403, headers: corsHeaders });
    }

    const temporaryPassword = body.generatePassword ? generatedPassword() : body.password;
    if (!temporaryPassword || temporaryPassword.length < 12) throw new Error('Temporary passwords must contain at least 12 characters');

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password: temporaryPassword,
      email_confirm: true,
    });
    if (createError || !created.user) throw new Error(createError?.message || 'Could not create the account');

    let teamId = body.teamId;
    if (isCreateTeam) {
      const { data: team, error: teamError } = await admin.from('teams').insert({ name: body.teamName!.trim(), created_by: actorResult.user.id }).select('id').single();
      if (teamError || !team) throw new Error(teamError?.message || 'Could not create the team');
      teamId = team.id;
      const { error: metaError } = await admin.from('team_meta').insert({ team_id: teamId, next_id: 1 });
      if (metaError) throw new Error(metaError.message);
    }
    const { error: memberError } = await admin.from('team_members').insert({
      team_id: teamId, user_id: created.user.id, role: body.role, granted_by: actorResult.user.id,
    });
    if (memberError) throw new Error(memberError.message);
    const { error: profileError } = await admin.from('user_profiles').upsert({ user_id: created.user.id, email });
    if (profileError) throw new Error(profileError.message);

    if (body.playerId !== undefined) {
      const playerUpdate = admin.from('team_players').update({ auth_user_id: created.user.id, email });
      const { error: playerError } = await playerUpdate.eq('team_id', teamId).eq('player_id', body.playerId);
      if (playerError) throw new Error(playerError.message);
    }
    await admin.from('team_audit_log').insert({
      team_id: teamId, actor_id: actorResult.user.id, event: isCreateTeam ? 'team_created_with_admin' : 'account_provisioned',
      details: { role: body.role, email, player_id: body.playerId ?? null },
    });
    return Response.json({ teamId, userId: created.user.id, temporaryPassword: body.generatePassword ? temporaryPassword : undefined }, { headers: corsHeaders });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : 'Unable to provision account' }, { status: 400, headers: corsHeaders });
  }
});
