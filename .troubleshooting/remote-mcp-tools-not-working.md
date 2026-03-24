# Issue: Remote MCP connector "connected" but tool calls fail

**Status:** Active
**Opened:** 2026-03-24
**Resolved:** _pending_

## Info
- **Symptom:** Claude macOS app shows Ledger MCP as "connected" but tools don't work. Claude Code (VS Code) shows zero ledger tools in deferred tool list.
- **Affected area:** `mcp-server/src/http.ts`, `mcp-server/src/oauth.ts`, Cloud Run deployment

### Background Research

1. **Connector URL:** User confirmed `https://ledger-mcp-twpe4tgoja-uc.a.run.app` (old-format URL, still routes to the same Cloud Run service `ledger-mcp` on `ledger-nine4`)

2. **Server health:** `/health` returns 200, OAuth discovery correct, `POST /mcp` returns proper 401 without auth.

3. **Cloud Run logs show two patterns:**
   - **Stale client** (`a72a9b0ad7ae67f793a7952389082fbb`) retrying refresh token every ~10 min → `invalid_grant` → then tool call → `Firebase ID token has no "kid" claim` error. Happening since March 23.
   - **Fresh client** (`4c512fbae9400531e7232ae60a5f59d6`) completed full OAuth flow at 2026-03-24 19:48 UTC → 7 successful `POST /` tool calls immediately after.

4. **Token signature mismatch:** The stale refresh token (iat: 2026-03-20 22:37 UTC) was signed with a different secret than the current `OAUTH_TOKEN_SECRET` on Cloud Run. Verified by computing HMAC locally — signatures don't match.

5. **Deploy command in memory uses `--set-env-vars`** which replaces ALL env vars. Between March 20-22, 7 redeployments occurred (revisions 21-27). Any deploy with `--set-env-vars FIREBASE_PROJECT_ID=ledger-nine4` would have wiped `OAUTH_TOKEN_SECRET`.

6. **`oauth.ts` doesn't throw when secret is missing** unless `NODE_ENV=production`. Cloud Run doesn't set this. So during deploys where secret was wiped, a random secret was generated silently.

7. **Auth fallback chain** (`http.ts:70-81`): When `verifyAccessToken()` returns null (bad signature), code unconditionally tries `verifyToken()` (Firebase ID token check) on the JWT → `no "kid" claim` error.

8. **`http.ts` missing `registerInventoryOperationTools`** — registered in `index.ts` (stdio) but not the HTTP entry point.

## Experiments

### H1: Token signed with different OAUTH_TOKEN_SECRET
- **Rationale:** Multiple redeployments between token issuance (March 20) and now. Deploy command uses `--set-env-vars` which can wipe the secret.
- **Experiment:** Compute HMAC of the stale refresh token using the current `OAUTH_TOKEN_SECRET` from Cloud Run, compare to actual signature.
- **Result:** Token sig `Qp1IOLinnziwrcg6XG_TUwHamNje9h8DNXh2UvSxtR8` ≠ expected `mzuratXAWOT3jjC0Tazeg9G5sE4nJLf6O4jd6OnM2qs`. Signatures don't match.
- **Verdict:** Confirmed

### H2: Fresh OAuth flow produces working tokens
- **Rationale:** If the current `OAUTH_TOKEN_SECRET` is stable, new tokens issued now should verify correctly.
- **Experiment:** Check logs for fresh auth code exchange and subsequent tool calls.
- **Result:** Fresh OAuth at 19:48:34 UTC → token exchange succeeded → 7 successful `POST /` calls at 19:48:48-50 with `uid=sHuIe2M85WVOf3yzC0t61s3l10e2`.
- **Verdict:** Confirmed — server works with fresh tokens.

### H3: Auth fallback chain produces confusing error
- **Rationale:** `http.ts:74` `verifyAccessToken()` returns null → line 78 `verifyToken()` tries Firebase ID token verification on a custom JWT → `no "kid" claim`.
- **Experiment:** Read code path in `authenticateRequest()` function.
- **Result:** Confirmed by code read — unconditional fallback to Firebase `verifyToken()` regardless of token format.
- **Verdict:** Confirmed — needs fix to only try Firebase when token has `kid` header.

## Resolution
_Pending deploy of auth chain fix + user reconnect in Claude macOS app._
