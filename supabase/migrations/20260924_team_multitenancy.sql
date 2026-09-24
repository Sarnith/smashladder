-- Smash Ladder multi-team migration.
-- This is additive: the five original global tables remain untouched for rollback.
begin;

create extension if not exists pgcrypto;

do $$ begin
  create type public.team_member_role as enum ('team_admin', 'scorer');
exception when duplicate_object then null;
end $$;

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  name_key text generated always as (lower(btrim(name))) stored unique,
  viewer_passcode_hash text,
  viewer_passcode_created_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_by uuid references auth.users(id),
  granted_at timestamptz not null default now()
);

create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.team_members (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.team_member_role not null,
  granted_by uuid references auth.users(id),
  granted_at timestamptz not null default now(),
  primary key (team_id, user_id)
);

-- A player belongs to a team even when they do not have a login account.
-- player_id preserves the IDs embedded in the historical session JSON.
create table if not exists public.team_players (
  team_id uuid not null references public.teams(id) on delete cascade,
  player_id bigint not null,
  name text not null,
  email text,
  auth_user_id uuid unique references auth.users(id) on delete set null,
  rank integer not null check (rank > 0),
  total_pts integer not null default 0,
  wins integer not null default 0,
  losses integer not null default 0,
  sessions_count integer not null default 0,
  rank_delta integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (team_id, player_id),
  unique (team_id, email)
);

create table if not exists public.team_sessions (
  team_id uuid not null references public.teams(id) on delete cascade,
  id text not null,
  pos integer not null check (pos >= 0),
  data jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (team_id, id),
  unique (team_id, pos)
);

