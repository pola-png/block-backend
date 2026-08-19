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
