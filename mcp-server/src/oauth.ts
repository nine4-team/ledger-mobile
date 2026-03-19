import {
  randomBytes,
  createHmac,
  createHash,
  timingSafeEqual,
} from "node:crypto";
import type { Express } from "express";
import type { Firestore } from "firebase-admin/firestore";
import { verifyToken, resolveAccountId } from "./auth.js";

// Firebase Web API key (same one client apps use — not secret)
const FIREBASE_API_KEY =
  process.env.FIREBASE_API_KEY ||
  "AIzaSyBOryqA4-z4YEiR_FQCyBo-o3NSCucfyVs";

// Token signing secret — required in production, random fallback for local dev
const TOKEN_SECRET = (() => {
  if (process.env.OAUTH_TOKEN_SECRET) return process.env.OAUTH_TOKEN_SECRET;
  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "OAUTH_TOKEN_SECRET env var is required in production. " +
        "Set a stable secret so tokens survive Cloud Run cold starts."
    );
  }
  return randomBytes(32).toString("hex");
})();

// ---------- Auth code store (Firestore-backed to survive cold starts) ----------

interface AuthCode {
  uid: string;
  accountId: string;
  codeChallenge: string;
  redirectUri: string;
  clientId: string;
  expiresAt: number;
}

// Firestore collection for auth codes — survives across Cloud Run instances
let _db: Firestore | null = null;
function authCodesCollection() {
  return _db!.collection("_mcp_auth_codes");
}

async function storeAuthCode(code: string, data: AuthCode): Promise<void> {
  await authCodesCollection().doc(code).set(data);
}

async function consumeAuthCode(code: string): Promise<AuthCode | null> {
  const doc = await authCodesCollection().doc(code).get();
  if (!doc.exists) return null;
  const data = doc.data() as AuthCode;
  if (data.expiresAt < Date.now()) {
    await doc.ref.delete();
    return null;
  }
  // One-time use
  await doc.ref.delete();
  return data;
}

// Client registrations are ephemeral — Claude re-registers each flow
const registeredClients = new Map<
  string,
  { clientId: string; clientSecret: string; redirectUris: string[] }
>();

// ---------- JWT helpers ----------

function signJwt(payload: Record<string, unknown>): string {
  const header = Buffer.from(
    JSON.stringify({ alg: "HS256", typ: "JWT" })
  ).toString("base64url");
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = createHmac("sha256", TOKEN_SECRET)
    .update(`${header}.${body}`)
    .digest("base64url");
  return `${header}.${body}.${signature}`;
}

function verifyJwtSignature(
  token: string
): Record<string, unknown> | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [header, body, signature] = parts;
  const expected = createHmac("sha256", TOKEN_SECRET)
    .update(`${header}.${body}`)
    .digest("base64url");
  if (
    signature.length !== expected.length ||
    !timingSafeEqual(Buffer.from(signature), Buffer.from(expected))
  )
    return null;
  const payload = JSON.parse(Buffer.from(body, "base64url").toString());
  if (payload.exp && payload.exp < Date.now() / 1000) return null;
  return payload;
}

/** Verify an OAuth access token issued by this server. */
export function verifyAccessToken(
  token: string
): { uid: string; accountId: string } | null {
  const payload = verifyJwtSignature(token);
  if (!payload || !payload.uid || !payload.accountId) return null;
  if (payload.type === "refresh") return null; // refresh tokens aren't access tokens
  return {
    uid: payload.uid as string,
    accountId: payload.accountId as string,
  };
}

/** PKCE S256: BASE64URL(SHA256(code_verifier)) */
function pkceS256(verifier: string): string {
  return createHash("sha256").update(verifier).digest("base64url");
}

// ---------- Routes ----------

function getOrigin(req: { protocol: string; get(name: string): string | undefined }): string {
  return process.env.PUBLIC_URL || `${req.protocol}://${req.get("host")}`;
}

