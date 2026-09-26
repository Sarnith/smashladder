-- Enforce badminton scoring on scorer saves (the app checks the same rules before sending).
-- Each court plays to its game length (maxScore, 15 or 21). Deuce off (default): the winner has
-- exactly the game length. Deuce on (court.deuce): at (length−1)-all play on until 2 clear, up to a
-- cap where the next point wins — 30 for 21-point games, 21 for 15-point games.

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
  v_max integer;
  v_cap integer;
  v_deuce boolean;
  v_win integer;
  v_lose integer;
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

  v_max := coalesce((v_data #>> array['courts', p_court_index::text, 'maxScore'])::integer, 21);
  v_deuce := coalesce((v_data #>> array['courts', p_court_index::text, 'deuce'])::boolean, false);
  v_cap := case when not v_deuce then v_max when v_max = 15 then 21 when v_max = 21 then 30 else v_max + 9 end;
  v_win := greatest(p_score_1, p_score_2);
  v_lose := least(p_score_1, p_score_2);
  if v_win = v_lose
     or (not v_deuce and v_win <> v_max) then
    raise exception 'Invalid score: %–% is not a finished game to % points', p_score_1, p_score_2, v_max;
  end if;
  if v_deuce and (v_win > v_cap
     or v_win = v_lose
     or v_win < v_max
     or (v_win = v_max and v_lose > v_max - 2)
     or (v_win > v_max and v_lose <> v_win - 2 and not (v_win = v_cap and v_lose = v_cap - 1))) then
    raise exception 'Invalid score: %–% is not a finished game to % points', p_score_1, p_score_2, v_max;
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
