-- ============================================
-- CRON JOBS
-- ============================================
-- Schedules the private.cron_* sweeps. The pg_cron extension is created in the
-- foundation migration.
-- ============================================

-- Unschedule first so this migration is idempotent on re-runs
-- (e.g. supabase db reset re-applies every migration from scratch).
SELECT cron.unschedule('expire-turns')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'expire-turns');

SELECT cron.schedule(
  'expire-turns',
  '* * * * *',   -- every minute; sub-minute accuracy is the client expiry nudge
  $cron$
    SELECT private.cron_expire_turns();
  $cron$
);

SELECT cron.unschedule('cleanup-idle-games')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup-idle-games');

SELECT cron.schedule(
  'cleanup-idle-games',
  '0 3 * * *',   -- daily at 03:00 UTC
  $cron$
    SELECT private.cron_cleanup_idle_games();
  $cron$
);

SELECT cron.unschedule('cleanup-stale-anon-users')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup-stale-anon-users');

SELECT cron.schedule(
  'cleanup-stale-anon-users',
  '30 3 * * *',   -- daily at 03:30 UTC, after idle-game cleanup
  $cron$
    SELECT private.cron_cleanup_stale_guests();
  $cron$
);
