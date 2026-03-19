# MCP Server — Remote OAuth Connection (Claude.ai)

## Pending verification (2026-03-19)

Added `POST /`, `GET /`, `DELETE /` as aliases for their `/mcp` counterparts in `http.ts`. Deployed as revision `ledger-mcp-00009-8bs`.

**Test:** Claude.ai → Settings → Integrations → Ledger → disconnect → reconnect → sign in with Google → verify tools appear.

## Resolved issues

| # | Symptom | Cause | Fix |
|---|---------|-------|-----|
| 1 | `TypeError: Cannot destructure 'grant_type'` at `/token` | Express missing `urlencoded` parser; OAuth sends `application/x-www-form-urlencoded` | Added `express.urlencoded({ extended: false })` to `http.ts` |
| 2 | `invalid_grant` on token exchange | Auth codes stored in-memory `Map`, lost on Cloud Run cold start / new instance | Moved to Firestore collection `_mcp_auth_codes` |
| 3 | `No account membership found for UID` | `auth.ts` queried `collectionGroup("members")` — actual subcollection is `users` (`accounts/{id}/users/{uid}`) | Changed to `collectionGroup("users")`; updated `docs/specs/data-model.md` |
| 4 | Auth always failed despite "connected" status | Claude.ai integration pointed at wrong Cloud Run URL (`ledger-mcp-141264030366` on `gbp-sync-1584-n4`) | Updated to `ledger-mcp-351137650087` on `ledger-nine4` |

## Infrastructure reference

| | |
|---|---|
| **Cloud Run** | `ledger-mcp` / `ledger-nine4` / `us-central1` |
| **URL** | `https://ledger-mcp-351137650087.us-central1.run.app` |
| **Deploy** | `gcloud run deploy ledger-mcp --source . --region us-central1 --project ledger-nine4` |
| **Env vars** | `FIREBASE_PROJECT_ID=ledger-nine4`, `OAUTH_TOKEN_SECRET` (must be stable across cold starts) |
| **Firestore** | `_mcp_auth_codes` collection for OAuth codes; `accounts/{id}/users/{uid}` for membership |
| **Logs** | `gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="ledger-mcp"' --project=ledger-nine4 --limit=30 --format='value(textPayload)'` |
