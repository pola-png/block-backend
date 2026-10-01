-- =====================================================================
-- XAPZAP REWARD LIVE STREAMING DATABASE SETUP (Complete with RLS & Realtime)
-- Run this in Supabase Dashboard -> SQL Editor
-- =====================================================================

-- -------------------------------------------------------------
-- 1. Persistent Reward Live State Table (24/7 Live Room)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.reward_live_state (
  id uuid PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000001'::uuid,
  status varchar NOT NULL DEFAULT 'ACTIVE', -- ACTIVE, PAUSED, MAINTENANCE
  live_started_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  reward_interval_seconds int NOT NULL DEFAULT 180, -- 3 minutes total
  claim_window_seconds int NOT NULL DEFAULT 120,    -- 2 minutes active drop window
  cycle_point_pool int NOT NULL DEFAULT 100,
  last_reward_cycle bigint NOT NULL DEFAULT 0,
  current_host_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  current_host_name varchar,
  current_host_avatar varchar,
  current_stream_id varchar,
  activity_mode varchar NOT NULL DEFAULT 'ACTIVE', -- ACTIVE, IDLE
  created_at timestamptz DEFAULT timezone('utc'::text, now()),
  updated_at timestamptz DEFAULT timezone('utc'::text, now())
);

-- RLS: reward_live_state
ALTER TABLE public.reward_live_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view reward live state" ON public.reward_live_state;
CREATE POLICY "Anyone can view reward live state" ON public.reward_live_state FOR SELECT USING (true);

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

DROP POLICY IF EXISTS "Admins can manage reward live state" ON public.reward_live_state;
CREATE POLICY "Admins can manage reward live state" ON public.reward_live_state FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = auth.uid() AND (profiles.username LIKE '%admin%' OR profiles.username LIKE '%staff%')
  )
);

-- Seed initial default 24/7 Reward Live State
INSERT INTO public.reward_live_state (
  id, status, live_started_at, reward_interval_seconds, claim_window_seconds, cycle_point_pool, activity_mode
) VALUES (
  '00000000-0000-0000-0000-000000000001'::uuid, 'ACTIVE', timezone('utc'::text, now()), 180, 120, 100, 'ACTIVE'
) ON CONFLICT (id) DO UPDATE SET 
  reward_interval_seconds = 180,
  claim_window_seconds = 120,
  cycle_point_pool = 100,
  updated_at = timezone('utc'::text, now());

-- -------------------------------------------------------------
-- 2. Reward Definitions Table (20 Official Gifts)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.reward_definitions (
  id varchar PRIMARY KEY,
  name varchar NOT NULL,
  icon varchar NOT NULL,
  animation varchar NOT NULL DEFAULT 'float_up',
  point_value int NOT NULL DEFAULT 1,
  rarity varchar NOT NULL DEFAULT 'common', -- common, uncommon, rare, epic, legendary, mythic
  weight int NOT NULL DEFAULT 100,
  enabled boolean NOT NULL DEFAULT true,
  display_order int NOT NULL DEFAULT 0,
  max_claims_per_cycle int NOT NULL DEFAULT 2,
  daily_limit int NOT NULL DEFAULT 500,
  created_at timestamptz DEFAULT timezone('utc'::text, now())
);

-- RLS: reward_definitions
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

-- Seed the 20 Official XapZap Gifts
INSERT INTO public.reward_definitions (id, name, icon, animation, point_value, rarity, weight, enabled, display_order) VALUES
  ('xapzap_universe', 'XapZap Universe', '🌌', 'galaxy_portal', 100, 'mythic', 10, true, 1),
  ('thunder_falcon', 'Thunder Falcon', '🦅', 'dragon_fly', 40, 'epic', 25, true, 2),
  ('fire_phoenix', 'Fire Phoenix', '🔥', 'dragon_fly', 50, 'legendary', 20, true, 3),
  ('leon_and_lion', 'Leon and Lion', '🦁', 'dragon_fly', 35, 'epic', 30, true, 4),
  ('zeus', 'Zeus', '⚡', 'galaxy_portal', 90, 'mythic', 12, true, 5),
  ('lion', 'Lion', '🦁', 'puppy_run', 30, 'rare', 35, true, 6),
  ('golden_sports_car', 'Golden Sports Car', '🚗', 'sports_car', 60, 'legendary', 18, true, 7),
  ('dragon_flame', 'Dragon Flame', '🔥', 'dragon_fly', 70, 'legendary', 15, true, 8),
  ('dragon_phoenix', 'Dragon/Phoenix', '🐉', 'dragon_fly', 80, 'mythic', 14, true, 9),
  ('castle_fantasy', 'Castle Fantasy', '🏰', 'galaxy_portal', 45, 'epic', 25, true, 10),
  ('dolphin', 'Dolphin', '🐬', 'puppy_jump', 20, 'rare', 45, true, 11),
  ('rocket', 'Rocket', '🚀', 'rocket_launch', 55, 'legendary', 20, true, 12),
  ('interstellar', 'Interstellar', '🌌', 'galaxy_portal', 85, 'mythic', 12, true, 13),
  ('falcon', 'Falcon', '🦅', 'dragon_fly', 25, 'rare', 40, true, 14),
  ('sports_car', 'Sports Car', '🏎️', 'sports_car', 35, 'rare', 35, true, 15),
  ('unicorn_fantasy', 'Unicorn Fantasy', '🦄', 'unicorn_rainbow', 50, 'legendary', 22, true, 16),
  ('private_jet', 'Private Jet', '✈️', 'sports_car', 65, 'legendary', 16, true, 17),
  ('whale_diving', 'Whale Diving', '🐋', 'puppy_jump', 30, 'rare', 35, true, 18),
  ('fireworks', 'Fireworks', '🎆', 'float_burst', 20, 'uncommon', 50, true, 19),
  ('galaxy', 'Galaxy', '🌌', 'galaxy_portal', 75, 'legendary', 15, true, 20)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  icon = EXCLUDED.icon,
  point_value = EXCLUDED.point_value,
  rarity = EXCLUDED.rarity,
  weight = EXCLUDED.weight,
  enabled = EXCLUDED.enabled;

