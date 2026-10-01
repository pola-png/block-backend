import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

// =====================================================================
// XapZap: Supabase Edge Function → Firebase FCM Push Notification Sender
// Deploy with: supabase functions deploy send-push-notification
// =====================================================================

const FIREBASE_PROJECT_ID = "xapzap-34fb4";
const FCM_ENDPOINT = `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`;

// Get an OAuth2 access token from Firebase service account
async function getFirebaseAccessToken(serviceAccount: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const encode = (obj: object) =>
    btoa(JSON.stringify(obj)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

  const headerB64 = encode(header);
  const payloadB64 = encode(payload);
  const signingInput = `${headerB64}.${payloadB64}`;

  // Import private key
  const privateKeyPem = serviceAccount.private_key;
  const pemContents = privateKeyPem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binaryKey = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput)
  );
  const signatureB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  const jwt = `${signingInput}.${signatureB64}`;

  // Exchange JWT for access token
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });

  const tokenData = await tokenRes.json();
  if (!tokenData.access_token) {
    throw new Error(`Failed to get access token: ${JSON.stringify(tokenData)}`);
  }
  return tokenData.access_token;
}

serve(async (req: Request) => {
  console.log(`[Push] Incoming request: ${req.method} ${req.url}`);

  // Allow CORS
  if (req.method === "OPTIONS") {
    console.log("[Push] CORS preflight OPTIONS request");
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const body = await req.json().catch((e: any) => {
      console.warn("[Push] Request body parsing failed:", e);
      return {};
    });
    console.log("[Push] Request body:", JSON.stringify(body));

    // 3-hour schedule notification alert pools (8 slots covering the 24-hour day)
    // Slot 0: 00:00-03:00 UTC | Slot 1: 03:00-06:00 UTC | Slot 2: 06:00-09:00 UTC | Slot 3: 09:00-12:00 UTC
    // Slot 4: 12:00-15:00 UTC | Slot 5: 15:00-18:00 UTC | Slot 6: 18:00-21:00 UTC | Slot 7: 21:00-24:00 UTC
    const scheduled3HourAlerts: Record<number, Array<{ title: string; message: string }>> = {
      // 00:00 - 02:59 UTC (Late Night Boost)
      0: [
        {
          title: "🔔 New $2.40 task available",
          message: "Night-owl tasks are live! Complete quick video tasks and earn $2.40 now.",
        },
        {
          title: "🌙 Midnight Boost: $3.10 task open",
          message: "New sponsored review tasks just unlocked. Start earning before spots fill up!",
        },
        {
          title: "⚡ Flash Task: Earn $1.95 in 2 mins",
          message: "Quick video task waiting for you. Get credited to your balance instantly!",
        },
      ],
      // 03:00 - 05:59 UTC (Early Morning Payouts)
      1: [
        {
          title: "🔔 New $2.40 task available",
          message: "Early bird rewards are here! Watch a quick sponsored video to claim your $2.40.",
        },
        {
          title: "💸 $4.20 VIP task unlocked",
          message: "Exclusive high-payout video task is available. Watch and review now!",
        },
        {
          title: "🚀 Daily tasks refreshed: $2.80 available",
          message: "Start your morning with fresh earnings. Log in to claim your tasks!",
        },
      ],
      // 06:00 - 08:59 UTC (Morning Rush)
      2: [
        {
          title: "🔔 New $2.40 task available",
          message: "Fresh morning task batch is online. Earn $2.40 directly into your creator balance!",
        },
        {
          title: "☕ Morning Coffee Bonus: $3.50 task",
          message: "Take 3 minutes to review sponsored videos and get paid right now.",
        },
        {
          title: "💰 $2.10 Quick Payout Task ready",
          message: "Easy watch-and-earn tasks are active. Don't miss today's top rates!",
        },
      ],
      // 09:00 - 11:59 UTC (Mid-Day Peak)
      3: [
        {
          title: "🔔 New $2.40 task available",
          message: "New sponsored tasks just dropped! Watch and review to claim your $2.40 reward.",
        },
        {
          title: "🔥 High-paying $4.80 campaign live",
          message: "Advertisers just posted top-tier review tasks. Grab your slot before it expires!",
        },
        {
          title: "💎 $3.25 Video Review Task Available",
          message: "Earn while watching creator content. Instant withdrawal to your wallet!",
        },
      ],
      // 12:00 - 14:59 UTC (Lunchtime Drop)
      4: [
        {
          title: "🔔 New $2.40 task available",
          message: "Lunchtime bonus is active! Complete simple video tasks and get paid $2.40 instantly.",
        },
        {
          title: "⚡ Quick $2.90 task waiting for you",
          message: "Spend 2 minutes during your break and grow your XapZap wallet balance!",
        },
        {
          title: "🎁 Sponsored Reward: $5.00 task live",
          message: "Level up your earnings with our highest paying tasks of the day!",
        },
      ],
      // 15:00 - 17:59 UTC (Afternoon Surge)
      5: [
        {
          title: "🔔 New $2.40 task available",
          message: "Afternoon reward surge! Watch, review and earn $2.40 instantly on XapZap.",
        },
        {
          title: "💰 Instant Payout: $3.60 task active",
          message: "Over 500+ users cashed out today. Hop on and complete your video tasks!",
        },
        {
          title: "🚀 $2.20 Express Task open",
          message: "Fast watch-and-earn tasks ready for completion. Tap to start now!",
        },
      ],
      // 18:00 - 20:59 UTC (Evening Prime Time)
      6: [
        {
          title: "🔔 New $2.40 task available",
          message: "Evening prime-time rewards are live! Complete the $2.40 featured task now.",
        },
        {
          title: "💎 Prime Reward: $4.50 task available",
          message: "Top sponsored campaigns just launched for the evening rush. Earn big today!",
        },
        {
          title: "🔥 $3.40 Video Task ready to claim",
          message: "Relax, watch entertaining content, and earn real cash balance instantly.",
        },
      ],
      // 21:00 - 23:59 UTC (Night Cap & Final Bonus)
      7: [
        {
          title: "🔔 New $2.40 task available",
          message: "Last call for today's high-paying tasks! Earn $2.40 before daily reset.",
        },
        {
          title: "🌟 End of Day Bonus: $3.75 task",
          message: "Complete your daily streak and boost your earnings before tomorrow!",
        },
        {
          title: "💸 Instant Withdrawal Alert: $2.50 task",
          message: "Hit your withdrawal threshold tonight with quick sponsored video reviews.",
        },
      ],
    };

    const currentUtcHour = new Date().getUTCHours();
    const currentSlot = Math.floor(currentUtcHour / 3);
    const alertPool = scheduled3HourAlerts[currentSlot] ?? scheduled3HourAlerts[0];
    const scheduledAlert = alertPool[Math.floor(Math.random() * alertPool.length)];

    const title: string = body.title ?? scheduledAlert.title;
    const message: string = body.message ?? scheduledAlert.message;
    const topic: string = body.topic ?? "all-users";
    const data: Record<string, string> = body.data ?? { type: "task_alert", reward: "2.40" };

    // Load Firebase service account from Supabase secrets
    const serviceAccountStr = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
    if (!serviceAccountStr) {
      console.error("[Push] Error: FIREBASE_SERVICE_ACCOUNT secret is not set in environment!");
      return new Response(
        JSON.stringify({ error: "FIREBASE_SERVICE_ACCOUNT secret not set" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
    
    console.log("[Push] FIREBASE_SERVICE_ACCOUNT secret found. Parsing...");
    const serviceAccount = JSON.parse(serviceAccountStr);

    // Get Firebase OAuth2 access token
    console.log("[Push] Requesting Firebase access token...");
    const accessToken = await getFirebaseAccessToken(serviceAccount);
    console.log("[Push] Firebase token generated successfully.");

    // Build FCM message payload
    const fcmPayload = {
      message: {
        topic,
        notification: { title, body: message },
        android: {
          priority: "high",
          notification: {
            sound: "default",
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        data: Object.fromEntries(
          Object.entries(data).map(([k, v]) => [k, String(v)])
        ),
      },
    };

    // Send to Firebase FCM
    console.log(`[Push] Sending FCM to topic "${topic}"...`);
    const fcmRes = await fetch(FCM_ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(fcmPayload),
    });

    const fcmData = await fcmRes.json();
    console.log("[Push] FCM Response status:", fcmRes.status);
    console.log("[Push] FCM Response body:", JSON.stringify(fcmData));

    if (!fcmRes.ok) {
      console.error("[Push] FCM error returned:", JSON.stringify(fcmData));
      return new Response(JSON.stringify({ error: "FCM error", details: fcmData }), {
        status: fcmRes.status,
        headers: { "Content-Type": "application/json" },
      });
    }

    console.log("[Push] Notification sent successfully!");
    return new Response(
      JSON.stringify({ success: true, messageId: fcmData.name, topic }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[Push] Uncaught exception in edge function:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
