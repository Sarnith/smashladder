# Smash Ladder — Requirements Backlog

Status key: ⬜ not started · 🟡 planning · 🔵 in progress · ✅ done · ❓ needs clarification

Items are grouped so related changes ship together. Original request numbers are kept in brackets.

---

## A. Safety & destructive actions — ✅ done

| # | Requirement | Status | Notes |
|---|---|---|---|
| A1 [1] | **Cancel Session** is allowed only when no game scores exist — in the current round **or any earlier round**. | ✅ | `cancelBlockReason()` disables the button and explains why; `cancelSession()` re-checks, and re-checks again on confirm (a scorer may enter a score while the dialog is open). |
| A2 [2] | Cancel Session shows a proper confirmation. | ✅ | Uses the shared two-step dialog (type `CANCEL`). |
| A3 [10] | **Remove Round** and **Cancel Session** not easily reachable. | ✅ | Moved into a collapsed "⋯ More options" section under the main button. Hidden for scorers and viewers. |
| A4 [12] | **All deletions need a 2-step check.** | ✅ | `confirmDanger()`: step 1 dialog explains the impact, step 2 the button unlocks only after typing the confirm word. Used for: cancel session (`CANCEL`), remove round (`REMOVE`), delete history session (session date), remove player (player name), remove player from session (player name), replace data from backup (`REPLACE`). |

## B. Round flow — ✅ done

| # | Requirement | Status | Notes |
|---|---|---|---|
| B1 [3] | A session **always starts with 1 round**. At the end of each round: **Add another round** or **End session**. | ✅ | "Number of Rounds" removed from setup. Once every game is scored: **+ Add Round N+1** or **🏁 End Today's Session**. "Remove Round N" (in More options) discards the current round and reopens the previous one. `numRounds` is kept equal to the rounds played (Code.gs export reads it). |
| B2 [9] | Rename **"Finalise & Update Rankings" → "End Today's Session"**. | ✅ | |
| B3 [7b] | From Round 2 on, **previous round results / session summary go at the bottom**, not the top. | ✅ | "Session so far" under the action buttons: each finished round's final standings per court (newest first) with ▲/▼ tags showing where each player went; game scores in a collapsible. |

## C. Scoring UX — ✅ done

| # | Requirement | Status | Notes |
|---|---|---|---|
| C1 [4] | **Courts as tabs** — more intuitive, easier for multiple scorers (each scorer sits on their court). | ✅ | Sticky court tab bar with per-court progress (`2/5`, `✓` when done); only the selected court renders. Selection remembered per device. |
| C2 [5] | Score entry **cannot exceed the max score**; deuce is an opt-in per court. | ✅ | Default: games end at exactly 15 / 21 (21–20 is final). Per-court **Deuce Off/On** toggle (carries to the next round): with deuce, at (max−1)-all play on until 2 clear, capped at **30** (21-pt) / **21** (15-pt). Deuce can be turned on any time, but not off once a game went past the length. Invalid scores aren't saved and show why; same rules enforced in the DB migration. |
| C3 [6] | Scores can be entered **right team first** (right-to-left) as well as left first. | ✅ | Nothing saves until both boxes have a value; Enter jumps to the empty box. |
| C4 [new] | **Score boxes wait before saving** — the first digit must not save. | ✅ | Typed values are drafts until a 1.5 s pause, leaving the game, or Enter. Drafts survive re-renders and are flushed if the page is hidden. Numeric keypad on phones. "edit" renamed "clear". |

## D. Ranking rules — ✅ done

