-- ============================================
-- App Config table
-- ============================================
-- Key-value store for environment-specific application configuration.
-- Lives in the private schema so it is not exposed via the REST API.
-- Sensitive values (secrets) should be stored in Vault instead.
CREATE TABLE private.app_config (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,
  description TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================
-- Games table with enums
-- ============================================

-- Games table (metadata only, no game_state)
CREATE TABLE public.games (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  status game_status NOT NULL DEFAULT 'waiting',
  access game_access NOT NULL DEFAULT 'public',
  -- Seconds per turn (per-action timer). NULL means untimed or use budget.
  -- Mutually exclusive with budget_seconds.
  turn_seconds INT,
  -- Personal time budget per player in seconds (accumulated clock).
  -- NULL means no bank. Mutually exclusive with turn_seconds.
  budget_seconds INT,
  -- Seconds added to a player's bank after each budget-consuming action
  -- (Fischer increment). Only meaningful when budget_seconds IS NOT NULL.
  -- NULL treated as 0.
  increment_seconds INT,
  -- Minimum players required to transition the game to 'ready' status.
  min_players INT NOT NULL DEFAULT 2,
  -- Maximum players allowed to join. join_game rejects once full.
  max_players INT NOT NULL DEFAULT 2,
  config JSONB NOT NULL DEFAULT '{}'::jsonb,
  short_code VARCHAR(6) UNIQUE NOT NULL,
  -- Whether this game counts toward player skill ratings.
  rated BOOLEAN NOT NULL DEFAULT false,
  -- Rating pool name (e.g. 'rapid', 'daily'). Non-null iff rated = true.
  -- Derived at creation time by GameModule.ratingPool().
  rating_pool TEXT,
  -- Schema-level guard: exactly one timing mode at a time.
  CONSTRAINT timing_mode_exclusive CHECK (
    turn_seconds IS NULL OR budget_seconds IS NULL
  ),
  -- Rated games must specify a pool; unrated games must not.
  CONSTRAINT rated_pool_consistent CHECK (
    NOT rated OR rating_pool IS NOT NULL
  ),
  -- increment_seconds is only meaningful with a budget.
  CONSTRAINT increment_requires_budget CHECK (
    increment_seconds IS NULL OR budget_seconds IS NOT NULL
  ),
  CONSTRAINT player_count_valid CHECK (min_players >= 1 AND max_players >= min_players),
  -- Hard bounds on timing values. Mirrors kMinTurnSeconds/kMaxTurnSeconds in Dart.
  CONSTRAINT turn_seconds_bounds CHECK (
    turn_seconds IS NULL OR (turn_seconds >= 30 AND turn_seconds <= 2592000)
  ),
  CONSTRAINT budget_seconds_bounds CHECK (
    budget_seconds IS NULL OR (budget_seconds >= 120 AND budget_seconds <= 864000)
  ),
  CONSTRAINT increment_seconds_bounds CHECK (
    increment_seconds IS NULL OR increment_seconds >= 0
  ),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indices
CREATE INDEX idx_games_status ON public.games(status);
CREATE INDEX idx_games_created_by ON public.games(created_by);
CREATE INDEX idx_games_access_status ON public.games(access, status);
-- Partial index for lobby queries (public waiting/ready games)
CREATE INDEX idx_games_lobby ON public.games(created_at DESC)
  WHERE access = 'public' AND status IN ('waiting', 'ready');

-- RLS (SELECT only - all mutations via RPC)
-- Note: Full policy with participant check is added in participants migration
ALTER TABLE public.games ENABLE ROW LEVEL SECURITY;

-- Updated_at trigger
CREATE TRIGGER update_games_updated_at
  BEFORE UPDATE ON public.games
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Enable Realtime for this table (for lobby and active games streams)
ALTER PUBLICATION supabase_realtime ADD TABLE public.games;
