import { createClient } from "@supabase/supabase-js";
import "@supabase/functions-js/edge-runtime.d.ts";
import { computeRatings, type PlayerInput } from "./ratings.ts";

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
    return new Response("Internal error applying rating updates", {
      status: 500,
    });
  }

  console.log(
    `Ratings updated for game ${gameId} (pool: ${pool}), ${players.length} players`,
  );

  return Response.json({ updated: players.length });
});