export function registerOAuthRoutes(app: Express, db: Firestore) {
  _db = db;
  // Protected Resource Metadata (RFC 9728) — Claude.ai checks this FIRST
  app.get("/.well-known/oauth-protected-resource", (req, res) => {
    const origin = getOrigin(req);
    res.json({
      resource: `${origin}/mcp`,
      authorization_servers: [origin],
      bearer_methods_supported: ["header"],
    });
  });

  // Path-specific variant: /.well-known/oauth-protected-resource/mcp
  app.get("/.well-known/oauth-protected-resource/mcp", (req, res) => {
    const origin = getOrigin(req);
    res.json({
      resource: `${origin}/mcp`,
      authorization_servers: [origin],
      bearer_methods_supported: ["header"],
    });
  });

  // OAuth Authorization Server Metadata (RFC 8414)
  app.get("/.well-known/oauth-authorization-server", (req, res) => {
    const origin = getOrigin(req);
    res.json({
      issuer: origin,
      authorization_endpoint: `${origin}/authorize`,
      token_endpoint: `${origin}/token`,
      registration_endpoint: `${origin}/register`,
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: [
        "client_secret_post",
        "none",
      ],
      logo_uri: `${origin}/logo.png`,
    });
  });

  // Dynamic client registration (RFC 7591)
  app.post("/register", (req, res) => {
    const body = req.body || {};
    console.error("[ledger-mcp] Registration request:", JSON.stringify(body));

    const clientId = randomBytes(16).toString("hex");
    const redirectUris = Array.isArray(body.redirect_uris) ? body.redirect_uris : [];
    // Respect the client's requested auth method — Claude is a public client ("none")
    const authMethod = body.token_endpoint_auth_method || "none";
    // Only issue a secret if the client wants one
    const clientSecret = authMethod === "none" ? undefined : randomBytes(32).toString("hex");

    registeredClients.set(clientId, {
      clientId,
      clientSecret: clientSecret || "",
      redirectUris,
    });

    const response: Record<string, unknown> = {
      client_id: clientId,
      client_name: body.client_name || "MCP Client",
      redirect_uris: redirectUris,
      grant_types: body.grant_types || ["authorization_code", "refresh_token"],
      response_types: body.response_types || ["code"],
      token_endpoint_auth_method: authMethod,
    };
    if (clientSecret) response.client_secret = clientSecret;

    console.error("[ledger-mcp] Registration response:", JSON.stringify(response));
    res.status(201).json(response);
  });

  // Authorization endpoint — renders login page
  app.get("/authorize", (req, res) => {
    console.error("[ledger-mcp] Authorize request:", JSON.stringify(req.query));
    const {
      client_id,
      redirect_uri,
      state,
      code_challenge,
      code_challenge_method,
      response_type,
    } = req.query;

    if (response_type !== "code") {
      res.status(400).json({ error: "unsupported_response_type" });
      return;
    }

    res.type("html").send(
      loginPage({
        clientId: (client_id as string) || "",
        redirectUri: (redirect_uri as string) || "",
        state: (state as string) || "",
        codeChallenge: (code_challenge as string) || "",
        codeChallengeMethod: (code_challenge_method as string) || "S256",
      })
    );
  });

  // Authorization callback — receives Firebase ID token, issues auth code
  app.post("/authorize/callback", async (req, res) => {
    try {
      const { id_token, client_id, redirect_uri, state, code_challenge } =
        req.body;

      // Verify Firebase ID token against production Firebase Auth
      let uid: string;
      try {
        uid = await verifyToken(id_token);
      } catch (e) {
        console.error("[ledger-mcp] verifyToken failed:", e instanceof Error ? e.message : e);
        throw e;
      }

      // Resolve account: try Firestore first, fall back to env var
      let accountId: string;
      const envAccountId = process.env.LEDGER_ACCOUNT_ID;
      try {
        accountId = await resolveAccountId(db, uid);
      } catch (e) {
        if (envAccountId) {
          console.error("[ledger-mcp] resolveAccountId failed, using LEDGER_ACCOUNT_ID:", envAccountId);
          accountId = envAccountId;
        } else {
          throw e;
        }
      }

      // Generate one-time auth code (stored in Firestore to survive cold starts)
      const code = randomBytes(32).toString("hex");
      await storeAuthCode(code, {
        uid,
        accountId,
        codeChallenge: code_challenge || "",
        redirectUri: redirect_uri,
        clientId: client_id,
        expiresAt: Date.now() + 10 * 60 * 1000, // 10 min
      });

      // Build redirect URL
      const url = new URL(redirect_uri);
      url.searchParams.set("code", code);
      if (state) url.searchParams.set("state", state);

      res.json({ redirect_url: url.toString() });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Authentication failed";
      console.error("[ledger-mcp] OAuth callback error:", message);
      res.status(401).json({ error: message });
    }
  });

  // Token endpoint — exchange auth code for access token, or refresh
  app.post("/token", async (req, res) => {
    console.error("[ledger-mcp] Token request:", JSON.stringify({ ...req.body, code: req.body?.code ? "[redacted]" : undefined, code_verifier: req.body?.code_verifier ? "[redacted]" : undefined }));
    const {
      grant_type,
      code,
      code_verifier,
      redirect_uri,
      refresh_token,
    } = req.body;

    if (grant_type === "authorization_code") {
      const stored = await consumeAuthCode(code);
      if (!stored) {
        res.status(400).json({
          error: "invalid_grant",
          error_description: "Invalid or expired authorization code",
        });
        return;
      }

      // Verify PKCE code_verifier
      if (stored.codeChallenge) {
        const computed = pkceS256(code_verifier || "");
        if (computed !== stored.codeChallenge) {
          res.status(400).json({
            error: "invalid_grant",
            error_description: "Invalid code_verifier",
          });
          return;
        }
      }

      // Verify redirect_uri matches
      if (stored.redirectUri !== redirect_uri) {
        res.status(400).json({
          error: "invalid_grant",
          error_description: "redirect_uri mismatch",
        });
        return;
      }

      // Issue non-expiring access + refresh tokens
      const now = Math.floor(Date.now() / 1000);
      const accessToken = signJwt({
        uid: stored.uid,
        accountId: stored.accountId,
        iat: now,
      });
      const newRefreshToken = signJwt({
        uid: stored.uid,
        accountId: stored.accountId,
        type: "refresh",
        iat: now,
      });

      res.json({
        access_token: accessToken,
        token_type: "Bearer",
        refresh_token: newRefreshToken,
      });
    } else if (grant_type === "refresh_token") {
      const payload = verifyJwtSignature(refresh_token);
      if (!payload || payload.type !== "refresh") {
        res.status(400).json({
          error: "invalid_grant",
          error_description: "Invalid refresh token",
        });
        return;
      }

      const now = Math.floor(Date.now() / 1000);
      const accessToken = signJwt({
        uid: payload.uid as string,
        accountId: payload.accountId as string,
        iat: now,
      });

      res.json({
        access_token: accessToken,
        token_type: "Bearer",
      });
    } else {
      res.status(400).json({ error: "unsupported_grant_type" });
    }
  });
}