create table if not exists public.team_active_sessions (
  team_id uuid primary key references public.teams(id) on delete cascade,
  data jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.team_meta (
  team_id uuid primary key references public.teams(id) on delete cascade,
  next_id bigint not null default 1 check (next_id > 0),
  updated_at timestamptz not null default now()
);

-- Viewers are anonymous Supabase users. Their supplied email is deliberately not
-- treated as verified identity; it is only an access record for the team admin.
create table if not exists public.viewer_access (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  entered_email text not null,
  granted_at timestamptz not null default now(),
  primary key (team_id, user_id)
);

create table if not exists public.team_audit_log (
  id bigint generated always as identity primary key,
  team_id uuid references public.teams(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  event text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Holds a passcode only for the short period in which the Team Admin may
-- reopen it. It is not readable directly by any client role.
create table if not exists public.team_passcode_windows (
  team_id uuid primary key references public.teams(id) on delete cascade,
  passcode text not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists team_members_user_id_idx on public.team_members(user_id);
create index if not exists viewer_access_user_id_idx on public.viewer_access(user_id);
create index if not exists team_audit_log_team_created_idx on public.team_audit_log(team_id, created_at desc);

create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.platform_admins where user_id = auth.uid()) $$;

-- These helper functions are called only by the server-side provisioning function.
-- They accept an explicit actor ID because the service key deliberately bypasses RLS.
create or replace function public.is_platform_admin_for(p_user_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.platform_admins where user_id = p_user_id) $$;

create or replace function public.can_manage_team_for(p_user_id uuid, p_team_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_platform_admin_for(p_user_id)
      or exists (select 1 from public.team_members where team_id = p_team_id and user_id = p_user_id and role = 'team_admin');
$$;

create or replace function public.is_team_admin(p_team_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_platform_admin()
      or exists (select 1 from public.team_members where team_id = p_team_id and user_id = auth.uid() and role = 'team_admin');
$$;

create or replace function public.can_view_team(p_team_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_platform_admin()
      or exists (select 1 from public.team_members where team_id = p_team_id and user_id = auth.uid())
      or exists (select 1 from public.viewer_access where team_id = p_team_id and user_id = auth.uid());
$$;

create or replace function public.can_score_team(p_team_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_team_admin(p_team_id)
      or exists (select 1 from public.team_members where team_id = p_team_id and user_id = auth.uid() and role = 'scorer');
$$;

create or replace function public.list_accessible_teams()
returns table(team_id uuid, team_name text, app_role text) language sql stable security definer set search_path = public
as $$
  select t.id, t.name, 'platform_admin'
  from public.teams t where public.is_platform_admin()
  union
  select t.id, t.name, m.role::text
  from public.team_members m join public.teams t on t.id = m.team_id
  where m.user_id = auth.uid() and not public.is_platform_admin()
  union
  select t.id, t.name, 'viewer'
  from public.viewer_access v join public.teams t on t.id = v.team_id
  where v.user_id = auth.uid() and not public.is_platform_admin()
$$;

revoke all on function public.is_platform_admin() from public;
revoke all on function public.is_team_admin(uuid) from public;
revoke all on function public.can_view_team(uuid) from public;
revoke all on function public.can_score_team(uuid) from public;
grant execute on function public.is_platform_admin() to authenticated, anon;
grant execute on function public.is_platform_admin_for(uuid) to service_role;
grant execute on function public.can_manage_team_for(uuid, uuid) to service_role;
grant execute on function public.is_team_admin(uuid) to authenticated, anon;
grant execute on function public.can_view_team(uuid) to authenticated, anon;
grant execute on function public.can_score_team(uuid) to authenticated, anon;
grant execute on function public.list_accessible_teams() to authenticated, anon;

alter table public.teams enable row level security;
alter table public.platform_admins enable row level security;
alter table public.user_profiles enable row level security;
alter table public.team_members enable row level security;
alter table public.team_players enable row level security;
alter table public.team_sessions enable row level security;
alter table public.team_active_sessions enable row level security;
alter table public.team_meta enable row level security;
alter table public.viewer_access enable row level security;
alter table public.team_audit_log enable row level security;
alter table public.team_passcode_windows enable row level security;

create policy "team visible to authorised users" on public.teams for select using (public.can_view_team(id));
create policy "platform admins manage teams" on public.teams for all using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy "platform admins read platform admins" on public.platform_admins for select using (public.is_platform_admin());
create policy "platform admins manage platform admins" on public.platform_admins for all using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy "team admins see member profiles" on public.user_profiles for select using (
  user_id = auth.uid() or public.is_platform_admin() or exists (select 1 from public.team_members m where m.user_id = public.user_profiles.user_id and public.is_team_admin(m.team_id))
);
create policy "members visible to authorised users" on public.team_members for select using (public.can_view_team(team_id));
-- Only Platform Admins may appoint or remove Team Admins. A Team Admin may
-- manage scorer memberships but cannot elevate a user to Team Admin.
create policy "team admins manage scorer memberships" on public.team_members for all
  using (public.is_platform_admin() or (public.is_team_admin(team_id) and role <> 'team_admin'))
  with check (public.is_platform_admin() or (public.is_team_admin(team_id) and role <> 'team_admin'));
create policy "players visible to authorised users" on public.team_players for select using (public.can_view_team(team_id));
create policy "team admins manage players" on public.team_players for all using (public.is_team_admin(team_id)) with check (public.is_team_admin(team_id));
create policy "sessions visible to authorised users" on public.team_sessions for select using (public.can_view_team(team_id));
create policy "team admins manage sessions" on public.team_sessions for all using (public.is_team_admin(team_id)) with check (public.is_team_admin(team_id));
create policy "active session visible to authorised users" on public.team_active_sessions for select using (public.can_view_team(team_id));
create policy "team admins manage active session" on public.team_active_sessions for all using (public.is_team_admin(team_id)) with check (public.is_team_admin(team_id));
create policy "meta visible to authorised users" on public.team_meta for select using (public.can_view_team(team_id));
create policy "team admins manage meta" on public.team_meta for all using (public.is_team_admin(team_id)) with check (public.is_team_admin(team_id));
create policy "viewers see only their access" on public.viewer_access for select using (user_id = auth.uid());
create policy "team admins view viewer access" on public.viewer_access for select using (public.is_team_admin(team_id));
create policy "audit visible to team admins" on public.team_audit_log for select using (public.is_team_admin(team_id));

-- Access code is created only by a team administrator and returned only once.
create or replace function public.create_or_rotate_viewer_passcode(p_team_id uuid, p_rotate boolean default false)
returns text language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  if not exists (select 1 from public.team_members where team_id = p_team_id and user_id = auth.uid() and role = 'team_admin') then
    raise exception 'Only a team admin can manage this team passcode';
  end if;
  if exists (select 1 from public.teams where id = p_team_id and viewer_passcode_hash is not null) and not p_rotate then
    select passcode into v_code from public.team_passcode_windows where team_id = p_team_id and expires_at > now();
    return v_code;
  end if;
  -- gen_random_uuid() is available on Supabase even when pgcrypto's byte
  -- helpers are installed in a non-public schema.
  v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
  update public.teams set viewer_passcode_hash = extensions.crypt(v_code, extensions.gen_salt('bf')), viewer_passcode_created_at = now(), updated_at = now() where id = p_team_id;
  insert into public.team_passcode_windows(team_id, passcode, expires_at) values (p_team_id, v_code, now() + interval '6 hours')
  on conflict (team_id) do update set passcode = excluded.passcode, expires_at = excluded.expires_at, created_at = now();
  insert into public.team_audit_log(team_id, actor_id, event) values (p_team_id, auth.uid(), case when p_rotate then 'viewer_passcode_rotated' else 'viewer_passcode_created' end);
  return v_code;
end $$;

-- An anonymous signed-in visitor supplies an email plus the shared passcode.
create or replace function public.enter_team_as_viewer(p_team_name text, p_passcode text, p_email text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_team_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign-in session required'; end if;
  select id into v_team_id from public.teams where name_key = lower(btrim(p_team_name)) and viewer_passcode_hash = extensions.crypt(p_passcode, viewer_passcode_hash);
  if v_team_id is null then raise exception 'Invalid team name or passcode'; end if;
  insert into public.viewer_access(team_id, user_id, entered_email) values (v_team_id, auth.uid(), lower(btrim(p_email)))
  on conflict (team_id, user_id) do update set entered_email = excluded.entered_email, granted_at = now();
  insert into public.team_audit_log(team_id, actor_id, event, details) values (v_team_id, auth.uid(), 'viewer_entered', jsonb_build_object('email', lower(btrim(p_email))));
  return v_team_id;
end $$;

grant execute on function public.create_or_rotate_viewer_passcode(uuid, boolean) to authenticated;
grant execute on function public.enter_team_as_viewer(text, text, text) to authenticated, anon;

create or replace function public.load_team_state(p_team_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'players', coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.player_id, 'name', p.name, 'email', p.email, 'rank', p.rank,
      'totalPts', p.total_pts, 'wins', p.wins, 'losses', p.losses,
      'sessions', p.sessions_count, 'rankDelta', p.rank_delta) order by p.rank)
      from public.team_players p where p.team_id = p_team_id), '[]'::jsonb),
    'sessions', coalesce((select jsonb_agg(s.data || jsonb_build_object('id', s.id) order by s.pos)
      from public.team_sessions s where s.team_id = p_team_id), '[]'::jsonb),
    'activeSession', (select a.data from public.team_active_sessions a where a.team_id = p_team_id),
    'nextId', coalesce((select m.next_id from public.team_meta m where m.team_id = p_team_id), 1)
  ) where public.can_view_team(p_team_id);
$$;

-- Team admins replace only their own team's state. This preserves the original
-- app's atomic save model while preventing cross-team writes.
create or replace function public.push_team_state(p_team_id uuid, p jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_team_admin(p_team_id) then raise exception 'Team admin access required'; end if;
  if jsonb_typeof(p->'players') <> 'array' or jsonb_typeof(p->'sessions') <> 'array' then
    raise exception 'Invalid team state';
  end if;
  delete from public.team_players where team_id = p_team_id;
  insert into public.team_players(team_id, player_id, name, email, rank, total_pts, wins, losses, sessions_count, rank_delta)
  select p_team_id, (x.item->>'id')::bigint, x.item->>'name', x.item->>'email', (x.item->>'rank')::integer,
    coalesce((x.item->>'totalPts')::integer, 0), coalesce((x.item->>'wins')::integer, 0),
    coalesce((x.item->>'losses')::integer, 0), coalesce((x.item->>'sessions')::integer, 0), coalesce((x.item->>'rankDelta')::integer, 0)
  from jsonb_array_elements(p->'players') as x(item);
  delete from public.team_sessions where team_id = p_team_id;
  insert into public.team_sessions(team_id, id, pos, data)
  select p_team_id, item->>'id', ordinality - 1, item - 'id'
  from jsonb_array_elements(p->'sessions') with ordinality as s(item, ordinality);
  if p->'activeSession' is null or p->'activeSession' = 'null'::jsonb then
    delete from public.team_active_sessions where team_id = p_team_id;
  else
    insert into public.team_active_sessions(team_id, data) values (p_team_id, p->'activeSession')
    on conflict (team_id) do update set data = excluded.data, updated_at = now();
  end if;
  insert into public.team_meta(team_id, next_id) values (p_team_id, coalesce((p->>'nextId')::bigint, 1))
  on conflict (team_id) do update set next_id = excluded.next_id, updated_at = now();
  insert into public.team_audit_log(team_id, actor_id, event) values (p_team_id, auth.uid(), 'team_state_saved');
end $$;

-- Scorers can modify exactly one game in the active session, and nothing else.
create or replace function public.save_current_game_score(p_team_id uuid, p_court_index integer, p_game_index integer, p_score_1 integer, p_score_2 integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_data jsonb;
begin
  if not public.can_score_team(p_team_id) then raise exception 'Scoring access required'; end if;
  if p_court_index < 0 or p_game_index < 0 or p_score_1 < 0 or p_score_2 < 0 then raise exception 'Invalid score'; end if;
  select data into v_data from public.team_active_sessions where team_id = p_team_id for update;
  if v_data is null or v_data #> array['courts', p_court_index::text, 'games', p_game_index::text] is null then
    raise exception 'Game not found in the current round';
  end if;
  update public.team_active_sessions
  set data = jsonb_set(
        jsonb_set(data, array['courts', p_court_index::text, 'games', p_game_index::text, 's1'], to_jsonb(p_score_1), true),
        array['courts', p_court_index::text, 'games', p_game_index::text, 's2'], to_jsonb(p_score_2), true),
      updated_at = now()
  where team_id = p_team_id;
  insert into public.team_audit_log(team_id, actor_id, event, details)
    values (p_team_id, auth.uid(), 'current_game_scored', jsonb_build_object('court', p_court_index, 'game', p_game_index));
end $$;

grant execute on function public.load_team_state(uuid) to authenticated, anon;
grant execute on function public.push_team_state(uuid, jsonb) to authenticated;
grant execute on function public.save_current_game_score(uuid, integer, integer, integer, integer) to authenticated;

-- Seed Sunday Smashers from the verified pre-migration global data.
do $$
declare v_team_id uuid := gen_random_uuid();
declare v_karthik uuid := 'c1b3514d-5355-439c-a603-e783c2d33dec';
begin
  if exists (select 1 from public.teams where name_key = 'sunday smashers') then
    raise exception 'Sunday Smashers already exists; migration stopped without changing legacy data';
  end if;

  insert into public.teams(id, name, created_by) values (v_team_id, 'Sunday Smashers', v_karthik);
  insert into public.user_profiles(user_id, email) values (v_karthik, 'karthik@konnectify.co') on conflict do nothing;
  insert into public.platform_admins(user_id, granted_by) values (v_karthik, v_karthik) on conflict do nothing;
  insert into public.team_members(team_id, user_id, role, granted_by) values (v_team_id, v_karthik, 'team_admin', v_karthik);
  insert into public.team_meta(team_id, next_id) select v_team_id, next_id from public.app_meta limit 1;
  insert into public.team_players(team_id, player_id, name, rank, total_pts, wins, losses, sessions_count, rank_delta)
    select v_team_id, id, name, rank, total_pts, wins, losses, sessions_count, rank_delta from public.players;
  insert into public.team_sessions(team_id, id, pos, data)
    select v_team_id, id, pos, data from public.sessions;
  insert into public.team_active_sessions(team_id, data)
    select v_team_id, data from public.active_session;
  insert into public.team_audit_log(team_id, actor_id, event, details)
    values (v_team_id, v_karthik, 'legacy_data_migrated', jsonb_build_object('players', (select count(*) from public.players), 'sessions', (select count(*) from public.sessions)));
end $$;

commit;
