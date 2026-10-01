-- ============================================================================
-- Supabase Scheduled Push Notifications (Every 3 Hours)
-- Run this in your Supabase SQL Editor to automate task alerts
-- ============================================================================

-- 1. Enable required extensions
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- 2. Create helper function to trigger the send-push-notification edge function
CREATE OR REPLACE FUNCTION send_scheduled_task_push_notification()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  project_url text := 'https://<YOUR-PROJECT-REF>.supabase.co'; -- Replace with your Supabase Project URL
  anon_key text := '<YOUR-ANON-KEY>'; -- Replace with your Supabase Anon/Service Key
BEGIN
  PERFORM net.http_post(
    url := project_url || '/functions/v1/send-push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || anon_key
    ),
    body := jsonb_build_object(
      'topic', 'all-users',
      'data', jsonb_build_object(
        'type', 'task_alert',
        'reward', '2.40'
      )
    )
  );
END;
$$;

-- 3. Schedule the function to run every 3 hours (At minute 0 past every 3rd hour: 00:00, 03:00, 06:00, 09:00, 12:00, 15:00, 18:00, 21:00 UTC)
-- First unschedule any existing job with the same name if exists
SELECT cron.unschedule('xapzap_3hour_task_notification')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'xapzap_3hour_task_notification'
);

-- Register cron job
SELECT cron.schedule(
  'xapzap_3hour_task_notification',
  '0 */3 * * *',
  'SELECT send_scheduled_task_push_notification();'
);

-- Check scheduled jobs
SELECT * FROM cron.job;
