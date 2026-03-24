# Issue: Local MCP server fails with RAPT re-authentication error

**Status:** Active
**Opened:** 2026-03-22
**Resolved:** _pending_

## Info
- **Symptom:** Local MCP server (stdio mode) throws: `2 UNKNOWN: Getting metadata from plugin failed with error: {"error":"invalid_grant","error_description":"reauth related error (invalid_rapt)","error_uri":"https://support.google.com/a/answer/9368756","error_subtype":"invalid_rapt"}`
- **Affected area:** `mcp-server/src/firebase.ts`, `.mcp.json`

### Background Research

1. **`.mcp.json`** sets `GOOGLE_APPLICATION_CREDENTIALS` → `/Users/benjaminmackenzie/.config/gcloud/ledger-nine4-firebase-adminsdk.json`
   - This file is a valid **service account** key (`type: service_account`, `firebase-adminsdk-fbsvc@ledger-nine4.iam.gserviceaccount.com`)
   - Service accounts are **never** subject to RAPT policies

2. **`firebase.ts`** (line 23) uses `admin.credential.applicationDefault()` — the Application Default Credentials (ADC) chain:
   - Step 1: `GOOGLE_APPLICATION_CREDENTIALS` env var → service account key file
   - Step 2: `~/.config/gcloud/application_default_credentials.json` → **fallback**
   - Step 3: GCE metadata

3. **ADC fallback file** (`~/.config/gcloud/application_default_credentials.json`):
   - Type: **`authorized_user`** (from `gcloud auth application-default login`)
   - This IS subject to RAPT policies (Google Workspace admin enforces periodic re-auth for `team@nine4.co`)
   - When RAPT token expires → `invalid_rapt` error

4. **The `2 UNKNOWN` prefix** is a gRPC status code, meaning the error occurs when Firestore's gRPC connection tries to authenticate.

5. **"Getting metadata from plugin"** = google-auth-library trying to refresh an `authorized_user` credential's refresh token, hitting RAPT.

## Experiments

### H1: ADC chain falls through to `authorized_user` credentials instead of using service account key
- **Rationale:** If `GOOGLE_APPLICATION_CREDENTIALS` env var isn't reaching the node process (Claude Code env handling, process inheritance issue), `applicationDefault()` falls through to `~/.config/gcloud/application_default_credentials.json` which is `authorized_user` type and subject to RAPT.
- **Experiment:** Added diagnostic logging to `firebase.ts` to print env var value and auth path. Ran without env var to simulate Cursor.
- **Result:** `GOOGLE_APPLICATION_CREDENTIALS=(not set)`, `Auth path: applicationDefault()` — confirmed Cursor does not pass `.mcp.json` `env` vars to child processes.
- **Verdict:** Confirmed

### H2: `authorized_user` ADC credential's RAPT token has expired
- **Rationale:** `team@nine4.co` is a Google Workspace account with RAPT enabled.
- **Experiment:** N/A — subsumed by H1. The ADC fallback is the root cause; RAPT expiry is just the trigger.
- **Verdict:** Confirmed (but secondary to H1)

## Resolution
_Pending user verification after Cursor restart._

- **Root cause:** Cursor does not pass `.mcp.json` `env` vars to spawned MCP server processes. Without `GOOGLE_APPLICATION_CREDENTIALS`, `firebase-admin` uses `applicationDefault()` which finds `~/.config/gcloud/application_default_credentials.json` (an `authorized_user` credential for `team@nine4.co`). That credential is subject to Google Workspace RAPT re-auth, causing periodic `invalid_rapt` errors.
- **Fix:** Moved credential path from `env` to `args` in `.mcp.json` (`--credentials <path>`). Updated `index.ts` to parse the arg and `firebase.ts` to accept it as a parameter, using `admin.credential.cert()` directly.
- **Files changed:**
  - `mcp-server/src/firebase.ts` — accept `credentialsPath` param, use `cert()` when available
  - `mcp-server/src/index.ts` — parse `--credentials` from `process.argv`
  - `.mcp.json` — credential path moved to `args` array
- **Lessons:** Cursor/Claude Code may not forward `.mcp.json` `env` vars to child processes. For critical config, use CLI args instead. Always verify env vars reach the target process before building logic around them.
