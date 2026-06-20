# Local-Bot Driver — design notes

How local bots actually _move_ in a solo game, why it's built this way, the
alternatives weighed, and the corner cases. This is the deep companion to
`engine_architecture.md` §26 (_Bots — Execution & Authentication_) and `bot.md`
(the overall bot design). Scope: **local** bots only — server bots are driven by
their own webhook + `bot-gateway`, nothing on the client.

---

## 1. The model in one sentence

**The sole human's client is the local bot's runtime; the server stays
authoritative.** A local bot is a pure `LocalBot.chooseAction` (Dart) that ships
in the build; it has no server presence, so the only place its code can run is
the client of the one human in the game. Every move it produces still goes
through the normal `submit_*` → `apply_seat_action` path and is re-validated
server-side under the `games FOR UPDATE` lock — exactly like a human move.

This is **forced** by two deliberate architectural choices, not chosen for its
own sake:

- **Server-authoritative.** The game rules live only in the SQL hooks
  (`game_apply_action`, `game_compute_observation`, …). The client never
  advances state; it just submits and waits for the fanned-out observation.
- **Zero-infra local bots.** A local bot is a `LocalBot` subclass in the game
  package — no endpoint, no deployment, no keys. The flip side is there is no
  server runtime to run it, so the client must.

If either choice changed, the driver would too (see _Options_, §6).

---

## 2. Current implementation

File: `lib/features/game/providers/local_bot_driver.dart`.

`LocalBotDriver` is a `void`-state `@riverpod` Notifier, family on `gameId`. The
game screen does `ref.watch(localBotDriverProvider(gameId:))` in `build` purely
to **keep it alive** — its state never changes, so it triggers no rebuilds; it
just needs to exist to react.

**Triggers.** In `build` it registers `ref.listen` on the four providers whose
change could mean "a local bot can now move", plus a one-shot kick:

- `gameStreamProvider` (status → `active`)
- `gameEngineProvider` (engine resolved)
- `gamePlayersProvider` (seats/identities resolved)
- `gameObservationProvider` (a new turn / `pending_players` changed)
- `Future.microtask(_maybeDrive)` — the listeners are change-only, so this
  attempts once on mount for an already-settled game (e.g. re-entered).

