# Cloudflare Migration — Analysis & Recommendation

> **Bottom line.** The money argument is weak (~$40–70/month saved at target
> scale, and *zero* saved if you keep Postgres). The architecture argument is
> strong, but only for **one half** of the stack: a per-game **Durable Object**
> structurally eliminates three things the current design pays real complexity
> for — optimistic-lock version conflicts, the cron/pg_net/grace-window timeout
> machinery, and the Realtime connection cap that binds first at scale.
> Meanwhile, leaving **Supabase's data plane** (Auth, PostgREST, RLS, Storage,
> Postgres) buys almost nothing and costs the most engineering. The recommended
> path is therefore a **hybrid**, staged, and reversible: move *compute and
> session* to Cloudflare, keep *data and identity* on Supabase. Do it now, while
> there are no production users.

---

## 1. What we're actually migrating

The engine is not "a database plus some functions" — it uses eight distinct
Supabase products, and each one has a different Cloudflare story.

| Supabase surface we use today | Where it appears | Cloudflare equivalent | Port difficulty |
| --- | --- | --- | --- |
| **Edge Function** (`engine`, Deno + hono, 4 route groups) | §21 | Workers (hono runs natively) | **Easy** — pure TS rules module, no Deno-specific logic beyond env/imports |
| **Postgres** (jsonb state, int[] pending, CHECK/FK/UNIQUE, pg_trgm search) | §2 | D1 (SQLite) *or* Neon/Hyperdrive (Postgres) | **Medium → Hard** (see §5) |
| **Gated `engine_*` SQL RPCs** (`FOR UPDATE` commit chokepoint) | §5 | Durable Object serialization, or same SQL | **Easy–Medium** |
| **PostgREST** (client-direct `app_*` RPCs + embedded selects for lobby/history/dashboard) | §5 | Hand-written Worker REST endpoints | **Hard** — nothing generates this for you |
| **RLS** (games/observations/relationships/`realtime.messages`/storage.objects) | §10 | Nothing. Authorization becomes 100% app code | **Hard** (loss, not a port) |
| **Realtime** (broadcast-from-DB, private per-seat topics) | §19 | Durable Object WebSockets (Hibernation API) | **Medium** — and a genuine upgrade |
| **Auth** (Google OIDC + **anonymous guests** + `is_anonymous` JWT claim + guest→permanent upgrade) | §25 | **Nothing.** Cloudflare has no consumer auth product | **Hard** (see §6) |
| **Storage** (avatars bucket + RLS policies) | §2 | R2 (+ Worker-signed uploads) | **Easy** |
| **pg_cron + pg_net + Vault** (expire sweep, guest purge) | §3, §22 | Cron Triggers + **DO alarms** + Worker secrets | **Easy** — and a genuine upgrade |

The client is the hidden cost: **22 Dart files** import `supabase_flutter`, and
they consume auth, PostgREST queries, RPCs, Realtime channels, and Storage. A
full migration rewrites the entire repository/transport layer of the app, not
just the server.

---

## 2. Where Durable Objects genuinely win

These are not generic "actor model is nice" arguments — each maps to a specific
complexity or limit in the current design.

**(a) It deletes the optimistic-locking problem.**
§5 *Version Conflicts* concedes that simultaneous-move games "will hit this
routinely with spurious conflicts", deferred to `future_plans.md`. A DO is
single-threaded per game: requests queue at the input gate, so two players
acting in the same round *cannot* race. The `version` column stays as a replay
ordinal, but the stale-state rejection, the client's "board updated — try again"
message, and the retry-on-stale in the forfeit path all become unnecessary.
Chess doesn't care; RPS, Set, and Poker (the games explicitly in the target
list, §1) do.

