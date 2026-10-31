-- ============================================================
-- Run the automatic no-show check every minute (Supabase pg_cron).
-- © 2026 Services Squire LLC. All rights reserved.
-- ============================================================
create extension if not exists pg_cron;

do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'crc-auto-no-show';
  perform cron.schedule('crc-auto-no-show', '* * * * *', 'select public.auto_no_show()');
end $$;
