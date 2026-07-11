/**
 * Post-commit turn notifications — the EF side of what the SQL `notify_your_turn`
 * trigger used to do off the observation write. After a transition commits, the
 * seats whose turn is starting are told: humans get an FCM push, server bots a
 * signed wake carrying their observation. Who counts as "starting" depends on
 * the transition's cause — the whole policy lives in {@link recipientSeats},
 * and every commit path routes through {@link notifyTransition} so no path can
 * forget to notify.
 *
 * Best-effort and run post-response via `EdgeRuntime.waitUntil`, so a slow or
 * failed send never blocks the action response. The fire-and-forget entry
 * points ({@link notifyTransition}, {@link notifyGameStarted},
 * {@link notifyGameInvite}) never throw — they log and give up, so callers can
 * hand them to `waitUntil` bare. Human pushes get no retry (the DB is the
 * truth; the app catches up on open); a bot wake is retried briefly on a
 * failed ack (see {@link wakeBot}) because the wake is the bot's only signal. The other EF-direct pushes live here too: the
 * friends-game invite ({@link notifyGameInvite}, from the `/game/create`
 * route) and the generic fan-out ({@link notifyUsers}, reused by social
 * handlers).
 *
 * This module orchestrates only: every query lives in `repo.ts`
 * (`readUserFids`, `pruneFids`, …), the pure FCM send in `fcm.ts` — so the
 * notification flow reads top-to-bottom without storage details.
 */

import { retry } from "@std/async";
import { signForBot } from "./bot_auth.ts";
import { getFirebaseEnv } from "./env.ts";
import { type NotificationMessage, sendNotifications } from "./fcm.ts";
import {
  type Db,
  pruneFids,
  readDisplayNames,
  readGameInviteContext,
  readGameState,
  readSeatObservation,
  readUserFids,
  type Seat,
} from "./repo.ts";

/** Send `message` to every FID registered to `userId` via FCM, then prune any
 * permanently unregistered devices. */
export async function pushToUser(
  db: Db,
  userId: string,
  message: NotificationMessage,
): Promise<void> {
  const firebaseEnv = getFirebaseEnv();
  if (!firebaseEnv) {
    console.warn(`Push skipped for ${userId}: FCM not configured`);
    return;
  }

  const fids = await readUserFids(db, userId);
  if (fids.length === 0) return;

  const responses = await sendNotifications(firebaseEnv, message, fids);

  const stale = responses.flatMap((r) =>
    r.status === "fulfilled" && r.value.prunable ? [r.value.fid] : []
  );
  if (stale.length > 0) await pruneFids(db, userId, stale);
}

/** Fan one push out to a set of users, best-effort. Shared by the social
 * handlers (friend request/accept) and the game-invite notifier. */
export async function notifyUsers(
  db: Db,
  recipients: string[],
  msg: NotificationMessage,
): Promise<void> {
  await Promise.allSettled(
    recipients.map((userId) => pushToUser(db, userId, msg)),
  );
}

/** Push a friends-game invite to every accepted friend of the creator. Called
 * post-commit from the `/game/create` route (replaces the `notify_game_invite`
 * trigger). No-op for non-friends games / a creator with no friends. Never
 * throws. */
export async function notifyGameInvite(db: Db, gameId: string): Promise<void> {
  try {
    const invite = await readGameInviteContext(db, gameId);
    if (!invite || invite.friendIds.length === 0) return;

    await notifyUsers(db, invite.friendIds, {
      title: `${invite.creatorName ?? "A friend"} started a game`,
      body: "Join now to play.",
      data: { category: "game_invite", deep_link: `/join/${invite.shortCode}` },
    });
  } catch (e) {
    console.error(`notifyGameInvite failed for ${gameId}:`, e);
  }
}

/** Why a transition committed — decides who is told it's their turn. */
export type NotifyCause =
  | { kind: "action"; actorSeat: number }
  | { kind: "forfeit" }
  | { kind: "timeout" }
  | { kind: "start" };

/** The seats a committed transition should alert.
 *
 * Seats that newly entered the pending set are always told — their turn is
 * starting. Two cause-specific rules cover what a pure diff misses:
 *
 * - `timeout`: everyone still pending is (re-)notified. Pushes are
 *   fire-and-forget and a wake retries only briefly (see {@link wakeBot}),
 *   so the expiry sweep doubles as the delivery retry of last resort; the
 *   deadline itself rate-limits the re-nudge.
 * - `action`: the actor's own seat can re-enter pending (an extra turn). A
 *   human actor is live in-app and needs no push, but a server bot's only
 *   signal is the wake, so it is woken again.
 */
function recipientSeats(
  cause: NotifyCause,
  prevPending: number[],
  finalPending: number[],
  roster: Seat[],
): number[] {
  if (cause.kind === "timeout") return finalPending;
  const prev = new Set(prevPending);
  const recipients = finalPending.filter((seat) => !prev.has(seat));
  if (
    cause.kind === "action" &&
    finalPending.includes(cause.actorSeat) &&
    !recipients.includes(cause.actorSeat)
  ) {
    const actor = roster.find((r) => r.player_index === cause.actorSeat);
    if (actor?.bot_id && !actor.is_local && actor.webhook_url) {
      recipients.push(cause.actorSeat);
    }
  }
  return recipients;
}

/** Notify the seats whose turn starts with this transition (see
 * {@link recipientSeats} for the cause-aware policy). Never throws. */