| # | Requirement | Status | Notes |
|---|---|---|---|
| D1 [8] | Default ranking within a court = **Wins, then Points**; toggle for **Points only**. | ✅ | Setup defaults to "Wins then Points"; "Points only" is the alternative. Live standings and round summaries show wins when they count. |
| D2 [7] | **Tie-break at the promotion/relegation line.** Example 5-player court: A 53, B 55, C 52, D 52, E 50 → E is relegated outright; C vs D tie is decided in favour of **the player who moved up into this court last round** (the climber stays up). | ✅ | `tallyCourt()` order: wins (when D1 applies) → points → **climber first** → current ladder rank. `regroupForNextRound()` records `court.climbers`; Round 1 has none, so it falls back to ladder rank. Climbers show a ↑ in live standings. Applies to every tie in the court, not only at the relegation line. |

## E. Ladder — ✅ done

| # | Requirement | Status | Notes |
|---|---|---|---|
| E1 [11] | Ladder shows **history of the last 5 sessions**. | ✅ | Last 5 sessions as columns (oldest → newest): rank after each session, green = climbed, red = dropped, dashed = absent (−2), blank = not on the ladder yet. Hover shows that session's W–L and points. Sessions without a rank snapshot are rebuilt from rank changes and marked ≈. |

## F. Access — ✅ built (needs migration applied)

| # | Requirement | Status | Notes |
|---|---|---|---|
| F1 [13] | Replace the viewer **passcode with a simple shareable URL**. | ✅ | `…/?join=<token>` → anonymous sign-in + read-only access, token removed from the address bar. Members tab: Copy / Share / Make a new link (type `NEW LINK`; revokes viewers who joined via the old link). Passcode UI removed; its DB functions kept for rollback. **Apply `supabase/migrations/20260927_viewer_share_link.sql`.** |
| F2 [new] | Server-side badminton score check for scorer saves. | ✅ | **Apply `supabase/migrations/20260927_score_rules.sql`.** |

## G. Look & feel — ✅ done

| # | Requirement | Status | Notes |
|---|---|---|---|
| G1 [14] | **Light and dark themes with a better colour palette.** | ✅ | **Profile → Theme**: 4 palettes (Court green, Night match, Arena indigo, Clay court) × System / Light / Dark, remembered per device and applied before first paint. Colours are role tokens (`--accent`, `--on-accent`, `--up`, `--red`, medals…) so wins/climbs stay green and drops red in every theme. |

---

## Decisions log

- **B** — "End Today's Session" asks for a simple one-step confirmation (not type-to-confirm — it isn't a deletion).

- **A1** — Any score, current or earlier round, blocks Cancel.
- **C2** — Hard limit at 15 / 21 by default; deuce is a per-court toggle. Deuce caps: 30 for 21-pt games, 21 for 15-pt games (BWF 15-pt format).
- **C3** — "RTL" means entering the right-hand team's score first.
- **D2** — Ties after wins and points: the player who moved up into this court last round stays up; if still tied, the **lower-ranked (climbing) player** wins the tie (changed 27 Sep after reviewing the 27 Sept session — was higher-ranked).
- **E1** — Last 5 sessions as columns on the ladder.
- **G1** — All four palettes offered as themes in Profile, each with light/dark; default Court green + follow system.

## Open questions

_None right now._

## Release checklist

1. Supabase SQL editor: run `supabase/migrations/20260927_viewer_share_link.sql`, then `supabase/migrations/20260927_score_rules.sql`.
2. Merge the PR (site redeploys from `main`).
3. Smoke-test: team admin (session, rounds, end session, share link), scorer (enter scores incl. invalid ones), share link in a private window.
4. If something breaks: revert the merge commit on `main`; if the problem is in the database, run `supabase/rollback/20260927_rollback.sql`. **Always run the rollback if the page is reverted but the score-rules migration stays** — the old page can't save deuce scores otherwise.

## Order

1. ~~**A** (safety)~~ ✅
2. ~~**B** (round flow)~~ ✅
3. ~~**D** (ranking rules)~~ ✅
4. ~~**C** (scoring UX / court tabs)~~ ✅
5. ~~**E** (ladder history)~~ ✅
6. ~~**F** (share URL)~~ ✅ — apply the two 20260927 migrations
7. ~~**G** (theme)~~ ✅
