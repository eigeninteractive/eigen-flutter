# Engine review — findings

End-to-end review of the engine flow (2026-07-09): Dart client (repository
streams, providers, screens, local-bot driver), TS edge function (handlers,
pipeline, observation fan-out, repo, notify), and SQL (commit RPCs, helpers,
lifecycle crons, RLS). The prompt for the review was the `previewAction`
discussion — "is there a high-level bias like the provisional-frame loop
anywhere else?" — so findings lean architectural: assumptions, policy gaps,
and design choices, not just bugs.

Each finding carries a status: **Fixed** (resolved 2026-07-09 unless dated
otherwise), **Ignored** (reviewed and deliberately not pursued), or
**Open** (to discuss later).

---

## Fixed

### 1. The error taxonomy was stringly-typed across every boundary

The chain was: SQL `RAISE EXCEPTION 'Stale state: ...'` → EF responded with
`{ error: message }` only → Dart re-wrapped the message into a bare
`Exception` → `humanize` dispatched on `s.contains('Stale state')` and a
dozen other literals. Rewording one server message silently degraded the
client to "Something went wrong", and games could never branch on failure
kind except by matching strings.

**Resolution** — one stable code registry across all three tiers:

- SQL raises the user-facing errors with `USING ERRCODE = 'EIGxx'`
  (join/lobby, commit guards, username RPCs), so client-direct RPC failures
  surface the code on `PostgrestException.code`.
- TS `EngineCode` (`_engine/runtime.ts`) is the registry; TS-raised
  `HttpError`s carry the same codes, `rpcErrorStatus` maps status by code
  first, and `app.ts` returns `{ error, code }`.
- Dart `EngineException` (`core/errors/engine_exception.dart`, with the
  `EngineErrorCodes` twin) is thrown by the repository for any server-side
  error; `humanize` dispatches on the code only — the old message-substring
  matching was deleted outright (dev phase, no legacy servers to tolerate).
  Uncoded errors are either network-shaped (detected by exception type text)
  or generic.

### 2. Client turn-gating ran on the game's *projected* pending set, with no truthfulness guarantee for the seat itself

