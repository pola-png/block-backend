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

-- ====================================================================
-- 9. XapZap REWARD LIVE — DATABASE TABLES, FUNCTIONS & SECURITY
-- ====================================================================

-- 9.1 Persistent Reward Live State Table
CREATE TABLE IF NOT EXISTS public.reward_live_state (
  id uuid PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000001'::uuid,
  status varchar NOT NULL DEFAULT 'ACTIVE', -- ACTIVE, PAUSED, MAINTENANCE
  live_started_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  reward_interval_seconds int NOT NULL DEFAULT 180,
  claim_window_seconds int NOT NULL DEFAULT 15,
  cycle_point_pool int NOT NULL DEFAULT 1000,
  last_reward_cycle bigint NOT NULL DEFAULT 0,
  current_host_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  current_host_name varchar,
  current_host_avatar varchar,
  current_stream_id varchar,
  activity_mode varchar NOT NULL DEFAULT 'ACTIVE', -- ACTIVE, IDLE
  created_at timestamptz DEFAULT timezone('utc'::text, now()),
  updated_at timestamptz DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.reward_live_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view reward live state" ON public.reward_live_state;
CREATE POLICY "Anyone can view reward live state" ON public.reward_live_state FOR SELECT USING (true);

DROP POLICY IF EXISTS "Admins can update reward live state" ON public.reward_live_state;
CREATE POLICY "Admins can update reward live state" ON public.reward_live_state FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = auth.uid() AND (profiles.username LIKE '%admin%' OR profiles.username LIKE '%staff%')
  )
);

DROP POLICY IF EXISTS "Users can update host in reward live state" ON public.reward_live_state;
CREATE POLICY "Users can update host in reward live state" ON public.reward_live_state FOR UPDATE USING (
  auth.uid() IS NOT NULL AND (
    current_host_id IS NULL OR current_host_id = auth.uid()
  )
) WITH CHECK (
  auth.uid() IS NOT NULL
);

DROP POLICY IF EXISTS "Users can insert default live state if empty" ON public.reward_live_state;
CREATE POLICY "Users can insert default live state if empty" ON public.reward_live_state FOR INSERT WITH CHECK (
  auth.uid() IS NOT NULL
);

-- Seed initial default 24/7 Reward Live State
INSERT INTO public.reward_live_state (
  id, status, live_started_at, reward_interval_seconds, claim_window_seconds, cycle_point_pool, activity_mode
) VALUES (
  '00000000-0000-0000-0000-000000000001'::uuid, 'ACTIVE', timezone('utc'::text, now()), 180, 15, 1000, 'ACTIVE'
) ON CONFLICT (id) DO UPDATE SET updated_at = timezone('utc'::text, now());

-- 9.2 Reward Definitions Table
CREATE TABLE IF NOT EXISTS public.reward_definitions (
  id varchar PRIMARY KEY,
  name varchar NOT NULL,
  icon varchar NOT NULL,
  animation varchar NOT NULL DEFAULT 'float_up',
  point_value int NOT NULL DEFAULT 1,
  rarity varchar NOT NULL DEFAULT 'common', -- common, uncommon, rare, epic, legendary
  weight int NOT NULL DEFAULT 100,
  enabled boolean NOT NULL DEFAULT true,
  display_order int NOT NULL DEFAULT 0,
  max_claims_per_cycle int NOT NULL DEFAULT 1,
  daily_limit int NOT NULL DEFAULT 500,
  created_at timestamptz DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.reward_definitions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view reward definitions" ON public.reward_definitions;
CREATE POLICY "Anyone can view reward definitions" ON public.reward_definitions FOR SELECT USING (true);

DROP POLICY IF EXISTS "Admins can manage reward definitions" ON public.reward_definitions;
CREATE POLICY "Admins can manage reward definitions" ON public.reward_definitions FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = auth.uid() AND (profiles.username LIKE '%admin%' OR profiles.username LIKE '%staff%')
  )
);

