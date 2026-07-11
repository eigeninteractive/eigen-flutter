# Engine Review Findings — 2026-07-10 sweep

Open items from the second full review pass (framework, infra, lifecycle). The
first pass's items were all fixed or deliberately parked; this file covers only
what is still open. Fixed items move to a one-line note under **Fixed**;
deliberate non-fixes move to **Ignored** with the reasoning.

## Open

1. **Stale-guest sweep can purge a guest who is legitimately mid-game and
   waiting.** `cron_cleanup_stale_guests` defines stale as "anonymous, 7+ days
   old, no `actions` row in the last 2 days" — but `turn_seconds` allows up to
   30 days, so in any correspondence-paced game it can be the opponent's turn
   for longer than 2 days: the guest has no recent action _because they are
   waiting_, and the sweep forfeits and deletes them anyway. Lobby-only activity
   (create/join) writes no actions either. Fix direction: use a last-seen signal
   (auth session refresh) instead of `actions`, or at minimum exempt guests
   whose active games are not pending on them.

2. **Invite codes are scannable.** `short_code` is md5-derived — hex-only, so
   the space is 16^6 ≈ 16.7M, not 36^6. Codes are UNIQUE across _all_ games
   forever (finished games keep theirs, densifying live targets), and
   `app_join_game_by_code` is a client-direct RPC with no rate limiting; a code
   is a join capability for private games. Fix directions (stack): generate from
   `gen_random_bytes` over a ≥32-symbol alphabet, release the code (or scope
   uniqueness) when a game leaves `waiting`, rate-limit the RPC.

3. **No rate limiting anywhere.** All EF routes and client RPCs are unthrottled;
   action submission (hooks + fan-out) is the most expensive thing an
   authenticated user can spam. Pre-launch hardening item.

4. **Stale-guest sweep has no batch cap.** The expire sweep has `LIMIT 200`; the
   guest sweep loops every stale guest in one cron transaction and sends the EF
   one unbounded `user_ids` array (processed sequentially). A first-run backlog
   means a very long transaction and a blown EF wall clock. Self-healing, but
   should get the same LIMIT treatment.

5. **Client roster staleness on mid-game purge.** Nothing invalidates
   `gamePlayersProvider` when a participant identity changes (no participants
   realtime subscription), so survivors keep the old name/avatar until a
   refetch. Cosmetic.

6. **Session-scratch verification tests are not checked in.** The purge /
   ghost-seat asserts / ratings-skip behaviors were verified with throwaway
   psql + Deno scripts. They belong in a real test suite alongside the
   twin-drift fixtures (see docs/todo.md P0).

7. How "deleted" is defined, layer by layer In the database, a deleted user is
   defined by absence. Everything keyed to the identity is cascade-deleted
   (public.users, user_profiles, player_ratings, rating_history, their
   observations). What remains are per-game tombstones: participants, actions,
   and game_outcomes rows that keep the seat (player_index) with user_id nulled.
   So the identification rule everywhere is: a participant with user_id IS NULL
   AND bot_id IS NULL. There is no global "deleted users" registry — deletion is
   only observable through the seats they left behind, which is also why
   PlayerInfo can't carry it: there's no app_players row to fetch, no id to ask
   about. The identity doesn't exist; only the seat remembers.

   On the client, that rule maps to the seat model, not the identity model.
   gamePlayers checks it per participant and produces GamePlayer(isDeleted:
   true) with a synthetic placeholder PlayerInfo (id: 'deleted_<gameId>_<seat>',
   displayName "Deleted User"). So the differentiation you're asking about lives
   on GamePlayer.isDeleted — one level up from PlayerInfo, which matches the
   reality that "deleted" is a property of a seat in a game, not of a resolvable
   identity.

   The gap: isDeleted is written but never read

   Grepping consumers: the flag is set in exactly one place and consumed
   nowhere. The GamePlayer doc comment says the synthetic id "must not be passed
   to identity lookups or profile sheets" — but that's a comment, not code. And
   there's a concrete near-miss: the pre-game roster's avatar tap
   (game_screen_pre_game.dart:373) passes gp.info.id straight into
   PlayerProfileSheet.show with no isDeleted check. It's unreachable today only
   by the same indirect argument as elsewhere — the purge removes participants
   from waiting/ready games, so pre-game screens can't contain deleted seats.
   But any active-game or history player list built the same way (and
   replay/spectating are both on the P0 list) would ship the bug: tapping
   "Deleted User" fires app_players with deleted_..., the repository's (response
   as List).single throws on the empty list, and the sheet errors.

   Secondary smell: if code holds only a PlayerInfo (not the GamePlayer), the
   only in-band marker is the deleted_ id prefix — stringly-typed and easy to
   miss.

   My take

   The model split is right — keep deletion off PlayerInfo, because
   absence-of-identity is the correct representation and a bool isDeleted on it
   would be exactly the kind of spread-out flag you just had me remove. The fix
   is to make GamePlayer.isDeleted load-bearing where taps and social
   affordances originate: null out the avatar's onTap (and any future
   friend/report actions) when isDeleted is true, so the guard sits at the one
   place that has the GamePlayer in hand. I'd also have
   PlayerRepository.getPlayer throw a distinct, typed error on an empty result
   rather than StateError from .single, so any future leak fails diagnosably.

   (it's a small change: gate the tap, type the empty-result error)?

8. Make the guest-viewer hint actionable. "Sign in to add friends." is currently
   inert text. Settings already has the upgrade flow (_UpgradeAccountCard), so
   the hint could be a button that routes there — turning a dead end into the
   conversion funnel. Probably the highest-value small UX change.

9. Shape parity in app_search_users. Its rows decode into PlayerInfo without
    is_guest, which is only correct because search happens to exclude guests —
    an invariant living in a different function. Adding false as is_guest (or
    au.is_anonymous, same thing post-filter) to its SELECT makes the shape
    self-consistent for a few characters, so a future "include guests in search"
    change can't silently mislabel them.

## Fixed

- Untimed + server bot via `game/add-bot` — the server⇒timed half of the
  timing invariant was enforced only on `game/create-solo`; now also gated in
  the add-bot route and backstopped in `private.seat_server_bot`. (The
  finding's "immortal zombie rows" half was wrong: `cron_cleanup_idle_games`
  already aborts idle waiting/ready games after 7 days and idle untimed
  active games after 30.)

## Ignored (deliberate)

- Append-only observation growth / retention & pruning — parked earlier; revisit
  before launch.
- Client clock skew, rated+untimed combinations, replay recompute — parked in
  the first review pass.

## Operational debt (not code findings)

- `database.types.ts` was hand-edited; regenerate from a running stack.
- `@supabase/server@^1` runtime boot still unverified
  (`supabase functions
  serve`; re-pin 1.2.0 if the hono peer error returns).
- `engine/deno.json` extends the shared map but repeats its entries — drift
  hazard the sync currently papers over.
