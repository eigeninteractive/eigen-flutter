import { createClient } from "@supabase/supabase-js";
import "@supabase/functions-js/edge-runtime.d.ts";
import { rate, rating } from "openskill";

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (value === undefined) throw new Error(`Missing env var: ${name}`);
  return value;
}

const supabase = createClient(
  requireEnv("SUPABASE_URL"),
  requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { persistSession: false } },
);
const WEBHOOK_SECRET = requireEnv("SERVERLESS_SECRET");

// display_rating = max(0, round((mu - 3σ) * 40))
function toDisplay(mu: number, sigma: number): number {
  return Math.max(0, Math.round((mu - 3 * sigma) * 40));
}

// Shape sent by the pg_net trigger. Current ratings are bundled so this
// function has no dependency on DB schema for computation.
interface PlayerInput {
  player_index: number;
  user_id: string | null;
  bot_id: string | null;
  /** Ordinal finish rank (1 = best); ties share the same value. */
  placement: number;
  /** Players sharing a team_index are rated as one team.
   * For individual games this equals player_index. */
  team_index: number;
  mu: number;
  sigma: number;
  display_rating: number;
}

// Computed per-player rating delta — passed directly to apply_rating_updates RPC.
interface RatingUpdate {
  identity: { user_id: string } | { bot_id: string };
  before: { mu: number; sigma: number; display_rating: number };
  after: { mu: number; sigma: number; display_rating: number };
}

function playerIdentity(player: PlayerInput): RatingUpdate["identity"] {
  if (player.user_id) return { user_id: player.user_id };
  if (player.bot_id) return { bot_id: player.bot_id };
  throw new Error(`Player ${player.player_index} has no identity`);
}

type NonEmptyArray<T> = [T, ...T[]];

function groupByTeam(players: PlayerInput[]): NonEmptyArray<PlayerInput>[] {
  const groups = new Map<number, NonEmptyArray<PlayerInput>>();
  for (const player of players) {
    const group = groups.get(player.team_index);
    if (group) {
      group.push(player);
    } else {
      groups.set(player.team_index, [player]);
    }
  }
  return [...groups.values()];
}

function computeRatings(players: PlayerInput[]): RatingUpdate[] {
  const teams = groupByTeam(players);

  const updatedTeams = rate(
    teams.map((members) =>
      members.map((p) => rating({ mu: p.mu, sigma: p.sigma }))
    ),
    { rank: teams.map(([first]) => first.placement) },
  );

  return teams.flatMap((members, i) =>
    members.map((player, j) => {
      const { mu, sigma } = updatedTeams[i][j];
      return {
        identity: playerIdentity(player),
        before: {
          mu: player.mu,
          sigma: player.sigma,
          display_rating: player.display_rating,
        },
        after: { mu, sigma, display_rating: toDisplay(mu, sigma) },
      };
    })
  );
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }
  if (req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
    return new Response("Unauthorized", { status: 401 });
  }

  let gameId: string;
  let pool: string;
  let players: PlayerInput[];
  try {
    const body = await req.json();
    gameId = body.game_id;
    pool = body.rating_pool;
    players = body.players;
    if (!gameId || !pool || !Array.isArray(players)) {
      throw new Error("missing required fields");
    }
  } catch {
    return new Response(
      "Bad Request: expected {game_id, rating_pool, players}",
      { status: 400 },
    );
  }

  if (players.length < 2) {
    return new Response("Not enough rated players", { status: 200 });
  }

  const updates = computeRatings(players);

  const { error } = await supabase.rpc("apply_rating_updates", {
    p_game_id: gameId,
    p_pool: pool,
    p_updates: updates,
  });

  if (error) {
    console.error("apply_rating_updates failed:", error);
    return new Response("Internal error applying rating updates", { status: 500 });
  }

  console.log(
    `Ratings updated for game ${gameId} (pool: ${pool}), ${players.length} players`,
  );

  return Response.json({ updated: players.length });
});