// ---------- Login page ----------

// Google OAuth Client ID for web sign-in
const GOOGLE_CLIENT_ID =
  process.env.GOOGLE_CLIENT_ID ||
  "351137650087-lfdb85vaoqrpp9mnpmdgklc1cpreitti.apps.googleusercontent.com";

function loginPage(params: {
  clientId: string;
  redirectUri: string;
  state: string;
  codeChallenge: string;
  codeChallengeMethod: string;
}): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <title>Sign in to Ledger</title>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <script src="https://accounts.google.com/gsi/client" async></script>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
      background: #f5f3f0;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      padding: 16px;
    }
    .card {
      background: white;
      border-radius: 12px;
      padding: 32px;
      max-width: 400px;
      width: 100%;
      box-shadow: 0 2px 8px rgba(0,0,0,0.08);
    }
    .logo {
      width: 48px;
      height: 48px;
      background: #987e55;
      border-radius: 10px;
      display: flex;
      align-items: center;
      justify-content: center;
      margin: 0 auto 20px;
      color: white;
      font-size: 22px;
      font-weight: 700;
    }
    h1 { font-size: 22px; text-align: center; margin-bottom: 6px; color: #1a1a1a; }
    .subtitle { color: #888; text-align: center; margin-bottom: 24px; font-size: 14px; }
    .google-btn-wrapper { display: flex; justify-content: center; margin-bottom: 20px; }
    .divider {
      display: flex;
      align-items: center;
      margin-bottom: 20px;
      color: #ccc;
      font-size: 13px;
    }
    .divider::before, .divider::after {
      content: "";
      flex: 1;
      height: 1px;
      background: #e5e5e5;
    }
    .divider span { padding: 0 12px; }
    label { display: block; font-size: 13px; font-weight: 600; margin-bottom: 5px; color: #444; }
    input {
      width: 100%;
      padding: 10px 12px;
      border: 1px solid #ddd;
      border-radius: 8px;
      font-size: 15px;
      margin-bottom: 16px;
      transition: border-color 0.15s;
    }
    input:focus { outline: none; border-color: #987e55; box-shadow: 0 0 0 2px rgba(152,126,85,0.2); }
    button {
      width: 100%;
      padding: 11px;
      background: #987e55;
      color: white;
      border: none;
      border-radius: 8px;
      font-size: 15px;
      font-weight: 600;
      cursor: pointer;
      transition: background 0.15s;
    }
    button:hover { background: #8a7049; }
    button:disabled { opacity: 0.6; cursor: not-allowed; }
    .error {
      color: #dc3545;
      font-size: 13px;
      margin-bottom: 16px;
      padding: 8px 12px;
      background: #fdf0f0;
      border-radius: 6px;
      display: none;
    }
    .status {
      color: #987e55;
      font-size: 13px;
      margin-bottom: 16px;
      padding: 8px 12px;
      background: #f9f6f2;
      border-radius: 6px;
      display: none;
      text-align: center;
    }
    .footer { text-align: center; margin-top: 20px; font-size: 12px; color: #aaa; }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">L</div>
    <h1>Sign in to Ledger</h1>
    <p class="subtitle">Connect your account to Claude</p>
    <div class="error" id="error"></div>
    <div class="status" id="status"></div>

    <!-- Google Sign-In button -->
    <div class="google-btn-wrapper">
      <div id="g_id_onload"
        data-client_id="${GOOGLE_CLIENT_ID}"
        data-callback="handleGoogleSignIn"
        data-auto_prompt="false">
      </div>
      <div class="g_id_signin"
        data-type="standard"
        data-size="large"
        data-theme="outline"
        data-text="sign_in_with"
        data-shape="rectangular"
        data-logo_alignment="left"
        data-width="336">
      </div>
    </div>

    <div class="divider"><span>or</span></div>

    <!-- Email/password fallback -->
    <form id="loginForm">
      <label for="email">Email</label>
      <input type="email" id="email" name="email" required autocomplete="email">
      <label for="password">Password</label>
      <input type="password" id="password" name="password" required autocomplete="current-password">
      <button type="submit" id="submitBtn">Sign In with Email</button>
    </form>
    <p class="footer">Your credentials are sent directly to Firebase Auth</p>
  </div>
  <script>
    const FIREBASE_API_KEY = ${JSON.stringify(FIREBASE_API_KEY)};
    const params = ${JSON.stringify(params)};

    function showError(msg) {
      const el = document.getElementById("error");
      el.textContent = msg;
      el.style.display = "block";
      document.getElementById("status").style.display = "none";
    }

    function showStatus(msg) {
      const el = document.getElementById("status");
      el.textContent = msg;
      el.style.display = "block";
      document.getElementById("error").style.display = "none";
    }

    // Exchange a Firebase ID token for an auth code and redirect to Claude
    async function exchangeTokenAndRedirect(firebaseIdToken) {
      showStatus("Connecting to Ledger\\u2026");
      const callbackRes = await fetch("/authorize/callback", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          id_token: firebaseIdToken,
          client_id: params.clientId,
          redirect_uri: params.redirectUri,
          state: params.state,
          code_challenge: params.codeChallenge,
        }),
      });
      const callbackData = await callbackRes.json();
      if (!callbackRes.ok) {
        throw new Error(callbackData.error || "Authorization failed");
      }
      showStatus("Redirecting to Claude\\u2026");
      window.location.href = callbackData.redirect_url;
    }

    // Google Sign-In callback
    async function handleGoogleSignIn(response) {
      try {
        showStatus("Signing in with Google\\u2026");
        // Exchange Google credential for Firebase ID token via signInWithIdp
        const authRes = await fetch(
          "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=" + FIREBASE_API_KEY,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              requestUri: window.location.origin,
              postBody: "id_token=" + response.credential + "&providerId=google.com",
              returnSecureToken: true,
              returnIdpCredential: true,
            }),
          }
        );
        const authData = await authRes.json();
        if (!authRes.ok) {
          throw new Error(authData.error?.message || "Google sign-in failed");
        }
        await exchangeTokenAndRedirect(authData.idToken);
      } catch (err) {
        showError(err.message.replace(/_/g, " "));
      }
    }
    // Make it globally available for Google's callback
    window.handleGoogleSignIn = handleGoogleSignIn;

    // Email/password sign-in
    document.getElementById("loginForm").addEventListener("submit", async (e) => {
      e.preventDefault();
      const btn = document.getElementById("submitBtn");
      btn.disabled = true;
      btn.textContent = "Signing in\\u2026";
      document.getElementById("error").style.display = "none";

      try {
        const authRes = await fetch(
          "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" + FIREBASE_API_KEY,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              email: document.getElementById("email").value,
              password: document.getElementById("password").value,
              returnSecureToken: true,
            }),
          }
        );
        const authData = await authRes.json();
        if (!authRes.ok) {
          throw new Error(authData.error?.message || "Authentication failed");
        }
        await exchangeTokenAndRedirect(authData.idToken);
      } catch (err) {
        const msg = err.message
          .replace(/_/g, " ")
          .replace(/email not found/i, "No account found with that email")
          .replace(/invalid password/i, "Incorrect password")
          .replace(/invalid.login.credentials/i, "Invalid email or password");
        showError(msg);
        btn.disabled = false;
        btn.textContent = "Sign In with Email";
      }
    });
  </script>
</body>
</html>`;
}