-- Seed configurable reward types
INSERT INTO public.reward_definitions (id, name, icon, animation, point_value, rarity, weight, enabled, display_order) VALUES
  ('reward_coin', 'Coin', 'coin', 'float_up', 1, 'common', 400, true, 1),
  ('reward_star', 'Star', 'star', 'star_burst', 2, 'common', 250, true, 2),
  ('reward_small_gift', 'Small Gift', 'gift', 'box_bounce', 3, 'uncommon', 150, true, 3),
  ('reward_diamond', 'Diamond', 'diamond', 'diamond_spin', 5, 'uncommon', 90, true, 4),
  ('reward_gift_box', 'Gift Box', 'gift_box', 'glow_burst', 10, 'rare', 55, true, 5),
  ('reward_golden_star', 'Golden Star', 'golden_star', 'golden_spiral', 15, 'rare', 35, true, 6),
  ('reward_crystal', 'Crystal', 'crystal', 'crystal_flash', 25, 'epic', 15, true, 7),
  ('reward_golden_gift', 'Golden Gift', 'golden_gift', 'legendary_explosion', 50, 'legendary', 5, true, 8)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  icon = EXCLUDED.icon,
  point_value = EXCLUDED.point_value,
  rarity = EXCLUDED.rarity,
  weight = EXCLUDED.weight;

-- 9.3 Host Sessions Table
CREATE TABLE IF NOT EXISTS public.reward_live_host_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  live_id uuid NOT NULL REFERENCES public.reward_live_state(id) ON DELETE CASCADE,
  host_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status varchar NOT NULL DEFAULT 'REQUESTED', -- REQUESTED, PAYMENT_PENDING, APPROVED, ACTIVE, RECONNECTING, LEFT, EXPIRED, REJECTED
  requested_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  approved_at timestamptz,
  joined_at timestamptz,
  left_at timestamptz,
  stream_id varchar,
  expires_at timestamptz,
  created_at timestamptz DEFAULT timezone('utc'::text, now()),
  updated_at timestamptz DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.reward_live_host_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view host sessions" ON public.reward_live_host_sessions;
CREATE POLICY "Anyone can view host sessions" ON public.reward_live_host_sessions FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can manage their own host sessions" ON public.reward_live_host_sessions;
CREATE POLICY "Users can manage their own host sessions" ON public.reward_live_host_sessions FOR ALL USING (
  auth.uid() = host_user_id
) WITH CHECK (
  auth.uid() = host_user_id
);

-- 9.4 Invitees / Voice Participants Table (Max 50 Voice Only)
CREATE TABLE IF NOT EXISTS public.reward_live_invitees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  live_id uuid NOT NULL REFERENCES public.reward_live_state(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status varchar NOT NULL DEFAULT 'REQUESTED', -- REQUESTED, APPROVED, ACTIVE, LEFT, REMOVED, REJECTED
  joined_at timestamptz,
  left_at timestamptz,
  microphone_enabled boolean NOT NULL DEFAULT true,
  camera_enabled boolean NOT NULL DEFAULT false, -- Always false for voice participants
  created_at timestamptz DEFAULT timezone('utc'::text, now()),
  updated_at timestamptz DEFAULT timezone('utc'::text, now()),
  UNIQUE(live_id, user_id)
);

ALTER TABLE public.reward_live_invitees ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view active invitees" ON public.reward_live_invitees;
CREATE POLICY "Anyone can view active invitees" ON public.reward_live_invitees FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can manage their own invitee record" ON public.reward_live_invitees;
CREATE POLICY "Users can manage their own invitee record" ON public.reward_live_invitees FOR ALL USING (
  auth.uid() = user_id
) WITH CHECK (
  auth.uid() = user_id
);

-- 9.5 Automatic Host/Invitee Earnings Settlement Ledger
CREATE TABLE IF NOT EXISTS public.reward_live_earnings_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id uuid NOT NULL,
  role varchar NOT NULL, -- host, invitee
  duration_seconds int NOT NULL,
  rate_per_minute numeric(10, 4) NOT NULL DEFAULT 0.05,
  points_earned int NOT NULL DEFAULT 0,
  amount_usd numeric(10, 4) NOT NULL DEFAULT 0.0,
  created_at timestamptz DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.reward_live_earnings_ledger ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own live earnings" ON public.reward_live_earnings_ledger;
CREATE POLICY "Users can view their own live earnings" ON public.reward_live_earnings_ledger FOR SELECT USING (auth.uid() = user_id);

-- ====================================================================
-- 9.6 SERVER TIME GETTER FOR CLIENT COUNTDOWN SYNC
-- ====================================================================

-- Lightweight server time getter to ensure client countdown sync
CREATE OR REPLACE FUNCTION public.get_server_time()
RETURNS timestamptz
LANGUAGE sql
STABLE
AS $$
  SELECT timezone('utc'::text, now());
$$;

GRANT EXECUTE ON FUNCTION public.get_server_time() TO anon, authenticated;


