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

## C. Scoring UX

| # | Requirement | Status | Notes |
|---|---|---|---|
| C1 [4] | **Courts as tabs** — more intuitive, easier for multiple scorers (each scorer sits on their court). | ⬜ | Court tab bar with per-court progress (e.g. "Court 2 · 3/5"). Remember the selected court per device. |
| C2 [5] | Score entry **cannot exceed the max score — deuce allowed**. | ⬜ | Badminton rules: first to max wins; at (max−1)-all, play on until 2 clear; hard cap at 30 (21-pt games) / 20 (15-pt games — confirm cap). Reject invalid scores (ties, winner below max, loser too close, over cap). |
| C3 [6] | Scores can be entered **right team first** (right-to-left) as well as left first. | ⬜ | Entering the right-hand box first must not save, re-render or steal focus until both boxes are filled; tab/"next" order follows whichever box was typed first. |

## D. Ranking rules — ✅ done

| # | Requirement | Status | Notes |
|---|---|---|---|
| D1 [8] | Default ranking within a court = **Wins, then Points**; toggle for **Points only**. | ✅ | Setup defaults to "Wins then Points"; "Points only" is the alternative. Live standings and round summaries show wins when they count. |
| D2 [7] | **Tie-break at the promotion/relegation line.** Example 5-player court: A 53, B 55, C 52, D 52, E 50 → E is relegated outright; C vs D tie is decided in favour of **the player who moved up into this court last round** (the climber stays up). | ✅ | `tallyCourt()` order: wins (when D1 applies) → points → **climber first** → current ladder rank. `regroupForNextRound()` records `court.climbers`; Round 1 has none, so it falls back to ladder rank. Climbers show a ↑ in live standings. Applies to every tie in the court, not only at the relegation line. |

## E. Ladder

| # | Requirement | Status | Notes |
|---|---|---|---|
| E1 [11] | Ladder shows **history of the last 5 sessions**. | ⬜ | Proposal: per player, a small rank trend over the last 5 sessions (e.g. `#4 → #3 → #3 → #2 → #2`) plus W/L form. Data already exists in `session.ranksAfter`. |

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
- **C2** — Deuce is allowed.
- **C3** — "RTL" means entering the right-hand team's score first.
- **D2** — Tie at the relegation line: the player who moved up into this court last round stays up.
- **G1** — Light + dark themes and a better palette.

## Open questions

1. **C2** — For 15-point games, what's the hard cap? (Common choice: 20 — i.e. 20–19 wins.)
2. **E1** — Rank trend, W/L form, points per session, or a mix?

## Order

1. ~~**A** (safety)~~ ✅
2. ~~**B** (round flow)~~ ✅
3. ~~**D** (ranking rules)~~ ✅
4. **C** (scoring UX / court tabs).
5. **E** (ladder history).
6. **F** (share URL) — needs a DB migration.
7. **G** (theme) — last, so it restyles the final UI.