**`_maybeDrive`** (single-flight): sets `_driving = true` **before any `await`**
(so concurrent triggers in one tick can't double-enter), then:

1. `module.localBots` non-empty; game `active`; engine + players + observation
   all present.
2. **Solo gate**: exactly one human (`humanCount == 1`). This is the security
   boundary — a local bot is only ever driven where there is no other human.
3. `await botCatalogById` (warm; for per-bot `config`). `_disposed` re-checked
   after.
4. Walk the human's `pending_players`; for the first pending **bot** seat whose
   `info.username` matches a `localBots` entry, call `_driveOneBot` and
   **return** (one move per trigger; the resulting observation re-fires the
   listener for the next seat). Seats with no `localBots` match are server bots
   → skipped.

**`_driveOneBot`**: `get_local_bot_observation` (server-gated to the sole human)
→ `engine.parseObservation` → `LocalBot.chooseAction` (client compute) →
`engine.serializeAction` → `submit_local_bot_action`. `_disposed` is checked
after each `await`.

**Correctness rests on the server, not the client.** `submit_local_bot_action` /
`apply_seat_action` re-check the seat, version, and pending set under lock, so a
stale or duplicated drive is rejected (`Stale state` / not-pending) and
swallowed. The client driver is an optimization of "who computes", never a trust
boundary.

---

## 3. Lifecycle & liveness

**Screen-scoped.** The provider is `autoDispose` and alive only while the game
screen watches it. Leave the screen → it disposes; re-enter → it rebuilds,
re-reads the current observation (the stream re-emits current state on
subscribe), and resumes. So **re-entry is the recovery path**, not a failure.

**Local bots are always untimed** (the `create_solo_game` partition: local ⇒
untimed, server ⇒ timed — see `bot.md`). This is what makes the screen-scoped
lifetime safe: with no turn deadline, navigating away merely _pauses_ the bot;
there is no clock to lose. (The earlier "tab away and the bot times out" worry
only existed when timed + local was allowed; the partition removed it.)

**Backstops cover the rest.** A solo game abandoned mid-bot-turn stays `active`
(and shows on Home). If the human never returns, the **idle-cleanup job**
eventually aborts long-abandoned untimed active games. So nothing hangs forever,
and nothing needs the driver to run while the app is closed — _that_ use case
("keep playing while away") is, by definition, a **server** bot.

---

## 4. Options weighed

Three independent axes came up. The current choices are marked **★**.

### 4a. Where the driver lives / its lifetime

| Option                                                 | Pros                                                                                        | Cons                                                                                                |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| In the game-screen `State` (original)                  | none beyond "it works"                                                                      | tangled with rendering; needed to watch engine/players _just to re-kick_ — a smell                  |
| **★ Dedicated `autoDispose` provider, screen-watched** | single responsibility; watching its deps is now legitimately its job; testable in isolation | still screen-scoped (won't run while navigated away — fine for untimed solo)                        |
| App-level `keepAlive` provider, keyed by `gameId`      | keeps driving while briefly navigated away                                                  | runs for every visited game (memory); helps a narrow case only; app-background/close still stops it |
| Server-side (no client driver)                         | bot plays regardless of client                                                              | = it's a **server** bot; needs a deployed endpoint per game → kills zero-infra local bots           |

### 4b. Single driver vs per-seat

| Option                                                                                                      | Pros                                                                                                                                                    | Cons                                                                                                                                                                                                                |
| ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **★ Single driver, global single-flight, one seat / trigger**                                               | simplest; correct for **sequential** games (one seat pending at a time)                                                                                 | coarse — serializes all seats; for **simultaneous-pending** games (several bot seats in one version) it serial-drives across observation cycles and can stall if a partial submit emits no intermediate observation |
| Single driver, **per-seat `Set<int>`/`Map` guard, drive _all_ pending local seats** (recommended next step) | per-seat single-flight (guard scopes to exactly one seat); drives simultaneous pending in parallel; per-seat scratch state in a map; still one provider | a bit more code; per-seat _bot_ state still needs a contract change (see _Considerations_)                                                                                                                          |
| Per-seat **providers** + a supervisor watching players                                                      | maximal isolation; per-seat lifecycle                                                                                                                   | a supervisor + N family providers + N×listeners for seats that in solo are **fixed at creation** → lifecycle isolation buys little                                                                                  |

The current single/one-per-trigger driver is fine because every shipped game so
far is **sequential**. The Set-guard "drive-all" variant is the cleanest upgrade
if/when a simultaneous-move game ships; full per-seat providers are
over-engineering for fixed solo seats.

### 4c. Is "solo" its own concept?

| Stance                      | Means                                                              | Pros                                                                                                       | Cons                                                                                                                                       |
| --------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| **★ Emergent**              | solo = a game _shape_ (1 human + bots), same spine                 | maximal reuse; server-authoritative; ratings/history/replay/timing "just work"; local bots stay zero-infra | client is the runtime; per-move server latency (~100–300 ms); plays only while on-screen                                                   |
| First-class **offline**     | rules reimplemented in Dart on-device, Drift, device-authoritative | instant; works offline                                                                                     | **second authoritative rule implementation** — the cardinal sin this architecture avoids; large scope; the explicit _non-goal_ in `bot.md` |
| **Server-driven** solo bots | solo bots run server-side                                          | no client driver                                                                                           | requires a deployed endpoint → not "local" anymore                                                                                         |

Verdict: keep it **emergent**. The client-driver is the honest price of "local
bot = pure Dart + server-authoritative". Offline single-player would be a
separate feature built on a different (device-authoritative) foundation.

---

## 5. Why the current design (summary)

- **Reactive provider, screen-scoped, single-flight** is the minimal correct
  shape given server-authoritative + zero-infra local bots.
- It reuses the entire human spine (submit → commit → finish → fan-out →
  ratings); solo adds _only_ this driver on the client.
- The server is the trust boundary, so the client driver can be "best-effort":
  races, double-drives, and stale submits are all rejected server-side.

---

## 6. Known limitations & corner cases

- **Per-move latency.** Each bot move is a server round-trip (~100–300 ms). Fine
  for casual solo; buttery instant single-player would require offline mode
  (§4c).
- **Simultaneous-pending games** are serial under the current
  one-seat-per-trigger driver and could stall if a partial submit emits no
  observation. No shipped game is simultaneous; the Set-guard "drive-all"
  variant (§4b) is the fix when one is.
- **Plays only while on-screen.** By design (see §3). Re-entry resumes;
  idle-cleanup reaps abandonment. "Keep playing while away" ⇒ server bot.
- **Disposal mid-compute.** If the human leaves during a slow `chooseAction`,
  the `_disposed` guard skips the submit; the (untimed) game simply waits for
  re-entry.
- **Mixed local+server in one solo game is impossible** (the partition: local ⇒
  untimed, server ⇒ timed). A solo game is therefore _either_ all-local-untimed
  _or_ all-server-timed, never both — which keeps the driver's "is this seat
  mine?" check unambiguous.

---

## 7. Considerations / open work

- **Per-seat _bot_ state** (e.g. an MCTS tree reused across a seat's turns) is
  _not_ possible today: `localBots` are `const` stateless singletons by
  contract, and `chooseAction` exposes no per-seat scratch. A per-seat driver
  could _hold_ state, but for the _bot_ to use it you'd have to thread a
  per-seat state bag into `chooseAction` — a contract change, weigh separately.
- **Set-guard "drive-all" driver** (§4b) — the recommended upgrade for
  simultaneous-pending robustness and per-seat single-flight. Low-risk, one
  provider.
- **Derived compute/effect split** — modelling "the next move to submit" as a
  pure provider and the submit as a listener is more idiomatic/testable, but the
  re-trigger loop makes it circular; judged a lateral move, not a clear win.
- **`keepAlive` lifetime** — only if "keep moving while briefly navigated away"
  becomes a real requirement; otherwise the screen scope is simpler and
  sufficient.

---

## 8. Pointers

- Code: `lib/features/game/providers/local_bot_driver.dart`; the contract
  `lib/core/game/local_bot.dart`; the gated RPCs `get_local_bot_observation` /
  `submit_local_bot_action` and the `create_solo_game` partition in
  `…/20260505045425_create_game_infra_functions.sql`.
- The solo picker that creates these games: `play_vs_bot_dialog.dart` (+
  `soloPlayAvailableProvider` gating the "New Solo Game" FAB).
- Architecture: `engine_architecture.md` §26. Overall bot design: `bot.md`.