The authoritative `game_states.pending_players` enforces "Not your turn" at
commit, while the per-seat projection from `computeObservation` is what
drives the client's input gating and turn display. The split is deliberate
(hidden-info games may mask *others'* pending status), but nothing checked
the invariant infra depends on: a seat's projection must be truthful about
that seat itself. A game bug there soft-locks the client or produces taps
that always 400.

**Resolution** — `fanOutObservations` (`observation.ts`) now asserts, per
seat, that the slice's own-seat pending membership matches the authoritative
set, and 500s at the source (same spirit as `assertHookState`).

### 3. `onAction`'s bool conflated "rejected" with "unconfirmed"

A network failure after the server committed also resolved `false`, so games
could not distinguish "no frame is coming" (revert and re-enable input) from
"a frame may still arrive" (revert and expect a possible re-apply).

**Resolution** — `onAction` now returns `Future<ActionSubmitResult>`
(`committed` / `rejected` / `unconfirmed`). The taxonomy fix is what made
this implementable: a typed `EngineException` is a definitive server verdict
→ `rejected`; any other failure is transport-shaped → `unconfirmed`. The
double-submit guard reports `rejected` (the tap definitively did not become
a move). Games that don't render optimistically ignore the result.

### 5. Budget mode's "one pending player" rule was convention-only

The SQL comment on `compute_next_deadline` admitted multi-pending budget games
were only gracefully degraded (MIN of banks), and `deduct_bank` charges full
elapsed time to each mover in that case. Nothing rejected the envelope that
created the situation.

**Resolution** (2026-07-10) — `assertBudgetPending` in `game-engine.ts`, run
next to `assertHookState` at all three hook sites (`handleStart`,
`applyGameAction`, `resolveLifecycle`): when the game has `budget_seconds`, an
envelope with more than one pending seat 500s at the source as a game bug.
Both read views (`readGameState`, `readForStart`) now carry `budget_seconds`.
The MIN-over-pending in `compute_next_deadline` stays as the SQL backstop (a
cross-table CHECK isn't expressible there).

---

## Ignored (reviewed, deliberately not pursued)

- **Rated + untimed games.** Decision: not a concern for now (no current
  game returns a rating pool for untimed configs).
- **Turn countdowns trust the device clock.** `TurnCountdown` / `BudgetClock`
  diff server deadlines against `DateTime.now()`; clock skew shifts the
  display. Revisit only if real users report countdown weirdness — the
  server's grace window already covers latency, and the server remains
  authoritative regardless of what the client shows.
- **Replay recomputes every frame per request.** O(versions) hook calls per
  replay call. Fine at current scale; finished games are immutable, so a
  per-(game, seat) cache or pagination is available later if long games make
  it slow.

---

## Open (discuss later)

### 4. Append-only tables grow forever, but observations are already re-derivable

No retention story for `observations`, `game_states`, or `actions`. Replay
recomputes observation slices from `game_states` + `actions`, so
**observation rows of finished games are pure cache** — a cron prune (e.g.
finished > 7 days) reclaims the largest table (versions × seats rows per
game) with zero functional loss. `game_states`/`actions` are the replay
ground truth and need an actual archival decision someday.

### 6. `handleStart` does the hook work before the creator check

`readForStart` doesn't select `created_by`; a non-creator caller runs
`initialState` + full observation fan-out before `engine_commit_start`
rejects them. Free compute for anyone who knows a game id. Add `created_by`
to the read and 403 first.

### 7. The expire sweep runs up to 200 sequential pipelines in one invocation

`handleExpireBatch` awaits each `expireGame` in series; each is a read +
hook + fan-out + commit + notify. 200 of those can brush against
edge-function wall-clock limits, and everything after the cutoff waits a
full cron tick (self-healing, so this is latency not correctness). Either
lower the batch LIMIT in `cron_expire_turns`, or run with a small
concurrency cap.

### 8. Nothing tests that the Dart twins match their TS originals

The twin doctrine (`isValidAction`, `previewAction`, `ratingPool`,
`botSeatable` mirroring TS) rests on "keep in sync per version" comments.
Drift only degrades UX by design — but it's also trivially testable:
establish a shared JSON fixture convention (a `fixtures/` of
`{obs, pending, action, playerIndex, config, expected}` cases) that the TS
unit tests and the Dart unit tests both consume. One fixture file per
version unit makes drift a CI failure instead of a player-reported bug.

---

## Notes (deliberate trade-offs worth keeping visible)

- **Realtime privacy is load-bearing on RLS.** The observation channel
  filters only by `game_id`; per-seat narrowing is done entirely by the
  `observations_select` policy flowing through postgres_changes. Correct
  today — but any future policy change (or a broadcast-based migration) must
  re-derive this property consciously.
- **The local-bot gate exists twice on purpose** — TS `assertLocalBotSeat`
  for EF routes, SQL `resolve_local_bot_seat` for the client-direct
  observation RPC. The mirrored comments cross-reference each other; keep
  them in lockstep when editing either.
- **Account deletion resolves rated games through the rules** (auto-forfeit →
  outcome → rating writes). Equivalent to resigning, so it adds no rating
  attack that resign doesn't already allow.
- **Local-bot brains are app-session-only** (`LocalBotStateCache`, in-memory,
  LRU-16) and solo local-bot games are untimed by rule, so an abandoned one
  lingers until the 30-day idle abort. Both documented in code; acceptable.
- **`previewAction` is a required, engine-unwired contract** (decided
  2026-07-09): games own optimism (pair `previewAction` with the
  `onAction` result); infra never emits predicted frames. The earlier
  provisional-frame design (`GameFrame.isProvisional`) was removed — don't
  reintroduce prediction into the infra frame pipeline.

---

## Checked and sound

Things the review deliberately probed and found correct, recorded so the next
review doesn't re-litigate them:

- **Optimistic-lock chain**: client `expected_version` from the observation
  row → EF fast-fail → authoritative re-check under the `games` row lock
  (`commit_should_abstain`). A successful submit at version v is necessarily
  the producer of v+1, which is what makes the client-side "next frame
  confirms my move" contract valid.
- **Timeout semantics**: timeout abstains (never errors) on any lost race;
  the deadline+grace comparison lives in exactly one function
  (`private.deadline_expired`) used by all three checkpoints, so the grace
  window cannot drift between accept, expire, and sweep.
- **Retry classification**: moves retry only rating-CAS conflicts (a moved
  board must reject, not re-apply); forfeits additionally retry board
  advances and recompute. Correct asymmetry.
- **Determinism**: per-transition RNG is `(rng_seed, version)`-derived;
  the seed is service-role-only and never crosses the commit wire.
- **Payload hygiene**: everything that reaches hooks, the `actions` log, or
  `games.config` has passed the version unit's Zod schema
  (`parseClientPayload` / `parseStoredPayload`); hook output is re-validated
  before commit (`assertHookState`).
- **Ordered frame delivery**: the observation stream serializes handling,
  drops stale/duplicate versions, back-fills gaps, and re-baselines on every
  reconnect. The local-bot driver correctly treats it as eventually
  consistent (strictly-greater supersession, server lock as backstop).
- **Trust boundaries**: engine_* RPCs revoked from `authenticated`; clients
  submit intents, only the EF submits computed state; server bots are
  HMAC-verified over version-bound claims (a replayed signature is
  version-rejected); the sole-human gate keeps local bots out of games with
  an opponent to cheat.
