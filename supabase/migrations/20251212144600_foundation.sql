-- ============================================
-- Foundation — runs first
-- ============================================
-- DB-wide prerequisites that no single table or function owns: the private
-- schema, the extensions, and the shared enum types. Defining them once here
-- (rather than scattering them across the table/function migrations that happen
-- to use them first) keeps the dependency obvious and the later files honest.
--
-- Rule: cross-cutting types live here. There are no purely table-local enums in
-- this engine — every enum is referenced by multiple tables, functions, or the
-- generated TS/Dart types (e.g. lifecycle_type has no table column at all),
-- so co-locating any of them would be arbitrary.
-- ============================================

-- Private schema — internal helpers (engine_*/cron_*/do_*); not exposed via the
-- Supabase API.
CREATE SCHEMA IF NOT EXISTS private;

-- Extensions (DB-wide capabilities). Placed in the `extensions` schema where the
-- extension supports it; pg_cron manages its own `cron` schema.
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;  -- trigram search (app_search_users)
CREATE EXTENSION IF NOT EXISTS pg_net  WITH SCHEMA extensions;  -- net.http_post (cron sweeps → internal EF)
CREATE EXTENSION IF NOT EXISTS pg_cron;                         -- scheduled jobs (cron_* in cron_jobs migration)

-- Shared enum types.
CREATE TYPE game_status AS ENUM ('waiting', 'ready', 'active', 'finished', 'aborted');
CREATE TYPE game_access AS ENUM ('public', 'private', 'friends');
CREATE TYPE action_type AS ENUM ('user', 'bot', 'system');
-- The two species of logged action, by contract: a 'game' action is
-- rules-scoped (game-defined payload, validated by applyAction, rejectable);
-- a 'lifecycle' action is engine-scoped (timeout / forfeit / auto_forfeit,
-- resolved unconditionally by applyLifecycle). Orthogonal to action_type,
-- which records WHO performed it — a resign is type 'user' + kind 'lifecycle'.
CREATE TYPE action_kind AS ENUM ('game', 'lifecycle');
CREATE TYPE game_result AS ENUM ('win', 'loss', 'draw', 'eliminated');
-- Infra-defined lifecycle-action subtypes. Game implementors handle these in
-- applyLifecycle but never add new values — only infra does.
CREATE TYPE lifecycle_type AS ENUM ('timeout', 'forfeit', 'auto_forfeit');
CREATE TYPE participant_type AS ENUM ('human', 'bot');
CREATE TYPE relationship_status AS ENUM ('pending', 'accepted', 'blocked');
