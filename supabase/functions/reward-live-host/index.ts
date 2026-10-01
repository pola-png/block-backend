import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import { AccessToken } from "npm:livekit-server-sdk@^2.6.0";

// =====================================================================
// XapZap Reward Live: Host & Invitee Management Edge Function
// Handles: Host requests, approvals, joining, leaving, reconnection,
// invitee requests (max 50, audio-only), LiveKit WebRTC Access Tokens,
// and earnings settlements.
// =====================================================================

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// LiveKit Server Configuration
const LIVEKIT_URL = Deno.env.get("LIVEKIT_URL") || "wss://xapzap-bu7rsekx.livekit.cloud";
const LIVEKIT_API_KEY = Deno.env.get("LIVEKIT_API_KEY") || "APIxEGnLKejZpCo";
const LIVEKIT_API_SECRET = Deno.env.get("LIVEKIT_API_SECRET");

async function generateLiveKitToken(
  identity: string,
  participantName: string,
  roomName: string,
  role: "host" | "invitee" | "viewer"
): Promise<{ token: string | null; url: string }> {
  if (!LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
    console.log("[LiveKit] Secret not set yet. Returning null token.");
    return { token: null, url: LIVEKIT_URL };
  }
  try {
    const at = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
      identity,
      name: participantName || identity,
      ttl: "4h",
    });

    if (role === "host") {
      at.addGrant({
        roomJoin: true,
        room: roomName,
        canPublish: true,
        canSubscribe: true,
        canPublishData: true,
      });
    } else if (role === "invitee") {
      at.addGrant({
        roomJoin: true,
        room: roomName,
        canPublish: true,
        canSubscribe: true,
        canPublishSources: ["microphone"],
        canPublishData: true,
      });
    } else {
      at.addGrant({
        roomJoin: true,
        room: roomName,
        canPublish: false,
        canSubscribe: true,
        canPublishData: true,
      });
    }

    const token = await at.toJwt();
    return { token, url: LIVEKIT_URL };
  } catch (e) {
    console.error("[LiveKitToken] Error creating token:", e);
    return { token: null, url: LIVEKIT_URL };
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const authHeader = req.headers.get("Authorization");

  if (!supabaseUrl || !supabaseServiceKey) {
    return new Response(
      JSON.stringify({ error: "Missing Supabase server environment configuration" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // Admin / Service role client for atomic state mutations
  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  // Authenticate user from JWT token
  let userId: string | null = null;
  if (authHeader) {
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (!authError && user) {
      userId = user.id;
    }
  }

  try {
    let body: any = {};
    try {
      const text = await req.text();
      if (text && text.trim().length > 0) {
        body = JSON.parse(text);
      }
    } catch (_) {}

    const action = (body.action || new URL(req.url).searchParams.get("action") || "") as string;
    const liveId = body.live_id || new URL(req.url).searchParams.get("live_id") || "00000000-0000-0000-0000-000000000001";
    if (!userId && (body.user_id || body.userId)) {
      userId = body.user_id || body.userId;
    }

    console.log(`[RewardLiveHost] action="${action}", userId="${userId}", liveId="${liveId}"`);

    // -------------------------------------------------------------
    // 1. GET LIVE ROOM STATE & VIEWER WEBRTC TOKEN
    // -------------------------------------------------------------
    if (action === "get_live_session") {
      let { data: liveState, error: liveErr } = await supabase
        .from("reward_live_state")
        .select("*")
        .eq("id", liveId)
        .maybeSingle();

      if (!liveState) {
        // Auto-seed default live state row if not found
        const { data: createdState } = await supabase
          .from("reward_live_state")
          .upsert({
            id: liveId,
            status: "ACTIVE",
            reward_interval_seconds: 180,
            claim_window_seconds: 120,
            cycle_point_pool: 100,
            activity_mode: "ACTIVE",
          })
          .select()
          .maybeSingle();

        liveState = createdState;
      }

      if (!liveState) {
        return new Response(
          JSON.stringify({ success: false, error: "Live room not found" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { data: activeInvitees } = await supabase
        .from("reward_live_invitees")
        .select("id, user_id, status, joined_at, microphone_enabled, camera_enabled")
        .eq("live_id", liveId)
        .eq("status", "ACTIVE")
        .order("joined_at", { ascending: true })
        .limit(50);

      const lk = await generateLiveKitToken(
        userId || `viewer_${Date.now()}`,
        "Viewer",
        liveId,
        "viewer"
      );

      return new Response(
        JSON.stringify({
          success: true,
          live: liveState,
          invitees: activeInvitees || [],
          livekit_url: lk.url,
          livekit_token: lk.token,
          server_time: new Date().toISOString(),
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Auth required for all mutating actions
    if (!userId) {
      return new Response(
        JSON.stringify({ success: false, error: "Unauthenticated. Please sign in." }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // -------------------------------------------------------------
    // 2. BECOME LIVE HOST (Request & Join with WebRTC Publishing Token)
    // -------------------------------------------------------------
    if (action === "request_host") {
      // 1. Get user profile details
      const { data: profile } = await supabase
        .from("profiles")
        .select("id, username, display_name, avatar_url, is_cheater")
        .eq("id", userId)
        .maybeSingle();

      if (profile?.is_cheater) {
        return new Response(
          JSON.stringify({ success: false, error: "Account flagged for policy violation." }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // 2. Atomically verify current_host_id IS NULL
      const { data: currentLive, error: getLiveErr } = await supabase
        .from("reward_live_state")
        .select("*")
        .eq("id", liveId)
        .maybeSingle();

      if (getLiveErr || !currentLive) {
        return new Response(
          JSON.stringify({ success: false, error: "Live session not found" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // If already has another host and that host didn't leave
      if (currentLive.current_host_id && currentLive.current_host_id !== userId) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Another host is currently live in this room.",
            current_host_id: currentLive.current_host_id,
          }),
          { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const streamId = `stream_${liveId}_${Date.now()}`;
      const nowIso = new Date().toISOString();
      const hostDisplayName = profile?.display_name || profile?.username || "Host";

      // Create host session record
      const { data: hostSession, error: sessionErr } = await supabase
        .from("reward_live_host_sessions")
        .insert({
          live_id: liveId,
          host_user_id: userId,
          status: "ACTIVE",
          requested_at: nowIso,
          approved_at: nowIso,
          joined_at: nowIso,
          stream_id: streamId,
        })
        .select()
        .single();

      if (sessionErr) {
        return new Response(
          JSON.stringify({ success: false, error: "Failed to create host session" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Update room state with host metadata WITHOUT modifying live_started_at
      await supabase
        .from("reward_live_state")
        .update({
          current_host_id: userId,
          current_host_name: hostDisplayName,
          current_host_avatar: profile?.avatar_url || "",
          current_stream_id: streamId,
          activity_mode: "ACTIVE",
          updated_at: nowIso,
        })
        .eq("id", liveId);

      // Generate LiveKit Publisher Token for Host (Audio + Video)
      const lk = await generateLiveKitToken(userId, hostDisplayName, liveId, "host");

      return new Response(
        JSON.stringify({
          success: true,
          status: "ACTIVE",
          session_id: hostSession.id,
          stream_id: streamId,
          host_user_id: userId,
          livekit_url: lk.url,
          livekit_token: lk.token,
          permissions: {
            camera: true,
            microphone: true,
            is_host: true,
          },
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // -------------------------------------------------------------
    // 3. HOST LEAVE (End Host Session)
    // -------------------------------------------------------------
    if (action === "leave_host") {
      const now = new Date();
      const nowIso = now.toISOString();

      // Find active host session
      const { data: activeSession } = await supabase
        .from("reward_live_host_sessions")
        .select("*")
        .eq("live_id", liveId)
        .eq("host_user_id", userId)
        .eq("status", "ACTIVE")
        .order("joined_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (activeSession) {
        const joinedAt = new Date(activeSession.joined_at || activeSession.requested_at);
        const durationSeconds = Math.max(0, Math.floor((now.getTime() - joinedAt.getTime()) / 1000));
        const ratePerMinute = 0.05; // 5 cents/min participation rate
        const earnedUsd = Number(((durationSeconds / 60) * ratePerMinute).toFixed(4));
        const pointsEarned = Math.floor(earnedUsd * 100);

        // Update session as LEFT
        await supabase
          .from("reward_live_host_sessions")
          .update({
            status: "LEFT",
            left_at: nowIso,
            updated_at: nowIso,
          })
          .eq("id", activeSession.id);

        // Settle earnings if duration > 30 seconds
        if (durationSeconds >= 30 && earnedUsd > 0) {
          await supabase.from("reward_live_earnings_ledger").insert({
            user_id: userId,
            session_id: activeSession.id,
            role: "host",
            duration_seconds: durationSeconds,
            rate_per_minute: ratePerMinute,
            points_earned: pointsEarned,
            amount_usd: earnedUsd,
          });

          // Credit balance atomically
          const { data: existingBal } = await supabase
            .from("creator_balances")
            .select("balance_usd, available_balance_usd")
            .eq("creator_id", userId)
            .maybeSingle();

          if (existingBal) {
            await supabase
              .from("creator_balances")
              .update({
                balance_usd: (existingBal.balance_usd || 0) + earnedUsd,
                available_balance_usd: (existingBal.available_balance_usd || 0) + earnedUsd,
                updated_at: nowIso,
              })
              .eq("creator_id", userId);
          } else {
            await supabase.from("creator_balances").insert({
              creator_id: userId,
              balance_usd: earnedUsd,
              available_balance_usd: earnedUsd,
            });
          }
        }
      }

      // Crucial: Clear host from live room WITHOUT resetting live_started_at
      await supabase
        .from("reward_live_state")
        .update({
          current_host_id: null,
          current_host_name: null,
          current_host_avatar: null,
          current_stream_id: null,
          updated_at: nowIso,
        })
        .eq("id", liveId)
        .eq("current_host_id", userId);

      return new Response(
        JSON.stringify({
          success: true,
          status: "LEFT",
          message: "Host session ended. Reward Live continues seamlessly.",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // -------------------------------------------------------------
    // 4. INVITEE / VOICE PARTICIPANT REQUEST (Max 50, Audio-only)
    // -------------------------------------------------------------
    if (action === "request_invitee") {
      // 1. Check current active invitee count (max 50 limit)
      const { count, error: countErr } = await supabase
        .from("reward_live_invitees")
        .select("*", { count: "exact", head: true })
        .eq("live_id", liveId)
        .eq("status", "ACTIVE");

      if (countErr) {
        return new Response(
          JSON.stringify({ success: false, error: "Failed to verify voice slot capacity" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if ((count || 0) >= 50) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Maximum 50 voice participants limit reached. Please wait for a slot.",
          }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const nowIso = new Date().toISOString();

      // Upsert invitee record (Microphone: YES, Camera: NO)
      const { data: invitee, error: invErr } = await supabase
        .from("reward_live_invitees")
        .upsert(
          {
            live_id: liveId,
            user_id: userId,
            status: "ACTIVE",
            joined_at: nowIso,
            microphone_enabled: true,
            camera_enabled: false, // Voice only!
            updated_at: nowIso,
          },
          { onConflict: "live_id,user_id" }
        )
        .select()
        .single();

      if (invErr) {
        return new Response(
          JSON.stringify({ success: false, error: "Failed to join voice participants" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Generate LiveKit Publisher Token for Voice Participant (Microphone only)
      const lk = await generateLiveKitToken(userId, `Voice_${userId.substring(0, 5)}`, liveId, "invitee");

      return new Response(
        JSON.stringify({
          success: true,
          status: "ACTIVE",
          invitee_id: invitee.id,
          livekit_url: lk.url,
          livekit_token: lk.token,
          permissions: {
            camera: false,
            microphone: true,
            is_invitee: true,
          },
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // -------------------------------------------------------------
    // 5. INVITEE LEAVE
    // -------------------------------------------------------------
    if (action === "leave_invitee") {
      const nowIso = new Date().toISOString();

      await supabase
        .from("reward_live_invitees")
        .update({
          status: "LEFT",
          left_at: nowIso,
          updated_at: nowIso,
        })
        .eq("live_id", liveId)
        .eq("user_id", userId);

      return new Response(
        JSON.stringify({ success: true, status: "LEFT" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ success: false, error: `Unknown action: ${action}` }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    console.error("[RewardLiveHost] Error:", err);
    return new Response(
      JSON.stringify({ success: false, error: String(err?.message || err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