-- -------------------------------------------------------------
-- 3. Host Sessions Table
-- -------------------------------------------------------------
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

-- RLS: reward_live_host_sessions
ALTER TABLE public.reward_live_host_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view host sessions" ON public.reward_live_host_sessions;
CREATE POLICY "Anyone can view host sessions" ON public.reward_live_host_sessions FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can manage their own host sessions" ON public.reward_live_host_sessions;
CREATE POLICY "Users can manage their own host sessions" ON public.reward_live_host_sessions FOR ALL USING (
  auth.uid() = host_user_id
) WITH CHECK (
  auth.uid() = host_user_id
);

-- -------------------------------------------------------------
-- 4. Invitees / Voice Participants Table (Max 50 Voice Only)
-- -------------------------------------------------------------
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

-- RLS: reward_live_invitees
ALTER TABLE public.reward_live_invitees ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view active invitees" ON public.reward_live_invitees;
CREATE POLICY "Anyone can view active invitees" ON public.reward_live_invitees FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can manage their own invitee record" ON public.reward_live_invitees;
CREATE POLICY "Users can manage their own invitee record" ON public.reward_live_invitees FOR ALL USING (
  auth.uid() = user_id
) WITH CHECK (
  auth.uid() = user_id
);

-- -------------------------------------------------------------
-- 5. Automatic Host/Invitee Earnings Settlement Ledger
-- -------------------------------------------------------------
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

-- RLS: reward_live_earnings_ledger
ALTER TABLE public.reward_live_earnings_ledger ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own live earnings" ON public.reward_live_earnings_ledger;
CREATE POLICY "Users can view their own live earnings" ON public.reward_live_earnings_ledger FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their live earnings" ON public.reward_live_earnings_ledger;
CREATE POLICY "Users can insert their live earnings" ON public.reward_live_earnings_ledger FOR INSERT WITH CHECK (auth.uid() = user_id);

-- -------------------------------------------------------------
-- 6. Creator Balances Table (Wallet & Rewards)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.creator_balances (
  creator_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  balance_usd numeric(10, 4) NOT NULL DEFAULT 0.0,
  available_balance_usd numeric(10, 4) NOT NULL DEFAULT 0.0,
  created_at timestamptz DEFAULT timezone('utc'::text, now()),
  updated_at timestamptz DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.creator_balances ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT timezone('utc'::text, now());
ALTER TABLE public.creator_balances ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT timezone('utc'::text, now());

-- RLS: creator_balances
ALTER TABLE public.creator_balances ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own creator balance" ON public.creator_balances;
CREATE POLICY "Users can view their own creator balance" ON public.creator_balances FOR SELECT USING (auth.uid() = creator_id);

DROP POLICY IF EXISTS "Users can manage their creator balance" ON public.creator_balances;
CREATE POLICY "Users can manage their creator balance" ON public.creator_balances FOR ALL USING (auth.uid() = creator_id) WITH CHECK (auth.uid() = creator_id);

-- Backfill creator_balances for ALL existing users (guarantees 100% user coverage)
INSERT INTO public.creator_balances (creator_id, balance_usd, available_balance_usd, created_at, updated_at)
SELECT id, 0.0, 0.0, timezone('utc'::text, now()), timezone('utc'::text, now())
FROM auth.users
ON CONFLICT (creator_id) DO NOTHING;

-- Trigger: Automatically create $0.00 creator balance row whenever ANY new user registers
CREATE OR REPLACE FUNCTION public.handle_new_user_creator_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.creator_balances (creator_id, balance_usd, available_balance_usd, created_at, updated_at)
  VALUES (NEW.id, 0.0, 0.0, timezone('utc'::text, now()), timezone('utc'::text, now()))
  ON CONFLICT (creator_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_creator_balance ON auth.users;
CREATE TRIGGER on_auth_user_created_creator_balance
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user_creator_balance();

-- -------------------------------------------------------------
-- 7. Server Clock Sync Function
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_server_time()
RETURNS timestamptz
LANGUAGE sql
STABLE
AS $$
  SELECT timezone('utc'::text, now());
$$;

-- -------------------------------------------------------------
-- 8. Realtime Publication Setup (for instant client sync)
-- -------------------------------------------------------------
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.reward_live_state;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.reward_live_invitees;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.creator_balances;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
END $$;


