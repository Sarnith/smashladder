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
| C2 [5] | Score entry **cannot exceed the max score — deuce allowed**. | ✅ | `scoreError()`: first to max; at (max−1)-all play on until 2 clear; hard cap **30** for 21-pt games, **21** for 15-pt games (BWF 15-pt format). Invalid scores aren't saved and show why. Game length can't be switched once a court has scores. |
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

## F. Access

| # | Requirement | Status | Notes |
|---|---|---|---|
| F1 [13] | Replace the viewer **passcode with a simple shareable URL**. | ⬜ | e.g. `https://<site>/?t=<unguessable-token>` → anonymous sign-in + read-only access. Needs a Supabase migration + RPC. Admin can copy/rotate the link in Members. |

## G. Look & feel

| # | Requirement | Status | Notes |
|---|---|---|---|
| G1 [14] | **Light and dark themes with a better colour palette.** | ⬜ | Follow the OS setting by default, with a manual toggle (remembered per device). Rework the palette into tokens so both themes stay readable (scores, win/loss, medals, danger). |

---

## Decisions log

- **B** — "End Today's Session" asks for a simple one-step confirmation (not type-to-confirm — it isn't a deletion).

- **A1** — Any score, current or earlier round, blocks Cancel.
- **C2** — Deuce is allowed. Caps: 30 for 21-pt games, 21 for 15-pt games (decided by Claude, per BWF 15-pt format).
- **C3** — "RTL" means entering the right-hand team's score first.
- **D2** — Tie at the relegation line: the player who moved up into this court last round stays up.
- **E1** — Last 5 sessions as columns on the ladder.
- **G1** — Light + dark themes and a better palette.

## Open questions

_None right now._

## Order

1. ~~**A** (safety)~~ ✅
2. ~~**B** (round flow)~~ ✅
3. ~~**D** (ranking rules)~~ ✅
4. ~~**C** (scoring UX / court tabs)~~ ✅
5. ~~**E** (ladder history)~~ ✅
6. **F** (share URL) — needs a DB migration.
7. **G** (theme) — last, so it restyles the final UI.
