-- Viewers join with a shareable link (…/?join=<token>) instead of team name + email + passcode.
-- Additive: the passcode columns and functions stay in place for rollback.
begin;

-- One live link per team. Kept out of public.teams (which viewers can read) and given no client
-- policies, so only the functions below can read or change it.
create table if not exists public.team_share_links (
  team_id uuid primary key references public.teams(id) on delete cascade,
  token text not null unique,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.team_share_links enable row level security;

-- Remember which viewers came in through the link, so replacing the link revokes exactly them.
alter table public.viewer_access add column if not exists via_link boolean not null default false;

-- Returns the team's link token, creating it on first use. p_rotate replaces it: the old link stops
-- working and viewers who joined through it lose access.
create or replace function public.get_or_rotate_share_link(p_team_id uuid, p_rotate boolean default false)
returns text language plpgsql security definer set search_path = public as $$
declare v_token text;
begin
  if not public.is_team_admin(p_team_id) then
    raise exception 'Only a team admin can manage the share link';
  end if;
  if not p_rotate then
    select token into v_token from public.team_share_links where team_id = p_team_id;
    if v_token is not null then return v_token; end if;
  end if;
  v_token := replace(gen_random_uuid()::text, '-', ''); -- 122 random bits
  insert into public.team_share_links(team_id, token, created_by) values (p_team_id, v_token, auth.uid())
  on conflict (team_id) do update set token = excluded.token, created_by = excluded.created_by, created_at = now();
  if p_rotate then
    delete from public.viewer_access where team_id = p_team_id and via_link;
  end if;
  insert into public.team_audit_log(team_id, actor_id, event)
  values (p_team_id, auth.uid(), case when p_rotate then 'share_link_rotated' else 'share_link_created' end);
  return v_token;
end $$;

-- Called by whoever opens the link (an anonymous session is created client-side first).
-- Members and platform admins already see the team with their own role, so they are not added
-- as viewers too.
create or replace function public.enter_team_by_link(p_token text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_team_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign-in session required'; end if;
  select team_id into v_team_id from public.team_share_links where token = btrim(p_token);
  if v_team_id is null then
    raise exception 'This link is no longer valid — ask your team admin for the current one';
  end if;
  if public.is_platform_admin()
     or exists (select 1 from public.team_members where team_id = v_team_id and user_id = auth.uid()) then
    return v_team_id;
  end if;
  insert into public.viewer_access(team_id, user_id, entered_email, via_link)
  values (v_team_id, auth.uid(), '', true)
  on conflict (team_id, user_id) do update set granted_at = now();
  insert into public.team_audit_log(team_id, actor_id, event) values (v_team_id, auth.uid(), 'viewer_entered_by_link');
  return v_team_id;
end $$;

revoke all on function public.get_or_rotate_share_link(uuid, boolean) from public;
revoke all on function public.enter_team_by_link(text) from public;
grant execute on function public.get_or_rotate_share_link(uuid, boolean) to authenticated;
-- anonymous Supabase sessions use the authenticated role
grant execute on function public.enter_team_by_link(text) to authenticated;

commit;