**(b) It deletes the timeout sweep and the triple-symmetry grace window.**
Today: `pg_cron` ticks → selects expired games → `pg_net` POSTs `internal/expire`
with the Vault secret → EF re-validates expiry under `FOR UPDATE` → and the
750 ms grace window must be applied identically in *three* places (commit,
expire-commit, cron selector) or the timeout path steals the race from an
on-time-but-latent submit (§3). A DO sets `alarm(turn_deadline + grace)` when it
commits the state. One timer, in the same actor that owns the state, fires at the
exact deadline. No cron, no `pg_net`, no Vault secret, no grace symmetry
invariant, no `internal/expire` batch route, no `cron_expire_turns`. Latency to
timeout drops from "up to one cron tick" to ~0.

**(c) It removes the binding scale limit.**
Supabase Pro caps **concurrent Realtime connections at 500** (+$10/1k). Target
peak is ~1,000 simultaneous games ⇒ ~2,000 sockets. That is the *first* limit we
hit — before compute, before storage. DO WebSockets with the **Hibernation API**
have no plan-level connection cap and cost nothing while idle, which is exactly
the shape of a turn-based game (a socket that's silent for 40s between moves).

**(d) Frames come from the thing that produced them.**
Today an observation frame's path is: EF → SQL commit → `AFTER INSERT` trigger →
`realtime.send` → Realtime server → RLS check on `realtime.messages` → client.
In a DO: commit → `ws.send()` on the sockets the same object is holding, in
version order, by construction. The append-only observation history and
gap-recovery logic stay (still needed for reconnect), but the delivery path loses
three hops and an RLS policy.

**(e) Hot state in memory.** The current per-action loop is read state → compute →
commit (two DB round trips). A DO holds the current state and roster in memory,
so an action is compute → one write.

**(f) Local dev gets much lighter.** `wrangler dev`/miniflare vs. the local
Supabase Docker stack (which has already cost us import-map, key, and grant
fixes).

---

## 3. Where Cloudflare loses

**(a) There is no auth product.** This is the single biggest gap. Supabase Auth
gives us Google OIDC, **anonymous guest accounts**, the `is_anonymous` claim that
several policy gates read (guests can't create `friends`-access games, can't play
rated, can't search users), the guest→permanent upgrade path (§25), and the
`handle_new_user` provisioning trigger. Cloudflare Access is B2B SSO, not this.
The options are: keep Supabase Auth standalone (free up to 50k MAU), pay for
Clerk/WorkOS/Auth0, or roll our own (feasible — we only need Google + guest — but
we'd then own refresh tokens, revocation, linking, and deletion).

**(b) Losing PostgREST means hand-writing the read API.** Every `app_*` RPC and
every embedded select (§5 *Client Query Patterns*: lobby pagination, friends
lobby, history with `game_outcomes` + `rating_history` embeds, `app_players`,
trigram user search) becomes a bespoke Worker endpoint plus a bespoke Dart
repository method. This is weeks of unglamorous work that produces zero new
capability.

**(c) Losing RLS removes the second line of defense.** Our stated philosophy is
already "policy in TS, integrity in SQL" — but RLS is what makes a bug in a *read*
path a non-event today (`observations` are filtered to `user_id = auth.uid()` by
the database, and the Realtime topic join is RLS-authorized). On Cloudflare,
every hidden-information leak is one missing `if` away. For a hidden-info game
engine, that is a real regression in safety margin.

**(d) Cross-store atomicity is lost if the DO owns state.** A finishing action
today writes `game_states` + `observations` + `actions` + `game_outcomes` +
`player_ratings` in **one Postgres transaction** (§8). If game state lives in DO
SQLite and ratings/history live in D1/Postgres, that's two stores and no shared
transaction — you need an outbox + idempotent apply. (We do already have rating
idempotency, so this is tractable, but it's new machinery for a guarantee we get
for free today.)

**(e) D1 does not fit at target scale.** Max **10 GB per database**, single-threaded
writer. At ~5,000 games/day × ~30 actions × 2 seats, `observations` alone grows
roughly **~9 GB/month**. D1 hits the wall inside the first month unless we archive
to R2 or stop persisting observation history — and append-only observations are
load-bearing for our reliable-frame-stream and replay design. So "Cloudflare +
D1" is only viable with an archival tier; **"Cloudflare + Postgres" is the honest
comparison**, which erases most of the cost savings (see §4).

**(f) Vendor lock-in asymmetry.** Postgres is portable; Durable Objects have no
open-source equivalent. Offsetting this: the rules module is pure TS, so the
*game* is never locked in — only the transport/session layer is.

---

## 4. Cost

### Model assumptions (from §21's stated target)

5,000 games/day · 2 seats avg · ~30 actions/game · peak 1,000 simultaneous games.
Monthly: **150k games**, **~4.5M game actions**, **~5.5M server invocations**
(incl. create/start/replay/lobby), **~9M observation rows/broadcast messages**,
**~2,000 peak WebSocket connections**, **~20M DB row writes**, **~9 GB/month**
storage growth.

### Getting started (free tiers)

| | Supabase Free | Cloudflare Free |
| --- | --- | --- |
| Compute | 500k edge-function invocations/mo | 100k Worker req/**day** (~3M/mo) + 100k DO req/day |
| DB | 500 MB Postgres, **project pauses after 7 days idle** | D1: 5 GB, 100k rows written/**day** |
| Realtime | 2M msgs, **200 concurrent connections** | DO WebSockets — no plan cap; 13k GB-s/day duration |
| Auth | 50k MAU included | **none** |
| Storage | 1 GB | R2: 10 GB, zero egress |

Cloudflare's free tier is more generous on the axes we'd actually stress
(sockets, invocations) and never pauses — but its daily reset means a demo spike
gets cut off mid-day, and it gives you nothing for auth. Supabase Free comfortably
carries dev + a ~100-concurrent-game beta.

### At target scale (monthly, approximate)

| | Supabase (today) | CF + D1 | CF + Neon/Hyperdrive |
| --- | --- | --- | --- |
| Base plan | $25 (Pro) | $5 (Workers Paid) | $5 |
| Compute / instance | ~$5–50 (Small→Medium add-on) | included (~30M CPU-ms) | included |
| Function invocations | ~$7 (3.5M over 2M @ $2/M) | ~$1–3 (reads move onto Workers too) | ~$1–3 |
| Durable Objects | — | ~$1 (requests; duration ~free **if hibernating**) | ~$1 |
| Realtime | **~$25** (msgs $10 + 1.5k extra connections $15) | $0 | $0 |
| Database | ~$3 (storage over 8 GB @ $0.125/GB) | **$0.75/GB-mo — and a hard 10 GB ceiling** | ~$20–80 (Neon: $0.106/CU-hr + $0.35/GB) |
| Auth | included | +$0 (keep Supabase Auth free) or +$25 (Clerk) | same |
| Storage | included | R2 free tier | R2 free tier |
| **Total** | **~$65–110** | **~$10–35** *(not viable past 10 GB)* | **~$30–90** |

**Read this table as: the savings are real but small, and they come almost
entirely from Realtime metering.** If you keep Postgres — which §3(e) says you
must — Cloudflare is roughly **cost-neutral**. The $40–70/month delta is not a
reason to spend two months of engineering. The *architecture* is.

**Cost landmine:** DO duration billing. A DO holding open WebSockets without the
**Hibernation API** bills GB-s continuously: 1,000 concurrent games × 8h/day ×
128 MB ≈ **460k GB-s/day**, or ~$175/month — worse than Supabase. With
hibernation it's ~$0. Getting this right is not optional.

---

## 5. Database options, ranked

1. **Keep Supabase Postgres** (called over HTTPS from Workers, exactly as the EF
   does today). Keeps RLS, PostgREST, the `engine_*` commit RPCs, `pg_trgm`
   search, jsonb, `int[]`, and the single finishing transaction. Zero data
   migration. No Hyperdrive needed (we speak PostgREST, not raw pg).
2. **Neon + Hyperdrive.** Real Postgres, keeps the schema and the commit RPCs, but
   you lose PostgREST/RLS/Auth/Realtime/Storage and must rebuild them. Hyperdrive's
   query cache is useless for us (write-heavy, freshness-critical); its value is
   connection pooling. Compute is billed by CU-hour, so an always-warm database is
   *not* cheap — this is the option that quietly costs as much as Supabase.
3. **D1.** Cheapest and the most "native", but: 10 GB/database ceiling (we blow
   through it in a month), single-threaded writer, no jsonb/arrays/trigram, and it
   forces the full client rewrite. Only viable with R2 archival of `observations`
   and `game_states`.
4. **DO SQLite as system of record.** Great for the hot game, hopeless for the
   cross-cutting reads we need (lobby, history, leaderboards, search, ratings) —
   those are inherently global queries. DO storage is a *cache/session* tier, not
   the database.

---

## 6. Recommended path — hybrid, staged, reversible

We have **no production users yet**, so the data-migration cost is zero *today*
and rises monotonically. If we're ever doing this, the ordering matters more than
the decision.

**Phase 0 — port the Edge Function to a Worker. (~1 week)**
`engine` is already hono + pure TS. Swap the Deno imports/env for Workers,
`@supabase/server` for `supabase-js` over HTTPS, and the Vault secret for a Worker
secret. Everything else — Postgres, RLS, PostgREST, Auth, Realtime, Storage, the
Dart client — is untouched. Verifies the runtime and gives us CF's CI/CD and local
dev. **Fully reversible.** The service-role key now lives in Cloudflare's secret
store, which is the one concession this phase makes (mitigable with a scoped
Postgres role instead of `service_role`).

**Phase 1 — introduce the per-game Durable Object. (~2–3 weeks)**
The DO becomes the serializer and the WebSocket hub, but **Postgres stays the
system of record**: the DO still commits through the same `engine_*` RPCs, so the
finishing transaction, the CHECK/FK/UNIQUE integrity backstop, and RLS on the read
paths all survive. This is where every win in §2 lands — DO alarms replace
`pg_cron`/`pg_net`/the grace-window symmetry, the input gate replaces optimistic
locking, and hibernating WebSockets replace Supabase Realtime (removing the 500-
connection cap and ~$25/mo). Client change is bounded: swap the Realtime channel
transport for a WebSocket, keep every PostgREST read.

**Phase 2 — only if a concrete need appears.** Moving Auth, PostgREST, and RLS off
Supabase costs the most and returns the least. Don't do it for the ~$40/month.
Do it only if we hit a Supabase limit we can't buy our way out of.

**Sequencing note:** Phase 1 depends on Phase 0, and both are cheap *now* and
expensive after launch (a live game session cannot be moved between a Postgres
`FOR UPDATE` chokepoint and a DO input gate without a maintenance window). If the
Cloudflare track in `todo.md` is real, it should land **before** Bravado ships,
not after.

---

## 7. Open questions for the decision

1. **What's driving this?** Cost (weak case), the simultaneous-move conflict
   problem (strong case — DO fixes it structurally), realtime scale limits (strong
   case), or platform consolidation/preference (fine, but say so)?
2. **Is dropping Supabase Auth acceptable?** Guest accounts + guest→Google upgrade
   is the most intricate thing we'd have to rebuild, and it has no Cloudflare
   answer. Keeping Supabase Auth alone (free tier) is the pragmatic move.
3. **Is `observations` history negotiable?** If we're willing to recompute
   observations from `game_states` on replay instead of persisting them per seat,
   the storage curve flattens ~3× and D1 becomes arguable. If not (and the reliable
   frame stream argues not), the DB stays Postgres.
4. **Web target.** `todo.md` lists web + web push. Workers + DO WebSockets are a
   better web story than Supabase Realtime; worth weighing if web is near-term.
