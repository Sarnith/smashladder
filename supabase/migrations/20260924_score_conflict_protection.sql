-- Live follow-up migration: prevent one scorer silently overwriting another.
-- The client sends both the score it originally saw and its proposed score.

drop function if exists public.save_current_game_score(uuid, integer, integer, integer, integer);

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
