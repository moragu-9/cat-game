-- Enable after the retention policy has been approved. Daily at 04:15 Korea time.
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('cat-game-retention','15 19 * * *',
 $$select public.cleanup_hunts();
 delete from cron.job_run_details where jobid=(select jobid from cron.job where jobname='cat-game-retention') and end_time<now()-interval '14 days';$$);
select jobname,schedule,active from cron.job where jobname='cat-game-retention';
