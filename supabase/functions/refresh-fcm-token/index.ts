import { createClient } from "@supabase/supabase-js";
import "@supabase/functions-js/edge-runtime.d.ts";
import { importPKCS8, SignJWT } from "jose";

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (value === undefined) throw new Error(`Missing env var: ${name}`);
  return value;
}

// Read once at cold-start — misconfigured functions fail immediately.
// FIREBASE_PRIVATE_KEY may have literal \n from shell quoting; normalise to real newlines.
const WEBHOOK_SECRET = requireEnv("SERVERLESS_SECRET");
const clientEmail = requireEnv("FIREBASE_CLIENT_EMAIL");
const projectId = requireEnv("FIREBASE_PROJECT_ID");
const privateKey = await importPKCS8(
  requireEnv("FIREBASE_PRIVATE_KEY").replace(/\\n/g, "\n"),
  "RS256",
);

const supabase = createClient(
  requireEnv("SUPABASE_URL"),
  requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
  { auth: { persistSession: false } },
);

async function getAccessToken(): Promise<string> {
  const jwt = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(clientEmail)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(privateKey);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`OAuth token exchange failed: ${await res.text()}`);
  }
  const { access_token } = await res.json();
  return access_token as string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }
  if (req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
    return new Response("Unauthorized", { status: 401 });
  }

  let accessToken: string;
  try {
    accessToken = await getAccessToken();
  } catch (err) {
    console.error("Failed to obtain FCM access token:", err);
    return new Response("Internal error", { status: 500 });
  }

  const { error } = await supabase.rpc("store_fcm_access_token", {
    p_token: accessToken,
    p_project_id: projectId,
  });

  if (error) {
    console.error("Failed to store FCM access token:", error);
    return new Response("Internal error", { status: 500 });
  }

  console.log("FCM access token refreshed successfully");
  return Response.json({ ok: true });
});
