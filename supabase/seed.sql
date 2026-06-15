-- Local development app configuration.
-- In production, set these values via the Supabase dashboard or a
-- deployment script — never commit production values here.

INSERT INTO private.app_config (key, value, description) VALUES
  ('serverless_base_url', 'http://host.docker.internal:54321/functions/v1',
   'Base URL for serverless functions')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Store the serverless shared secret in Vault.
DO $$
DECLARE
  v_id UUID;
BEGIN
  SELECT id INTO v_id FROM vault.secrets WHERE name = 'serverless_secret';
  IF v_id IS NULL THEN
    PERFORM vault.create_secret(
      'local-dev-secret',
      'serverless_secret',
      'Shared secret verified by all serverless functions (see SERVERLESS_SECRET in .env.local)'
    );
  ELSE
    PERFORM vault.update_secret(
      v_id,
      'local-dev-secret',
      'serverless_secret',
      'Shared secret verified by all serverless functions (see SERVERLESS_SECRET in .env.local)'
    );
  END IF;
END $$;
