-- ====================================================================
-- XapZap Database Migration: Level Upgrades, Campaigns & Withdrawals
-- Run this script in the Supabase SQL Editor:
-- https://supabase.com/dashboard/project/tnjmwahnzosuhqpkvuwo/sql
-- ====================================================================

-- 1. Extend user profiles to track registration date and upgrade level
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT timezone('utc'::text, now());
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS user_level int DEFAULT 1;

-- 2. Create withdrawal details table
CREATE TABLE IF NOT EXISTS public.user_withdrawal_details (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  bank_name varchar,
  account_number varchar,
  account_name varchar,
  routing_number_or_swift varchar,
  crypto_address varchar,
  preferred_method varchar DEFAULT 'bank_transfer',
  updated_at timestamptz DEFAULT timezone('utc'::text, now()),
  UNIQUE(user_id)
);

-- Enable Row Level Security (RLS) on withdrawal details
ALTER TABLE public.user_withdrawal_details ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own withdrawal details"
  ON public.user_withdrawal_details
  FOR ALL
  USING (auth.uid() = user_id);

-- 3. Create level upgrade transactions table
CREATE TABLE IF NOT EXISTS public.level_upgrades (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  from_level int DEFAULT 1,
  to_level int NOT NULL,
  amount_paid numeric(10, 2) NOT NULL,
  payment_method varchar NOT NULL,
  reference_id varchar UNIQUE,
  status varchar DEFAULT 'pending', -- pending, completed, failed
  created_at timestamptz DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.level_upgrades ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own upgrades"
  ON public.level_upgrades
  FOR SELECT
  USING (auth.uid() = user_id);

-- 4. Create advertiser video campaigns table
CREATE TABLE IF NOT EXISTS public.video_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  advertiser_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  video_url varchar NOT NULL,
  campaign_type varchar NOT NULL,
  duration_minutes int NOT NULL,
  target_reviews int NOT NULL,
  reviews_completed int DEFAULT 0,
  total_paid numeric(10, 2) NOT NULL,
  status varchar DEFAULT 'pending', -- pending, active, paused, completed, rejected, canceled
  created_at timestamptz DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.video_campaigns ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view active video campaigns"
  ON public.video_campaigns
  FOR SELECT
  USING (status = 'active');

CREATE POLICY "Advertisers can manage their own campaigns"
  ON public.video_campaigns
  FOR ALL
  USING (auth.uid() = advertiser_id);

CREATE POLICY "Admins can manage all campaigns"
  ON public.video_campaigns
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid() AND (profiles.username LIKE '%admin%' OR profiles.username LIKE '%staff%')
    )
  );

-- 5. Create user completed reviews table (to track who completed which campaign and prevent double earning)
CREATE TABLE IF NOT EXISTS public.user_completed_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  campaign_id uuid REFERENCES public.video_campaigns(id) ON DELETE CASCADE,
  rating_stars int NOT NULL CHECK (rating_stars >= 1 AND rating_stars <= 5),
  feedback_quality int NOT NULL CHECK (feedback_quality >= 1 AND feedback_quality <= 5),
  feedback_actors int NOT NULL CHECK (feedback_actors >= 1 AND feedback_actors <= 5),
  general_feedback text,
  earned_amount numeric(10, 3) NOT NULL,
  created_at timestamptz DEFAULT timezone('utc'::text, now()),
  UNIQUE(user_id, campaign_id)
);

ALTER TABLE public.user_completed_reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own completed reviews"
  ON public.user_completed_reviews
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own reviews"
  ON public.user_completed_reviews
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- 6. Create website tasks table to store visit-website URLs
CREATE TABLE IF NOT EXISTS public.website_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  url varchar NOT NULL UNIQUE,
  is_visible boolean DEFAULT true,
  created_at timestamptz DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.website_tasks ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.website_tasks ADD COLUMN IF NOT EXISTS is_visible boolean DEFAULT true;
ALTER TABLE public.website_tasks ADD COLUMN IF NOT EXISTS is_direct boolean DEFAULT false;

DROP POLICY IF EXISTS "Anyone can view website tasks" ON public.website_tasks;
CREATE POLICY "Anyone can view website tasks"
  ON public.website_tasks
  FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Admins can manage website tasks" ON public.website_tasks;
CREATE POLICY "Admins can manage website tasks"
  ON public.website_tasks
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid() AND (profiles.username LIKE '%admin%' OR profiles.username LIKE '%staff%')
    )
  );

-- Seed initial website links
INSERT INTO public.website_tasks (url, is_visible) VALUES
  ('https://www.profitableratecpmnetwork.com/chrbnk3865?key=a94643bb549f8e0c76e4fa34b3041468', true),
  ('https://www.profitableratecpmnetwork.com/jmq51gqwmj?key=5a1f43bebb2399ff8b697c3e6520b092', true),
  ('https://www.profitableratecpmnetwork.com/ng0muydek8?key=ca8a96af33fe76b70e804e7a9b944fda', true),
  ('https://www.profitableratecpmnetwork.com/wjxp5816d?key=815fccee5f572eedcc89699cb6d4e7cc', true),
  ('https://www.profitableratecpmnetwork.com/hfwzvp5hw?key=9d67d4c9254359b8de5e5123898a00b7', true),
  ('https://www.profitableratecpmnetwork.com/pvms5sdi28?key=e7714064cc2f40fb7b357f826e40c910', true),
  ('https://www.profitableratecpmnetwork.com/fwqa4t7p?key=e7ac381e69c2426bfbf1e5c327876bb8', true),
  ('https://www.profitableratecpmnetwork.com/cntr3s5zd?key=31be3450feaa26807e3a998b40a08f9f', true),
  ('https://www.profitableratecpmnetwork.com/eepv3zn8?key=46237b4eae98c1640f8f0d2dee0a7eb5', true),
  ('https://www.profitableratecpmnetwork.com/ensmm8ye4a?key=c8f0e696e0e2687122edea923628e1b1', true)
ON CONFLICT (url) DO NOTHING;

-- 7. Create app settings table for global configuration
CREATE TABLE IF NOT EXISTS public.app_settings (
  key varchar PRIMARY KEY,
  value varchar NOT NULL,
  updated_at timestamptz DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view app settings" ON public.app_settings;
CREATE POLICY "Anyone can view app settings" ON public.app_settings FOR SELECT USING (true);

DROP POLICY IF EXISTS "Admins can manage app settings" ON public.app_settings;
CREATE POLICY "Admins can manage app settings" ON public.app_settings FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = auth.uid() AND (profiles.username LIKE '%admin%' OR profiles.username LIKE '%staff%')
  )
);

INSERT INTO public.app_settings (key, value) VALUES ('total_payout_usd', '132450.80') ON CONFLICT (key) DO NOTHING;

-- 8. Add is_tasks_unlocked column to public.profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_tasks_unlocked boolean DEFAULT false;

-- Seed existing user profiles (old users) to have tasks unlocked automatically
UPDATE public.profiles SET is_tasks_unlocked = true WHERE is_tasks_unlocked IS NULL;

