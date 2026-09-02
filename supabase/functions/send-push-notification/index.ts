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

    const defaultAlerts = [
      {
        title: "💰 Earnings Alert!",
        message: "Users are withdrawing their earnings right now! Come back and earn yours!"
      },
      {
        title: "⚡ New Tasks Available!",
        message: "High-paying watch jobs have just been added. Start earning now!"
      },
      {
        title: "🔥 Daily Payouts Active!",
        message: "Boom! Payouts are processing. Log in to check your active earnings."
      },
      {
        title: "💎 Level Up Your Earnings!",
        message: "Earn up to $1.00 per video review. Check out active levels today!"
      },
      {
        title: "🚀 Earn on the Go!",
        message: "Spend 2 minutes watching sponsored videos and get paid instantly."
      }
    ];

    const randomAlert = defaultAlerts[Math.floor(Math.random() * defaultAlerts.length)];

    const title: string = body.title ?? randomAlert.title;
    const message: string = body.message ?? randomAlert.message;
    const topic: string = body.topic ?? "all-users";
    const data: Record<string, string> = body.data ?? { type: "earnings_alert" };

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
