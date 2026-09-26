-- Undo the two 20260927 migrations (viewer share link + score rules).
-- Only needed if the 27 Sep release is reverted. Safe to run even if only one of them was applied.
-- Effect: scorer saves go back to having no score-rule check; share links stop working
-- (the passcode flow, which was never removed from the database, is what the old page uses).
begin;

-- 1. Score rules → restore save_current_game_score from 20260924_score_conflict_protection.sql
create or replace function public.save_current_game_score(
  p_team_id uuid,
  p_court_index integer,
  p_game_index integer,
  p_expected_score_1 integer,
  p_expected_score_2 integer,
  p_score_1 integer,
  p_score_2 integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_data jsonb;
  v_current_score_1 integer;
  v_current_score_2 integer;
begin
  if not public.can_score_team(p_team_id) then
    raise exception 'Scoring access required';
  end if;

  if p_court_index < 0 or p_game_index < 0 or p_score_1 < 0 or p_score_2 < 0 then
    raise exception 'Invalid score';
  end if;

  select data into v_data
  from public.team_active_sessions
  where team_id = p_team_id
  for update;

  if v_data is null or v_data #> array['courts', p_court_index::text, 'games', p_game_index::text] is null then
    raise exception 'Game not found in the current round';
  end if;

  v_current_score_1 := (v_data #>> array['courts', p_court_index::text, 'games', p_game_index::text, 's1'])::integer;
  v_current_score_2 := (v_data #>> array['courts', p_court_index::text, 'games', p_game_index::text, 's2'])::integer;

  if v_current_score_1 is distinct from p_expected_score_1
     or v_current_score_2 is distinct from p_expected_score_2 then
    raise exception 'Score conflict: this game was updated by another scorer. Reloaded the latest score.'
      using errcode = 'P0001';
  end if;

  update public.team_active_sessions
  set data = jsonb_set(
        jsonb_set(data, array['courts', p_court_index::text, 'games', p_game_index::text, 's1'], to_jsonb(p_score_1), true),
        array['courts', p_court_index::text, 'games', p_game_index::text, 's2'], to_jsonb(p_score_2), true
      ),
      updated_at = now()
  where team_id = p_team_id;

  insert into public.team_audit_log(team_id, actor_id, event, details)
  values (
    p_team_id,
    auth.uid(),
    'current_game_scored',
    jsonb_build_object('court', p_court_index, 'game', p_game_index)
  );
end;
$$;

grant execute on function public.save_current_game_score(uuid, integer, integer, integer, integer, integer, integer) to authenticated;

-- 2. Share link → remove its functions, table and column.
-- Viewers who joined by link keep their viewer_access rows (read-only access to that team).
drop function if exists public.enter_team_by_link(text);
drop function if exists public.get_or_rotate_share_link(uuid, boolean);
drop table if exists public.team_share_links;
alter table public.viewer_access drop column if exists via_link;

commit;
