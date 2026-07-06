-- Local development app configuration.
-- In production, set these values via the Supabase dashboard or a
-- deployment script — never commit production values here.

INSERT INTO private.app_config (key, value, description) VALUES
  ('serverless_base_url', 'http://host.docker.internal:54321/functions/v1',
   'Base URL for serverless functions')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Vault secret `secret_api_key`: the project's secret API key, sent by the
-- cron sweeps as the `apikey` header to the engine EF's /engine/internal/*
-- routes (validated by @supabase/server's `auth: 'secret'` mode against the
-- SUPABASE_SECRET_KEY the functions runtime sees).
--
-- It is NOT seeded automatically: the local key is project-specific (printed
-- by `supabase status`). Until it is set, the sweeps log a loud
-- "secret_api_key not in Vault" warning and skip — set it once per local
-- reset:
--
--   SELECT vault.create_secret(
--     '<secret key from `supabase status`>',
--     'secret_api_key',
--     'Project secret API key; apikey header for cron -> engine EF calls'
--   );