export async function notifyTransition(
  db: Db,
  args: {
    gameId: string;
    cause: NotifyCause;
    prevPending: number[];
    finalPending: number[];
    roster: Seat[];
  },
): Promise<void> {
  try {
    const recipients = recipientSeats(
      args.cause,
      args.prevPending,
      args.finalPending,
      args.roster,
    );
    if (recipients.length === 0) return;

    // Display names are only needed to personalise a human's "your turn" push,
    // so resolve them only when a human is being notified.
    const hasHumanRecipient = recipients.some(
      (seat) => args.roster.find((r) => r.player_index === seat)?.user_id,
    );
    const names = hasHumanRecipient
      ? await readDisplayNames(db, args.roster)
      : new Map<number, string>();

    for (const seat of recipients) {
      const ref = args.roster.find((r) => r.player_index === seat);
      if (!ref) continue;
      try {
        if (ref.user_id) {
          await pushToUser(
            db,
            ref.user_id,
            turnPush(args.gameId, seat, args.roster, names),
          );
        } else if (ref.bot_id && !ref.is_local && ref.webhook_url) {
          await wakeBot(db, args.gameId, seat, ref.bot_id, ref.webhook_url);
        }
      } catch (e) {
        console.error(`notify seat ${seat} failed:`, e);
      }
    }
  } catch (e) {
    console.error(`notifyTransition failed for ${args.gameId}:`, e);
  }
}

/** Notify the opening mover(s) after a start commit. The roster (with bot wake
 * fields) is re-read because the start commit doesn't return it. Never throws. */
export async function notifyGameStarted(
  db: Db,
  gameId: string,
  finalPending: number[],
): Promise<void> {
  try {
    const read = await readGameState(db, gameId);
    await notifyTransition(db, {
      gameId,
      cause: { kind: "start" },
      prevPending: [],
      finalPending,
      roster: read.roster,
    });
  } catch (e) {
    console.error(`notifyGameStarted failed for ${gameId}:`, e);
  }
}

/** Build the "your turn" push for `seat`. With exactly one identified opponent
 * the body names them ("It's your move against Ada."); otherwise it stays
 * generic, since the engine has no game title to lean on. */
function turnPush(
  gameId: string,
  seat: number,
  roster: Seat[],
  names: Map<number, string>,
): NotificationMessage {
  const data = { category: "your_turn", deep_link: `/game/${gameId}` };
  const opponents = roster.filter(
    (r) => r.player_index !== seat && (r.user_id || r.bot_id),
  );
  if (opponents.length === 1) {
    const name = names.get(opponents[0].player_index);
    if (name) {
      return {
        title: "Your turn",
        body: `It's your move against ${name}.`,
        data,
      };
    }
  }
  return { title: "Your turn", body: "It's your move.", data };
}

/** Wake retry policy: 3 attempts, pausing 2s then 8s. Short by design:
 * these run inside the post-response worker (`waitUntil`), whose wall clock
 * is finite — anything longer-lived than seconds is the expiry sweep's job. */
const wakeRetryOptions = {
  maxAttempts: 3,
  minTimeout: 2000,
  multiplier: 4,
  jitter: 0,
};

/** How long a bot gets to *ack* a wake. Acking is "queued", not "acted", so
 * a healthy bot answers near-instantly; a hung endpoint must not pin the
 * worker for the platform's whole wall clock. */
const wakeAckTimeoutMs = 10_000;

/** Post a signed wake to a server bot, carrying its freshly-committed
 * observation so the bot needs no callback to fetch state.
 *
 * The bot's 2xx response is an ack of receipt only — the move arrives later
 * on `bot/action` — so a failed ack (non-2xx, timeout, network error) is
 * retried a few times with short backoff. Duplicate wakes are safe: each
 * carries the same `version`, and a duplicated action loses the version
 * check at commit. A bot that stays down past the retries rides the timeout
 * backstop (server ⇒ timed). */
async function wakeBot(
  db: Db,
  gameId: string,
  playerIndex: number,
  botId: string,
  webhookUrl: string,
): Promise<void> {
  const obs = await readSeatObservation(db, gameId, playerIndex);
  if (!obs) {
    console.error(`bot wake skipped (no observation) for seat ${playerIndex}`);
    return;
  }

  const body = JSON.stringify({
    game_id: gameId,
    bot_id: botId,
    player_index: playerIndex,
    observation: obs.data,
    version: obs.version,
    pending_players: obs.pending_players,
    turn_deadline: obs.turn_deadline,
  });
  const signature = await signForBot(botId, "wake", body);

  const attemptWake = async () => {
    try {
      await postWake(webhookUrl, signature, body);
    } catch (e) {
      console.error(
        `bot wake attempt for game ${gameId} seat ${playerIndex} ` +
          `failed: ${e instanceof Error ? e.message : e}`,
      );
      throw e;
    }
  };

  try {
    await retry(attemptWake, wakeRetryOptions);
  } catch {
    console.error(
      `bot wake for game ${gameId} seat ${playerIndex} exhausted ` +
        `${wakeRetryOptions.maxAttempts} attempts — giving up; ` +
        `the turn deadline is the backstop`,
    );
  }
}

/** One wake POST. Resolves on a 2xx ack; throws on anything else (non-2xx
 * status, timeout, network error) so {@link retry} treats it as a failed
 * attempt. */
async function postWake(
  webhookUrl: string,
  signature: string,
  body: string,
): Promise<void> {
  const res = await fetch(webhookUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-wake-signature": signature,
    },
    body,
    signal: AbortSignal.timeout(wakeAckTimeoutMs),
  });
  await res.body?.cancel();
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
}
