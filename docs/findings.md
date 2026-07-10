# Engine Review Findings — 2026-07-10 sweep

Open items from the second full review pass (framework, infra, lifecycle).
The first pass's items were all fixed or deliberately parked; this file covers
only what is still open. Fixed items move to a one-line note under **Fixed**;
deliberate non-fixes move to **Ignored** with the reasoning.

## Open

1. **Stale-guest sweep can purge a guest who is legitimately mid-game and
   waiting.** `cron_cleanup_stale_guests` defines stale as "anonymous, 7+ days
   old, no `actions` row in the last 2 days" — but `turn_seconds` allows up to
   30 days, so in any correspondence-paced game it can be the opponent's turn
   for longer than 2 days: the guest has no recent action *because they are
   waiting*, and the sweep forfeits and deletes them anyway. Lobby-only
   activity (create/join) writes no actions either. Fix direction: use a
   last-seen signal (auth session refresh) instead of `actions`, or at minimum
   exempt guests whose active games are not pending on them.

2. **Untimed games break the "expiry sweep doubles as retry" design.** Bot
   wakes and pushes are fire-and-forget; `notify.ts` documents the expiry
   sweep as the retry for lost deliveries. That only holds when a deadline
   exists — `turn_seconds` is nullable. Untimed + server bot + one lost
   webhook wake = the game is stuck forever (no retry, no reaper). Abandoned
   untimed games between registered users are likewise immortal zombie rows
   (guests eventually fall to the stale sweep). Fix direction: require a
   timing mode whenever a server bot is seated (cheap), and/or a low-frequency
   stalled-game sweep that re-nudges pending bot seats.

3. **Invite codes are scannable.** `short_code` is md5-derived — hex-only, so
   the space is 16^6 ≈ 16.7M, not 36^6. Codes are UNIQUE across *all* games
   forever (finished games keep theirs, densifying live targets), and
   `app_join_game_by_code` is a client-direct RPC with no rate limiting; a
   code is a join capability for private games. Fix directions (stack):
   generate from `gen_random_bytes` over a ≥32-symbol alphabet, release the
   code (or scope uniqueness) when a game leaves `waiting`, rate-limit the
   RPC.

4. **No rate limiting anywhere.** All EF routes and client RPCs are
   unthrottled; action submission (hooks + fan-out) is the most expensive
   thing an authenticated user can spam. Pre-launch hardening item.

5. **Stale-guest sweep has no batch cap.** The expire sweep has `LIMIT 200`;
   the guest sweep loops every stale guest in one cron transaction and sends
   the EF one unbounded `user_ids` array (processed sequentially). A first-run
   backlog means a very long transaction and a blown EF wall clock.
   Self-healing, but should get the same LIMIT treatment.

6. **Client roster staleness on mid-game purge.** Nothing invalidates
   `gamePlayersProvider` when a participant identity changes (no participants
   realtime subscription), so survivors keep the old name/avatar until a
   refetch. Cosmetic.

7. **Session-scratch verification tests are not checked in.** The purge /
   ghost-seat asserts / ratings-skip behaviors were verified with throwaway
   psql + Deno scripts. They belong in a real test suite alongside the
   twin-drift fixtures (see docs/todo.md P0).

## Ignored (deliberate)

- Append-only observation growth / retention & pruning — parked earlier;
  revisit before launch.
- Client clock skew, rated+untimed combinations, replay recompute — parked in
  the first review pass.

## Operational debt (not code findings)

- `database.types.ts` was hand-edited; regenerate from a running stack.
- `@supabase/server@^1` runtime boot still unverified (`supabase functions
  serve`; re-pin 1.2.0 if the hono peer error returns).
- `engine/deno.json` extends the shared map but repeats its entries — drift
  hazard the sync currently papers over.
